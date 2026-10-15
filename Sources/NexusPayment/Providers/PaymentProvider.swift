import Foundation
import StoreKit

public struct PurchaseRequest: Sendable {
    public var product: Product
    public var uid: String
    public var paymentContext: PaymentContext
}

public struct ProviderPurchaseResult: Sendable {
    public var channel: PaymentChannel
    public var product: Product
    public var success: Bool
    public var orderId: String?
    public var purchaseToken: String?
    public var platformProductId: String
    public var isSubscription: Bool
    public var message: String?
    public var rawData: [String: AnySendableValue]
    public var pending: Bool = false
}

public struct RestoreResult: Sendable {
    public var channel: PaymentChannel
    public var purchases: [ProviderPurchaseResult]
    public var message: String?
}

public protocol PaymentProvider: AnyObject, Sendable {
    var channel: PaymentChannel { get }
    var requiresServerVerification: Bool { get }
    func getProducts(productIds: [String]) async throws -> [Product]
    func purchase(request: PurchaseRequest) async throws -> ProviderPurchaseResult
    func completePurchase(_ result: ProviderPurchaseResult) async
    func restore() async throws -> RestoreResult
}

public extension PaymentProvider {
    func getProducts(productIds: [String]) async throws -> [Product] { [] }
    func completePurchase(_ result: ProviderPurchaseResult) async {}
    func restore() async throws -> RestoreResult { RestoreResult(channel: channel, purchases: [], message: nil) }
}

public final class MockPaymentProvider: PaymentProvider, @unchecked Sendable {
    public let channel: PaymentChannel = .mock
    public let requiresServerVerification = false
    public init() {}

    public func purchase(request: PurchaseRequest) async throws -> ProviderPurchaseResult {
        let orderId = "mock_\(request.product.marketProductId)_\(Int64(Date().timeIntervalSince1970 * 1000))"
        return ProviderPurchaseResult(
            channel: channel,
            product: request.product,
            success: true,
            orderId: orderId,
            purchaseToken: orderId,
            platformProductId: request.product.marketProductId,
            isSubscription: request.product.productType == .subscription,
            message: "Mock purchase success",
            rawData: [:]
        )
    }
}

public final class ThirdPartyPaymentProvider: PaymentProvider, @unchecked Sendable {
    public let channel: PaymentChannel
    public let requiresServerVerification = false

    public init(channel: PaymentChannel) {
        self.channel = channel
    }

    public func purchase(request: PurchaseRequest) async throws -> ProviderPurchaseResult {
        ProviderPurchaseResult(
            channel: channel,
            product: request.product,
            success: false,
            orderId: nil,
            purchaseToken: nil,
            platformProductId: request.product.marketProductId,
            isSubscription: request.product.productType == .subscription,
            message: "Payment provider is not implemented for \(channel.rawValue)",
            rawData: [:]
        )
    }
}

public final class AppStorePaymentProvider: PaymentProvider, @unchecked Sendable {
    public let channel: PaymentChannel = .appStore
    public let requiresServerVerification = true
    private var updatesTask: Task<Void, Never>?
    private var pendingTransactions: [UInt64: Transaction] = [:]
    private let pendingLock = NSLock()
    public init() {}
    deinit {
        updatesTask?.cancel()
    }

    public func getProducts(productIds: [String]) async throws -> [Product] {
        let storeProducts = try await StoreKit.Product.products(for: productIds)
        return storeProducts.map { storeProduct in
            Product(
                marketProductId: storeProduct.id,
                name: storeProduct.displayName,
                description: storeProduct.description,
                productType: storeProduct.type == .autoRenewable ? .subscription : .iap,
                price: "\(storeProduct.price)",
                currency: storeProduct.priceFormatStyle.currencyCode,
                localizedPrice: storeProduct.displayPrice,
                subscriptionPeriod: storeProduct.subscription?.subscriptionPeriod.iso8601Text,
                trialPeriod: nil,
                hasTrial: storeProduct.subscription?.introductoryOffer != nil,
                storeDetailsAvailable: true
            )
        }
    }

