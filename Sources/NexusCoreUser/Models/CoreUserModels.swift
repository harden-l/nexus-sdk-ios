import Foundation

private enum CoreUserConfigDefaults {
    static var country: String {
        let parts = Locale.current.identifier.split(separator: "_")
        return parts.count > 1 ? String(parts[1]) : "US"
    }

    static var language: String {
        Locale.current.identifier.split(separator: "_").first.map(String.init) ?? "en"
    }
}

public enum LoginType: String, Codable, Sendable {
    case guest
    case email
    case phone
}

public struct CoreUserConfig: Codable, Equatable, Sendable {
    public var appId: String
    public var productId: String
    public var productName: String
    public var accountName: String
    public var apiBaseUrl: String
    public var version: String
    public var country: String
    public var language: String
    public var encrypt: Bool
    public var encryptionKey: String?
    public var debug: Bool
    public var gt: Int?

    public init(
        appId: String = "",
        productId: String,
        productName: String,
        accountName: String = "test",
        apiBaseUrl: String,
        version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
        country: String = "",
        language: String = "",
        encrypt: Bool = true,
        encryptionKey: String? = nil,
        debug: Bool = false,
        gt: Int? = nil
    ) throws {
        guard !productId.isEmpty else { throw CoreUserError.invalidConfig("productId is required") }
        guard !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreUserError.invalidConfig("accountName is required")
        }
        guard !apiBaseUrl.isEmpty else { throw CoreUserError.invalidConfig("apiBaseUrl is required") }
        if encrypt {
            guard let encryptionKey, !encryptionKey.isEmpty else {
                throw CoreUserError.invalidConfig("encryptionKey is required when encrypt=true")
            }
            guard [16, 24, 32].contains(encryptionKey.utf8.count) else {
                throw CoreUserError.invalidConfig("encryptionKey must be 16, 24 or 32 bytes")
            }
        }
        self.appId = appId
        self.productId = productId
        self.productName = productName
        self.accountName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiBaseUrl = apiBaseUrl
        self.version = version.isEmpty ? "1.0.0" : version
        self.country = country.isEmpty ? CoreUserConfigDefaults.country : country
        self.language = language.isEmpty ? CoreUserConfigDefaults.language : language
        self.encrypt = encrypt
        self.encryptionKey = encryptionKey
        self.debug = debug
        self.gt = gt
    }
}

public struct SDKUser: Codable, Equatable, Sendable {
    public var uid: String
    public var deviceId: String
    public var email: String?
    public var phone: String?
    public var phonePrefix: String?
    public var emailBound: Bool
    public var phoneBound: Bool
    public var balance: Double
    public var balanceDecimal: Decimal
    public var isVip: Bool
    public var vipExpiredAt: Int64
    public var userInfoSynced: Bool

    public init(
        uid: String,
        deviceId: String,
        email: String? = nil,
        phone: String? = nil,
        emailBound: Bool = false,
        phoneBound: Bool = false,
        balance: Double = 0,
        isVip: Bool = false,
        vipExpiredAt: Int64 = 0,
        userInfoSynced: Bool = false,
        phonePrefix: String? = nil,
        balanceDecimal: Decimal? = nil
    ) {
        self.uid = uid
        self.deviceId = deviceId
        self.email = email
        self.phone = phone
        self.phonePrefix = phonePrefix
        self.emailBound = emailBound
        self.phoneBound = phoneBound
        self.balance = balance
        self.balanceDecimal = balanceDecimal ?? Decimal(string: String(balance)) ?? 0
        self.isVip = isVip
        self.vipExpiredAt = vipExpiredAt
        self.userInfoSynced = userInfoSynced
    }

