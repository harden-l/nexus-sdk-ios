import Foundation
import NexusCoreUser
import NexusGrowthAnalyticsAd
#if canImport(UIKit)
import UIKit
#endif

public final class NexusPayment: @unchecked Sendable {
    public static let shared = NexusPayment()
    public static let version = "0.0.8"

    private var config: PaymentConfig?
    private var providers: [PaymentChannel: PaymentProvider] = [:]
    private var appStoreProvider: AppStorePaymentProvider?
    private var orderVerificationAPI: OrderVerificationAPI?
    private var products: [Product] = []
    private var apiProducts: [Product] = []
    private var relatedProducts: [RelatedProduct] = []
    private var useTestingProducts = false
    private var useTestingRelatedProducts = false
    private let entitlementLock = NSLock()
    private var subscriptionPageCallbacks: [UUID: (SubscriptionPageEvent) -> Void] = [:]
    private var activeSubscriptionPageConfig: SubscriptionPageConfig?
    private weak var subscriptionPageViewController: AnyObject?

    private init() {}

    public func initialize(config: PaymentConfig) {
        self.config = config
        products.removeAll()
        apiProducts.removeAll()
        relatedProducts.removeAll()
        useTestingProducts = false
        useTestingRelatedProducts = false
        self.orderVerificationAPI = try? OrderVerificationAPI(config: NexusCoreUser.shared.getSdkConfig())
        providers.removeAll()
        registerProvider(MockPaymentProvider())
        let appStoreProvider = AppStorePaymentProvider()
        self.appStoreProvider = appStoreProvider
        registerProvider(appStoreProvider)
        registerProvider(ThirdPartyPaymentProvider(channel: .stripe))
        registerProvider(ThirdPartyPaymentProvider(channel: .paypal))
        registerProvider(ThirdPartyPaymentProvider(channel: .webCheckout))
        observeAppStoreTransactions(appStoreProvider)
    }

    public func getAvailableChannels() throws -> [PaymentChannel] {
        try requireConfig().enabledChannels
    }

    public func getConfig() throws -> PaymentConfig {
        try requireConfig()
    }

    public func resolvePaymentChannel(context: PaymentContext = PaymentContext()) throws -> ResolvedPaymentChannels {
        let config = try requireConfig()
        if let rule = config.rules.first(where: { paymentRule($0, matches: context) }) {
            return ResolvedPaymentChannels(defaultChannel: rule.defaultChannel, enabledChannels: rule.enabledChannels, fallbackChannels: rule.fallbackChannels, matchedRule: rule)
        }
        return ResolvedPaymentChannels(defaultChannel: config.defaultChannel, enabledChannels: config.enabledChannels, fallbackChannels: config.fallbackChannels, matchedRule: nil)
    }

    public func registerProvider(_ provider: PaymentProvider) {
        providers[provider.channel] = provider
    }

    public func getRegisteredProviders() -> [PaymentProvider] {
        Array(providers.values)
    }

    public func setProductsForTesting(_ products: [Product]) {
        self.products = products
        self.apiProducts = products
        self.useTestingProducts = true
    }

    public func setRelatedProductsForTesting(_ products: [RelatedProduct]) {
        self.relatedProducts = products
        self.useTestingRelatedProducts = true
    }

    public func getProducts(forceRefresh: Bool = false) async throws -> [Product] {
        if useTestingProducts { return products }
        if !forceRefresh && !products.isEmpty { return products }
        let loadedAPIProducts = try await getAPIProducts(forceRefresh: forceRefresh)
        products = await enrichProductsWithAppStore(loadedAPIProducts)
        return products
    }

    func getAPIProducts(forceRefresh: Bool = false) async throws -> [Product] {
        if useTestingProducts { return apiProducts }
        if !forceRefresh && !apiProducts.isEmpty { return apiProducts }
        let coreConfig = try NexusCoreUser.shared.getSdkConfig()
        apiProducts = try await ProductAPI(config: coreConfig).getProducts()
        products = apiProducts
        return apiProducts
    }

    func enrichProductsWithAppStore(_ apiProducts: [Product]) async -> [Product] {
        let enrichedProducts = await mergeProviderProducts(apiProducts)
        products = enrichedProducts
        return enrichedProducts
    }

    public func getRelatedProducts(forceRefresh: Bool = false) async throws -> [RelatedProduct] {
        if useTestingRelatedProducts { return relatedProducts }
        return try await NexusCoreUser.shared.getRelatedProducts(forceRefresh: forceRefresh)
    }