    public func purchase(request: PurchaseRequest) async throws -> ProviderPurchaseResult {
        guard let storeProduct = try await StoreKit.Product.products(for: [request.product.marketProductId]).first else {
            return ProviderPurchaseResult(
                channel: channel,
                product: request.product,
                success: false,
                orderId: nil,
                purchaseToken: nil,
                platformProductId: request.product.marketProductId,
                isSubscription: request.product.productType == .subscription,
                message: "App Store product not found: \(request.product.marketProductId)",
                rawData: [:]
            )
        }
        let result = try await storeProduct.purchase(options: try purchaseOptions(uid: request.uid))
        switch result {
        case .success(let verification):
            guard let transaction = try? checkVerified(verification) else {
                return ProviderPurchaseResult(channel: channel, product: request.product, success: false,
                    orderId: nil, purchaseToken: nil, platformProductId: request.product.marketProductId,
                    isSubscription: request.product.productType == .subscription,
                    message: "Store verification pending", rawData: [:], pending: true)
            }
            let signedTransactionInfo = verification.jwsRepresentation
            remember(transaction)
            return ProviderPurchaseResult(
                channel: channel,
                product: request.product,
                success: true,
                orderId: String(transaction.id),
                purchaseToken: signedTransactionInfo,
                platformProductId: transaction.productID,
                isSubscription: request.product.productType == .subscription,
                message: "App Store purchase success",
                rawData: [
                    "transaction_id": AnySendableValue(transaction.id),
                    "original_transaction_id": AnySendableValue(transaction.originalID),
                    "purchase_date": AnySendableValue(transaction.purchaseDate.timeIntervalSince1970),
                    "signed_transaction_info": AnySendableValue(signedTransactionInfo),
                    "owner_uid": AnySendableValue(transaction.appAccountToken?.uuidString ?? "")
                ]
            )
        case .userCancelled:
            return ProviderPurchaseResult(
                channel: channel,
                product: request.product,
                success: false,
                orderId: nil,
                purchaseToken: nil,
                platformProductId: request.product.marketProductId,
                isSubscription: request.product.productType == .subscription,
                message: "User cancelled",
                rawData: [:]
            )
        case .pending:
            return ProviderPurchaseResult(
                channel: channel,
                product: request.product,
                success: false,
                orderId: nil,
                purchaseToken: nil,
                platformProductId: request.product.marketProductId,
                isSubscription: request.product.productType == .subscription,
                message: "Purchase pending",
                rawData: [:],
                pending: true
            )
        @unknown default:
            return ProviderPurchaseResult(
                channel: channel,
                product: request.product,
                success: false,
                orderId: nil,
                purchaseToken: nil,
                platformProductId: request.product.marketProductId,
                isSubscription: request.product.productType == .subscription,
                message: "Unknown purchase result",
                rawData: [:]
            )
        }
    }

    public func completePurchase(_ result: ProviderPurchaseResult) async {
        guard let transactionId = result.rawData["transaction_id"]?.value as? UInt64,
              let transaction = takePending(transactionId)
        else { return }
        await transaction.finish()
    }

