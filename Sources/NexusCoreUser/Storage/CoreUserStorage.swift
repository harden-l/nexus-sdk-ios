import Foundation
import CryptoKit
import Security

public struct SessionInfo: Equatable, Sendable {
    public let uid: String
    public let expiresAt: Int64
    public let loginType: LoginType
    public var isValid: Bool { expiresAt > Int64(Date().timeIntervalSince1970) }
}

struct LoginSession: Codable, Equatable, Sendable {
    let uid: String
    let token: String
    let expiresAt: Int64
    let loginType: LoginType
    var isValid: Bool { !token.isEmpty && !uid.isEmpty && expiresAt > Int64(Date().timeIntervalSince1970) }
}

final class CoreUserStorage: @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String
    private let devicePrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(suiteName: String? = nil, productId: String, apiBaseUrl: String = "") {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.devicePrefix = "nexus.coreuser.\(productId)."
        let scope = apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "|" + productId + "|" + (suiteName ?? "standard")
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        self.prefix = "nexus.coreuser.v1.\(digest)."
    }

    func getOrCreateDeviceId() -> String {
        let key = devicePrefix + "device_id"
        if let value = defaults.string(forKey: key), !value.isEmpty {
            return value
        }
        let value = "ios_" + UUID().uuidString.lowercased()
        defaults.set(value, forKey: key)
        return value
    }

    func saveUser(_ user: SDKUser) {
        defaults.set(try? encoder.encode(user), forKey: prefix + "user")
    }

    func getUser() -> SDKUser? {
        guard let data = defaults.data(forKey: prefix + "user") else { return nil }
        return try? decoder.decode(SDKUser.self, from: data)
    }

    func clearUser() {
        defaults.removeObject(forKey: prefix + "user")
    }

    var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.nexus.sdk.coreuser.session",
         kSecAttrAccount as String: prefix]
    }

    func getSession() throws -> LoginSession? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CoreUserError.storageFailure(status) }
        let session = try decoder.decode(LoginSession.self, from: data)
        // Keychain can outlive preferences (e.g. reinstall). Retain the identity kind before expiry/401 clearing.
        defaults.set(session.loginType.rawValue, forKey: prefix + "login_type")
        return session.token.isEmpty ? nil : session
    }

    func saveSession(_ session: LoginSession) throws {
        let data = try encoder.encode(session)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(keychainQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(keychainQuery.merging(attrs) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CoreUserError.storageFailure(status) }
        defaults.set(session.loginType.rawValue, forKey: prefix + "login_type")
    }

    func clearSession(resetLoginType: Bool = false) throws {
        let type = resetLoginType ? LoginType.guest : try getSession()?.loginType ?? lastLoginType
        if !resetLoginType, type != .guest {
            // Keep only an account-kind marker with Keychain lifetime; never retain the invalid token or UID.
            try saveSession(LoginSession(uid: "", token: "", expiresAt: 0, loginType: type))
            clearUser()
            return
        }
        let status = SecItemDelete(keychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CoreUserError.storageFailure(status) }
        clearUser()
        if resetLoginType { defaults.removeObject(forKey: prefix + "login_type") }
    }

    var lastLoginType: LoginType {
        LoginType(rawValue: defaults.string(forKey: prefix + "login_type") ?? "guest") ?? .guest
    }

    func setLoginAttributionEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: prefix + "login_att")
    }

    func isLoginAttributionEnabled() -> Bool {
        defaults.bool(forKey: prefix + "login_att")
    }
}