    public func mockPurchase(product: Product) async throws -> PurchaseResult {
        try await purchase(product: product, channel: .mock)
    }

    public func purchase(product: Product, channel: PaymentChannel? = nil, paymentContext: PaymentContext = PaymentContext()) async throws -> PurchaseResult {
        let selected = try channel ?? resolvePaymentChannel(context: paymentContext).defaultChannel
        guard let provider = providers[selected] else { throw PaymentError.providerNotRegistered("Payment provider is not registered for \(selected.rawValue)") }
        let available = try getAvailableChannels()
        guard available.contains(selected) || selected == .mock else { throw PaymentError.channelDisabled("Payment channel is disabled: \(selected.rawValue)") }
        let uid: String
        if let cachedUid = try NexusCoreUser.shared.getCurrentUser()?.uid {
            uid = cachedUid
        } else {
            uid = try await NexusCoreUser.shared.silentLogin().uid
        }
        let providerResult = try await provider.purchase(request: PurchaseRequest(product: product, uid: uid, paymentContext: paymentContext))
        guard providerResult.success else {
            return PurchaseResult(channel: providerResult.channel, product: product, success: false, orderId: providerResult.orderId, message: providerResult.message)
        }
        guard let orderId = providerResult.orderId else {
            throw PaymentError.apiError("Purchase succeeded without order id")
        }
        let verification = try await verifyProviderPurchaseIfNeeded(provider: provider, result: providerResult, uid: uid)
        guard verification.isSuccessful else {
            return PurchaseResult(
                channel: providerResult.channel,
                product: providerResult.product,
                success: false,
                orderId: orderId,
                message: "Order verification status: \(verification.status.rawValue)",
                verification: verification
            )
        }
        await provider.completePurchase(providerResult)
        let entitlement = grant(
            product: product,
            orderId: orderId,
            deliveryId: deliveryId(for: providerResult),
            channel: providerResult.channel,
            verification: verification,
            uid: uid
        )
        if let entitlement {
            reportPurchaseRevenue(product: product, orderId: orderId, channel: providerResult.channel, verification: verification)
            return PurchaseResult(channel: providerResult.channel, product: product, success: true, orderId: orderId, message: providerResult.message, verification: verification, entitlement: entitlement)
        }
        return PurchaseResult(channel: providerResult.channel, product: product, success: true, orderId: orderId, message: providerResult.message, verification: verification, entitlement: nil)
    }

    public func restore(channel: PaymentChannel = .appStore) async throws -> RestoreResult {
        guard let provider = providers[channel] else { throw PaymentError.providerNotRegistered("Payment provider is not registered for \(channel.rawValue)") }
        let available = try getAvailableChannels()
        guard available.contains(channel) || channel == .mock else { throw PaymentError.channelDisabled("Payment channel is disabled: \(channel.rawValue)") }
        let result = try await provider.restore()
        let uid = try await currentUid()
        for purchase in result.purchases where purchase.success {
            guard let orderId = purchase.orderId else { continue }
            let verification = try await verifyProviderPurchaseIfNeeded(provider: provider, result: purchase, uid: uid)
            if verification.isSuccessful {
                await provider.completePurchase(purchase)
                if let entitlement = grant(
                    product: purchase.product,
                    orderId: orderId,
                    deliveryId: deliveryId(for: purchase),
                    channel: purchase.channel,
                    verification: verification,
                    uid: uid
                ) {
                    reportPurchaseRevenue(product: purchase.product, orderId: orderId, channel: purchase.channel, verification: verification)
                    _ = entitlement
                }
            }
        }
        return result
    }

    public func getEntitlements() -> [Entitlement] {
        do {
            guard let uid = try NexusCoreUser.shared.getCurrentUser()?.uid else { return [] }
            return Array(loadEntitlementState(uid: uid).entitlements.values)
        } catch {
            return []
        }
    }

    public func showSubscriptionPage(config: SubscriptionPageConfig) {
        activeSubscriptionPageConfig = config
        dispatchSubscriptionPageEvent(pageEvent(name: .pageShow, state: .ready))
    }

    #if canImport(UIKit)
    public func showSubscriptionPage(presenting viewController: UIViewController, config: SubscriptionPageConfig) {
        activeSubscriptionPageConfig = config
        dispatchSubscriptionPageEvent(pageEvent(name: .pageShow, state: .loading))
        let page = SubscriptionPageViewController(sdk: self, config: config)
        subscriptionPageViewController = page
        let navigation = UINavigationController(rootViewController: page)
        navigation.modalPresentationStyle = .formSheet
        navigation.presentationController?.delegate = page
        viewController.present(navigation, animated: true)
    }
    #endif

