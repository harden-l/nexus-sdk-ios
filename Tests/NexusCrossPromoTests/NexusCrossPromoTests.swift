import XCTest
@testable import NexusCoreUser
import NexusGrowthAnalyticsAd
@testable import NexusCrossPromo

final class NexusCrossPromoTests: XCTestCase {
    func testIncomingLinkAndFlushUserLink() throws {
        let core = NexusCoreUser.shared
        core.initialize(config: try CoreUserConfig(productId: "target", productName: "demo", accountName: "test-account", apiBaseUrl: "https://example.com", encrypt: false))
        try core.clearLocalSession()
        let storageUser = SDKUser(uid: "target-uid", deviceId: try core.getDeviceId(), email: "user@example.com")
        let storage = CoreUserStorage(productId: "target", apiBaseUrl: "https://example.com")
        try storage.saveSession(LoginSession(uid: "target-uid", token: "test-token", expiresAt: 4102444800, loginType: .guest))
        storage.saveUser(storageUser)
        defer { try? core.clearLocalSession() }

        let sdk = NexusCrossPromo.shared
        sdk.initialize(config: try CrossPromoConfig(sourceProductId: "target"))
        let result = try sdk.handleIncomingPromoLink("nexus://promo?click_id=c1&source_product_id=source&target_product_id=target&source_uid=u0&source_device_id=d0")

        XCTAssertEqual(result.clickId, "c1")
        let payload = try sdk.flushPendingAttributionAfterLogin()
        XCTAssertEqual(payload?.sourceProductId, "source")
        XCTAssertEqual(payload?.targetUid, "target-uid")
        XCTAssertNil(sdk.getPendingAttribution())
    }

    func testShowPromoPageStoresDescription() throws {
        let sdk = NexusCrossPromo.shared
        sdk.initialize(config: try CrossPromoConfig(sourceProductId: "1"))
        try sdk.showPromoPage(options: ShowPromoPageOptions(title: "Apps", description: "More tools"))
        XCTAssertEqual(sdk.getActivePageOptions().description, "More tools")
    }

    func testOpenProductUsesIosSchemeBeforeStoreUrl() async throws {
        let opener = RecordingURLOpener()
        let sdk = NexusCrossPromo.shared
        sdk.initialize(config: try CrossPromoConfig(sourceProductId: "1"), urlOpener: opener)
        sdk.setProductsForTesting([
            try CrossPromoProduct(productId: "2", title: "Target", iosScheme: "targetapp", storeUrl: "https://apps.apple.com/app/id123")
        ])

        let opened = try await sdk.openProduct(OpenProductOptions(productId: "2"))

        XCTAssertTrue(opened)
        XCTAssertEqual(opener.opened.first?.scheme, "targetapp")
    }
}

private final class RecordingURLOpener: CrossPromoURLOpener, @unchecked Sendable {
    var opened: [URL] = []

    func canOpen(url: URL) -> Bool {
        url.scheme == "targetapp"
    }

    func open(url: URL) -> Bool {
        opened.append(url)
        return true
    }
}
