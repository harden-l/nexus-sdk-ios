import XCTest
@testable import NexusCoreUser

final class NexusCoreUserTests: XCTestCase {
    func testVersionAndConfigDefaults() throws {
        let config = try CoreUserConfig(productId: "7", productName: "demo", apiBaseUrl: "https://example.com", encrypt: false)
        XCTAssertEqual(NexusCoreUser.version, "0.0.6")
        XCTAssertEqual(config.version.isEmpty, false)
        XCTAssertEqual(config.country.isEmpty, false)
        XCTAssertEqual(config.language.isEmpty, false)
        XCTAssertEqual(config.accountName, "test")
        XCTAssertNil(config.gt)
    }

    func testConfigRejectsBlankAccountName() {
        XCTAssertThrowsError(
            try CoreUserConfig(
                productId: "7",
                productName: "demo",
                accountName: " ",
                apiBaseUrl: "https://example.com",
                encrypt: false
            )
        )
    }

    func testEncryptionMatchesServerExample() throws {
        let encrypted = try APIRequestEncryption.encryptString(
            #"{"status":1,"hotUpdateUrl":""}"#,
            key: "1b8df48c1fa64ce28a2e8133dffe600c"
        )
        XCTAssertEqual(String(data: encrypted, encoding: .utf8), "n+JgfkzArtm/JTkQQj1tZa6pMAucAqMU2RqMZ/6uq3o=")
        let decrypted = try APIRequestEncryption.decryptString(
            "n+JgfkzArtm/JTkQQj1tZa6pMAucAqMU2RqMZ/6uq3o=",
            key: "1b8df48c1fa64ce28a2e8133dffe600c"
        )
        XCTAssertEqual(decrypted, #"{"status":1,"hotUpdateUrl":""}"#)
    }

    func testSilentLoginStoresUserAndDynamicConfig() async throws {
        MockURLProtocol.responses = [
            "/m/v7/user/login": #"{"code":1,"message":"success","data":{"uid":"u1","feature":"on","coins":10}}"#,
            "/m/v7/user/info": #"{"code":1,"message":"success","data":{"uid":"u1","email":"user@example.com","phone":"","email_bound":true,"phone_bound":false,"balance":88.75}}"#
        ]
        let session = URLSession(configuration: .mock)
        let sdk = NexusCoreUser.shared
        sdk.initialize(config: try CoreUserConfig(productId: "core-test", productName: "demo", accountName: "test-account", apiBaseUrl: "https://unit.test", encrypt: false), session: session)
        try sdk.clearLocalSession()

        let user = try await sdk.silentLogin()

        XCTAssertEqual(user.uid, "u1")
        XCTAssertEqual(user.balance, 88.75)
        XCTAssertEqual(try sdk.getConfig()["feature"] as? String, "on")
        XCTAssertNil(try sdk.getConfig()["uid"])
    }

    func testSilentLoginSendsGrantTierCodeWhenConfigured() async throws {
        MockURLProtocol.responses = [
            "/m/v7/user/login": #"{"code":1,"message":"success","data":{"uid":"u2"}}"#,
            "/m/v7/user/info": #"{"code":1,"message":"success","data":{"uid":"u2","email":"","phone":"","email_bound":false,"phone_bound":false,"balance":0}}"#
        ]
        MockURLProtocol.requestBodies = [:]
        let session = URLSession(configuration: .mock)
        let sdk = NexusCoreUser.shared
        sdk.initialize(config: try CoreUserConfig(productId: "core-test-gt", productName: "demo", accountName: "test-account", apiBaseUrl: "https://unit.test", encrypt: false, gt: 3), session: session)
        try sdk.clearLocalSession()

        _ = try await sdk.silentLogin()

        let loginBody = try XCTUnwrap(MockURLProtocol.requestBodies["/m/v7/user/login"])
        XCTAssertEqual(loginBody["gt"] as? Int, 3)
    }

    func testGetRelatedProductsSendsAccountNameAndProductId() async throws {
        MockURLProtocol.responses = [
            "/related_products": #"{"code":1,"message":"success","data":{"list":[{"product_id":8,"product_name":"Related App"}]}}"#
        ]
        MockURLProtocol.requestBodies = [:]
        let session = URLSession(configuration: .mock)
        let sdk = NexusCoreUser.shared
        sdk.initialize(
            config: try CoreUserConfig(
                productId: "7",
                productName: "demo",
                accountName: "app-store-account",
                apiBaseUrl: "https://unit.test",
                encrypt: false
            ),
            session: session
        )

        let products = try await sdk.getRelatedProducts()

        let body = try XCTUnwrap(MockURLProtocol.requestBodies["/related_products"])
        XCTAssertEqual(body["product_id"] as? String, "7")
        XCTAssertEqual(body["account_name"] as? String, "app-store-account")
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.productId, "8")
    }

