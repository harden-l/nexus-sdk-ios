import Foundation
#if canImport(UIKit)
import UIKit
#endif

public final class NexusCoreUser: @unchecked Sendable {
    public static let shared = NexusCoreUser()
    public static let version = "0.1.0"
    private let lock = NSLock()
    private var runtime: CoreUserRuntime?
    private init() {}
    private init(runtime: CoreUserRuntime) { self.runtime = runtime }

    public func initialize(config: CoreUserConfig, appGroupSuiteName: String? = nil, session: URLSession = .shared) {
        lock.lock()
        defer { lock.unlock() }
        runtime?.invalidate()
        runtime = CoreUserRuntime(config: config, suiteName: appGroupSuiteName, session: session)
    }

    private func requireRuntime() throws -> CoreUserRuntime {
        lock.lock()
        defer { lock.unlock() }
        guard let runtime else { throw CoreUserError.notInitialized }
        return runtime
    }

    public func getSdkConfig() throws -> CoreUserConfig { try requireRuntime().config }
    public func getDeviceId() throws -> String {
        let runtime = try requireRuntime()
        return runtime.locked { runtime.storage.getOrCreateDeviceId() }
    }
    public func setLoginAttributionEnabled(_ enabled: Bool) throws {
        let runtime = try requireRuntime()
        runtime.locked { runtime.storage.setLoginAttributionEnabled(enabled) }
    }
    public func isLoginAttributionEnabled() throws -> Bool {
        let runtime = try requireRuntime()
        return runtime.locked { runtime.storage.isLoginAttributionEnabled() }
    }
    public func getToken() throws -> String? { try requireRuntime().validSession()?.token }
    public func getSessionInfo() throws -> SessionInfo? {
        guard let session = try requireRuntime().validSession() else { return nil }
        return SessionInfo(uid: session.uid, expiresAt: session.expiresAt, loginType: session.loginType)
    }
    public func getCurrentUser() throws -> SDKUser? { try requireRuntime().user() }
    public func clearLocalSession() throws { try requireRuntime().clear(resetLoginType: true) }

    public func silentLogin(loginType: LoginType = .guest) async throws -> SDKUser {
        guard loginType == .guest else { throw CoreUserError.invalidConfig("Use loginWithEmail or loginWithPhone") }
        return try await requireRuntime().login(type: .guest)
    }
    public func loginWithEmail(email: String, password: String) async throws -> SDKUser {
        try await requireRuntime().login(type: .email, email: email, password: password)
    }
    public func loginWithPhone(phonePrefix: String, phone: String, password: String) async throws -> SDKUser {
        try await requireRuntime().login(type: .phone, phonePrefix: phonePrefix, phone: phone, password: password)
    }
    public func ensureAuthenticatedUser() async throws -> SDKUser {
        let runtime = try requireRuntime()
        _ = try await runtime.authenticatedSession()
        guard let user = try runtime.user() else { throw CoreUserError.sessionChanged }
        return user
    }
    public func postAuthenticated(path: String, body: Data, expectedUid: String? = nil) async throws -> Data {
        let runtime = try requireRuntime()
        let session = try await runtime.authenticatedSession()
        if let expectedUid, session.uid != expectedUid { throw CoreUserError.sessionChanged }
        return try await runtime.request(path: path, body: body, session: session)
    }
    public func captureAuthenticatedSession() async throws -> CoreUserSessionContext {
        try await requireRuntime().captureContext()
    }
    public func fetchUserInfo() async throws -> SDKUser {
        let runtime = try requireRuntime()
        return try await runtime.fetchUser(session: runtime.authenticatedSession())
    }

    public func getWeeklyPointsInfo() async throws -> WeeklyPointsInfo {
        try await captureAuthenticatedSession().getWeeklyPointsInfo()
    }
    public func claimWeeklyPoints() async throws -> WeeklyPointsClaimResult {
        try await captureAuthenticatedSession().claimWeeklyPoints()
    }
    @available(*, deprecated, message: "Server chooses the eligible subscription; call claimWeeklyPoints()")
    public func claimWeeklyPoints(marketProductId: String?) async throws -> WeeklyPointsClaimResult {
        guard (marketProductId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreUserError.invalidConfig("Selecting a SKU for weekly claims is not supported")
        }
        return try await claimWeeklyPoints()
    }

