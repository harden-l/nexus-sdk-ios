import Foundation
import NexusCoreUser

final class OrderVerificationAPI: @unchecked Sendable {
    private let config: CoreUserConfig
    private let session: URLSession

    init(config: CoreUserConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func verify(
        channel: PaymentChannel,
        token: String,
        platformProductId: String,
        uid: String,
        isSubscription: Bool,
        tradeOrderId: String
    ) async throws -> OrderVerificationResult {
        let path: String
        switch channel {
        case .appStore:
            path = "/pp/v7/apple/os"
        case .googlePlay:
            path = "/pp/v7/gp/os"
        default:
            throw PaymentError.apiError("Server verification is not configured for \(channel.rawValue)")
        }

        let body = try jsonString([
            "token": token,
            "platform_product_id": platformProductId,
            "uid": uid,
            "issub": isSubscription,
            "trade_order_id": tradeOrderId
        ])
        let response = try await post(path: path, body: body)
        let root = try jsonObject(response)
        if let code = int(root["code"]), code != 1 {
            throw PaymentError.apiError(string(root["message"]) ?? "Order verification failed")
        }
        let data = root["data"] as? [String: Any] ?? root
        return OrderVerificationResult(
            tradeOrderId: string(data["trade_order_id"]) ?? tradeOrderId,
            status: OrderVerificationResult.Status.fromCode(int(data["status"])),
            isSubscription: bool(data["issub"]) ?? isSubscription,
            token: string(data["token"]) ?? token,
            platformProductId: string(data["platform_product_id"]) ?? platformProductId,
            startedTime: int64(data["started_time"]),
            endsTime: int64(data["ends_time"]),
            successCount: int(data["success_count"]),
            amount: string(data["amount"])
        )
    }

    private func post(path: String, body: String) async throws -> String {
        guard let url = URL(string: config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw PaymentError.invalidConfig("Invalid apiBaseUrl")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.productName, forHTTPHeaderField: "Product")
        request.setValue(config.encrypt ? "1" : "0", forHTTPHeaderField: "Encrypt")
        if !config.encrypt {
            request.setValue(config.productId, forHTTPHeaderField: "ProductId")
        }
        request.httpBody = try APIRequestEncryption.prepareBody(body, config: config, encrypt: config.encrypt)
        if config.debug {
            print("[OrderVerificationAPI] POST \(path) encrypt=\(config.encrypt ? 1 : 0)")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let decoded = try APIRequestEncryption.readResponse(data, config: config, encrypt: config.encrypt)
        if config.debug {
            print("[OrderVerificationAPI] POST \(path) status=\(status) response=\(decoded)")
        }
        guard (200..<300).contains(status) else {
            throw PaymentError.apiError("HTTP \(status): \(decoded)")
        }
        return decoded
    }

    private func jsonString(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonObject(_ body: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] ?? [:]
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value { return "\(value)" }
        return nil
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "1" || value.lowercased() == "true" }
        return nil
    }
}
