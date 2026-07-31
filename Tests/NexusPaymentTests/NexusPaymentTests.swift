import XCTest
import NexusCoreUser
@testable import NexusPayment

final class NexusPaymentTests: XCTestCase {
    func testSubscriptionPageRequiresUrlsWhenEnabled() throws {
        XCTAssertThrowsError(try SubscriptionPageConfig(showTerms: true))
        XCTAssertThrowsError(try SubscriptionPageConfig(showPrivacy: true))
        XCTAssertNoThrow(try SubscriptionPageConfig(showTerms: true, showPrivacy: true, termsUrl: "https://example.com/t", privacyUrl: "https://example.com/p"))
    }

    func testProductParserReadsApiList() throws {
        let body = #"{"code":1,"data":{"list":[{"market_product_id":"vip_month","name":"VIP Monthly","description":"Pro","product_type":2,"coins_granted":100,"price":"9.99","currency":"USD","benefits":["A","B"]}]}}"#
        let products = try ProductParser.parse(body)

        XCTAssertEqual(products.first?.marketProductId, "vip_month")
        XCTAssertEqual(products.first?.productType, .subscription)
        XCTAssertEqual(products.first?.coinsGranted, 100)
        XCTAssertEqual(products.first?.benefits, ["A", "B"])
    }

    func testMockPurchaseGrantsEntitlement() async throws {
        let core = NexusCoreUser.shared
        core.initialize(config: try CoreUserConfig(productId: "pay-test", productName: "demo", accountName: "test-account", apiBaseUrl: "https://example.com", encrypt: false))
        UserDefaults.standard.set(
            try JSONEncoder().encode(SDKUser(uid: "pay-user", deviceId: try core.getDeviceId())),
            forKey: "nexus.coreuser.pay-test.user"
        )
        let sdk = NexusPayment.shared
        sdk.initialize(config: try PaymentConfig(productId: "pay-test", defaultChannel: .mock, enabledChannels: [.mock]))
        let product = Product(marketProductId: "coins_100", name: "100 Coins", productType: .iap, coinsGranted: 100)

        let result = try await sdk.mockPurchase(product: product)

        XCTAssertTrue(result.success)
        XCTAssertEqual(sdk.getEntitlements().first?.productId, "coins_100")
    }
}
