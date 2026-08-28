import Foundation

final class CoreUserStorage: @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(suiteName: String? = nil, productId: String) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.prefix = "nexus.coreuser.\(productId)."
    }

    func getOrCreateDeviceId() -> String {
        let key = prefix + "device_id"
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
        guard let user = getUser() else {
            defaults.removeObject(forKey: prefix + "user")
            return
        }
        let retainedUser = SDKUser(uid: user.uid, deviceId: user.deviceId)
        saveUser(retainedUser)
    }

    func saveSwitchConfig(_ value: String) {
        defaults.set(value, forKey: prefix + "switch_config")
    }

    func getSwitchConfig() -> String? {
        defaults.string(forKey: prefix + "switch_config")
    }

    func clearSwitchConfig() {
        defaults.removeObject(forKey: prefix + "switch_config")
    }

    func setLoginAttributionEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: prefix + "login_att")
    }

    func isLoginAttributionEnabled() -> Bool {
        defaults.bool(forKey: prefix + "login_att")
    }
}
