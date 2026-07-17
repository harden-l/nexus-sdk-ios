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

        let event = try sdk.track("ad_impression", params: ["ad_format": "banner"])

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
}
