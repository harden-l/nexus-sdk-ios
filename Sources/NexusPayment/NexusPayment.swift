import Foundation
import NexusCoreUser
import NexusGrowthAnalyticsAd
#if canImport(UIKit)
import UIKit
#endif

public final class NexusPayment: @unchecked Sendable {
    public static let shared = NexusPayment()
    public static let version = "0.1.0"

    private var config: PaymentConfig?
    private var providers: [PaymentChannel: PaymentProvider] = [:]
    private var appStoreProvider: AppStorePaymentProvider?
    private var products: [Product] = []
    private var apiProducts: [Product] = []
    private var relatedProducts: [RelatedProduct] = []
    private var useTestingProducts = false
    private var useTestingRelatedProducts = false
    private let stateLock = NSRecursiveLock()
    private var generation = UUID()
    private var catalogScope: String?
    private var catalogSession: CoreUserSessionContext?
    private var pendingPurchases: [String: ProviderPurchaseResult] = [:]
    private var reconciliationTasks: [String: ReconciliationJob] = [:]
    private var processingTransactions: Set<String> = []
    private var checkoutReservations: [String: [String: UUID]] = [:]
    static let stateDidChange = Notification.Name("NexusPayment.stateDidChange")
    private var subscriptionPageCallbacks: [UUID: (SubscriptionPageEvent) -> Void] = [:]
    private var activeSubscriptionPageConfig: SubscriptionPageConfig?
    private weak var subscriptionPageViewController: AnyObject?

    private init() {}

    public func initialize(config: PaymentConfig) {
        stateLock.lock()
        defer { stateLock.unlock() }
        generation = UUID()
        reconciliationTasks.values.forEach { $0.task.cancel() }
        reconciliationTasks.removeAll()
        pendingPurchases.removeAll()
        processingTransactions.removeAll()
        checkoutReservations.removeAll()
        catalogScope = nil
        catalogSession = nil
        appStoreProvider?.stopObservingTransactions()
        self.config = config
        products.removeAll()
        apiProducts.removeAll()
        relatedProducts.removeAll()
        useTestingProducts = false
        useTestingRelatedProducts = false
        providers.removeAll()
        registerProvider(MockPaymentProvider())
        let appStoreProvider = AppStorePaymentProvider()
        self.appStoreProvider = appStoreProvider
        registerProvider(appStoreProvider)
        registerProvider(ThirdPartyPaymentProvider(channel: .stripe))
        registerProvider(ThirdPartyPaymentProvider(channel: .paypal))
        registerProvider(ThirdPartyPaymentProvider(channel: .webCheckout))
        if config.enabledChannels.contains(.appStore) {
            observeAppStoreTransactions(appStoreProvider)
        }
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
        locked { providers[provider.channel] = provider }
    }

    public func getRegisteredProviders() -> [PaymentProvider] {
        locked { Array(providers.values) }
    }

    public func setProductsForTesting(_ products: [Product]) {
        stateLock.lock()
        defer { stateLock.unlock() }
        self.products = products
        self.apiProducts = products
        self.useTestingProducts = true
    }

    public func setRelatedProductsForTesting(_ products: [RelatedProduct]) {
        stateLock.lock()
        defer { stateLock.unlock() }
        self.relatedProducts = products
        self.useTestingRelatedProducts = true
    }

    public func getProducts(forceRefresh: Bool = false) async throws -> [Product] {
        let operation = try await captureOperation()
        if let cached = try locked({ () throws -> [Product]? in
            try validate(operation)
            return useTestingProducts || (!forceRefresh && catalogScope == operation.scope && (try? catalogSession?.validate()) != nil && !products.isEmpty) ? products : nil
        }) { return cached }
        let loaded = try await getAPIProducts(forceRefresh: forceRefresh, operation: operation)
        return try await enrichProductsWithAppStore(loaded, operation: operation)
    }

    func getAPIProducts(forceRefresh: Bool = false) async throws -> [Product] {
        try await getAPIProducts(forceRefresh: forceRefresh, operation: captureOperation())
    }

