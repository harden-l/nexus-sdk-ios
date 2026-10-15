import Foundation

/// A captured authenticated identity. It fails after account/product/session changes instead of selecting a new user.
public final class CoreUserSessionContext: @unchecked Sendable {
    private let runtime: CoreUserRuntime
    private let session: LoginSession
    private let revision: Int
    public var uid: String { session.uid }
    init(runtime: CoreUserRuntime, session: LoginSession, revision: Int) {
        self.runtime = runtime; self.session = session; self.revision = revision
    }
    public func validate() throws { try runtime.locked { try runtime.assertIdentity(session, expectedRevision: revision) } }
    public func post(path: String, body: Data) async throws -> Data {
        try await runtime.request(path: path, body: body, session: session, expectedRevision: revision)
    }
    public func fetchUserInfo() async throws -> SDKUser { try await runtime.fetchUser(session: session, expectedRevision: revision) }

    func bindAccount(_ params: BindAccountParams) async throws -> BindAccountResult {
        try validate()
        var fields: [String: APIJSON] = ["account_type": .string(params.accountType.rawValue)]
        if let password = params.password, !password.isEmpty {
            try CoreUserAPI.validatePassword(password)
            fields["password"] = .string(password)
        }
        switch params.accountType {
        case .email:
            let email = (params.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !email.isEmpty else { throw CoreUserError.invalidConfig("email is required") }
            fields["email"] = .string(email)
        case .phone:
            let prefix = (params.phonePrefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = (params.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty, !phone.isEmpty else { throw CoreUserError.invalidConfig("phonePrefix and phone are required") }
            fields["phone_prefix"] = .string(prefix)
            fields["phone"] = .string(phone)
        }
        fields["device_id"] = .string(runtime.locked { runtime.storage.getOrCreateDeviceId() })
        let value = try APIJSON.decode(await post(path: "/api/v1/account/bind", body: APIJSON.object(fields).data()))
        let result = try BindAccountResult(uid: value.requireString("uid"), accountType: value.requireString("account_type"),
                                          accountValue: value.requireString("account_value"), bound: value.requireBool("bound"))
        try runtime.locked {
            try validate()
            guard result.uid == session.uid else { throw CoreUserError.invalidResponse("Binding identity mismatch") }
            if var user = try runtime.user() {
                user.userInfoSynced = false
                if params.accountType == .email { user.email = result.accountValue; user.emailBound = result.bound }
                else { user.phone = params.phone; user.phonePrefix = params.phonePrefix; user.phoneBound = result.bound }
                runtime.storage.saveUser(user)
            }
        }
        _ = try? await fetchUserInfo()
        try validate()
        return result
    }
    public func getWeeklyPointsInfo() async throws -> WeeklyPointsInfo {
        let value = try APIJSON.decode(await post(path: "/api/v1/weekly-points/info", body: Data("{}".utf8)))
        let points = try value.requireNumber("weekly_points")
        return try WeeklyPointsInfo(isVip: value.requireBool("is_vip"), marketProductId: value.requireString("market_product_id", nonempty: false),
                                    weeklyPoints: NSDecimalNumber(decimal: points).intValue, canClaim: value.requireBool("can_claim"),
                                    cannotClaimReason: value.requireString("cannot_claim_reason", nonempty: false), weeklyPointsDecimal: points)
    }
    public func claimWeeklyPoints() async throws -> WeeklyPointsClaimResult {
        let value = try APIJSON.decode(await post(path: "/api/v1/weekly-points/claim", body: Data("{}".utf8)))
        let points = try value.requireNumber("points")
        let time = try value.requireSeconds("claim_time")
        return try WeeklyPointsClaimResult(success: true, points: NSDecimalNumber(decimal: points).intValue,
                                           transactionId: value.requireString("transaction_id"),
                                           claimTime: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(time))),
                                           pointsDecimal: points, marketProductId: value.requireString("market_product_id"),
                                           claimTimeSeconds: time, beforeCoinsDecimal: value.requireNumber("before_coins"),
                                           afterCoinsDecimal: value.requireNumber("after_coins"), balanceDecimal: value.requireNumber("balance"))
    }
}
