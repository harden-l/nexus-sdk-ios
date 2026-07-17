import Foundation

public struct CrossPromoConfig: Equatable, Sendable {
    public var sourceProductId: String
    public var campaign: String
    public var defaultPlacement: String

    public init(sourceProductId: String, campaign: String = "internal_cross_promo", defaultPlacement: String = "unknown") throws {
        guard !sourceProductId.isEmpty else { throw CrossPromoError.invalidConfig("sourceProductId is required") }
        self.sourceProductId = sourceProductId
        self.campaign = campaign
        self.defaultPlacement = defaultPlacement
    }
}

public struct CrossPromoProduct: Equatable, Sendable {
    public var productId: String
    public var title: String
    public var description: String
    public var iconUrl: String
    public var iosBundleId: String?
    public var iosScheme: String?
    public var deepLinkUrl: String?
    public var storeUrl: String?
    public var campaign: String?

    public init(productId: String, title: String, description: String = "", iconUrl: String = "", iosBundleId: String? = nil, iosScheme: String? = nil, deepLinkUrl: String? = nil, storeUrl: String? = nil, campaign: String? = nil) throws {
        guard !productId.isEmpty else { throw CrossPromoError.invalidConfig("productId is required") }
        guard !title.isEmpty else { throw CrossPromoError.invalidConfig("title is required") }
        self.productId = productId
        self.title = title
        self.description = description
        self.iconUrl = iconUrl
        self.iosBundleId = iosBundleId
        self.iosScheme = iosScheme
        self.deepLinkUrl = deepLinkUrl
        self.storeUrl = storeUrl
        self.campaign = campaign
    }
}

public struct ShowPromoPageOptions: Equatable, Sendable {
    public var placement: String?
    public var campaign: String?
    public var title: String
    public var description: String
    public init(placement: String? = nil, campaign: String? = nil, title: String = "Recommended Apps", description: String = "") {
        self.placement = placement
        self.campaign = campaign
        self.title = title
        self.description = description
    }
}

public struct OpenProductOptions: Equatable, Sendable {
    public var productId: String
    public var placement: String?
    public var campaign: String?
    public init(productId: String, placement: String? = nil, campaign: String? = nil) {
        self.productId = productId
        self.placement = placement
        self.campaign = campaign
    }
}

public struct CrossPromoLinkResult: Equatable, Codable, Sendable {
    public var clickId: String?
    public var sourceProductId: String?
    public var targetProductId: String?
    public var placement: String?
    public var campaign: String?
    public var sourceUid: String?
    public var sourceDeviceId: String?
    public var rawUrl: String
}

public struct CrossProductUserLinkPayload: Equatable, Sendable {
    public var clickId: String?
    public var sourceProductId: String
    public var targetProductId: String
    public var sourceUid: String?
    public var targetUid: String?
    public var sourceDeviceId: String?
    public var targetDeviceId: String?
    public var email: String?
    public var placement: String?
    public var campaign: String?
}

public enum CrossPromoError: Error, LocalizedError, Equatable {
    case invalidConfig(String)
    case notInitialized
    case productNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let message), .productNotFound(let message):
            return message
        case .notInitialized:
            return "CrossPromoSDK is not initialized"
        }
    }
}
