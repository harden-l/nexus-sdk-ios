import Foundation
import NexusCoreUser
#if canImport(UIKit)
import UIKit
#endif

public final class NexusGrowthAnalyticsAd: @unchecked Sendable {
    public static let shared = NexusGrowthAnalyticsAd()
    public static let version = "0.0.8"

    private var config: AnalyticsConfig?
    private var currentUser: SDKUser?
    private var providers: [AnalyticsProvider] = []
    private var adProvider: AdProvider = MockAdProvider()
    private let frequencyController = AdFrequencyController()
    private let attributionStorage = AttributionStorage()
    private var userProperties: [String: Any?] = [:]
    private var reportedPurchaseKeys = Set<String>()

    private init() {}

    public func initialize(config: AnalyticsConfig, providers: [AnalyticsProvider]? = nil, adProvider: AdProvider? = nil) {
        self.config = config
        self.providers = providers ?? defaultProviders(config)
        self.adProvider = adProvider ?? MockAdProvider()
        self.reportedPurchaseKeys.removeAll()
        self.frequencyController.reset()
        debugLog("initialized providers=\(self.providers.map(\.name))")
    }

    public func setUser(_ user: SDKUser?) {
        currentUser = user
        providers.forEach { ($0 as? UserIdentityAnalyticsProvider)?.setUserId(user?.uid) }
    }

    public func setUserProperties(_ properties: [String: Any?]) {
        userProperties.merge(properties) { _, new in new }
        providers.forEach { ($0 as? UserPropertiesAnalyticsProvider)?.setUserProperties(userProperties) }
    }

    public func getInstallSource() -> AttributionData? {
        attributionStorage.getInstallSource()
    }

    public func getLastDeepLink() -> DeepLinkResult? {
        attributionStorage.getLastDeepLink()
    }

    @discardableResult
    public func handleDeepLink(_ url: String) -> DeepLinkResult {
        let result = DeepLinkParser.parse(url)
        attributionStorage.saveDeepLink(result)
        return result
    }

    @discardableResult
    public func handleAttribution(params: [String: Any?]) -> AttributionData {
        let stringParams = params.reduce(into: [String: String]()) { result, item in
            guard let value = item.value else { return }
            result[item.key] = "\(value)"
        }
        let data = DeepLinkParser.attribution(from: stringParams)
        attributionStorage.saveInstallSource(data)
        debugLog("attribution source=\(data.source ?? "-") campaign=\(data.campaign ?? "-")")
        return data
    }

    @discardableResult
    public func track(_ eventName: String, params: [String: Any?] = [:]) throws -> AnalyticsEvent {
        let config = try requireConfig()
        let event = AnalyticsEvent(
            eventName: eventName,
            uid: currentUser?.uid,
            deviceId: currentUser?.deviceId,
            productId: config.productId,
            platform: config.platform,
            timestamp: nowMillis(),
            params: userProperties.merging(params) { _, new in new }
        )
        debugLog("track event=\(eventName) params=\(event.params)")
        providers.forEach { $0.track(event) }
        return event
    }

    public func flush() {
        providers.forEach { $0.flush() }
    }

    public func getProviders() -> [AnalyticsProvider] {
        providers
    }

    public func isInitialized() -> Bool {
        config != nil
    }

    public func loadAd(_ placement: AdPlacement, callbacks: AdCallbacks? = nil) throws {
        try track("ad_load", params: placement.eventParams())
        adProvider.loadAd(placement, callbacks: callbacks)
    }

    public func showAd(_ placement: AdPlacement, callbacks: AdCallbacks? = nil) throws {
        guard frequencyController.canShow(placement) else {
            try track("ad_frequency_block", params: placement.eventParams())
            callbacks?.onFailed(placement, error: GrowthAnalyticsError.providerUnsupported("Frequency cap reached for \(placement.placement)"))
            return
        }
        try track("ad_show", params: placement.eventParams())
        adProvider.showAd(
            placement,
            callbacks: ShownTrackingAdCallbacks(
                downstream: callbacks,
                onShown: { [weak self] in self?.frequencyController.recordShown(placement) }
            )
        )
    }