    public func closeSubscriptionPage() {
        #if canImport(UIKit)
        (subscriptionPageViewController as? UIViewController)?.dismiss(animated: true)
        subscriptionPageViewController = nil
        #endif
        dispatchSubscriptionPageEvent(pageEvent(name: .close, state: .cancelled))
        activeSubscriptionPageConfig = nil
    }

    @discardableResult
    public func onSubscriptionPageEvent(_ callback: @escaping (SubscriptionPageEvent) -> Void) -> () -> Void {
        let id = UUID()
        subscriptionPageCallbacks[id] = callback
        return { [weak self] in
            self?.subscriptionPageCallbacks.removeValue(forKey: id)
        }
    }

    private func mergeProviderProducts(_ apiProducts: [Product]) async -> [Product] {
        guard !apiProducts.isEmpty else { return [] }
        guard let paymentConfig = config else { return apiProducts }
        let requestedChannels = activeSubscriptionPageConfig?.paymentChannels.isEmpty == false
            ? activeSubscriptionPageConfig!.paymentChannels
            : paymentConfig.enabledChannels
        guard requestedChannels.contains(.appStore) else { return apiProducts }
        guard let provider = appStoreProvider else {
            return apiProducts
        }
        do {
            let providerProducts = try await provider.getProducts(productIds: apiProducts.map(\.marketProductId))
            guard !providerProducts.isEmpty else {
                return apiProducts
            }
            return ProductDetailsMerger.merge(apiProducts: apiProducts, storeProducts: providerProducts)
        } catch {
            return apiProducts
        }
    }

    private func currentUid() async throws -> String {
        if let cachedUid = try NexusCoreUser.shared.getCurrentUser()?.uid {
            return cachedUid
        }
        return try await NexusCoreUser.shared.silentLogin().uid
    }

    private func verifyProviderPurchaseIfNeeded(provider: PaymentProvider, result: ProviderPurchaseResult, uid: String) async throws -> OrderVerificationResult {
        guard provider.requiresServerVerification else {
            return OrderVerificationResult(
                tradeOrderId: result.orderId ?? "",
                status: .success,
                isSubscription: result.isSubscription,
                token: result.purchaseToken,
                platformProductId: result.platformProductId,
                startedTime: Int64(Date().timeIntervalSince1970 * 1000),
                endsTime: nil,
                successCount: nil,
                amount: nil
            )
        }
        guard let token = result.purchaseToken, !token.isEmpty else {
            throw PaymentError.apiError("Purchase token is required for server verification")
        }
        guard let orderId = result.orderId, !orderId.isEmpty else {
            throw PaymentError.apiError("Order id is required for server verification")
        }
        guard let orderVerificationAPI else {
            throw PaymentError.apiError("Order verification API is not available; initialize CoreUserSDK before PaymentSDK")
        }
        return try await orderVerificationAPI.verify(
            channel: result.channel,
            token: token,
            platformProductId: result.platformProductId,
            uid: uid,
            isSubscription: result.isSubscription,
            tradeOrderId: orderId
        )
    }

    private func reportPurchaseRevenue(product: Product, orderId: String, channel: PaymentChannel, verification: OrderVerificationResult) {
        guard NexusGrowthAnalyticsAd.shared.isInitialized() else { return }
        _ = try? NexusGrowthAnalyticsAd.shared.reportPurchaseRevenue(PurchaseRevenuePayload(
            paymentChannel: growthPaymentChannel(channel),
            orderId: orderId,
            transactionId: verification.token,
            storeProductId: product.marketProductId,
            purchaseType: product.productType == .subscription ? .subscription : .oneTime,
            subscriptionPeriod: product.subscriptionPeriod,
            currency: product.currency ?? "USD",
            revenue: Double(verification.amount ?? product.price ?? "") ?? 0
        ))
    }

    private func growthPaymentChannel(_ channel: PaymentChannel) -> GrowthPaymentChannel {
        switch channel {
        case .googlePlay: .googlePlay
        case .appStore: .appStore
        case .stripe: .stripe
        case .paypal: .paypal
        case .webCheckout: .webCheckout
        case .mock: .mock
        }
    }