    func testLogoutRetainsUidForNextLogin() async throws {
        MockURLProtocol.responses = [
            "/m/v7/user/login": #"{"code":1,"message":"success","data":{"uid":"u-retained"}}"#,
            "/m/v7/user/info": #"{"code":1,"message":"success","data":{"uid":"u-retained","email":"","phone":"","email_bound":false,"phone_bound":false,"balance":0}}"#,
            "/m/v7/coins/deregister": #"{"code":1,"message":"success","data":{}}"#
        ]
        MockURLProtocol.requestBodies = [:]
        let session = URLSession(configuration: .mock)
        let sdk = NexusCoreUser.shared
        sdk.initialize(config: try CoreUserConfig(productId: "core-test-logout", productName: "demo", accountName: "test-account", apiBaseUrl: "https://unit.test", encrypt: false), session: session)
        try sdk.clearLocalSession()

        _ = try await sdk.silentLogin()
        try await sdk.logout()
        _ = try await sdk.silentLogin()

        let logoutBody = try XCTUnwrap(MockURLProtocol.requestBodies["/m/v7/coins/deregister"])
        XCTAssertEqual(logoutBody["uid"] as? String, "u-retained")
        let loginBody = try XCTUnwrap(MockURLProtocol.requestBodies["/m/v7/user/login"])
        XCTAssertEqual(loginBody["uid"] as? String, "u-retained")
    }

