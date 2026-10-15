import Foundation
import NexusCoreUser

typealias AuthenticatedPaymentPost = @Sendable (String, Data) async throws -> Data

final class OrderVerificationAPI: Sendable {
    private let post: AuthenticatedPaymentPost?

    init(post: AuthenticatedPaymentPost? = nil) {
        self.post = post
    }

    func verify(
        channel: PaymentChannel,
        token: String,
        platformProductId: String,
        isSubscription: Bool,
        tradeOrderId: String,
        originalTransactionId: String? = nil,
        expectedUid: String? = nil
    ) async throws -> OrderVerificationResult {
        let path: String
        switch channel {
        case .appStore: path = "/api/v1/order/apple/status"
        case .googlePlay: path = "/api/v1/order/google/status"
        default: throw PaymentError.apiError("Server verification is not configured for \(channel.rawValue)")
        }
        var body: [String: Any] = ["issub": isSubscription]
        if isSubscription {
            if channel == .appStore {
                guard let originalTransactionId, !originalTransactionId.isEmpty else {
                    throw PaymentError.apiError("Apple original transaction id is required")
                }
                body["original_transaction_id"] = originalTransactionId
            } else {
                guard !token.isEmpty else { throw PaymentError.apiError("Google subscription token is required") }
                body["token"] = token
            }
        } else {
            guard !platformProductId.isEmpty else { throw PaymentError.apiError("Platform product id is required") }
            guard channel == .googlePlay ? (!token.isEmpty && !tradeOrderId.isEmpty) : (!token.isEmpty || !tradeOrderId.isEmpty) else {
                throw PaymentError.apiError("Store transaction credentials are required")
            }
            body["platform_product_id"] = platformProductId
            if !token.isEmpty { body["token"] = token }
            if !tradeOrderId.isEmpty { body["trade_order_id"] = tradeOrderId }
        }
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        if let post { data = try await post(path, encoded) }
        else { data = try await NexusCoreUser.shared.postAuthenticated(path: path, body: encoded, expectedUid: expectedUid) }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return OrderVerificationResult(
            tradeOrderId: response.trade_order_id,
            status: .fromCode(response.status),
            isSubscription: response.issub,
            token: nil,
            platformProductId: response.platform_product_id,
            startedTime: response.started_at,
            endsTime: response.expires_at,
            successCount: response.success_count,
            amount: response.amount,
            currency: response.currency
        )
    }

    private struct Response: Decodable {
        let trade_order_id: String
        let status: Int
        let issub: Bool
        let platform_product_id: String
        let amount: String
        let currency: String
        let started_at: Int64?
        let expires_at: Int64?
        let success_count: Int?
    }
}
