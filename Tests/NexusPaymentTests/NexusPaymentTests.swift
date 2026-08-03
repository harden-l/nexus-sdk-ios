import Foundation
import XCTest
import NexusCoreUser
@testable import NexusPayment

final class NexusPaymentTests: XCTestCase {
    func testCoinAmountFormatterUsesSubscriptionDisplayScale() {
        XCTAssertEqual(CoinAmountFormatter.displayText(20), "2000")
        XCTAssertEqual(CoinAmountFormatter.displayText(20.25), "2025")
        XCTAssertEqual(CoinAmountFormatter.displayText(0.125), "12.5")
    }

    func testSubscriptionPageLegalLinkDefaultsAndValidation() throws {
        let config = try SubscriptionPageConfig()
        XCTAssertTrue(config.showTerms)
        XCTAssertTrue(config.showPrivacy)
        XCTAssertEqual(config.termsUrl, SubscriptionPageConfig.defaultTermsUrl)
        XCTAssertEqual(config.privacyUrl, SubscriptionPageConfig.defaultPrivacyUrl)

        XCTAssertThrowsError(try SubscriptionPageConfig(showTerms: true, termsUrl: ""))
        XCTAssertThrowsError(try SubscriptionPageConfig(showPrivacy: true, privacyUrl: ""))
        XCTAssertNoThrow(try SubscriptionPageConfig(showTerms: true, showPrivacy: true, termsUrl: "https://example.com/t", privacyUrl: "https://example.com/p"))
        XCTAssertNoThrow(try SubscriptionPageConfig(showTerms: false, showPrivacy: false, termsUrl: "", privacyUrl: ""))
    }

    func testPaymentConfigValidatesChannels() throws {
        XCTAssertThrowsError(try PaymentConfig(
            productId: "pay-test",
            enabledChannels: [.appStore, .appStore]
        ))
        XCTAssertThrowsError(try PaymentConfig(
            productId: "pay-test",
            fallbackChannels: [.stripe]
        ))
        XCTAssertThrowsError(try PaymentRule(
            enabledChannels: [.appStore],
            defaultChannel: .appStore,
            fallbackChannels: [.stripe]
        ))
    }

    func testPaymentRuleMatchesVersionAndIgnoresCase() throws {
        let sdk = NexusPayment.shared
        let rule = try PaymentRule(
            country: "us",
            platform: "IOS",
            minVersion: "2.1.0",
            enabledChannels: [.mock],
            defaultChannel: .mock
        )
        sdk.initialize(config: try PaymentConfig(productId: "pay-test", rules: [rule]))

        XCTAssertEqual(
            try sdk.resolvePaymentChannel(context: PaymentContext(country: "US", platform: "ios", appVersion: "2.0.9")).defaultChannel,
            .appStore
        )
        XCTAssertEqual(
            try sdk.resolvePaymentChannel(context: PaymentContext(country: "US", platform: "ios", appVersion: "2.1")).defaultChannel,
            .mock
        )
    }

    func testProductParserReadsApiList() throws {
        let body = #"{"code":1,"data":{"list":[{"market_product_id":"vip_month","name":"VIP Monthly","description":"Pro","product_type":2,"coins_granted":100.25,"price":"9.99","currency":"USD","benefits":["A","B"]}]}}"#
        let products = try ProductParser.parse(body)

        XCTAssertEqual(products.first?.marketProductId, "vip_month")
        XCTAssertEqual(products.first?.productType, .subscription)
        XCTAssertEqual(products.first?.coinsGranted, 100.25)
        XCTAssertEqual(products.first?.benefits, ["A", "B"])
    }

    func testProductParserTreatsCoinProductAsConsumable() throws {
        let body = #"{"code":1,"data":{"list":[{"market_product_id":"coins_100","name":"100 Coins","product_type":1,"coins_granted":100}]}}"#

        let products = try ProductParser.parse(body)

        XCTAssertEqual(products.first?.productType, .consumable)
    }