    private enum CodingKeys: String, CodingKey {
        case uid, deviceId, email, phone, phonePrefix, emailBound, phoneBound, balance, balanceDecimal, isVip, vipExpiredAt, userInfoSynced
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        uid = try values.decode(String.self, forKey: .uid)
        deviceId = try values.decode(String.self, forKey: .deviceId)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        phone = try values.decodeIfPresent(String.self, forKey: .phone)
        phonePrefix = try values.decodeIfPresent(String.self, forKey: .phonePrefix)
        emailBound = try values.decodeIfPresent(Bool.self, forKey: .emailBound) ?? false
        phoneBound = try values.decodeIfPresent(Bool.self, forKey: .phoneBound) ?? false
        balance = try values.decodeIfPresent(Double.self, forKey: .balance) ?? 0
        balanceDecimal = try values.decodeIfPresent(Decimal.self, forKey: .balanceDecimal) ?? Decimal(string: String(balance)) ?? 0
        isVip = try values.decodeIfPresent(Bool.self, forKey: .isVip) ?? false
        vipExpiredAt = try values.decodeIfPresent(Int64.self, forKey: .vipExpiredAt) ?? 0
        userInfoSynced = try values.decodeIfPresent(Bool.self, forKey: .userInfoSynced) ?? false
    }
}

public struct WeeklyPointsInfo: Codable, Equatable, Sendable {
    public var isVip: Bool
    public var marketProductId: String
    @available(*, deprecated, message: "Use weeklyPointsDecimal; this compatibility value truncates fractions")
    public var weeklyPoints: Int
    public var weeklyPointsDecimal: Decimal
    public var productId: String { marketProductId }
    public var canClaim: Bool
    public var cannotClaimReason: String

    public init(
        isVip: Bool,
        marketProductId: String,
        weeklyPoints: Int,
        canClaim: Bool,
        cannotClaimReason: String,
        weeklyPointsDecimal: Decimal? = nil
    ) {
        self.isVip = isVip
        self.marketProductId = marketProductId
        self.weeklyPoints = weeklyPoints
        self.weeklyPointsDecimal = weeklyPointsDecimal ?? Decimal(weeklyPoints)
        self.canClaim = canClaim
        self.cannotClaimReason = cannotClaimReason
    }
}

public struct WeeklyPointsClaimResult: Codable, Equatable, Sendable {
    public var success: Bool
    @available(*, deprecated, message: "Use pointsDecimal; this compatibility value truncates fractions")
    public var points: Int
    public var pointsDecimal: Decimal
    public var marketProductId: String
    public var productId: String { marketProductId }
    public var claimTimeSeconds: Int64
    public var beforeCoinsDecimal: Decimal
    public var afterCoinsDecimal: Decimal
    public var balanceDecimal: Decimal
    public var transactionId: String
    public var claimTime: String

    public init(success: Bool, points: Int, transactionId: String, claimTime: String,
                pointsDecimal: Decimal? = nil, marketProductId: String = "", claimTimeSeconds: Int64 = 0,
                beforeCoinsDecimal: Decimal = 0, afterCoinsDecimal: Decimal = 0, balanceDecimal: Decimal = 0) {
        self.success = success
        self.points = points
        self.pointsDecimal = pointsDecimal ?? Decimal(points)
        self.marketProductId = marketProductId
        self.claimTimeSeconds = claimTimeSeconds
        self.beforeCoinsDecimal = beforeCoinsDecimal
        self.afterCoinsDecimal = afterCoinsDecimal
        self.balanceDecimal = balanceDecimal
        self.transactionId = transactionId
        self.claimTime = claimTime
    }
}

public struct BindAccountParams: Equatable, Sendable {
    public enum AccountType: String, Sendable {
        case email
        case phone
    }

    public var accountType: AccountType
    public var email: String?
    public var phonePrefix: String?
    public var phone: String?
    public var password: String?

    public init(
        accountType: AccountType,
        email: String? = nil,
        phonePrefix: String? = nil,
        phone: String? = nil,
        password: String? = nil
    ) {
        self.accountType = accountType
        self.email = email
        self.phonePrefix = phonePrefix
        self.phone = phone
        self.password = password
    }
}

public struct BindAccountResult: Equatable, Sendable {
    public var uid: String
    public var accountType: String
    public var accountValue: String
    public var bound: Bool
}

public struct ConsumeChatCoinsResult: Codable, Equatable, Sendable {
    public var idempotencyKey: String
    public var uid: String
    public var changeType: String
    public var cost: Double
    public var beforeCoins: Double
    public var afterCoins: Double
    public var balance: Double
    public var costDecimal: Decimal
    public var beforeCoinsDecimal: Decimal
    public var afterCoinsDecimal: Decimal
    public var balanceDecimal: Decimal