    #if canImport(UIKit)
    public func loadBanner(_ placement: AdPlacement, container: UIView, callbacks: AdCallbacks? = nil) throws {
        try track("ad_load", params: placement.eventParams())
        adProvider.loadBanner(placement, container: container, callbacks: callbacks)
    }

    public func loadNative(_ placement: AdPlacement, callbacks: NativeAdCallbacks?) throws {
        try track("ad_load", params: placement.eventParams())
        adProvider.loadNative(placement, callbacks: callbacks)
    }
    #endif

    @discardableResult
    public func reportAdRevenue(_ payload: AdRevenuePayload) throws -> AnalyticsEvent {
        try track("ad_revenue", params: [
            "revenue_type": "ad",
            "ad_platform": payload.adPlatform,
            "mediation_platform": payload.mediationPlatform,
            "ad_unit_id": payload.adUnitId,
            "placement": payload.placement,
            "ad_format": payload.adFormat.rawValue,
            "currency": payload.currency,
            "revenue": payload.revenue,
            "country": payload.country,
            "network_name": payload.networkName,
            "network_firm_id": payload.networkFirmId,
            "scene": payload.scene,
            "precision": payload.precision
        ])
    }

    @discardableResult
    public func reportPurchaseRevenue(_ payload: PurchaseRevenuePayload) throws -> AnalyticsEvent? {
        guard reportedPurchaseKeys.insert(payload.dedupeKey()).inserted else { return nil }
        return try track("purchase_revenue", params: [
            "revenue_type": payload.paymentChannel.rawValue,
            "payment_channel": payload.paymentChannel.rawValue,
            "order_id": payload.orderId,
            "transaction_id": payload.transactionId,
            "store_product_id": payload.storeProductId,
            "purchase_type": payload.purchaseType.rawValue,
            "subscription_period": payload.subscriptionPeriod,
            "currency": payload.currency,
            "revenue": payload.revenue,
            "country": payload.country,
            "is_trial": payload.isTrial,
            "is_renewal": payload.isRenewal
        ])
    }

    @discardableResult
    public func reportPurchaseEvent(_ eventName: String, payload: [String: Any?]) throws -> AnalyticsEvent {
        try track(eventName, params: payload)
    }

    private func defaultProviders(_ config: AnalyticsConfig) -> [AnalyticsProvider] {
        var providers: [AnalyticsProvider] = []
        if config.enableBI { providers.append(PersistentQueuedAnalyticsProvider(wrapped: MockAnalyticsProvider(name: "bi"), productId: config.productId, maxSize: config.queueMaxSize)) }
        if config.enableFirebase { providers.append(PersistentQueuedAnalyticsProvider(wrapped: MockAnalyticsProvider(name: "firebase"), productId: config.productId, maxSize: config.queueMaxSize)) }
        if config.enableAppsflyer { providers.append(PersistentQueuedAnalyticsProvider(wrapped: MockAnalyticsProvider(name: "appsflyer"), productId: config.productId, maxSize: config.queueMaxSize)) }
        return providers
    }

    private func requireConfig() throws -> AnalyticsConfig {
        guard let config else { throw GrowthAnalyticsError.notInitialized }
        return config
    }

    private func debugLog(_ message: String) {
        if config?.debug == true {
            print("[NexusGrowthAnalyticsAd] \(message)")
        }
    }
}

private final class ShownTrackingAdCallbacks: AdCallbacks, @unchecked Sendable {
    private let downstream: AdCallbacks?
    private let onShownHandler: @Sendable () -> Void

    init(downstream: AdCallbacks?, onShown: @escaping @Sendable () -> Void) {
        self.downstream = downstream
        self.onShownHandler = onShown
    }

    func onLoaded(_ placement: AdPlacement) {
        downstream?.onLoaded(placement)
    }

    func onShown(_ placement: AdPlacement) {
        onShownHandler()
        downstream?.onShown(placement)
    }

    func onClicked(_ placement: AdPlacement) {
        downstream?.onClicked(placement)
    }

    func onClosed(_ placement: AdPlacement) {
        downstream?.onClosed(placement)
    }

    func onReward(_ placement: AdPlacement) {
        downstream?.onReward(placement)
    }

    func onFailed(_ placement: AdPlacement, error: Error) {
        downstream?.onFailed(placement, error: error)
    }
}
