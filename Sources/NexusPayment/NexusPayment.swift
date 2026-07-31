import Foundation
import NexusCoreUser
import NexusGrowthAnalyticsAd
#if canImport(UIKit)
import UIKit
#endif

public final class NexusPayment: @unchecked Sendable {
    public static let shared = NexusPayment()
    public static let version = "0.0.4"

    private var config: PaymentConfig?
    private var providers: [PaymentChannel: PaymentProvider] = [:]
    private var appStoreProvider: AppStorePaymentProvider?
    private var orderVerificationAPI: OrderVerificationAPI?
    private var products: [Product] = []
    private var relatedProducts: [RelatedProduct] = []
    private var useTestingProducts = false
    private var useTestingRelatedProducts = false
    private var entitlements: [String: Entitlement] = [:]
    private var deliveredOrderIds = Set<String>()
    private var subscriptionPageCallbacks: [(SubscriptionPageEvent) -> Void] = []
    private weak var subscriptionPageViewController: AnyObject?

    private init() {}

    public func initialize(config: PaymentConfig) {
        self.config = config
        self.orderVerificationAPI = try? OrderVerificationAPI(config: NexusCoreUser.shared.getSdkConfig())
        providers.removeAll()
        registerProvider(MockPaymentProvider())
        let appStoreProvider = AppStorePaymentProvider()
        self.appStoreProvider = appStoreProvider
        registerProvider(appStoreProvider)
        registerProvider(ThirdPartyPaymentProvider(channel: .stripe))
        registerProvider(ThirdPartyPaymentProvider(channel: .paypal))
        registerProvider(ThirdPartyPaymentProvider(channel: .webCheckout))
        deliveredOrderIds.removeAll()
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
        if let rule = config.rules.first(where: { rule in
            (rule.country == nil || rule.country == context.country) &&
            (rule.platform == nil || rule.platform == context.platform)
        }) {
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
        self.useTestingProducts = true
    }

    public func setRelatedProductsForTesting(_ products: [RelatedProduct]) {
        self.relatedProducts = products
        self.useTestingRelatedProducts = true
    }

    public func getProducts(forceRefresh: Bool = false) async throws -> [Product] {
        if useTestingProducts { return products }
        if !forceRefresh && !products.isEmpty { return products }
        let coreConfig = try NexusCoreUser.shared.getSdkConfig()
        let response = try await ProductAPI(config: coreConfig).getProducts()
        products = try await mergeProviderProducts(response)
        return products
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
        let entitlement = grant(product: product, orderId: orderId, channel: providerResult.channel, verification: verification)
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
            if verification.isSuccessful, let entitlement = grant(product: purchase.product, orderId: orderId, channel: purchase.channel, verification: verification) {
                reportPurchaseRevenue(product: purchase.product, orderId: orderId, channel: purchase.channel, verification: verification)
                _ = entitlement
            }
        }
        return result
    }

    public func getEntitlements() -> [Entitlement] {
        Array(entitlements.values)
    }