    private func grant(
        product: Product,
        orderId: String,
        deliveryId: String,
        channel: PaymentChannel,
        verification: OrderVerificationResult?,
        uid: String
    ) -> Entitlement? {
        entitlementLock.lock()
        defer { entitlementLock.unlock() }
        var state = loadEntitlementStateUnlocked(uid: uid)
        guard state.deliveredOrderIds.insert(deliveryId).inserted else { return nil }
        let entitlement = Entitlement(
            entitlementId: product.entitlementId ?? product.marketProductId,
            productId: product.marketProductId,
            orderId: orderId,
            channel: channel,
            startedTime: verification?.startedTime,
            endsTime: verification?.endsTime,
            active: verification?.isSuccessful ?? true
        )
        state.entitlements[entitlement.entitlementId] = entitlement
        saveEntitlementStateUnlocked(state, uid: uid)
        return entitlement
    }

    private func revoke(product: Product, orderId: String, channel: PaymentChannel, verification: OrderVerificationResult?, uid: String) {
        entitlementLock.lock()
        defer { entitlementLock.unlock() }
        var state = loadEntitlementStateUnlocked(uid: uid)
        let entitlementId = product.entitlementId ?? product.marketProductId
        state.entitlements[entitlementId] = Entitlement(
            entitlementId: entitlementId,
            productId: product.marketProductId,
            orderId: orderId,
            channel: channel,
            startedTime: verification?.startedTime,
            endsTime: verification?.endsTime,
            active: false
        )
        saveEntitlementStateUnlocked(state, uid: uid)
    }

    private func observeAppStoreTransactions(_ provider: AppStorePaymentProvider) {
        provider.observeTransactions { [weak self] providerResult in
            guard let self else { return false }
            do {
                let uid = try await self.currentUid()
                guard let orderId = providerResult.orderId else { return false }
                let verification = try await self.verifyProviderPurchaseIfNeeded(provider: provider, result: providerResult, uid: uid)
                if verification.isSuccessful {
                    if let entitlement = self.grant(
                        product: providerResult.product,
                        orderId: orderId,
                        deliveryId: self.deliveryId(for: providerResult),
                        channel: providerResult.channel,
                        verification: verification,
                        uid: uid
                    ) {
                        self.reportPurchaseRevenue(product: providerResult.product, orderId: orderId, channel: providerResult.channel, verification: verification)
                        _ = entitlement
                    }
                    return true
                } else if verification.status == .cancelled || verification.status == .refunded || !providerResult.success {
                    self.revoke(
                        product: providerResult.product,
                        orderId: orderId,
                        channel: providerResult.channel,
                        verification: verification,
                        uid: uid
                    )
                    self.dispatchSubscriptionPageEvent(SubscriptionPageEvent(
                        name: .purchaseFailed,
                        productId: providerResult.product.marketProductId,
                        paymentChannel: providerResult.channel,
                        state: .failed,
                        params: ["order_id": orderId, "status": verification.status.rawValue, "message": providerResult.message]
                    ))
                    return true
                }
                return false
            } catch {
                self.dispatchSubscriptionPageEvent(SubscriptionPageEvent(
                    name: .purchaseFailed,
                    productId: providerResult.product.marketProductId,
                    paymentChannel: providerResult.channel,
                    state: .failed,
                    params: ["message": error.localizedDescription]
                ))
                return false
            }
        }
    }

    func dispatchSubscriptionPageEvent(_ event: SubscriptionPageEvent) {
        subscriptionPageCallbacks.values.forEach { $0(event) }
        if NexusGrowthAnalyticsAd.shared.isInitialized() {
            _ = try? NexusGrowthAnalyticsAd.shared.reportPurchaseEvent(event.name.rawValue, payload: event.analyticsParams())
        }
    }

    private func requireConfig() throws -> PaymentConfig {
        guard let config else { throw PaymentError.notInitialized }
        return config
    }

    func subscriptionPageWasDismissed() {
        subscriptionPageViewController = nil
        activeSubscriptionPageConfig = nil
    }

    func deliveryId(for result: ProviderPurchaseResult) -> String {
        if let value = result.rawData["transaction_id"]?.value as? UInt64 {
            return String(value)
        }
        if let value = result.rawData["transaction_id"]?.value as? NSNumber {
            return value.stringValue
        }
        if let value = result.rawData["transaction_id"]?.value as? String, !value.isEmpty {
            return value
        }
        return result.orderId ?? result.purchaseToken ?? result.platformProductId
    }

    private func loadEntitlementState(uid: String) -> PersistedEntitlementState {
        entitlementLock.lock()
        defer { entitlementLock.unlock() }
        return loadEntitlementStateUnlocked(uid: uid)
    }

    private func loadEntitlementStateUnlocked(uid: String) -> PersistedEntitlementState {
        guard let data = UserDefaults.standard.data(forKey: entitlementStorageKey(uid: uid)),
              let state = try? JSONDecoder().decode(PersistedEntitlementState.self, from: data)
        else { return PersistedEntitlementState() }
        return state
    }