    func getAPIProducts(forceRefresh: Bool, operation: PaymentOperation) async throws -> [Product] {
        if let cached = try locked({ () throws -> [Product]? in
            try validate(operation)
            return useTestingProducts || (!forceRefresh && catalogScope == operation.scope && (try? catalogSession?.validate()) != nil && !apiProducts.isEmpty) ? apiProducts : nil
        }) { return cached }
        let loaded = try await ProductAPI { path, body in
            try await operation.session.post(path: path, body: body)
        }.getProducts()
        return try locked {
            try validate(operation)
            catalogScope = operation.scope
            catalogSession = operation.session
            apiProducts = loaded
            products = loaded
            return loaded
        }
    }

    func enrichProductsWithAppStore(_ apiProducts: [Product], operation: PaymentOperation) async throws -> [Product] {
        let provider = try locked { () throws -> PaymentProvider? in
            try validate(operation)
            let channels = activeSubscriptionPageConfig?.paymentChannels.isEmpty == false
                ? activeSubscriptionPageConfig!.paymentChannels : try requireConfig().enabledChannels
            return channels.contains(.appStore) ? providers[.appStore] : nil
        }
        let store = try? await provider?.getProducts(productIds: apiProducts.map(\.marketProductId))
        let enriched = ProductDetailsMerger.merge(apiProducts: apiProducts, storeProducts: store ?? [])
        return try locked {
            try validate(operation)
            catalogScope = operation.scope
            catalogSession = operation.session
            products = enriched
            return enriched
        }
    }

    public func getRelatedProducts(forceRefresh: Bool = false) async throws -> [RelatedProduct] {
        let operation = try await captureOperation()
        if let cached = locked({ useTestingRelatedProducts ? relatedProducts : nil }) { return cached }
        let result = try await NexusCoreUser.shared.getRelatedProducts(forceRefresh: forceRefresh)
        try validate(operation)
        return result
    }

    public func mockPurchase(product: Product) async throws -> PurchaseResult {
        try await purchase(product: product, channel: .mock)
    }

    public func purchase(product: Product, channel: PaymentChannel? = nil, paymentContext: PaymentContext = PaymentContext()) async throws -> PurchaseResult {
        try await purchase(product: product, channel: channel, paymentContext: paymentContext, operation: captureOperation())
    }

    func purchase(product: Product, channel: PaymentChannel?, paymentContext: PaymentContext = PaymentContext(), operation: PaymentOperation) async throws -> PurchaseResult {
        try validate(operation)
        let selected = try channel ?? resolvePaymentChannel(context: paymentContext).defaultChannel
        let provider = try provider(for: selected, operation: operation)
        let reservationId = UUID()
        let reserved = try locked { () throws -> Bool in
            try validate(operation)
            var state = loadState(operation)
            if let user = try? NexusCoreUser.shared.getCurrentUser() { refreshEntitlements(&state, user: user) }
            guard !pendingProducts(state).contains(product.marketProductId),
                  checkoutReservations[operation.storageKey]?[product.marketProductId] == nil else { return false }
            checkoutReservations[operation.storageKey, default: [:]][product.marketProductId] = reservationId
            return true
        }
        guard reserved else { return pendingResult(product: product, channel: selected) }
        defer {
            // Cleanup is scope- and reservation-specific, even after the session became stale.
            locked {
                if checkoutReservations[operation.storageKey]?[product.marketProductId] == reservationId {
                    checkoutReservations[operation.storageKey]?.removeValue(forKey: product.marketProductId)
                }
            }
        }
        let storeResult: ProviderPurchaseResult
        do {
            try validate(operation)
            storeResult = try await provider.purchase(request: PurchaseRequest(product: product, uid: operation.session.uid, paymentContext: paymentContext))
        } catch {
            try validate(operation)
            throw error
        }
        if storeResult.success || storeResult.pending {
            // A store-confirmed unresolved payment belongs to the captured scope even
            // when its caller became stale. Never grant or finish through this path.
            locked {
                var state = loadState(operation)
                state.pendingProductIds.insert(product.marketProductId)
                saveState(state, key: operation.storageKey)
            }
        }
        try validate(operation)
        guard storeResult.success else {
            if storeResult.pending {
                return pendingResult(product: product, channel: selected)
            }
            return PurchaseResult(channel: selected, product: product, success: false, orderId: storeResult.orderId, message: storeResult.message)
        }
        return try await reconcile(storeResult, provider: provider, operation: operation)
    }