    public func bindEmail(_ email: String, password: String? = nil) async throws -> BindAccountResult {
        try await bindAccount(BindAccountParams(accountType: .email, email: email, password: password))
    }
    public func bindPhone(phonePrefix: String, phone: String, password: String? = nil) async throws -> BindAccountResult {
        try await bindAccount(BindAccountParams(accountType: .phone, phonePrefix: phonePrefix, phone: phone, password: password))
    }
    public func bindAccount(_ params: BindAccountParams) async throws -> BindAccountResult {
        try await captureAuthenticatedSession().bindAccount(params)
    }

    public func consumeChatCoins(cost: Double, remark: String? = nil, idempotencyKey: String = UUID().uuidString) async throws -> ConsumeChatCoinsResult {
        guard cost.isFinite, let decimal = Decimal(string: String(cost)) else { throw CoreUserError.invalidConfig("cost must be finite") }
        return try await consumeChatCoins(cost: decimal, remark: remark, idempotencyKey: idempotencyKey)
    }
    public func consumeChatCoins(cost: Decimal, remark: String? = nil, idempotencyKey: String = UUID().uuidString) async throws -> ConsumeChatCoinsResult {
        guard !cost.isNaN, cost > 0 else { throw CoreUserError.invalidConfig("cost must be greater than 0") }
        guard (1...128).contains(idempotencyKey.utf8.count), idempotencyKey.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }) else { throw CoreUserError.invalidConfig("Invalid idempotencyKey") }
        guard (remark?.unicodeScalars.count ?? 0) <= 255 else { throw CoreUserError.invalidConfig("remark must be at most 255 characters") }
        var fields: [String: APIJSON] = ["cost": .number(cost), "idempotency_key": .string(idempotencyKey)]
        if let remark, !remark.isEmpty { fields["remark"] = .string(remark) }
        do {
            let context = try await captureAuthenticatedSession()
            let value = try APIJSON.decode(await context.post(path: "/api/v1/coins/consume", body: APIJSON.object(fields).data()))
            let uid = try value.requireString("uid")
            guard uid == context.uid else { throw CoreUserError.invalidResponse("Debit identity mismatch") }
            let charged = try value.requireNumber("cost")
            let before = try value.requireNumber("before_coins")
            let after = try value.requireNumber("after_coins")
            let balance = try value.requireNumber("balance")
            return try ConsumeChatCoinsResult(uid: uid, changeType: value.requireString("change_type"),
                cost: NSDecimalNumber(decimal: charged).doubleValue, beforeCoins: NSDecimalNumber(decimal: before).doubleValue,
                afterCoins: NSDecimalNumber(decimal: after).doubleValue, balance: NSDecimalNumber(decimal: balance).doubleValue,
                costDecimal: charged, beforeCoinsDecimal: before, afterCoinsDecimal: after, balanceDecimal: balance,
                idempotencyKey: idempotencyKey)
        } catch { throw ConsumeChatCoinsError(idempotencyKey: idempotencyKey, underlyingError: error) }
    }

    public func getRelatedProducts(forceRefresh: Bool = false) async throws -> [RelatedProduct] {
        let runtime = try requireRuntime()
        let session = try await runtime.authenticatedSession()
        let body = try APIJSON.object(["account_name": .string(runtime.config.accountName)]).data()
        let value = try APIJSON.decode(await runtime.request(path: "/api/v1/product/related-products", body: body, session: session))
        return value["list"].array.map {
            RelatedProduct(productId: $0["product_id"].string, productName: $0["product_name"].string,
                           description: $0["description"].string, icon: $0["icon"].string,
                           downloadUrl: $0["download_url"].string, packageName: $0["package_name"].string)
        }
    }
    public func logout() async throws {
        let runtime = try requireRuntime()
        guard let session = try runtime.validSession() else {
            throw CoreUserError.business(code: 401, message: "No valid session to deregister", httpStatus: 200, traceId: nil)
        }
        _ = try await runtime.request(path: "/api/v1/account/deregister", session: session)
        try runtime.locked { try runtime.assertIdentity(session); try runtime.clear(resetLoginType: true) }
    }

    public func silentLogin(loginType: LoginType = .guest, completion: @escaping @Sendable (CoreUserResult<SDKUser>) -> Void) {
        complete(completion) { try await $0.silentLogin(loginType: loginType) }
    }
    public func loginWithEmail(email: String, password: String, completion: @escaping @Sendable (CoreUserResult<SDKUser>) -> Void) {
        complete(completion) { try await $0.loginWithEmail(email: email, password: password) }
    }
    public func loginWithPhone(phonePrefix: String, phone: String, password: String, completion: @escaping @Sendable (CoreUserResult<SDKUser>) -> Void) {
        complete(completion) { try await $0.loginWithPhone(phonePrefix: phonePrefix, phone: phone, password: password) }
    }
    public func fetchUserInfo(completion: @escaping @Sendable (CoreUserResult<SDKUser>) -> Void) {
        complete(completion) { try await $0.fetchUserInfo() }
    }
    public func getWeeklyPointsInfo(completion: @escaping @Sendable (CoreUserResult<WeeklyPointsInfo>) -> Void) {
        complete(completion) { try await $0.getWeeklyPointsInfo() }
    }
    public func claimWeeklyPoints(completion: @escaping @Sendable (CoreUserResult<WeeklyPointsClaimResult>) -> Void) {
        complete(completion) { try await $0.claimWeeklyPoints() }
    }
    @available(*, deprecated, message: "Server chooses the eligible subscription; omit marketProductId")
    public func claimWeeklyPoints(marketProductId: String?, completion: @escaping @Sendable (CoreUserResult<WeeklyPointsClaimResult>) -> Void) {
        complete(completion) { try await $0.claimWeeklyPoints(marketProductId: marketProductId) }
    }
    public func consumeChatCoins(cost: Double, remark: String? = nil, idempotencyKey: String = UUID().uuidString,
                                 completion: @escaping @Sendable (CoreUserResult<ConsumeChatCoinsResult>) -> Void) {
        complete(completion, failure: { error in
            error as? ConsumeChatCoinsError ?? ConsumeChatCoinsError(idempotencyKey: idempotencyKey, underlyingError: error)
        }) { try await $0.consumeChatCoins(cost: cost, remark: remark, idempotencyKey: idempotencyKey) }
    }
    public func consumeChatCoins(cost: Decimal, remark: String? = nil, idempotencyKey: String = UUID().uuidString,
                                 completion: @escaping @Sendable (CoreUserResult<ConsumeChatCoinsResult>) -> Void) {
        complete(completion, failure: { error in
            error as? ConsumeChatCoinsError ?? ConsumeChatCoinsError(idempotencyKey: idempotencyKey, underlyingError: error)
        }) { try await $0.consumeChatCoins(cost: cost, remark: remark, idempotencyKey: idempotencyKey) }
    }
    public func logout(completion: @escaping @Sendable (CoreUserResult<Void>) -> Void) {
        complete(completion) { try await $0.logout() }
    }
    private func complete<Value>(_ completion: @escaping @Sendable (CoreUserResult<Value>) -> Void,
                                  failure: @escaping @Sendable (Error) -> Error = { $0 },
                                  operation: @escaping @Sendable (NexusCoreUser) async throws -> Value) {
        let captured = Result { try requireRuntime() }
        Task {
            do {
                let runtime = try captured.get()
                let value = try await operation(NexusCoreUser(runtime: runtime))
                guard try requireRuntime() === runtime else { throw CoreUserError.sessionChanged }
                completion(.success(value))
            }
            catch { completion(.failure(failure(error))) }
        }
    }

    #if canImport(UIKit)
    public func ensureEmailBound(presenting viewController: UIViewController,
                                 completion: @escaping @Sendable (BindEmailFlowResult) -> Void = { _ in }) {
        Task {
            do {
                let runtime = try requireRuntime()
                let context = try await runtime.captureContext()
                let user = try await context.fetchUserInfo()
                try await MainActor.run {
                    try context.validate()
                    if user.emailBound { completion(BindEmailFlowResult(status: .alreadyBound, user: user)); return }
                    CoreUserEmailBindPresenter.show(presenting: viewController, initialEmail: user.email,
                        onCancel: {
                            do {
                                try context.validate()
                                completion(BindEmailFlowResult(status: .cancelled, user: user))
                            } catch { completion(BindEmailFlowResult(status: .bindFailed, error: error)) }
                        },
                        onSubmit: { email, password in
                            Task {
                                do {
                                    let result = try await context.bindAccount(BindAccountParams(accountType: .email, email: email, password: password))
                                    let updated = try runtime.user()
                                    try await MainActor.run {
                                        try context.validate()
                                        completion(BindEmailFlowResult(status: .bound, user: updated, bindResult: result))
                                    }
                                } catch {
                                    await MainActor.run { completion(BindEmailFlowResult(status: .bindFailed, error: error)) }
                                }
                            }
                        })
                }
            } catch {
                await MainActor.run { completion(BindEmailFlowResult(status: .userInfoFailed, error: error)) }
            }
        }
    }
    #endif
}
