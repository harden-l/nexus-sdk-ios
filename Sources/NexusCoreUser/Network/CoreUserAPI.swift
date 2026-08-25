import Foundation

final class CoreUserAPI: @unchecked Sendable {
    private static let userBalanceDisplayScale = 100.0
    private let config: CoreUserConfig
    private let session: URLSession

    init(config: CoreUserConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func login(
        deviceId: String,
        uid: String,
        loginType: LoginType,
        att: Int,
        email: String? = nil,
        phonePrefix: String? = nil,
        phone: String? = nil,
        password: String? = nil
    ) async throws -> (uid: String, config: [String: Any?]) {
        try validateLogin(
            loginType: loginType,
            email: email,
            phonePrefix: phonePrefix,
            phone: phone,
            password: password
        )
        var values: [String: Any?] = [
            "login_type": loginType.rawValue,
            "uid": uid,
            "device_id": deviceId,
            "version": config.version,
            "country": config.country,
            "language": config.language,
            "is_has_sim": false,
            "st": timestamp(),
            "att": att,
            "level": 1,
            "email": email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "phone_prefix": phonePrefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "phone": phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "password": password ?? ""
        ]
        if let gt = config.gt {
            values["gt"] = gt
        }
        let response = try await post(
            path: "/m/v7/user/login",
            values: values,
            encrypt: false
        )
        let root = try JSONObject.decodeObject(response)
        let data = root["data"] as? [String: Any] ?? [:]
        guard let uid = JSONObject.string(root, keys: "uid") ?? JSONObject.string(data, keys: "uid") else {
            throw CoreUserError.invalidResponse("Login response missing uid")
        }
        let configObject = data.isEmpty ? root : data
        let loginConfig = configObject.filter { !["uid", "code", "message", "data"].contains($0.key) }
        return (uid, loginConfig)
    }

    func getUserInfo(uid: String, deviceId: String) async throws -> SDKUser {
        let response = try await post(path: "/m/v7/user/info", values: ["uid": uid])
        let root = try JSONObject.decodeObject(response)
        if let code = JSONObject.int(root, key: "code"), code != 1 {
            throw CoreUserError.apiError(JSONObject.string(root, keys: "message") ?? "Get user info failed")
        }
        let data = root["data"] as? [String: Any] ?? root
        return SDKUser(
            uid: JSONObject.string(data, keys: "uid") ?? uid,
            deviceId: deviceId,
            email: JSONObject.string(data, keys: "email"),
            phone: JSONObject.string(data, keys: "phone"),
            emailBound: JSONObject.bool(data, key: "email_bound"),
            phoneBound: JSONObject.bool(data, key: "phone_bound"),
            balance: (JSONObject.double(data, key: "balance") ?? 0) * Self.userBalanceDisplayScale,
            userInfoSynced: true
        )
    }

    func bindAccount(uid: String, deviceId: String, params: BindAccountParams) async throws -> BindAccountResult {
        guard !params.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreUserError.invalidConfig("password is required")
        }
        switch params.accountType {
        case .email where (params.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            throw CoreUserError.invalidConfig("email is required")
        case .phone where (params.phonePrefix ?? "").isEmpty || (params.phone ?? "").isEmpty:
            throw CoreUserError.invalidConfig("phonePrefix and phone are required")
        default:
            break
        }
        let response = try await post(path: "/m/v7/user/bind_account", values: [
            "uid": uid,
            "device_id": deviceId,
            "account_type": params.accountType.rawValue,
            "email": params.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "phone_prefix": params.phonePrefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "phone": params.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "password": params.password
        ])
        let root = try JSONObject.decodeObject(response)
        if let code = JSONObject.int(root, key: "code"), code != 1 {
            throw CoreUserError.apiError(JSONObject.string(root, keys: "message") ?? "Bind account failed")
        }
        let data = root["data"] as? [String: Any] ?? root
        return BindAccountResult(
            uid: JSONObject.string(data, keys: "uid") ?? uid,
            accountType: JSONObject.string(data, keys: "account_type") ?? params.accountType.rawValue,
            accountValue: JSONObject.string(data, keys: "account_value") ?? params.email ?? [params.phonePrefix, params.phone].compactMap { $0 }.joined(),
            bound: JSONObject.bool(data, key: "bound", default: true)
        )
    }

    private func validateLogin(
        loginType: LoginType,
        email: String?,
        phonePrefix: String?,
        phone: String?,
        password: String?
    ) throws {
        switch loginType {
        case .guest:
            return
        case .email:
            guard !(email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CoreUserError.invalidConfig("email is required")
            }
            guard !(password ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CoreUserError.invalidConfig("password is required")
            }
        case .phone:
            guard !(phonePrefix ?? "").isEmpty, !(phone ?? "").isEmpty else {
                throw CoreUserError.invalidConfig("phonePrefix and phone are required")
            }
            guard !(password ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CoreUserError.invalidConfig("password is required")
            }
        }
    }

    func consumeChatCoins(uid: String, cost: Double, remark: String?) async throws -> ConsumeChatCoinsResult {
        guard cost > 0 else { throw CoreUserError.invalidConfig("cost must be greater than 0") }
        var values: [String: Any?] = [
            "uid": uid,
            "cost": cost
        ]
        let trimmedRemark = remark?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedRemark, !trimmedRemark.isEmpty {
            values["remark"] = trimmedRemark
        }
        let response = try await post(path: "/m/v7/coins/consume_chat", values: values)
        let root = try JSONObject.decodeObject(response)
        if let code = JSONObject.int(root, key: "code"), code != 1 {
            throw CoreUserError.apiError(JSONObject.string(root, keys: "message") ?? "Consume chat coins failed")
        }
        let data = root["data"] as? [String: Any] ?? root
        return ConsumeChatCoinsResult(
            uid: JSONObject.string(data, keys: "uid") ?? uid,
            changeType: JSONObject.string(data, keys: "change_type") ?? "",
            cost: JSONObject.double(data, key: "cost") ?? cost,
            beforeCoins: JSONObject.double(data, key: "before_coins") ?? 0,
            afterCoins: JSONObject.double(data, key: "after_coins") ?? 0,
            balance: JSONObject.double(data, key: "balance") ?? 0
        )
    }

    func logout(uid: String) async throws {
        let response = try await post(path: "/m/v7/coins/deregister", values: ["uid": uid])
        let root = try JSONObject.decodeObject(response)
        if let code = JSONObject.int(root, key: "code"), code != 1 {
            throw CoreUserError.apiError(JSONObject.string(root, keys: "message") ?? "Logout failed")
        }
    }

    func getRelatedProducts() async throws -> [RelatedProduct] {
        let values: [String: Any?] = [
            "product_id": config.productId,
            "account_name": config.accountName
        ]
        let response = try await post(path: "/related_products", values: values)
        let root = try JSONObject.decodeObject(response)
        let array = (root["data"] as? [[String: Any]])
            ?? ((root["data"] as? [String: Any])?["list"] as? [[String: Any]])
            ?? (root["list"] as? [[String: Any]])
            ?? []
        return array.map {
            RelatedProduct(
                productId: JSONObject.string($0, keys: "product_id", "id") ?? "",
                productName: JSONObject.string($0, keys: "product_name", "name", "title") ?? "",
                description: JSONObject.string($0, keys: "description", "desc") ?? "",
                icon: JSONObject.string($0, keys: "icon", "icon_url") ?? "",
                downloadUrl: JSONObject.string($0, keys: "download_url", "store_url", "url") ?? "",
                packageName: JSONObject.string($0, keys: "package_name", "bundle_id") ?? "",
                iosScheme: JSONObject.string($0, keys: "ios_scheme", "scheme", "url_scheme")
            )
        }.filter { !$0.productId.isEmpty && !$0.productName.isEmpty }
    }

    private func post(path: String, values: [String: Any?], encrypt: Bool? = nil) async throws -> String {
        let shouldEncrypt = encrypt ?? config.encrypt
        guard let url = URL(string: config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw CoreUserError.invalidConfig("Invalid apiBaseUrl")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.productName, forHTTPHeaderField: "Product")
        request.setValue(shouldEncrypt ? "1" : "0", forHTTPHeaderField: "Encrypt")
        if !shouldEncrypt {
            request.setValue(config.productId, forHTTPHeaderField: "ProductId")
        }
        let plainBody = String(data: try JSONObject.encode(values), encoding: .utf8) ?? "{}"
        request.httpBody = try APIRequestEncryption.prepareBody(plainBody, config: config, encrypt: shouldEncrypt)
        if config.debug {
            var debugValues = values
            if debugValues.keys.contains("password") {
                debugValues["password"] = "***"
            }
            let debugBody = String(data: try JSONObject.encode(debugValues), encoding: .utf8) ?? "{}"
            print("[CoreUserAPI] POST \(path) encrypt=\(shouldEncrypt ? 1 : 0) request=\(debugBody)")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let decoded = try APIRequestEncryption.readResponse(data, config: config, encrypt: shouldEncrypt)
        if config.debug {
            print("[CoreUserAPI] POST \(path) status=\(status) response=\(decoded)")
        }
        guard (200..<300).contains(status) else { throw CoreUserError.httpStatus(status, decoded) }
        return decoded
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }
}
