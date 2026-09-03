import Foundation

public struct SubscriptionPageConfig: Equatable, Sendable {
    public static let defaultTermsUrl = "https://www.crypsiscollectiveinc.com/terms.html"
    public static let defaultPrivacyUrl = "https://www.crypsiscollectiveinc.com/privacy.html"

    public var templateId: String
    public var scene: String
    public var title: String
    public var benefitDescription: String
    public var benefits: [String]
    public var sharedApps: SubscriptionSharedAppsConfig
    public var paymentChannels: [PaymentChannel]
    public var showPaymentChannel: Bool
    public var showRestore: Bool
    public var showTerms: Bool
    public var showPrivacy: Bool
    public var termsUrl: String
    public var privacyUrl: String
    public var ctaText: String
    public var restoreText: String
    public var termsText: String
    public var privacyText: String

    public init(
        templateId: String = SubscriptionPageTemplateId.aurora.rawValue,
        scene: String = "",
        title: String = "Upgrade to Pro",
        benefitDescription: String = "Purchase one product and get VIP access to all other products.",
        benefits: [String] = [],
        sharedApps: SubscriptionSharedAppsConfig = SubscriptionSharedAppsConfig(),
        paymentChannels: [PaymentChannel] = [],
        showPaymentChannel: Bool = true,
        showRestore: Bool = true,
        showTerms: Bool = true,
        showPrivacy: Bool = true,
        termsUrl: String = SubscriptionPageConfig.defaultTermsUrl,
        privacyUrl: String = SubscriptionPageConfig.defaultPrivacyUrl,
        ctaText: String = "Start Pro",
        restoreText: String = "Restore",
        termsText: String = "Terms",
        privacyText: String = "Privacy"
    ) throws {
        guard !showTerms || !termsUrl.isEmpty else { throw PaymentError.invalidConfig("termsUrl is required when showTerms is true") }
        guard !showPrivacy || !privacyUrl.isEmpty else { throw PaymentError.invalidConfig("privacyUrl is required when showPrivacy is true") }
        self.templateId = templateId
        self.scene = scene
        self.title = title
        self.benefitDescription = benefitDescription
        self.benefits = benefits
        self.sharedApps = sharedApps
        self.paymentChannels = paymentChannels
        self.showPaymentChannel = showPaymentChannel
        self.showRestore = showRestore
        self.showTerms = showTerms
        self.showPrivacy = showPrivacy
        self.termsUrl = termsUrl
        self.privacyUrl = privacyUrl
        self.ctaText = ctaText
        self.restoreText = restoreText
        self.termsText = termsText
        self.privacyText = privacyText
    }
}

public struct SubscriptionSharedAppsConfig: Equatable, Sendable {
    public var title: String
    public var description: String
    public init(title: String = "membership share", description: String = "Your membership gives you access to every current service in this app.") {
        self.title = title
        self.description = description
    }
}

public enum SubscriptionPageEventName: String, Sendable {
    case pageShow = "purchase_page_show"
    case productSelect = "purchase_product_select"
    case channelSelect = "purchase_channel_select"
    case purchaseClick = "purchase_click"
    case purchaseSuccess = "purchase_success"
    case purchaseFailed = "purchase_failed"
    case purchaseCancel = "purchase_cancel"
    case weeklyPointsClaimClick = "weekly_points_claim_click"
    case weeklyPointsClaimSuccess = "weekly_points_claim_success"
    case weeklyPointsClaimFailed = "weekly_points_claim_failed"
    case restoreClick = "purchase_restore_click"
    case restoreSuccess = "purchase_restore_success"
    case restoreFailed = "purchase_restore_failed"
    case close = "purchase_page_close"
}

public enum SubscriptionPageState: String, Sendable {
    case loading
    case ready
    case purchasing
    case success
    case failed
    case cancelled
}

public struct SubscriptionPageEvent: Sendable {
    public var name: SubscriptionPageEventName
    public var productId: String?
    public var paymentChannel: PaymentChannel?
    public var state: SubscriptionPageState?
    public var params: [String: AnySendableValue]

    public init(name: SubscriptionPageEventName, productId: String? = nil, paymentChannel: PaymentChannel? = nil, state: SubscriptionPageState? = nil, params: [String: Any?] = [:]) {
        self.name = name
        self.productId = productId
        self.paymentChannel = paymentChannel
        self.state = state
        self.params = params.compactMapValues { $0.map(AnySendableValue.init) }
    }

    public func analyticsParams() -> [String: Any?] {
        var values = params.mapValues(\.value)
        if let productId { values["product_id"] = productId }
        if let paymentChannel { values["payment_channel"] = paymentChannel.rawValue }
        if let state { values["state"] = state.rawValue }
        return values
    }
}

public struct AnySendableValue: @unchecked Sendable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
}