    func testProductApiLoadsIapList() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductURLProtocol.self]
        let session = URLSession(configuration: configuration)
        ProductURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/m/v7/iap/list")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Encrypt"), "0")
            let body = #"{"code":1,"data":{"list":[{"market_product_id":"vip_month","name":"VIP Monthly","product_type":2,"coins_granted":100.25}]}}"#
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
        defer { ProductURLProtocol.requestHandler = nil }

        let coreConfig = try CoreUserConfig(
            productId: "7",
            productName: "TEST PRODUCT",
            accountName: "test",
            apiBaseUrl: "https://example.com",
            encrypt: false
        )
        let products = try await ProductAPI(config: coreConfig, session: session).getProducts()

        XCTAssertEqual(products.first?.marketProductId, "vip_month")
        XCTAssertEqual(products.first?.coinsGranted, 100.25)
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

    func testEntitlementsPersistAcrossInitializationAndAreUserScoped() async throws {
        let productId = "payment-persistence-\(UUID().uuidString)"
        let userKey = "nexus.coreuser.\(productId).user"
        let userA = "payment-user-a"
        let userB = "payment-user-b"
        let entitlementKeyA = "nexus.payment.\(productId).entitlements.\(userA)"
        let entitlementKeyB = "nexus.payment.\(productId).entitlements.\(userB)"
        defer {
            UserDefaults.standard.removeObject(forKey: userKey)
            UserDefaults.standard.removeObject(forKey: entitlementKeyA)
            UserDefaults.standard.removeObject(forKey: entitlementKeyB)
        }

        let core = NexusCoreUser.shared
        core.initialize(config: try CoreUserConfig(
            productId: productId,
            productName: "demo",
            accountName: "test-account",
            apiBaseUrl: "https://example.com",
            encrypt: false
        ))
        let deviceId = try core.getDeviceId()
        func selectUser(_ uid: String) throws {
            UserDefaults.standard.set(
                try JSONEncoder().encode(SDKUser(uid: uid, deviceId: deviceId)),
                forKey: userKey
            )
        }

        try selectUser(userA)
        let sdk = NexusPayment.shared
        let paymentConfig = try PaymentConfig(productId: productId, defaultChannel: .mock, enabledChannels: [.mock])
        sdk.initialize(config: paymentConfig)
        let product = Product(marketProductId: "premium", name: "Premium", productType: .iap)
        _ = try await sdk.mockPurchase(product: product)
        XCTAssertEqual(sdk.getEntitlements().map(\.productId), ["premium"])

        sdk.initialize(config: paymentConfig)
        XCTAssertEqual(sdk.getEntitlements().map(\.productId), ["premium"])

        try selectUser(userB)
        XCTAssertTrue(sdk.getEntitlements().isEmpty)

        try selectUser(userA)
        XCTAssertEqual(sdk.getEntitlements().map(\.productId), ["premium"])
    }

    func testAppStoreRenewalsUseUniqueTransactionIdForDelivery() throws {
        let sdk = NexusPayment.shared
        let product = Product(marketProductId: "premium_monthly", name: "Premium", productType: .subscription)
        let first = ProviderPurchaseResult(
            channel: .appStore,
            product: product,
            success: true,
            orderId: "original_transaction",
            purchaseToken: "jws-1",
            platformProductId: product.marketProductId,
            isSubscription: true,
            message: nil,
            rawData: ["transaction_id": AnySendableValue(UInt64(101))]
        )
        let renewal = ProviderPurchaseResult(
            channel: .appStore,
            product: product,
            success: true,
            orderId: "original_transaction",
            purchaseToken: "jws-2",
            platformProductId: product.marketProductId,
            isSubscription: true,
            message: nil,
            rawData: ["transaction_id": AnySendableValue(UInt64(102))]
        )

        XCTAssertEqual(sdk.deliveryId(for: first), "101")
        XCTAssertEqual(sdk.deliveryId(for: renewal), "102")
        XCTAssertNotEqual(sdk.deliveryId(for: first), sdk.deliveryId(for: renewal))
    }
}

private final class ProductURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.requestHandler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