    public func restore(channel: PaymentChannel = .appStore) async throws -> RestoreResult {
        try await restore(channel: channel, operation: captureOperation())
    }

    func restore(channel: PaymentChannel, operation: PaymentOperation) async throws -> RestoreResult {
        let provider = try provider(for: channel, operation: operation)
        var result = try await provider.restore()
        try validate(operation)
        for (index, purchase) in result.purchases.enumerated() {
            do {
                guard purchase.success || purchase.rawData["revocation_date"] != nil else { continue }
                let reconciled = try await reconcile(purchase, provider: provider, operation: operation)
                result.purchases[index].success = reconciled.success
                result.purchases[index].pending = reconciled.pending
                result.purchases[index].message = reconciled.message
            } catch {
                // Ownership and malformed items are item failures, never batch failures.
                try validate(operation)
                result.purchases[index].success = false
                result.purchases[index].message = error.localizedDescription
            }
        }
        try validate(operation)
        return result
    }

    public func getEntitlements() -> [Entitlement] {
        locked {
            guard let user = try? NexusCoreUser.shared.getCurrentUser(),
                  let scope = try? storageScope() else { return [] }
            var state = loadState(key: storageKey(scope: scope, uid: user.uid))
            refreshEntitlements(&state, user: user)
            saveState(state, key: storageKey(scope: scope, uid: user.uid))
            return Array(state.entitlements.values)
        }
    }

    public func getPendingProductIds() -> Set<String> {
        locked {
            guard let user = try? NexusCoreUser.shared.getCurrentUser(),
                  let scope = try? storageScope() else { return [] }
            var state = loadState(key: storageKey(scope: scope, uid: user.uid))
            refreshEntitlements(&state, user: user)
            return pendingProducts(state).union(checkoutReservations[storageKey(scope: scope, uid: user.uid)]?.keys.map { $0 } ?? [])
        }
    }

    private func pendingProducts(_ state: PersistedEntitlementState) -> Set<String> {
        state.pendingProductIds.union(state.entitlements.values.filter(\.reconciliationPending).map(\.productId))
    }

    public func getWeeklyPointsInfo() async throws -> WeeklyPointsInfo {
        let operation = try await captureOperation()
        let result = try await operation.session.getWeeklyPointsInfo()
        try validate(operation)
        return result
    }

    public func getWeeklyPointsInfo(
        completion: @escaping @Sendable (CoreUserResult<WeeklyPointsInfo>) -> Void
    ) {
        Task {
            do { completion(.success(try await getWeeklyPointsInfo())) }
            catch { completion(.failure(error)) }
        }
    }

    public func claimWeeklyPoints() async throws -> WeeklyPointsClaimResult {
        try await claimWeeklyPoints(operation: captureOperation())
    }

    func claimWeeklyPoints(operation: PaymentOperation) async throws -> WeeklyPointsClaimResult {
        try validate(operation)
        let outcome: Result<WeeklyPointsClaimResult, Error>
        do {
            outcome = .success(try await operation.session.claimWeeklyPoints())
        } catch {
            outcome = .failure(error)
        }
        // Even an uncertain claim gets read-only reconciliation, never claim replay.
        try validate(operation)
        _ = try? await operation.session.fetchUserInfo()
        try validate(operation)
        _ = try? await operation.session.getWeeklyPointsInfo()
        try validate(operation)
        return try outcome.get()
    }

    public func claimWeeklyPoints(
        completion: @escaping @Sendable (CoreUserResult<WeeklyPointsClaimResult>) -> Void
    ) {
        Task {
            do {
                let operation = try await captureOperation()
                let result = try await claimWeeklyPoints(operation: operation)
                try validate(operation)
                completion(.success(result))
            }
            catch { completion(.failure(error)) }
        }
    }

    @available(*, deprecated, message: "The server selects the subscription; use claimWeeklyPoints()")
    public func claimWeeklyPoints(marketProductId: String?) async throws -> WeeklyPointsClaimResult {
        guard (marketProductId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PaymentError.invalidConfig("Weekly claim does not accept a product id")
        }
        return try await claimWeeklyPoints()
    }