    func testLogoutCompletionReturnsApiError() async throws {
        MockURLProtocol.responses = [
            "/m/v7/user/login": #"{"code":1,"message":"success","data":{"uid":"u-logout-error"}}"#,
            "/m/v7/user/info": #"{"code":1,"message":"success","data":{"uid":"u-logout-error","email":"","phone":"","email_bound":false,"phone_bound":false,"balance":0}}"#,
            "/m/v7/coins/deregister": #"{"code":0,"message":"logout denied","data":{}}"#
        ]
        MockURLProtocol.requestBodies = [:]
        let session = URLSession(configuration: .mock)
        let sdk = NexusCoreUser.shared
        sdk.initialize(config: try CoreUserConfig(productId: "core-test-logout-error", productName: "demo", accountName: "test-account", apiBaseUrl: "https://unit.test", encrypt: false), session: session)
        try sdk.clearLocalSession()

        _ = try await sdk.silentLogin()
        let expectation = expectation(description: "logout completion")
        sdk.logout { result in
            switch result {
            case .success:
                XCTFail("Expected logout failure")
            case .failure(let error):
                XCTAssertEqual(error.localizedDescription, "logout denied")
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(try sdk.getCurrentUser()?.uid, "u-logout-error")
    }

    func testConsumeChatCoinsSendsRequestAndParsesResult() async throws {
        MockURLProtocol.responses = [
            "/m/v7/user/login": #"{"code":1,"message":"success","data":{"uid":"u-coins"}}"#,
            "/m/v7/user/info": #"{"code":1,"message":"success","data":{"uid":"u-coins","email":"","phone":"","email_bound":false,"phone_bound":false,"balance":120}}"#,
            "/m/v7/coins/consume_chat": #"{"code":1,"message":"success","data":{"uid":"u-coins","change_type":"consume_chat","cost":2.5,"before_coins":120.5,"after_coins":118,"balance":118}}"#
        ]
        MockURLProtocol.requestBodies = [:]
        let session = URLSession(configuration: .mock)
        let sdk = NexusCoreUser.shared
        sdk.initialize(config: try CoreUserConfig(productId: "core-test-consume", productName: "demo", accountName: "test-account", apiBaseUrl: "https://unit.test", encrypt: false), session: session)
        try sdk.clearLocalSession()

        _ = try await sdk.silentLogin()
        let result = try await sdk.consumeChatCoins(cost: 2.5, remark: "chat billing")

        XCTAssertEqual(result.uid, "u-coins")
        XCTAssertEqual(result.changeType, "consume_chat")
        XCTAssertEqual(result.cost, 2.5)
        XCTAssertEqual(result.beforeCoins, 120.5)
        XCTAssertEqual(result.afterCoins, 118)
        XCTAssertEqual(result.balance, 118)
        let body = try XCTUnwrap(MockURLProtocol.requestBodies["/m/v7/coins/consume_chat"])
        XCTAssertEqual(body["uid"] as? String, "u-coins")
        XCTAssertEqual(body["cost"] as? Double, 2.5)
        XCTAssertEqual(body["remark"] as? String, "chat billing")
    }

    func testConsumeChatCoinsSkipsBlankRemarkAndCompletionReturnsResult() async throws {
        MockURLProtocol.responses = [
            "/m/v7/user/login": #"{"code":1,"message":"success","data":{"uid":"u-coins-completion"}}"#,
            "/m/v7/user/info": #"{"code":1,"message":"success","data":{"uid":"u-coins-completion","email":"","phone":"","email_bound":false,"phone_bound":false,"balance":2}}"#,
            "/m/v7/coins/consume_chat": #"{"code":1,"message":"success","data":{"uid":"u-coins-completion","change_type":"consume_chat","cost":1,"before_coins":2,"after_coins":1,"balance":1}}"#
        ]
        MockURLProtocol.requestBodies = [:]
        let session = URLSession(configuration: .mock)
        let sdk = NexusCoreUser.shared
        sdk.initialize(config: try CoreUserConfig(productId: "core-test-consume-completion", productName: "demo", accountName: "test-account", apiBaseUrl: "https://unit.test", encrypt: false), session: session)
        try sdk.clearLocalSession()

        _ = try await sdk.silentLogin()
        let expectation = expectation(description: "consume completion")
        sdk.consumeChatCoins(cost: 1, remark: " ") { result in
            switch result {
            case .success(let consumeResult):
                XCTAssertEqual(consumeResult.balance, 1)
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)

        let body = try XCTUnwrap(MockURLProtocol.requestBodies["/m/v7/coins/consume_chat"])
        XCTAssertNil(body["remark"])
    }

    func testConsumeChatCoinsThrowsApiErrorAndRejectsInvalidCost() async throws {
        MockURLProtocol.responses = [
            "/m/v7/user/login": #"{"code":1,"message":"success","data":{"uid":"u-coins-error"}}"#,
            "/m/v7/user/info": #"{"code":1,"message":"success","data":{"uid":"u-coins-error","email":"","phone":"","email_bound":false,"phone_bound":false,"balance":0}}"#,
            "/m/v7/coins/consume_chat": #"{"code":0,"message":"not enough coins","data":{}}"#
        ]
        MockURLProtocol.requestBodies = [:]
        let session = URLSession(configuration: .mock)
        let sdk = NexusCoreUser.shared
        sdk.initialize(config: try CoreUserConfig(productId: "core-test-consume-error", productName: "demo", accountName: "test-account", apiBaseUrl: "https://unit.test", encrypt: false), session: session)
        try sdk.clearLocalSession()

        _ = try await sdk.silentLogin()
        do {
            _ = try await sdk.consumeChatCoins(cost: 1, remark: nil)
            XCTFail("Expected API error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "not enough coins")
        }

        do {
            _ = try await sdk.consumeChatCoins(cost: 0, remark: nil)
            XCTFail("Expected invalid cost error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "cost must be greater than 0")
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    static var responses: [String: String] = [:]
    static var requestBodies: [String: [String: Any]] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        if let httpBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream),
           let object = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any] {
            Self.requestBodies[path] = object
        }
        let body = Self.responses[path] ?? #"{"code":1,"data":{}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}

private extension URLSessionConfiguration {
    static var mock: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }
}