    public func showSubscriptionPage(config: SubscriptionPageConfig) {
        dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .pageShow, state: .ready, params: ["template_id": config.templateId, "scene": config.scene]))
    }

    #if canImport(UIKit)
    public func showSubscriptionPage(presenting viewController: UIViewController, config: SubscriptionPageConfig) {
        dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .pageShow, state: .loading, params: ["template_id": config.templateId, "scene": config.scene]))
        let page = SubscriptionPageViewController(sdk: self, config: config)
        subscriptionPageViewController = page
        let navigation = UINavigationController(rootViewController: page)
        navigation.modalPresentationStyle = .formSheet
        viewController.present(navigation, animated: true)
    }
    #endif

    public func closeSubscriptionPage() {
        #if canImport(UIKit)
        (subscriptionPageViewController as? UIViewController)?.dismiss(animated: true)
        subscriptionPageViewController = nil
        #endif
        dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .close, state: .cancelled))
    }

    @discardableResult
    public func onSubscriptionPageEvent(_ callback: @escaping (SubscriptionPageEvent) -> Void) -> () -> Void {
        subscriptionPageCallbacks.append(callback)
        let index = subscriptionPageCallbacks.count - 1
        return { [weak self] in
            guard let self, self.subscriptionPageCallbacks.indices.contains(index) else { return }
            self.subscriptionPageCallbacks.remove(at: index)
        }
    }

    private func mergeProviderProducts(_ apiProducts: [Product]) async throws -> [Product] {
        var merged = apiProducts
        for provider in providers.values {
            let providerProducts = try await provider.getProducts(productIds: apiProducts.map(\.marketProductId))
            for providerProduct in providerProducts {
                if let index = merged.firstIndex(where: { $0.marketProductId == providerProduct.marketProductId }) {
                    let apiProduct = merged[index]
                    merged[index] = Product(
                        marketProductId: apiProduct.marketProductId,
                        name: providerProduct.name.isEmpty ? apiProduct.name : providerProduct.name,
                        description: apiProduct.description.isEmpty ? providerProduct.description : apiProduct.description,
                        productType: apiProduct.productType == .unknown ? providerProduct.productType : apiProduct.productType,
                        coinsGranted: apiProduct.coinsGranted,
                        price: providerProduct.price ?? apiProduct.price,
                        currency: providerProduct.currency ?? apiProduct.currency,
                        localizedPrice: providerProduct.localizedPrice ?? apiProduct.localizedPrice,
                        subscriptionPeriod: providerProduct.subscriptionPeriod ?? apiProduct.subscriptionPeriod,
                        trialPeriod: providerProduct.trialPeriod ?? apiProduct.trialPeriod,
                        hasTrial: apiProduct.hasTrial || providerProduct.hasTrial,
                        entitlementId: apiProduct.entitlementId,
                        benefits: apiProduct.benefits
                    )
                }
            }
        }
        return merged
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

    private func grant(product: Product, orderId: String, channel: PaymentChannel, verification: OrderVerificationResult?) -> Entitlement? {
        guard deliveredOrderIds.insert(orderId).inserted else { return nil }
        let entitlement = Entitlement(
            entitlementId: product.entitlementId ?? product.marketProductId,
            productId: product.marketProductId,
            orderId: orderId,
            channel: channel,
            startedTime: verification?.startedTime,
            endsTime: verification?.endsTime,
            active: verification?.isSuccessful ?? true
        )
        entitlements[entitlement.entitlementId] = entitlement
        return entitlement
    }

    private func revoke(product: Product, orderId: String, channel: PaymentChannel, verification: OrderVerificationResult?) {
        let entitlementId = product.entitlementId ?? product.marketProductId
        entitlements[entitlementId] = Entitlement(
            entitlementId: entitlementId,
            productId: product.marketProductId,
            orderId: orderId,
            channel: channel,
            startedTime: verification?.startedTime,
            endsTime: verification?.endsTime,
            active: false
        )
    }

    private func observeAppStoreTransactions(_ provider: AppStorePaymentProvider) {
        provider.observeTransactions { [weak self] providerResult in
            guard let self else { return }
            do {
                let uid = try await self.currentUid()
                guard let orderId = providerResult.orderId else { return }
                let verification = try await self.verifyProviderPurchaseIfNeeded(provider: provider, result: providerResult, uid: uid)
                if verification.isSuccessful {
                    if let entitlement = self.grant(product: providerResult.product, orderId: orderId, channel: providerResult.channel, verification: verification) {
                        self.reportPurchaseRevenue(product: providerResult.product, orderId: orderId, channel: providerResult.channel, verification: verification)
                        _ = entitlement
                    }
                } else if verification.status == .cancelled || verification.status == .refunded || !providerResult.success {
                    self.revoke(product: providerResult.product, orderId: orderId, channel: providerResult.channel, verification: verification)
                    self.dispatchSubscriptionPageEvent(SubscriptionPageEvent(
                        name: .purchaseFailed,
                        productId: providerResult.product.marketProductId,
                        paymentChannel: providerResult.channel,
                        state: .failed,
                        params: ["order_id": orderId, "status": verification.status.rawValue, "message": providerResult.message]
                    ))
                }
            } catch {
                self.dispatchSubscriptionPageEvent(SubscriptionPageEvent(
                    name: .purchaseFailed,
                    productId: providerResult.product.marketProductId,
                    paymentChannel: providerResult.channel,
                    state: .failed,
                    params: ["message": error.localizedDescription]
                ))
            }
        }
    }

    func dispatchSubscriptionPageEvent(_ event: SubscriptionPageEvent) {
        subscriptionPageCallbacks.forEach { $0(event) }
        if NexusGrowthAnalyticsAd.shared.isInitialized() {
            _ = try? NexusGrowthAnalyticsAd.shared.reportPurchaseEvent(event.name.rawValue, payload: event.analyticsParams())
        }
    }

    private func requireConfig() throws -> PaymentConfig {
        guard let config else { throw PaymentError.notInitialized }
        return config
    }
}

final class ProductAPI: @unchecked Sendable {
    private let config: CoreUserConfig
    private let session: URLSession

    init(config: CoreUserConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func getProducts() async throws -> [Product] {
        guard let url = URL(string: config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/m/v7/iap/list") else {
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
            return Product(
                marketProductId: id,
                name: string(item["name"]) ?? "",
                description: string(item["description"]) ?? "",
                productType: type(int(item["product_type"])),
                coinsGranted: int(item["coins_granted"]),
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

    private static func type(_ value: Int?) -> ProductType {
        switch value {
        case 1: .iap
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

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "1" || value.lowercased() == "true" }
        return false
    }
}