    @available(*, deprecated, message: "The server selects the subscription; use claimWeeklyPoints(completion:)")
    public func claimWeeklyPoints(marketProductId: String?, completion: @escaping @Sendable (CoreUserResult<WeeklyPointsClaimResult>) -> Void) {
        guard (marketProductId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(PaymentError.invalidConfig("Weekly claim does not accept a product id")))
            return
        }
        claimWeeklyPoints(completion: completion)
    }

    public func showSubscriptionPage(config: SubscriptionPageConfig) {
        locked { activeSubscriptionPageConfig = config }
        dispatchSubscriptionPageEvent(pageEvent(name: .pageShow, state: .ready))
    }

    #if canImport(UIKit)
    public func showSubscriptionPage(presenting viewController: UIViewController, config: SubscriptionPageConfig) {
        locked { activeSubscriptionPageConfig = config }
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
        locked { activeSubscriptionPageConfig = nil }
    }

    @discardableResult
    public func onSubscriptionPageEvent(_ callback: @escaping (SubscriptionPageEvent) -> Void) -> () -> Void {
        let id = UUID()
        locked { subscriptionPageCallbacks[id] = callback }
        return { [weak self] in
            _ = self?.locked { self?.subscriptionPageCallbacks.removeValue(forKey: id) }
        }
    }

    private func verifyProviderPurchaseIfNeeded(provider: PaymentProvider, result: ProviderPurchaseResult, operation: PaymentOperation) async throws -> OrderVerificationResult {
        try validate(operation)
        guard provider.requiresServerVerification else {
            return OrderVerificationResult(
                tradeOrderId: result.orderId ?? "",
                status: .success,
                isSubscription: result.isSubscription,
                token: result.purchaseToken,
                platformProductId: result.platformProductId,
                startedTime: Int64(Date().timeIntervalSince1970),
                endsTime: nil,
                successCount: nil,
                amount: nil
            )
        }
        let orderVerificationAPI = OrderVerificationAPI { path, body in
            try await operation.session.post(path: path, body: body)
        }
        return try await orderVerificationAPI.verify(
            channel: result.channel,
            token: result.purchaseToken ?? "",
            platformProductId: result.platformProductId,
            isSubscription: result.isSubscription,
            tradeOrderId: result.orderId ?? "",
            originalTransactionId: result.rawData["original_transaction_id"].map { String(describing: $0.value) },
            expectedUid: operation.session.uid
        )
    }

    private func reportPurchaseRevenue(product: Product, orderId: String, channel: PaymentChannel, verification: OrderVerificationResult) {
        guard NexusGrowthAnalyticsAd.shared.isInitialized() else { return }
        _ = try? NexusGrowthAnalyticsAd.shared.reportPurchaseRevenue(PurchaseRevenuePayload(
            paymentChannel: growthPaymentChannel(channel),
            orderId: orderId,
            transactionId: verification.tradeOrderId,
            storeProductId: product.marketProductId,
            purchaseType: product.productType == .subscription ? .subscription : .oneTime,
            subscriptionPeriod: product.subscriptionPeriod,
            currency: verification.currency ?? product.currency ?? "USD",
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

    private func checkOwner(_ purchase: ProviderPurchaseResult, operation: PaymentOperation) throws {
        try validate(operation)
        if purchase.channel == .appStore {
            guard let owner = purchase.rawData["owner_uid"]?.value as? String,
                  let expected = AppStorePaymentProvider.accountToken(uid: operation.session.uid),
                  expected == UUID(uuidString: owner) else {
                throw PaymentError.apiError("App Store transaction does not belong to the current account")
            }
        }
    }

    private func pendingResult(product: Product, channel: PaymentChannel, orderId: String? = nil,
                               verification: OrderVerificationResult? = nil) -> PurchaseResult {
        PurchaseResult(channel: channel, product: product, success: false, orderId: orderId,
                       message: "Payment is pending confirmation. Do not purchase again.",
                       verification: verification, pending: true)
    }

    private func reconcile(_ purchase: ProviderPurchaseResult, provider: PaymentProvider,
                           operation: PaymentOperation, scheduleRetry: Bool = true) async throws -> PurchaseResult {
        try checkOwner(purchase, operation: operation)
        let key = pendingKey(purchase, operation)
        guard locked({ processingTransactions.insert(key).inserted }) else {
            return pendingResult(product: purchase.product, channel: purchase.channel, orderId: purchase.orderId)
        }
        defer { locked { if generation == operation.generation { processingTransactions.remove(key) } } }
        try updateState(operation) { state in
            state.pendingProductIds.insert(purchase.platformProductId)
            pendingPurchases[key] = purchase
        }
        let verification: OrderVerificationResult
        do {
            guard purchase.orderId != nil else { throw PaymentError.apiError("Missing store order id") }
            verification = try await verifyProviderPurchaseIfNeeded(provider: provider, result: purchase, operation: operation)
        } catch {
            try validate(operation)
            if scheduleRetry { scheduleReconciliation(operation) }
            return pendingResult(product: purchase.product, channel: purchase.channel, orderId: purchase.orderId)
        }
        try validate(operation)
        guard verification.isSuccessful || verification.isTerminal else {
            if scheduleRetry { scheduleReconciliation(operation) }
            return pendingResult(product: purchase.product, channel: purchase.channel,
                                 orderId: purchase.orderId, verification: verification)
        }
        // Revoked or unverified store transactions cannot be finished or granted as paid.
        let paid = verification.isSuccessful && purchase.success
        if verification.isSuccessful && !paid {
            return pendingResult(product: purchase.product, channel: purchase.channel, orderId: purchase.orderId)
        }
        var user: SDKUser?
        if provider.requiresServerVerification {
            user = try? await operation.session.fetchUserInfo()
            try validate(operation)
        }
        let entitlementId = purchase.product.entitlementId ?? purchase.platformProductId
        var entitlement = Entitlement(entitlementId: entitlementId, productId: purchase.platformProductId,
            orderId: purchase.orderId ?? "", channel: purchase.channel,
            startedTime: verification.startedTime, endsTime: verification.endsTime, active: paid)
        if purchase.isSubscription && provider.requiresServerVerification {
            entitlement.active = paid && authoritativeVIP(user) && !hasExpired(entitlement.endsTime)
            entitlement.reconciliationPending = paid && !entitlement.active
        }
        let recordedEntitlement = entitlement
        var newDelivery = false
        try updateState(operation) { state in
            newDelivery = paid && state.deliveredOrderIds.insert(deliveryId(for: purchase)).inserted
            if purchase.isSubscription && provider.requiresServerVerification {
                state.serverSubscriptionIds.insert(entitlementId)
                recordSubscription(purchase, entitlement: recordedEntitlement, terminal: verification.isTerminal,
                                   state: &state, user: user)
            } else {
                state.entitlements[entitlementId] = recordedEntitlement
            }
            pendingPurchases.removeValue(forKey: key)
            // Another unresolved renewal of this SKU must continue to block checkout.
            if !pendingPurchases.contains(where: { $0.key.hasPrefix(operation.storageKey + ".") && $0.value.platformProductId == purchase.platformProductId }) {
                state.pendingProductIds.remove(purchase.platformProductId)
            }
        }
        // Persist the verified delivery before finishing so interruption cannot strand
        // a pending marker after StoreKit has removed its only recoverable transaction.
        if paid {
            try validate(operation)
            await provider.completePurchase(purchase)
            try validate(operation)
        }
        if newDelivery {
            try validate(operation)
            reportPurchaseRevenue(product: purchase.product, orderId: purchase.orderId ?? "", channel: purchase.channel, verification: verification)
        }
        if entitlement.reconciliationPending && scheduleRetry { scheduleReconciliation(operation) }
        return PurchaseResult(channel: purchase.channel, product: purchase.product, success: paid,
                              orderId: purchase.orderId, message: "Order verification status: \(verification.status.rawValue)",
                              verification: verification, entitlement: newDelivery ? entitlement : nil)
    }

    /// Read-only retries of already-paid transactions and delayed membership maintenance.
    public func reconcilePendingPurchases() async throws {
        try await reconcilePendingPurchases(operation: captureOperation())
    }

    private func reconcilePendingPurchases(operation: PaymentOperation) async throws {
        try validate(operation)
        let pending = locked { pendingPurchases.filter { $0.key.hasPrefix(operation.storageKey + ".") }.map(\.value) }
        for purchase in pending {
            let provider = try provider(for: purchase.channel, operation: operation)
            _ = try await reconcile(purchase, provider: provider, operation: operation, scheduleRetry: false)
        }
        try validate(operation)
        let user = try? await operation.session.fetchUserInfo()
        try validate(operation)
        if let user { try updateState(operation) { refreshEntitlements(&$0, user: user) } }
    }

    private func scheduleReconciliation(_ operation: PaymentOperation) {
        locked {
            guard (try? validate(operation)) != nil else { return }
            if let existing = reconciliationTasks[operation.storageKey] {
                if (try? existing.session.validate()) != nil { return }
                existing.task.cancel()
            }
            let jobId = UUID()
            let task = Task { [weak self] in
                defer { self?.locked {
                    if self?.reconciliationTasks[operation.storageKey]?.id == jobId {
                        self?.reconciliationTasks.removeValue(forKey: operation.storageKey)
                    }
                } }
                for delay in [1, 3, 10] {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                        guard let self else { return }
                        try self.validate(operation)
                        try await self.reconcilePendingPurchases(operation: operation)
                    } catch { return }
                }
            }
            reconciliationTasks[operation.storageKey] = ReconciliationJob(id: jobId, session: operation.session, task: task)
        }
    }

    private func authoritativeVIP(_ user: SDKUser?) -> Bool {
        guard let user, user.userInfoSynced, user.isVip else { return false }
        return user.vipExpiredAt > Int64(Date().timeIntervalSince1970)
    }

    private func hasExpired(_ seconds: Int64?) -> Bool {
        seconds.map { $0 <= Int64(Date().timeIntervalSince1970) } ?? false
    }

    private func recordSubscription(_ purchase: ProviderPurchaseResult, entitlement: Entitlement, terminal: Bool,
                                    state: inout PersistedEntitlementState, user: SDKUser?) {
        let id = entitlement.entitlementId
        let originalId = purchase.rawData["original_transaction_id"].map { String(describing: $0.value) }
        let chainId = purchase.channel.rawValue + ":" + (originalId ?? purchase.orderId ?? deliveryId(for: purchase))
        var chains = state.subscriptionChains?[id] ?? [:]
        // Preserve pre-chain cache entries until verified store recovery identifies them.
        if chains.isEmpty, let previous = state.entitlements[id] {
            chains["legacy:" + previous.orderId] = SubscriptionChainState(
                transactionId: previous.orderId, transactionTime: previous.startedTime,
                entitlement: previous, terminal: state.revokedEntitlementIds.contains(id))
        }
        chains.removeValue(forKey: "legacy:" + entitlement.orderId)
        let date = (purchase.rawData["purchase_date"]?.value as? TimeInterval).map { Int64($0) }
        let incoming = SubscriptionChainState(transactionId: deliveryId(for: purchase),
            transactionTime: date ?? entitlement.startedTime, entitlement: entitlement, terminal: terminal)
        if let previous = chains[chainId] {
            if previous.transactionId == incoming.transactionId {
                // A replayed paid callback cannot undo a known terminal decision for that delivery.
                if !previous.terminal || incoming.terminal { chains[chainId] = incoming }
            } else if subscriptionOrder(previous, precedes: incoming) {
                chains[chainId] = incoming
            }
        } else {
            chains[chainId] = incoming
        }
        if state.subscriptionChains == nil { state.subscriptionChains = [:] }
        state.subscriptionChains?[id] = chains
        state.revokedEntitlementIds.remove(id)
        selectSubscription(id, state: &state, user: user)
    }

    private func subscriptionOrder(_ left: SubscriptionChainState, precedes right: SubscriptionChainState) -> Bool {
        if left.transactionTime != right.transactionTime {
            return (left.transactionTime ?? Int64.min) < (right.transactionTime ?? Int64.min)
        }
        if left.entitlement.endsTime != right.entitlement.endsTime {
            return (left.entitlement.endsTime ?? Int64.min) < (right.entitlement.endsTime ?? Int64.min)
        }
        // Stable tie break only; callback arrival order never determines the current chain.
        return left.transactionId.compare(right.transactionId, options: .numeric) == .orderedAscending
    }

    private func selectSubscription(_ id: String, state: inout PersistedEntitlementState, user: SDKUser?) {
        guard let chains = state.subscriptionChains?[id], !chains.isEmpty else { return }
        let eligible = chains.filter { !$0.value.terminal && !hasExpired($0.value.entitlement.endsTime) }
        let candidates = eligible.isEmpty ? chains : eligible
        guard let selected = candidates.max(by: {
            if subscriptionOrder($0.value, precedes: $1.value) { return true }
            if subscriptionOrder($1.value, precedes: $0.value) { return false }
            return $0.key < $1.key
        }) else { return }
        var entitlement = selected.value.entitlement
        entitlement.active = !selected.value.terminal && !hasExpired(entitlement.endsTime) && authoritativeVIP(user)
        if entitlement.active || selected.value.terminal || hasExpired(entitlement.endsTime) {
            entitlement.reconciliationPending = false
        }
        state.subscriptionChains?[id]?[selected.key]?.entitlement = entitlement
        state.entitlements[id] = entitlement
    }

    private func refreshEntitlements(_ state: inout PersistedEntitlementState, user: SDKUser) {
        for id in state.serverSubscriptionIds {
            if state.subscriptionChains?[id]?.isEmpty == false {
                selectSubscription(id, state: &state, user: user)
                continue
            }
            guard var entitlement = state.entitlements[id] else { continue }
            entitlement.active = !state.revokedEntitlementIds.contains(id) && authoritativeVIP(user) && !hasExpired(entitlement.endsTime)
            if entitlement.active || hasExpired(entitlement.endsTime) || state.revokedEntitlementIds.contains(id) {
                entitlement.reconciliationPending = false
            }
            state.entitlements[id] = entitlement
        }
    }

    private func observeAppStoreTransactions(_ provider: AppStorePaymentProvider) {
        let observedGeneration = generation
        provider.observeTransactions { [weak self] result in
            guard let self else { return false }
            do {
                _ = try await self.handleTransactionUpdate(result, provider: provider, observedGeneration: observedGeneration)
            } catch { /* Keep foreign, stale, and unverified transactions unfinished. */ }
            // Reconciliation owns finishing, shared with purchase and restore.
            return false
        }
    }

    func handleTransactionUpdate(_ result: ProviderPurchaseResult, provider: PaymentProvider,
                                 observedGeneration: UUID) async throws -> PurchaseResult {
        let operation = try await captureOperation()
        guard operation.generation == observedGeneration else { throw CoreUserError.sessionChanged }
        return try await reconcile(result, provider: provider, operation: operation)
    }

    func dispatchSubscriptionPageEvent(_ event: SubscriptionPageEvent) {
        let callbacks = locked { Array(subscriptionPageCallbacks.values) }
        callbacks.forEach { $0(event) }
        if NexusGrowthAnalyticsAd.shared.isInitialized() {
            _ = try? NexusGrowthAnalyticsAd.shared.reportPurchaseEvent(event.name.rawValue, payload: event.analyticsParams())
        }
    }

    private func requireConfig() throws -> PaymentConfig {
        try locked {
            guard let config else { throw PaymentError.notInitialized }
            return config
        }
    }

    func subscriptionPageWasDismissed() {
        subscriptionPageViewController = nil
        locked { activeSubscriptionPageConfig = nil }
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

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try operation()
    }

    func captureOperation() async throws -> PaymentOperation {
        let (capturedGeneration, scope) = try locked { (generation, try storageScope()) }
        let session = try await NexusCoreUser.shared.captureAuthenticatedSession()
        let operation = PaymentOperation(generation: capturedGeneration, scope: scope, session: session,
                                         storageKey: storageKey(scope: scope, uid: session.uid))
        try validate(operation)
        return operation
    }

    func validate(_ operation: PaymentOperation) throws {
        try locked {
            guard generation == operation.generation, try storageScope() == operation.scope else { throw CoreUserError.sessionChanged }
            try operation.session.validate()
        }
    }

    private func provider(for channel: PaymentChannel, operation: PaymentOperation) throws -> PaymentProvider {
        try locked {
            try validate(operation)
            guard try requireConfig().enabledChannels.contains(channel) || channel == .mock else {
                throw PaymentError.channelDisabled("Payment channel is disabled: \(channel.rawValue)")
            }
            guard let provider = providers[channel] else {
                throw PaymentError.providerNotRegistered("Payment provider is not registered for \(channel.rawValue)")
            }
            return provider
        }
    }

    private func storageScope() throws -> String {
        let payment = try requireConfig()
        let core = try NexusCoreUser.shared.getSdkConfig()
        return try JSONEncoder().encode([core.apiBaseUrl, core.productId, payment.productId]).base64EncodedString()
    }

    private func storageKey(scope: String, uid: String) -> String {
        "nexus.payment.v2.\(scope).\(Data(uid.utf8).base64EncodedString())"
    }

    private func pendingKey(_ purchase: ProviderPurchaseResult, _ operation: PaymentOperation) -> String {
        operation.storageKey + "." + purchase.channel.rawValue + "." + deliveryId(for: purchase)
    }

    private func loadState(_ operation: PaymentOperation) -> PersistedEntitlementState {
        loadState(key: operation.storageKey)
    }

    private func loadState(key: String) -> PersistedEntitlementState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(PersistedEntitlementState.self, from: data)
        else { return PersistedEntitlementState() }
        return state
    }

    private func saveState(_ state: PersistedEntitlementState, _ operation: PaymentOperation) {
        saveState(state, key: operation.storageKey)
        Task { @MainActor [weak self] in
            guard let self, (try? self.validate(operation)) != nil else { return }
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        }
    }

    private func saveState(_ state: PersistedEntitlementState, key: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func updateState(_ operation: PaymentOperation, _ update: (inout PersistedEntitlementState) -> Void) throws {
        try locked {
            try validate(operation)
            var state = loadState(operation)
            update(&state)
            saveState(state, operation)
        }
    }

    private func pageEvent(
        name: SubscriptionPageEventName,
        productId: String? = nil,
        paymentChannel: PaymentChannel? = nil,
        state: SubscriptionPageState? = nil,
        params: [String: Any?] = [:]
    ) -> SubscriptionPageEvent {
        var values = params
        if let config = locked({ activeSubscriptionPageConfig }) {
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
    var pendingProductIds: Set<String> = []
    var serverSubscriptionIds: Set<String> = []
    var revokedEntitlementIds: Set<String> = []
    var subscriptionChains: [String: [String: SubscriptionChainState]]?
}

private struct SubscriptionChainState: Codable {
    let transactionId: String
    let transactionTime: Int64?
    var entitlement: Entitlement
    let terminal: Bool
}

struct PaymentOperation: Sendable {
    let generation: UUID
    let scope: String
    let session: CoreUserSessionContext
    let storageKey: String
}

private struct ReconciliationJob {
    let id: UUID
    let session: CoreUserSessionContext
    let task: Task<Void, Never>
}

final class ProductAPI: Sendable {
    private let post: AuthenticatedPaymentPost

    init(post: @escaping AuthenticatedPaymentPost = { path, body in
        try await NexusCoreUser.shared.postAuthenticated(path: path, body: body)
    }) {
        self.post = post
    }

    func getProducts() async throws -> [Product] {
        try ProductParser.parse(await post("/api/v1/iap/products", Data("{}".utf8)))
    }
}

enum ProductParser {
    static func parse(_ body: String) throws -> [Product] {
        try parse(Data(body.utf8))
    }

    static func parse(_ data: Data) throws -> [Product] {
        // Decode Decimal directly from JSON bytes, never through Double/JSONSerialization.
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.list.enumerated()
            .filter { !$0.element.market_product_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                let lhs = $0.element.sort ?? 0
                let rhs = $1.element.sort ?? 0
                return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
            }
            .map { _, item in
                let coins = item.coins_granted ?? 0
                let type: ProductType = item.product_type == 2 ? .subscription
                    : item.product_type == 1 ? (coins > 0 ? .consumable : .iap) : .unknown
                return Product(
                    marketProductId: item.market_product_id,
                    name: item.name ?? "",
                    description: item.description ?? "",
                    productType: type,
                    weeklyPointsEnabled: item.weekly_points_enabled == 1,
                    coinsGrantedDecimal: coins,
                    weeklyPointsDecimal: item.weekly_points ?? 0,
                    priceUsd: item.price_usd,
                    sort: item.sort ?? 0
                )
            }
    }

    private struct Response: Decodable {
        let list: [Item]
    }

    private struct Item: Decodable {
        let market_product_id: String
        let name: String?
        let description: String?
        let product_type: Int?
        let coins_granted: Decimal?
        let weekly_points_enabled: Int?
        let weekly_points: Decimal?
        let price_usd: Int?
        let sort: Int?
    }
}
