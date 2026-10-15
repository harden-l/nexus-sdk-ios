import XCTest
import Security
@testable import NexusCoreUser

final class NexusCoreUserTests: XCTestCase {
    let sdk = NexusCoreUser.shared
    var config: CoreUserConfig!
    var suite: String!
    var session: URLSession!

    override func setUpWithError() throws {
        suite = "nexus-v1-test-" + UUID().uuidString
        config = try CoreUserConfig(productId: "7", productName: "TEST PRODUCT", accountName: "test",
                                    apiBaseUrl: "https://unit.test", encrypt: false, gt: 1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [V1URLProtocol.self]
        session = URLSession(configuration: configuration)
        V1URLProtocol.reset()
        sdk.initialize(config: config, appGroupSuiteName: suite, session: session)
        try sdk.clearLocalSession()
    }
    override func tearDownWithError() throws {
        try sdk.clearLocalSession()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        session.invalidateAndCancel()
    }

    func testVersionConfigAndAESKeyLengths() throws {
        XCTAssertEqual(NexusCoreUser.version, "0.1.0")
        XCTAssertFalse(config.country.isEmpty)
        for size in [16, 24, 32] {
            let key = String(repeating: "a", count: size)
            let data = try APIRequestEncryption.encryptString("{\"x\":0.125}", key: key)
            XCTAssertEqual(try APIRequestEncryption.decryptString(String(decoding: data, as: UTF8.self), key: key), "{\"x\":0.125}")
            _ = try CoreUserConfig(productId: "7", productName: "x", apiBaseUrl: "https://unit.test", encryptionKey: key)
        }
        XCTAssertThrowsError(try APIRequestEncryption.encryptString("{}", key: "invalid"))
        let cipher = try APIRequestEncryption.encryptString(#"{"status":1,"hotUpdateUrl":""}"#, key: "1b8df48c1fa64ce28a2e8133dffe600c")
        XCTAssertEqual(String(decoding: cipher, as: UTF8.self), "n+JgfkzArtm/JTkQQj1tZa6pMAucAqMU2RqMZ/6uq3o=")
    }

    func testLoginFieldsTokenAndExactBalance() async throws {
        XCTAssertNil(try sdk.getToken())
        let user = try await sdk.silentLogin()
        XCTAssertEqual(user.uid, "u1")
        XCTAssertEqual(user.balanceDecimal, Decimal(string: "12050.0123456789012345"))
        XCTAssertEqual(user.phonePrefix, "86")
        XCTAssertEqual(try sdk.getToken(), "opaque-test-token")
        XCTAssertEqual(try sdk.getSessionInfo()?.loginType, .guest)
        let login = try V1URLProtocol.body("/api/v1/account/login")
        XCTAssertEqual(Set(login.keys), ["login_type", "device_id", "version", "country", "language", "gt"])
        XCTAssertEqual(login["gt"] as? Int, 1)
        XCTAssertEqual(try V1URLProtocol.body("/api/v1/account/info").count, 0)
        XCTAssertEqual(V1URLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer opaque-test-token")
        XCTAssertEqual(V1URLProtocol.requests.first?.value(forHTTPHeaderField: "ProductId"), "7")
        XCTAssertNil(V1URLProtocol.requests.first?.value(forHTTPHeaderField: "Product"))
    }

    func testConcurrentGuestLoginCoalescesAndReusesSession() async throws {
        try await withThrowingTaskGroup(of: SDKUser.self) { group in
            for _ in 0..<12 { group.addTask { try await self.sdk.silentLogin() } }
            for try await user in group { XCTAssertEqual(user.uid, "u1") }
        }
        _ = try await sdk.silentLogin()
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/login"), 1)
    }

    func testKeychainRestorationAndServiceProductIsolation() async throws {
        _ = try await sdk.silentLogin()
        sdk.initialize(config: config, appGroupSuiteName: suite, session: session)
        XCTAssertEqual(try sdk.getToken(), "opaque-test-token")
        _ = try await sdk.fetchUserInfo()
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/login"), 1)
        var other = config!
        other.productId = "8"
        sdk.initialize(config: other, appGroupSuiteName: suite, session: session)
        XCTAssertNil(try sdk.getToken())
        other = config; other.apiBaseUrl = "https://another.test"
        sdk.initialize(config: other, appGroupSuiteName: suite, session: session)
        XCTAssertNil(try sdk.getToken())
        sdk.initialize(config: config, appGroupSuiteName: suite, session: session)
    }

    func testLegacyUIDIsNotAValidSessionOrAppUID() async throws {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(try JSONEncoder().encode(SDKUser(uid: "legacy", deviceId: "device")), forKey: "nexus.coreuser.7.user")
        XCTAssertNil(try sdk.getCurrentUser())
        _ = try await sdk.silentLogin()
        XCTAssertNil(try V1URLProtocol.body("/api/v1/account/login")["uid"])
        XCTAssertNil(try V1URLProtocol.body("/api/v1/account/login")["app_uid"])
    }

    func testLoginEncryptionPlainRequestEncryptedResponseAndErrorMetadata() async throws {
        config.encrypt = true; config.encryptionKey = String(repeating: "k", count: 24)
        V1URLProtocol.encryptionKey = config.encryptionKey
        sdk.initialize(config: config, appGroupSuiteName: suite, session: session)
        _ = try await sdk.silentLogin()
        XCTAssertEqual(V1URLProtocol.requests.first?.value(forHTTPHeaderField: "Encrypt"), "1")
        XCTAssertEqual(V1URLProtocol.requests.first?.value(forHTTPHeaderField: "Product"), "TEST PRODUCT")
        XCTAssertNil(V1URLProtocol.requests.first?.value(forHTTPHeaderField: "ProductId"))
        V1URLProtocol.responses["/api/v1/account/info"] = #"{"code":401,"message":"expired","data":[]}"#
        V1URLProtocol.plainError = true
        do { _ = try await sdk.fetchUserInfo(); XCTFail("Expected 401") }
        catch let error as CoreUserError { XCTAssertEqual(error.businessCode, 401); XCTAssertEqual(error.traceId, "trace-test") }
        XCTAssertNil(try sdk.getToken())
    }

    func testExpiredAccountRequiresPasswordButGuestMayRelogin() async throws {
        let storage = CoreUserStorage(suiteName: suite, productId: "7", apiBaseUrl: config.apiBaseUrl)
        try storage.saveSession(LoginSession(uid: "u1", token: "expired", expiresAt: 1, loginType: .email))
        XCTAssertNil(try sdk.getToken())
        do { _ = try await sdk.silentLogin(); XCTFail("Do not downgrade email to guest") }
        catch let error as CoreUserError { XCTAssertEqual(error.businessCode, 401) }
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/login"), 0)
        try storage.clearSession(resetLoginType: true)
        try storage.saveSession(LoginSession(uid: "u1", token: "expired", expiresAt: 1, loginType: .guest))
        _ = try await sdk.silentLogin()
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/login"), 1)
    }

    func testEmailPhonePasswordRulesAndOptionalBindingPassword() async throws {
        for password in ["short", " spaced123", "spaced123 ", "nonASCII密码", String(repeating: "a", count: 73)] {
            do { _ = try await sdk.loginWithEmail(email: "x@y.com", password: password); XCTFail("Invalid password") }
            catch { XCTAssertTrue(error.localizedDescription.contains("password")) }
        }
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/login"), 0)
        _ = try await sdk.loginWithEmail(email: " USER@Example.com ", password: "Password123!")
        XCTAssertEqual(try V1URLProtocol.body("/api/v1/account/login")["email"] as? String, "user@example.com")
        _ = try await sdk.loginWithPhone(phonePrefix: "86", phone: "123456789", password: "Password123!")
        let phone = try V1URLProtocol.body("/api/v1/account/login")
        XCTAssertEqual(phone["phone_prefix"] as? String, "86")
        XCTAssertNil(phone["email"])
        _ = try await sdk.bindEmail(" User@example.com ")
        let bind = try V1URLProtocol.body("/api/v1/account/bind")
        XCTAssertNil(bind["password"]); XCTAssertNil(bind["uid"])
        XCTAssertEqual(bind["email"] as? String, "user@example.com")
    }

    func testDebitExactAmountWhitelistAndNoCacheMutation() async throws {
        let user = try await sdk.silentLogin()
        let cost = Decimal(string: "0.000000000000000001")!
        let result = try await sdk.consumeChatCoins(cost: cost, idempotencyKey: "bill-1")
        XCTAssertEqual(result.costDecimal, cost)
        XCTAssertEqual(result.balanceDecimal, Decimal(string: "0.099999999999999999"))
        XCTAssertEqual(try sdk.getCurrentUser()?.balanceDecimal, user.balanceDecimal)
        let request = try XCTUnwrap(V1URLProtocol.requests.last?.httpBody)
        XCTAssertTrue(String(decoding: request, as: UTF8.self).contains("0.000000000000000001"))
        let body = try V1URLProtocol.body("/api/v1/coins/consume")
        XCTAssertEqual(Set(body.keys), ["cost", "idempotency_key"])
        for cost: Double in [0, -1, .nan, .infinity] {
            do { _ = try await sdk.consumeChatCoins(cost: cost); XCTFail("Invalid amount") } catch {}
        }
        XCTAssertEqual(V1URLProtocol.count("/api/v1/coins/consume"), 1)
    }

    func testBusinessFailureDoesNotReplayMutationOrDowngradeAccount() async throws {
        _ = try await sdk.loginWithEmail(email: "user@example.com", password: "Password123!")
        V1URLProtocol.responses["/api/v1/coins/consume"] = #"{"code":401,"message":"expired","data":[]}"#
        do { _ = try await sdk.consumeChatCoins(cost: 1.0); XCTFail("Expected failure") } catch {}
        XCTAssertNil(try sdk.getToken())
        do { _ = try await sdk.fetchUserInfo(); XCTFail("Expected re-login required") } catch {}
        XCTAssertEqual(V1URLProtocol.count("/api/v1/coins/consume"), 1)
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/login"), 1)
    }

    func testWeeklyStrictBodyDecimalUnixTimeAndUnsupportedSKU() async throws {
        let info = try await sdk.getWeeklyPointsInfo()
        XCTAssertEqual(info.weeklyPointsDecimal, Decimal(string: "0.375"))
        let result = try await sdk.claimWeeklyPoints()
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.pointsDecimal, Decimal(string: "0.375"))
        XCTAssertEqual(result.claimTimeSeconds, 1789084800)
        XCTAssertTrue(result.claimTime.hasSuffix("Z"))
        XCTAssertEqual(result.balanceDecimal, Decimal(string: "120.875"))
        for path in ["/api/v1/weekly-points/info", "/api/v1/weekly-points/claim"] {
            XCTAssertEqual(try V1URLProtocol.body(path).count, 0)
        }
        do { _ = try await sdk.claimWeeklyPoints(marketProductId: "sku"); XCTFail("Must reject SKU") } catch {}
        XCTAssertEqual(V1URLProtocol.count("/api/v1/weekly-points/claim"), 1)
    }

    func testRelatedProductsAndLogoutKeepDeviceOnly() async throws {
        let device = try sdk.getDeviceId()
        let products = try await sdk.getRelatedProducts()
        XCTAssertEqual(products.first?.productId, "8")
        XCTAssertEqual(Set(try V1URLProtocol.body("/api/v1/product/related-products").keys), ["account_name"])
        try await sdk.logout()
        XCTAssertNil(try sdk.getToken()); XCTAssertNil(try sdk.getCurrentUser())
        XCTAssertEqual(try sdk.getDeviceId(), device)
        XCTAssertEqual(try V1URLProtocol.body("/api/v1/account/deregister").count, 0)
        do { try await sdk.logout(); XCTFail("Not an idempotent logout") } catch {}
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/deregister"), 1)
    }

    func testCompletionEntryPointsAndStrictSuccessCode() async throws {
        let done = expectation(description: "callback")
        sdk.consumeChatCoins(cost: 0.1) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        V1URLProtocol.responses["/api/v1/account/info"] = #"{"message":"missing code","data":{"uid":"u1"}}"#
        do { _ = try await sdk.fetchUserInfo(); XCTFail("Missing code must fail") } catch {}
    }

    func testHTTP401WithoutEnvelopeClearsSession() async throws {
        _ = try await sdk.silentLogin()
        V1URLProtocol.responses["/api/v1/account/info"] = #"{"message":"Unauthorized"}"#
        V1URLProtocol.httpStatus = 401
        do { _ = try await sdk.fetchUserInfo(); XCTFail("Expected unauthorized") }
        catch let error as CoreUserError { XCTAssertEqual(error.businessCode, 401) }
        XCTAssertNil(try sdk.getToken())
    }

    func testKeychainAccountKindSurvivesPreferenceLossAndInvalidation() async throws {
        let storage = CoreUserStorage(suiteName: suite, productId: "7", apiBaseUrl: config.apiBaseUrl)
        try storage.saveSession(LoginSession(uid: "u1", token: "expired", expiresAt: 1, loginType: .email))
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        XCTAssertNil(try sdk.getToken())
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        do { _ = try await sdk.ensureAuthenticatedUser(); XCTFail("Account must require credentials") }
        catch let error as CoreUserError { XCTAssertEqual(error.businessCode, 401) }
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/login"), 0)
    }

    func testLostDebitResponseExposesSameKeyForExplicitRetry() async throws {
        _ = try await sdk.silentLogin()
        V1URLProtocol.failPath = "/api/v1/coins/consume"
        var key: String?
        do { _ = try await sdk.consumeChatCoins(cost: 0.1); XCTFail("Expected timeout") }
        catch let error as ConsumeChatCoinsError {
            key = error.idempotencyKey
            XCTAssertEqual((error.underlyingError as NSError).code, NSURLErrorTimedOut)
        }
        let captured = try V1URLProtocol.body("/api/v1/coins/consume")["idempotency_key"] as? String
        XCTAssertEqual(key, captured)
        XCTAssertEqual(V1URLProtocol.count("/api/v1/coins/consume"), 1)
        V1URLProtocol.failPath = nil
        let result = try await sdk.consumeChatCoins(cost: 0.1, idempotencyKey: XCTUnwrap(key))
        XCTAssertEqual(result.idempotencyKey, captured)
        XCTAssertEqual(V1URLProtocol.count("/api/v1/coins/consume"), 2)
    }

    func testMalformedFinancialSuccessCannotBecomeZeroValueSuccess() async throws {
        _ = try await sdk.silentLogin()
        for data in ["[]", "{}", #"{"points":"0.375","market_product_id":"sku","transaction_id":"1","claim_time":1789084800,"before_coins":1,"after_coins":2,"balance":2}"#,
                     #"{"points":0.375,"market_product_id":"sku","transaction_id":"1","claim_time":1789084800.5,"before_coins":1,"after_coins":2,"balance":2}"#] {
            V1URLProtocol.responses["/api/v1/weekly-points/claim"] = "{\"code\":1,\"data\":" + data + "}"
            do { _ = try await sdk.claimWeeklyPoints(); XCTFail("Malformed success must fail") } catch {}
        }
        V1URLProtocol.responses["/api/v1/coins/consume"] = #"{"code":1,"data":{"uid":"u1"}}"#
        do { _ = try await sdk.consumeChatCoins(cost: 1.0); XCTFail("Missing financial fields") }
        catch let error as ConsumeChatCoinsError { XCTAssertFalse(error.idempotencyKey.isEmpty) }
    }

    func testPinnedContextAndExpectedUidRejectChangedIdentityBeforeRequest() async throws {
        let context = try await sdk.captureAuthenticatedSession()
        try sdk.clearLocalSession()
        do { _ = try await context.claimWeeklyPoints(); XCTFail("Old context must fail") }
        catch { XCTAssertEqual(error as? CoreUserError, .sessionChanged) }
        do { _ = try await sdk.postAuthenticated(path: "/api/v1/coins/consume", body: Data("{}".utf8), expectedUid: "someone-else"); XCTFail("Wrong identity") }
        catch { XCTAssertEqual(error as? CoreUserError, .sessionChanged) }
        XCTAssertEqual(V1URLProtocol.count("/api/v1/weekly-points/claim"), 0)
        XCTAssertEqual(V1URLProtocol.count("/api/v1/coins/consume"), 0)
    }

    func testBindingDialogContextCannotSelectReplacementAccount() async throws {
        let context = try await sdk.captureAuthenticatedSession()
        try context.validate()
        V1URLProtocol.responses["/api/v1/account/login"] = #"{"code":1,"data":{"uid":"u2","token":"second-account","expires_at":4102444800}}"#
        V1URLProtocol.responses["/api/v1/account/info"] = #"{"code":1,"data":{"uid":"u2","balance":0,"is_vip":false,"vip_expired_at":0}}"#
        _ = try await sdk.loginWithEmail(email: "second@example.com", password: "Password123!")
        do {
            _ = try await context.bindAccount(BindAccountParams(accountType: .email, email: "first@example.com", password: "Password123!"))
            XCTFail("Dialog must retain its original account")
        } catch { XCTAssertEqual(error as? CoreUserError, .sessionChanged) }
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/bind"), 0)
        XCTAssertEqual(try sdk.getCurrentUser()?.uid, "u2")
    }

    func testBindingRefreshCannotDeliverIntoReplacementSession() async throws {
        let context = try await sdk.captureAuthenticatedSession()
        let started = expectation(description: "bind profile refresh captured")
        let gate = ResponseGate()
        V1URLProtocol.gate = { request, delivery in
            guard request.url?.path == "/api/v1/account/info" else { return false }
            if gate.capture(delivery) { started.fulfill(); return true }
            return false
        }
        let pending = Task {
            try await context.bindAccount(BindAccountParams(accountType: .email, email: "user@example.com"))
        }
        await fulfillment(of: [started], timeout: 5)
        V1URLProtocol.responses["/api/v1/account/login"] = #"{"code":1,"data":{"uid":"u1","token":"replacement-token","expires_at":4102444800}}"#
        _ = try await sdk.loginWithEmail(email: "user@example.com", password: "Password123!")
        gate.release()
        do { _ = try await pending.value; XCTFail("Stale binding result must fail") }
        catch { XCTAssertEqual(error as? CoreUserError, .sessionChanged) }
        XCTAssertEqual(V1URLProtocol.count("/api/v1/account/bind"), 1)
        XCTAssertEqual(try sdk.getToken(), "replacement-token")
    }

    func testDelayedUserInfoCannotPublishAfterReinitialize() async throws {
        _ = try await sdk.silentLogin()
        let started = expectation(description: "old request captured")
        let gate = ResponseGate()
        V1URLProtocol.gate = { request, delivery in
            guard request.url?.path == "/api/v1/account/info" else { return false }
            if gate.capture(delivery) { started.fulfill(); return true }
            return false
        }
        let pending = Task { try await self.sdk.fetchUserInfo() }
        await fulfillment(of: [started], timeout: 5)
        var other = config!
        other.productId = "8"
        sdk.initialize(config: other, appGroupSuiteName: suite, session: session)
        gate.release()
        do { _ = try await pending.value; XCTFail("Stale response must be discarded") }
        catch { XCTAssertEqual(error as? CoreUserError, .sessionChanged) }
        XCTAssertNil(try sdk.getCurrentUser())
        sdk.initialize(config: config, appGroupSuiteName: suite, session: session)
    }

    func testDelayed401DoesNotClearNewLogin() async throws {
        _ = try await sdk.silentLogin()
        let started = expectation(description: "old 401 captured")
        let gate = ResponseGate()
        let originalInfo = V1URLProtocol.responses["/api/v1/account/info"]
        V1URLProtocol.responses["/api/v1/account/info"] = #"{"code":401,"message":"old token expired","data":[]}"#
        V1URLProtocol.gate = { request, delivery in
            guard request.url?.path == "/api/v1/account/info" else { return false }
            if gate.capture(delivery) { started.fulfill(); return true }
            return false
        }
        let pending = Task { try await self.sdk.fetchUserInfo() }
        await fulfillment(of: [started], timeout: 5)
        V1URLProtocol.responses["/api/v1/account/info"] = originalInfo
        V1URLProtocol.responses["/api/v1/account/login"] = #"{"code":1,"data":{"uid":"u1","token":"replacement-token","expires_at":4102444800}}"#
        _ = try await sdk.loginWithEmail(email: "user@example.com", password: "Password123!")
        gate.release()
        do { _ = try await pending.value; XCTFail("Expected old 401") } catch {}
        XCTAssertEqual(try sdk.getToken(), "replacement-token")
    }

    func testOldContextCannotReviveWithIdenticalLoginToken() async throws {
        let context = try await sdk.captureAuthenticatedSession()
        try sdk.clearLocalSession()
        _ = try await sdk.silentLogin()
        XCTAssertThrowsError(try context.validate())
        do { _ = try await context.claimWeeklyPoints(); XCTFail("Old lifecycle") }
        catch { XCTAssertEqual(error as? CoreUserError, .sessionChanged) }
        XCTAssertEqual(V1URLProtocol.count("/api/v1/weekly-points/claim"), 0)
    }

    func testInvalidVIPFieldsDoNotOverwriteProfile() async throws {
        let before = try await sdk.silentLogin()
        for fields in ["", #", "is_vip":null,"vip_expired_at":0"#,
                       #", "is_vip":1,"vip_expired_at":0"#,
                       #", "is_vip":true,"vip_expired_at":123.5"#] {
            V1URLProtocol.responses["/api/v1/account/info"] = "{\"code\":1,\"data\":{\"uid\":\"u1\",\"balance\":1" + fields + "}}"
            do { _ = try await sdk.fetchUserInfo(); XCTFail("Invalid membership must fail") } catch {}
            XCTAssertEqual(try sdk.getCurrentUser(), before)
        }
    }

    func testExplicitClearRecoversCorruptKeychainRecord() async throws {
        _ = try await sdk.silentLogin()
        let storage = CoreUserStorage(suiteName: suite, productId: "7", apiBaseUrl: config.apiBaseUrl)
        XCTAssertEqual(SecItemUpdate(storage.keychainQuery as CFDictionary,
                                     [kSecValueData as String: Data("corrupt session".utf8)] as CFDictionary), errSecSuccess)
        XCTAssertThrowsError(try sdk.getToken())
        try sdk.clearLocalSession()
        XCTAssertNil(try sdk.getToken())
        _ = try await sdk.silentLogin()
        XCTAssertNotNil(try sdk.getToken())
    }

    func testDebitCompletionRetainsKeyAfterReinitialize() async throws {
        _ = try await sdk.silentLogin()
        let started = expectation(description: "debit captured")
        let completed = expectation(description: "debit callback")
        let gate = ResponseGate()
        V1URLProtocol.gate = { request, delivery in
            guard request.url?.path == "/api/v1/coins/consume" else { return false }
            if gate.capture(delivery) { started.fulfill(); return true }
            return false
        }
        sdk.consumeChatCoins(cost: 0.1, idempotencyKey: "callback-bill") { result in
            if case .failure(let error) = result {
                XCTAssertEqual((error as? ConsumeChatCoinsError)?.idempotencyKey, "callback-bill")
            } else { XCTFail("Stale callback must fail") }
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 5)
        sdk.initialize(config: config, appGroupSuiteName: suite, session: session)
        gate.release()
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(V1URLProtocol.count("/api/v1/coins/consume"), 1)
    }
}

private final class ResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var captured = false
    private var delivery: (@Sendable () -> Void)?
    func capture(_ value: @escaping @Sendable () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !captured else { return false }
        captured = true; delivery = value; return true
    }
    func release() {
        lock.lock(); let value = delivery; delivery = nil; lock.unlock()
        value?()
    }
}

private final class V1URLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var responses: [String: String] = [:]
    static var encryptionKey: String?
    static var plainError = false
    static var httpStatus = 200
    static var failPath: String?
    static var gate: ((URLRequest, @escaping @Sendable () -> Void) -> Bool)?
    static func reset() {
        requests = []; encryptionKey = nil; plainError = false; httpStatus = 200; failPath = nil; gate = nil
        responses = [
            "/api/v1/account/login": #"{"code":1,"data":{"uid":"u1","token":"opaque-test-token","expires_at":4102444800}}"#,
            "/api/v1/account/info": #"{"code":1,"data":{"uid":"u1","email":"user@example.com","phone_prefix":"86","phone":"123","email_bound":true,"phone_bound":true,"balance":120.500123456789012345,"is_vip":true,"vip_expired_at":4102444800}}"#,
            "/api/v1/account/bind": #"{"code":1,"data":{"uid":"u1","account_type":"email","account_value":"user@example.com","bound":true}}"#,
            "/api/v1/account/deregister": #"{"code":1,"data":{"uid":"u1","deregistered":true}}"#,
            "/api/v1/coins/consume": #"{"code":1,"data":{"uid":"u1","change_type":"consume_chat","cost":0.000000000000000001,"before_coins":0.1,"after_coins":0.099999999999999999,"balance":0.099999999999999999}}"#,
            "/api/v1/weekly-points/info": #"{"code":1,"data":{"is_vip":true,"market_product_id":"weekly","weekly_points":0.375,"can_claim":true,"cannot_claim_reason":""}}"#,
            "/api/v1/weekly-points/claim": #"{"code":1,"data":{"points":0.375,"market_product_id":"weekly","transaction_id":"123","claim_time":1789084800,"before_coins":120.5,"after_coins":120.875,"balance":120.875}}"#,
            "/api/v1/product/related-products": #"{"code":1,"data":{"list":[{"product_id":8,"product_name":"Other app"}]}}"#
        ]
    }
    static func count(_ path: String) -> Int { requests.filter { $0.url?.path == path }.count }
    static func body(_ path: String) throws -> [String: Any] {
        let data = try XCTUnwrap(requests.last { $0.url?.path == path }?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
                captured.httpBody = data
            }
            Self.lock.lock()
            Self.requests.append(captured)
            let text = Self.responses[request.url!.path] ?? #"{"code":404,"message":"unknown","data":[]}"#
            let key = Self.encryptionKey
            let plainError = Self.plainError
            Self.lock.unlock()
            if Self.failPath == request.url?.path {
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
                return
            }
            let body = try key.map { key in plainError && text.contains("\"code\":401") ? Data(text.utf8) : try APIRequestEncryption.encryptString(text, key: key) } ?? Data(text.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.httpStatus, httpVersion: nil, headerFields: ["X-Trace-ID": "trace-test"])!
            let deliver: @Sendable () -> Void = { [self] in
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
            if Self.gate?(request, deliver) != true { deliver() }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