    public init(
        uid: String,
        changeType: String,
        cost: Double,
        beforeCoins: Double,
        afterCoins: Double,
        balance: Double,
        costDecimal: Decimal? = nil,
        beforeCoinsDecimal: Decimal? = nil,
        afterCoinsDecimal: Decimal? = nil,
        balanceDecimal: Decimal? = nil,
        idempotencyKey: String = ""
    ) {
        self.uid = uid
        self.idempotencyKey = idempotencyKey
        self.changeType = changeType
        self.cost = cost
        self.beforeCoins = beforeCoins
        self.afterCoins = afterCoins
        self.balance = balance
        self.costDecimal = costDecimal ?? Decimal(string: String(cost)) ?? 0
        self.beforeCoinsDecimal = beforeCoinsDecimal ?? Decimal(string: String(beforeCoins)) ?? 0
        self.afterCoinsDecimal = afterCoinsDecimal ?? Decimal(string: String(afterCoins)) ?? 0
        self.balanceDecimal = balanceDecimal ?? Decimal(string: String(balance)) ?? 0
    }
}

public enum BindEmailFlowStatus: String, Sendable {
    case alreadyBound = "already_bound"
    case bound
    case cancelled
    case userInfoFailed = "user_info_failed"
    case bindFailed = "bind_failed"
}

public struct BindEmailFlowResult: Sendable {
    public var status: BindEmailFlowStatus
    public var user: SDKUser?
    public var bindResult: BindAccountResult?
    public var error: Error?

    public init(
        status: BindEmailFlowStatus,
        user: SDKUser? = nil,
        bindResult: BindAccountResult? = nil,
        error: Error? = nil
    ) {
        self.status = status
        self.user = user
        self.bindResult = bindResult
        self.error = error
    }
}

public struct RelatedProduct: Codable, Equatable, Sendable {
    public var productId: String
    public var productName: String
    public var description: String
    public var icon: String
    public var downloadUrl: String
    public var packageName: String
    public var iosScheme: String?

    public init(
        productId: String,
        productName: String,
        description: String = "",
        icon: String = "",
        downloadUrl: String = "",
        packageName: String = "",
        iosScheme: String? = nil
    ) {
        self.productId = productId
        self.productName = productName
        self.description = description
        self.icon = icon
        self.downloadUrl = downloadUrl
        self.packageName = packageName
        self.iosScheme = iosScheme
    }
}

public enum CoreUserResult<Value> {
    case success(Value)
    case failure(Error)
}

public struct ConsumeChatCoinsError: Error, LocalizedError, @unchecked Sendable {
    public let idempotencyKey: String
    public let underlyingError: Error
    public var errorDescription: String? { underlyingError.localizedDescription }
}

public enum CoreUserError: Error, LocalizedError, Equatable {
    case invalidConfig(String)
    case notInitialized
    case invalidResponse(String)
    case httpStatus(Int, String)
    case apiError(String)
    case encryptionKeyRequired
    case encryptionFailed
    case business(code: Int, message: String, httpStatus: Int, traceId: String?)
    case sessionChanged
    case storageFailure(Int32)

    public var businessCode: Int? {
        if case .business(let code, _, _, _) = self { return code }
        return nil
    }

    public var traceId: String? {
        if case .business(_, _, _, let trace) = self { return trace }
        return nil
    }

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let message), .invalidResponse(let message), .apiError(let message):
            return message
        case .notInitialized:
            return "CoreUserSDK is not initialized"
        case .httpStatus(let status, let body):
            return "HTTP \(status): \(body)"
        case .encryptionKeyRequired:
            return "encryptionKey is required"
        case .encryptionFailed:
            return "AES encryption failed"
        case .business(let code, let message, let status, let trace):
            return "\(message) (code=\(code), HTTP=\(status), trace=\(trace ?? "-"))"
        case .sessionChanged:
            return "Session changed; discard this operation and retry explicitly"
        case .storageFailure(let code):
            return "Keychain operation failed (\(code))"
        }
    }
}
