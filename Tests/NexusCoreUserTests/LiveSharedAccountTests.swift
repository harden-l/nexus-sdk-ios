import XCTest
@testable import NexusCoreUser

final class LiveSharedAccountTests: XCTestCase {
    // Opt-in only: creates, binds, debits and deregisters its own test identity.
    func testIsolatedLiveAccount() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["NEXUS_LIVE_API_URL"], let key = env["NEXUS_LIVE_API_KEY"] else {
            throw XCTSkip("Set authorized test-service environment variables to run real account verification")
        }
        let run = UUID().uuidString.lowercased()
        let suite = "nexus-live-v1-" + run
        let config = try CoreUserConfig(productId: "7", productName: "TEST PRODUCT", apiBaseUrl: base,
                                       encryptionKey: key, gt: 1)
        let sdk = NexusCoreUser.shared
        sdk.initialize(config: config, appGroupSuiteName: suite)
        try sdk.clearLocalSession()
        do {
            let guest = try await sdk.silentLogin()
            XCTAssertTrue(guest.userInfoSynced)
            XCTAssertEqual(guest.balanceDecimal, 10)
            let token = try XCTUnwrap(sdk.getToken())
            _ = try await sdk.silentLogin()
            XCTAssertTrue(try sdk.getToken() == token, "Valid guest session must be reused")
            sdk.initialize(config: config, appGroupSuiteName: suite)
            XCTAssertTrue(try sdk.getToken() == token, "Keychain session must survive SDK reinitialization")
            let restored = try await sdk.fetchUserInfo()
            XCTAssertEqual(restored.uid, guest.uid)

            var request = URLRequest(url: URL(string: base + "/api/v1/account/info")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("0", forHTTPHeaderField: "Encrypt")
            request.setValue("7", forHTTPHeaderField: "ProductId")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = Data("{}".utf8)
            let (data, _) = try await URLSession.shared.data(for: request)
            let independent = try APIJSON.decode(data)
            XCTAssertEqual(independent["code"].int, 1)
            XCTAssertEqual(independent["data"]["uid"].string, guest.uid)

            let products = try APIJSON.decode(await sdk.postAuthenticated(path: "/api/v1/iap/products", body: Data("{}".utf8)))
            let related = try await sdk.getRelatedProducts()
            print("Live catalog count=\(products["list"].array.count), related count=\(related.count)")
            let info = try await sdk.getWeeklyPointsInfo()
            XCTAssertFalse(info.canClaim)
            do { _ = try await sdk.claimWeeklyPoints(); XCTFail("Unsubscribed test user must not claim") }
            catch let error as CoreUserError { XCTAssertEqual(error.businessCode, 2131) }

            let email = "nexus-ios-" + run + "@example.com"
            let password = "NexusTest!" + run
            let binding = try await sdk.bindEmail(email, password: password)
            XCTAssertTrue(binding.bound)
            let emailUser = try await sdk.loginWithEmail(email: " " + email.uppercased() + " ", password: password)
            XCTAssertEqual(emailUser.uid, guest.uid)
            let bill = UUID().uuidString
            let cost = Decimal(string: "0.001")!
            let first = try await sdk.consumeChatCoins(cost: cost, remark: "isolated iOS SDK acceptance", idempotencyKey: bill)
            let repeated = try await sdk.consumeChatCoins(cost: cost, remark: "isolated iOS SDK acceptance", idempotencyKey: bill)
            XCTAssertEqual(first.balanceDecimal, repeated.balanceDecimal)
            XCTAssertEqual(first.beforeCoinsDecimal - first.afterCoinsDecimal, cost)
            let updated = try await sdk.fetchUserInfo()
            XCTAssertEqual(updated.balanceDecimal, first.afterCoinsDecimal * 100)
            try await sdk.logout()
            XCTAssertNil(try sdk.getToken())
            XCTAssertNil(try sdk.getCurrentUser())
            print("Live iOS v1 PASS: encrypted login, Keychain restore, exported Token request, binding/email login, debit idempotency, weekly rejection, deregistration. No paid store purchase.")
        } catch {
            do { try await sdk.logout() }
            catch { print("Live test cleanup did not complete; inspect the test-scoped session before retrying") }
            throw error
        }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}
