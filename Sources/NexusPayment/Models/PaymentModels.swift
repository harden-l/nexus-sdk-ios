import Foundation

public enum PaymentChannel: String, Codable, Sendable {
    case googlePlay = "google_play"
    case appStore = "app_store"
    case stripe
    case paypal
    case webCheckout = "web_checkout"
    case mock
}

public struct PaymentConfig: Equatable, Sendable {
    public var productId: String
    public var platform: String
    public var country: String?
    public var appVersion: String?
    public var defaultChannel: PaymentChannel
    public var enabledChannels: [PaymentChannel]
    public var fallbackChannels: [PaymentChannel]
    public var rules: [PaymentRule]

    public init(
        productId: String,
        platform: String = "ios",
        country: String? = nil,
        appVersion: String? = nil,
        defaultChannel: PaymentChannel = .appStore,
        enabledChannels: [PaymentChannel] = [.appStore],
        fallbackChannels: [PaymentChannel] = [],
        rules: [PaymentRule] = []
    ) throws {
        guard !productId.isEmpty else { throw PaymentError.invalidConfig("productId is required") }
        guard !platform.isEmpty else { throw PaymentError.invalidConfig("platform is required") }
        guard !enabledChannels.isEmpty else { throw PaymentError.invalidConfig("enabledChannels is required") }
        guard enabledChannels.contains(defaultChannel) else { throw PaymentError.invalidConfig("defaultChannel must be included in enabledChannels") }
        guard Set(enabledChannels).count == enabledChannels.count else { throw PaymentError.invalidConfig("enabledChannels contains duplicates") }
        guard fallbackChannels.allSatisfy(enabledChannels.contains) else { throw PaymentError.invalidConfig("fallbackChannels must be included in enabledChannels") }
        self.productId = productId
        self.platform = platform
        self.country = country
        self.appVersion = appVersion
        self.defaultChannel = defaultChannel
        self.enabledChannels = enabledChannels
        self.fallbackChannels = fallbackChannels
        self.rules = rules
    }
}

public struct PaymentRule: Equatable, Sendable {
    public var country: String?
    public var platform: String?
    public var minVersion: String?
    public var enabledChannels: [PaymentChannel]
    public var defaultChannel: PaymentChannel
    public var fallbackChannels: [PaymentChannel]

    public init(country: String? = nil, platform: String? = nil, minVersion: String? = nil, enabledChannels: [PaymentChannel], defaultChannel: PaymentChannel, fallbackChannels: [PaymentChannel] = []) throws {
        guard !enabledChannels.isEmpty else { throw PaymentError.invalidConfig("rule enabledChannels is required") }
        guard enabledChannels.contains(defaultChannel) else { throw PaymentError.invalidConfig("rule defaultChannel must be included in enabledChannels") }
        guard Set(enabledChannels).count == enabledChannels.count else { throw PaymentError.invalidConfig("rule enabledChannels contains duplicates") }
        guard fallbackChannels.allSatisfy(enabledChannels.contains) else { throw PaymentError.invalidConfig("rule fallbackChannels must be included in enabledChannels") }
        self.country = country
        self.platform = platform
        self.minVersion = minVersion
        self.enabledChannels = enabledChannels
        self.defaultChannel = defaultChannel
        self.fallbackChannels = fallbackChannels
    }
}

public struct PaymentContext: Equatable, Sendable {
    public var country: String?
    public var platform: String
    public var appVersion: String?
    public init(country: String? = nil, platform: String = "ios", appVersion: String? = nil) {
        self.country = country
        self.platform = platform
        self.appVersion = appVersion
    }
}

public struct ResolvedPaymentChannels: Equatable, Sendable {
    public var defaultChannel: PaymentChannel
    public var enabledChannels: [PaymentChannel]
    public var fallbackChannels: [PaymentChannel]
    public var matchedRule: PaymentRule?
}

public enum ProductType: String, Codable, Sendable {
    case consumable
    case iap
    case subscription
    case unknown
}

public struct Product: Equatable, Codable, Sendable {
    public var marketProductId: String
    public var name: String
    public var description: String
    public var productType: ProductType
    public var coinsGranted: Double?
    public var price: String?
    public var currency: String?
    public var localizedPrice: String?
    public var subscriptionPeriod: String?
    public var trialPeriod: String?
    public var hasTrial: Bool
    public var entitlementId: String?
    public var benefits: [String]
    public var weeklyPointsEnabled: Bool
    public var weeklyPoints: Int

    public init(marketProductId: String, name: String, description: String = "", productType: ProductType, coinsGranted: Double? = nil, price: String? = nil, currency: String? = nil, localizedPrice: String? = nil, subscriptionPeriod: String? = nil, trialPeriod: String? = nil, hasTrial: Bool = false, entitlementId: String? = nil, benefits: [String] = [], weeklyPointsEnabled: Bool = false, weeklyPoints: Int = 0) {
        self.marketProductId = marketProductId
        self.name = name
        self.description = description
        self.productType = productType
        self.coinsGranted = coinsGranted
        self.price = price
        self.currency = currency
        self.localizedPrice = localizedPrice
        self.subscriptionPeriod = subscriptionPeriod
        self.trialPeriod = trialPeriod
        self.hasTrial = hasTrial
        self.entitlementId = entitlementId
        self.benefits = benefits
        self.weeklyPointsEnabled = weeklyPointsEnabled
        self.weeklyPoints = weeklyPoints
    }
}

public struct Entitlement: Equatable, Codable, Sendable {
    public var entitlementId: String
    public var productId: String
    public var orderId: String
    public var channel: PaymentChannel
    public var startedTime: Int64?
    public var endsTime: Int64?
    public var active: Bool
}

public struct OrderVerificationResult: Equatable, Sendable {
    public enum Status: String, Sendable {
        case success
        case pending
        case failed
        case cancelled
        case refunded
        case unknown

        public static func fromCode(_ code: Int?) -> Status {
            switch code {
            case 10: .pending
            case 20: .success
            case 60: .failed
            case 70: .cancelled
            case 80: .refunded
            default: .unknown
            }
        }
    }

    public var tradeOrderId: String
    public var status: Status
    public var isSubscription: Bool
    public var token: String?
    public var platformProductId: String?
    public var startedTime: Int64?
    public var endsTime: Int64?
    public var successCount: Int?
    public var amount: String?
    public var isSuccessful: Bool { status == .success }
}

public struct PurchaseResult: Equatable, Sendable {
    public var channel: PaymentChannel
    public var product: Product
    public var success: Bool
    public var orderId: String?
    public var message: String?
    public var verification: OrderVerificationResult?
    public var entitlement: Entitlement?
}

public enum PaymentError: Error, LocalizedError, Equatable {
    case invalidConfig(String)
    case notInitialized
    case providerNotRegistered(String)
    case channelDisabled(String)
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let message), .providerNotRegistered(let message), .channelDisabled(let message), .apiError(let message):
            return message
        case .notInitialized:
            return "PaymentSDK is not initialized"
        }
    }
}
