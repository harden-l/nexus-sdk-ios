import XCTest
import NexusCoreUser
@testable import NexusGrowthAnalyticsAd

final class NexusGrowthAnalyticsAdTests: XCTestCase {
    func testTrackMergesUserAndProperties() throws {
        let provider = MockAnalyticsProvider(name: "bi")
        let sdk = NexusGrowthAnalyticsAd.shared
        sdk.initialize(config: try AnalyticsConfig(productId: "7", enableFirebase: false, enableAppsflyer: false), providers: [provider])
        sdk.setUser(SDKUser(uid: "u1", deviceId: "d1"))
        sdk.setUserProperties(["level": 3])

        let event = try sdk.track("page_view", params: ["page": "home"])

        XCTAssertEqual(event.uid, "u1")
        XCTAssertEqual(event.params["level"]?.description, "3")
        XCTAssertEqual(provider.events.count, 1)
    }

    func testDeepLinkCreatesInstallSource() {
        let sdk = NexusGrowthAnalyticsAd.shared
        let result = sdk.handleDeepLink("nexus://open?utm_source=af&utm_campaign=c1&deep_link_value=target")

        XCTAssertEqual(result.source, "af")
        XCTAssertEqual(sdk.getInstallSource()?.campaign, "c1")
        XCTAssertEqual(sdk.getLastDeepLink()?.deepLinkValue, "target")
    }

    func testAttributionParamsCreateInstallSource() {
        let sdk = NexusGrowthAnalyticsAd.shared
        let attribution = sdk.handleAttribution(params: [
            "media_source": "appsflyer",
            "campaign": "cross_promo",
            "af_adset": "set1",
            "deep_link_value": "target"
        ])

        XCTAssertEqual(attribution.mediaSource, "appsflyer")
        XCTAssertEqual(attribution.campaign, "cross_promo")
        XCTAssertEqual(sdk.getInstallSource()?.adset, "set1")
    }

    func testPurchaseRevenueIsDeduped() throws {
        let provider = MockAnalyticsProvider(name: "bi")
        let sdk = NexusGrowthAnalyticsAd.shared
        sdk.initialize(config: try AnalyticsConfig(productId: "7", enableFirebase: false, enableAppsflyer: false), providers: [provider])
        let payload = try PurchaseRevenuePayload(paymentChannel: .appStore, orderId: "o1", transactionId: "t1", storeProductId: "sku", purchaseType: .subscription, currency: "USD", revenue: 1.99)

        XCTAssertNotNil(try sdk.reportPurchaseRevenue(payload))
        XCTAssertNil(try sdk.reportPurchaseRevenue(payload))
    }

    func testShowWithoutCachePreloadsAndOnlyActualShowConsumesFrequency() throws {
        let sdk = NexusGrowthAnalyticsAd.shared
        sdk.initialize(
            config: try AnalyticsConfig(productId: "ad-state-test", enableFirebase: false, enableAppsflyer: false),
            providers: [],
            adProvider: MockAdProvider()
        )
        let placement = try AdPlacement(
            placement: "screen_a",
            adUnitId: "shared-unit",
            format: .interstitial,
            frequencyCap: 1
        )
        let callbacks = RecordingAdCallbacks()

        try sdk.showAd(placement, callbacks: callbacks)
        try sdk.showAd(placement, callbacks: callbacks)
        try sdk.showAd(placement, callbacks: callbacks)

        XCTAssertEqual(callbacks.shownPlacements, ["screen_a"])
        XCTAssertEqual(callbacks.failureCount, 2)
    }

    func testMockCacheIsSharedByFormatAndAdUnitId() throws {
        let provider = MockAdProvider()
        let first = try AdPlacement(placement: "screen_a", adUnitId: "shared-unit", format: .interstitial)
        let second = try AdPlacement(placement: "screen_b", adUnitId: "shared-unit", format: .interstitial)
        let callbacks = RecordingAdCallbacks()

        provider.loadAd(first, callbacks: nil)
        provider.showAd(second, callbacks: callbacks)

        XCTAssertEqual(callbacks.shownPlacements, ["screen_b"])
        XCTAssertEqual(callbacks.failureCount, 0)
    }
}

private final class RecordingAdCallbacks: AdCallbacks, @unchecked Sendable {
    var shownPlacements: [String] = []
    var failureCount = 0

    func onShown(_ placement: AdPlacement) {
        shownPlacements.append(placement.placement)
    }

    func onFailed(_ placement: AdPlacement, error: Error) {
        failureCount += 1
    }
}
