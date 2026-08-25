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
            guard encryptionKey.data(using: .utf8)?.count == 32 else {
                throw CoreUserError.invalidConfig("encryptionKey must be 32 bytes for AES-256")
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
    public var emailBound: Bool
    public var phoneBound: Bool
    public var balance: Double
    public var userInfoSynced: Bool

    public init(
        uid: String,
        deviceId: String,
        email: String? = nil,
        phone: String? = nil,
        emailBound: Bool = false,
        phoneBound: Bool = false,
        balance: Double = 0,
        userInfoSynced: Bool = false
    ) {
        self.uid = uid
        self.deviceId = deviceId
        self.email = email
        self.phone = phone
        self.emailBound = emailBound
        self.phoneBound = phoneBound
        self.balance = balance
        self.userInfoSynced = userInfoSynced
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
    public var password: String

    public init(
        accountType: AccountType,
        email: String? = nil,
        phonePrefix: String? = nil,
        phone: String? = nil,
        password: String
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
    public var uid: String
    public var changeType: String
    public var cost: Double
    public var beforeCoins: Double
    public var afterCoins: Double
    public var balance: Double

    public init(
        uid: String,
        changeType: String,
        cost: Double,
        beforeCoins: Double,
        afterCoins: Double,
        balance: Double
    ) {
        self.uid = uid
        self.changeType = changeType
        self.cost = cost
        self.beforeCoins = beforeCoins
        self.afterCoins = afterCoins
        self.balance = balance
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

public enum CoreUserError: Error, LocalizedError, Equatable {
    case invalidConfig(String)
    case notInitialized
    case invalidResponse(String)
    case httpStatus(Int, String)
    case apiError(String)
    case encryptionKeyRequired
    case encryptionFailed

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
        }
    }
}