    private func saveEntitlementStateUnlocked(_ state: PersistedEntitlementState, uid: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: entitlementStorageKey(uid: uid))
    }

    private func entitlementStorageKey(uid: String) -> String {
        "nexus.payment.\(config?.productId ?? "unknown").entitlements.\(uid)"
    }

    private func pageEvent(
        name: SubscriptionPageEventName,
        productId: String? = nil,
        paymentChannel: PaymentChannel? = nil,
        state: SubscriptionPageState? = nil,
        params: [String: Any?] = [:]
    ) -> SubscriptionPageEvent {
        var values = params
        if let config = activeSubscriptionPageConfig {
            values["template_id"] = config.templateId
            values["scene"] = config.scene
        }
        return SubscriptionPageEvent(
            name: name,
            productId: productId,
            paymentChannel: paymentChannel,
            state: state,
            params: values
        )
    }

    private func paymentRule(_ rule: PaymentRule, matches context: PaymentContext) -> Bool {
        if let country = rule.country,
           country.caseInsensitiveCompare(context.country ?? "") != .orderedSame {
            return false
        }
        if let platform = rule.platform,
           platform.caseInsensitiveCompare(context.platform) != .orderedSame {
            return false
        }
        if let minimumVersion = rule.minVersion,
           let appVersion = context.appVersion,
           compareVersions(appVersion, minimumVersion) < 0 {
            return false
        }
        return true
    }

    private func compareVersions(_ left: String, _ right: String) -> Int {
        let leftParts = left.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = right.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(leftParts.count, rightParts.count) {
            let difference = (index < leftParts.count ? leftParts[index] : 0) -
                (index < rightParts.count ? rightParts[index] : 0)
            if difference != 0 { return difference }
        }
        return 0
    }
}

private struct PersistedEntitlementState: Codable {
    var deliveredOrderIds: Set<String> = []
    var entitlements: [String: Entitlement] = [:]
}

final class ProductAPI: @unchecked Sendable {
    private let config: CoreUserConfig
    private let session: URLSession

    init(config: CoreUserConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func getProducts() async throws -> [Product] {
        guard let url = URL(string: config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/m/v6/iap/list") else {
            throw PaymentError.invalidConfig("Invalid apiBaseUrl")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.productName, forHTTPHeaderField: "Product")
        request.setValue(config.encrypt ? "1" : "0", forHTTPHeaderField: "Encrypt")
        if !config.encrypt { request.setValue(config.productId, forHTTPHeaderField: "ProductId") }
        request.httpBody = try APIRequestEncryption.prepareBody("{}", config: config, encrypt: config.encrypt)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let body = try APIRequestEncryption.readResponse(data, config: config, encrypt: config.encrypt)
        guard (200..<300).contains(status) else { throw PaymentError.apiError("HTTP \(status): \(body)") }
        return try ProductParser.parse(body)
    }
}

enum ProductParser {
    static func parse(_ body: String) throws -> [Product] {
        let root = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] ?? [:]
        if let code = int(root["code"]), code != 1 {
            throw PaymentError.apiError(root["message"] as? String ?? "Get products failed")
        }
        let data = root["data"] as? [String: Any]
        let list = data?["list"] as? [[String: Any]] ?? root["list"] as? [[String: Any]] ?? root["data"] as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let id = string(item["market_product_id"]), !id.isEmpty else { return nil }
            let coinsGranted = double(item["coins_granted"])
            return Product(
                marketProductId: id,
                name: string(item["name"]) ?? "",
                description: string(item["description"]) ?? "",
                productType: type(int(item["product_type"]), coinsGranted: coinsGranted),
                coinsGranted: coinsGranted,
                price: string(item["price"]),
                currency: string(item["currency"]),
                localizedPrice: string(item["localized_price"]),
                subscriptionPeriod: string(item["subscription_period"]),
                trialPeriod: string(item["trial_period"]),
                hasTrial: bool(item["has_trial"]),
                entitlementId: string(item["entitlement_id"]),
                benefits: item["benefits"] as? [String] ?? []
            )
        }
    }

    private static func type(_ value: Int?, coinsGranted: Double?) -> ProductType {
        switch value {
        case 1: (coinsGranted ?? 0) > 0 ? .consumable : .iap
        case 2: .subscription
        default: .unknown
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value { return "\(value)" }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "1" || value.lowercased() == "true" }
        return false
    }
}
