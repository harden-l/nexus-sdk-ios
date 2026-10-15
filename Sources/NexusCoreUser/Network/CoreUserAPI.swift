import Foundation

final class CoreUserAPI: @unchecked Sendable {
    let config: CoreUserConfig
    private let session: URLSession
    init(config: CoreUserConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func post(path: String, body: Data = Data("{}".utf8), token: String? = nil, login: Bool = false) async throws -> Data {
        guard path.hasPrefix("/api/v1/"), !path.contains(".."), !path.contains("?"), !path.contains("#"),
              let base = URL(string: config.apiBaseUrl), let scheme = base.scheme,
              ["https", "http"].contains(scheme), base.host != nil,
              let url = URL(string: config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
        else { throw CoreUserError.invalidConfig("Invalid API URL or path") }
        guard case .object = try APIJSON.decode(body) else { throw CoreUserError.invalidConfig("Request must be a JSON object") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.encrypt ? "1" : "0", forHTTPHeaderField: "Encrypt")
        request.setValue(config.encrypt ? config.productName : config.productId,
                         forHTTPHeaderField: config.encrypt ? "Product" : "ProductId")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try APIRequestEncryption.prepareBody(String(decoding: body, as: UTF8.self), config: config, encrypt: config.encrypt && !login)
        if config.debug { print("[CoreUserAPI] POST \(path) encrypt=\(config.encrypt ? 1 : 0)") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoreUserError.invalidResponse("Missing HTTP response") }
        let trace = http.value(forHTTPHeaderField: "X-Trace-ID")
        let root: APIJSON
        let plain = try? APIJSON.decode(data)
        // Product/key failures can arrive before server-side encryption.
        if let plain, case .number(let code) = plain["code"], code != 1 {
            root = plain
        } else {
            do {
                let text = try APIRequestEncryption.readResponse(data, config: config)
                root = try APIJSON.decode(Data(text.utf8))
            } catch {
                throw CoreUserError.business(code: http.statusCode == 401 ? 401 : -1,
                                             message: "Invalid or undecodable API response", httpStatus: http.statusCode, traceId: trace)
            }
        }
        guard case .number(let code) = root["code"], code == Decimal(root["code"].int) else {
            throw CoreUserError.business(code: http.statusCode == 401 ? 401 : -1, message: "Response missing integer code", httpStatus: http.statusCode, traceId: trace)
        }
        if config.debug { print("[CoreUserAPI] \(path) HTTP=\(http.statusCode) code=\(code) trace=\(trace ?? "-")") }
        guard (200..<300).contains(http.statusCode), code == 1 else {
            throw CoreUserError.business(code: http.statusCode == 401 ? 401 : root["code"].int,
                                         message: root["message"].string, httpStatus: http.statusCode, traceId: trace)
        }
        guard case .object = root["data"] else { throw CoreUserError.invalidResponse("Response data must be an object") }
        return try root["data"].data()
    }

    func login(deviceId: String, type: LoginType, email: String?, phonePrefix: String?, phone: String?, password: String?) async throws -> LoginSession {
        var fields: [String: APIJSON] = ["login_type": .string(type.rawValue), "device_id": .string(deviceId),
                                       "version": .string(config.version), "country": .string(config.country), "language": .string(config.language)]
        if let gt = config.gt { fields["gt"] = .number(Decimal(gt)) }
        switch type {
        case .guest: break
        case .email:
            let email = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !email.isEmpty else { throw CoreUserError.invalidConfig("email is required") }
            try Self.validatePassword(password ?? "")
            fields["email"] = .string(email)
            fields["password"] = .string(password!)
        case .phone:
            let prefix = (phonePrefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = (phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty, !phone.isEmpty else { throw CoreUserError.invalidConfig("phonePrefix and phone are required") }
            try Self.validatePassword(password ?? "")
            fields["phone_prefix"] = .string(prefix)
            fields["phone"] = .string(phone)
            fields["password"] = .string(password!)
        }
        let body = try APIJSON.object(fields).data()
        let result = try APIJSON.decode(await post(path: "/api/v1/account/login", body: body, login: true))
        let uid = try result.requireString("uid")
        let token = try result.requireString("token")
        let expiresAt = try result.requireSeconds("expires_at")
        guard expiresAt > Int64(Date().timeIntervalSince1970) else {
            throw CoreUserError.invalidResponse("Login response missing valid uid/token/expires_at")
        }
        return LoginSession(uid: uid, token: token, expiresAt: expiresAt, loginType: type)
    }

    static func validatePassword(_ password: String) throws {
        guard (8...72).contains(password.utf8.count), password.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw CoreUserError.invalidConfig("password must be 8-72 bytes of visible ASCII without whitespace")
        }
    }

    static func user(_ data: Data, deviceId: String) throws -> SDKUser {
        let value = try APIJSON.decode(data)
        let uid = try value.requireString("uid")
        let balance = try value.requireNumber("balance") * 100
        return SDKUser(uid: uid, deviceId: deviceId, email: value["email"].string,
                       phone: value["phone"].string, emailBound: value["email_bound"].bool,
                       phoneBound: value["phone_bound"].bool, balance: NSDecimalNumber(decimal: balance).doubleValue,
                       isVip: try value.requireBool("is_vip"), vipExpiredAt: try value.requireSeconds("vip_expired_at"),
                       userInfoSynced: true, phonePrefix: value["phone_prefix"].string, balanceDecimal: balance)
    }
}