    public func restore() async throws -> RestoreResult {
        try await AppStore.sync()
        var purchases: [ProviderPurchaseResult] = []
        var seen = Set<UInt64>()
        var invalidCount = 0
        for await verification in Transaction.unfinished {
            guard let transaction = try? checkVerified(verification) else { invalidCount += 1; continue }
            if seen.insert(transaction.id).inserted {
                purchases.append(recoveredResult(transaction, verification: verification))
            }
        }
        for await verification in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(verification) else { invalidCount += 1; continue }
            if seen.insert(transaction.id).inserted {
                purchases.append(recoveredResult(transaction, verification: verification))
            }
        }
        return RestoreResult(channel: channel, purchases: purchases,
                             message: invalidCount > 0 ? "Skipped \(invalidCount) unverified store transactions" : nil)
    }

    public func observeTransactions(_ handler: @escaping @Sendable (ProviderPurchaseResult) async -> Bool) {
        updatesTask?.cancel()
        updatesTask = Task {
            for await verification in Transaction.unfinished {
                guard !Task.isCancelled else { return }
                guard let transaction = try? checkVerified(verification) else { continue }
                let result = recoveredResult(transaction, verification: verification)
                if await handler(result) { await completePurchase(result) }
            }
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { return }
                do {
                    let transaction = try checkVerified(verification)
                    let result = providerResult(
                        transaction: transaction,
                        signedTransactionInfo: verification.jwsRepresentation,
                        product: Product(
                            marketProductId: transaction.productID,
                            name: transaction.productID,
                            productType: transaction.productType == .autoRenewable ? .subscription : .iap
                        ),
                        message: transaction.revocationDate == nil ? "Transaction updated" : "Transaction revoked"
                    )
                    if await handler(result) {
                        await completePurchase(result)
                    }
                } catch {
                    continue
                }
            }
        }
    }

    func stopObservingTransactions() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    static func accountToken(uid: String) -> UUID? {
        if let uuid = UUID(uuidString: uid) { return uuid }
        guard uid.utf8.count == 32, uid.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return nil }
        let chars = Array(uid)
        let formatted = [String(chars[0..<8]), String(chars[8..<12]), String(chars[12..<16]),
                         String(chars[16..<20]), String(chars[20..<32])].joined(separator: "-")
        return UUID(uuidString: formatted)
    }

    private func purchaseOptions(uid: String) throws -> Set<StoreKit.Product.PurchaseOption> {
        guard let uuid = Self.accountToken(uid: uid) else {
            throw PaymentError.apiError("The account uid cannot be represented as an App Store account token")
        }
        return [.appAccountToken(uuid)]
    }

    private func remember(_ transaction: Transaction) {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        pendingTransactions[transaction.id] = transaction
    }

    private func takePending(_ id: UInt64) -> Transaction? {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        return pendingTransactions.removeValue(forKey: id)
    }

    private func recoveredResult(_ transaction: Transaction, verification: VerificationResult<Transaction>) -> ProviderPurchaseResult {
        providerResult(
            transaction: transaction,
            signedTransactionInfo: verification.jwsRepresentation,
            product: Product(marketProductId: transaction.productID, name: transaction.productID,
                             productType: transaction.productType == .autoRenewable ? .subscription : .iap),
            message: "Restored"
        )
    }

    private func providerResult(
        transaction: Transaction,
        signedTransactionInfo: String,
        product: Product,
        message: String
    ) -> ProviderPurchaseResult {
        remember(transaction)
        return ProviderPurchaseResult(
            channel: channel,
            product: product,
            success: transaction.revocationDate == nil,
            orderId: String(transaction.id),
            purchaseToken: signedTransactionInfo,
            platformProductId: transaction.productID,
            isSubscription: transaction.productType == .autoRenewable,
            message: message,
            rawData: [
                "transaction_id": AnySendableValue(transaction.id),
                "original_transaction_id": AnySendableValue(transaction.originalID),
                "purchase_date": AnySendableValue(transaction.purchaseDate.timeIntervalSince1970),
                "owner_uid": AnySendableValue(transaction.appAccountToken?.uuidString ?? ""),
                "signed_transaction_info": AnySendableValue(signedTransactionInfo),
                "revocation_date": transaction.revocationDate.map { AnySendableValue($0.timeIntervalSince1970) } as AnySendableValue?
            ].compactMapValues { $0 }
        )
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }
}

private extension StoreKit.Product.SubscriptionPeriod {
    var iso8601Text: String {
        switch unit {
        case .day: "P\(value)D"
        case .week: "P\(value)W"
        case .month: "P\(value)M"
        case .year: "P\(value)Y"
        @unknown default: "P\(value)D"
        }
    }
}
