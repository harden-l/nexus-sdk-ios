import Foundation

public struct AttributionData: Equatable, Sendable {
    public var source: String?
    public var campaign: String?
    public var medium: String?
    public var channel: String?
    public var adset: String?
    public var ad: String?
    public var afStatus: String?
    public var mediaSource: String?
    public var deepLinkValue: String?
    public var target: String?
    public var rawParams: [String: String]
    public var timestamp: Int64

    public init(
        source: String? = nil,
        campaign: String? = nil,
        medium: String? = nil,
        channel: String? = nil,
        adset: String? = nil,
        ad: String? = nil,
        afStatus: String? = nil,
        mediaSource: String? = nil,
        deepLinkValue: String? = nil,
        target: String? = nil,
        rawParams: [String: String] = [:],
        timestamp: Int64? = nil
    ) {
        self.source = source
        self.campaign = campaign
        self.medium = medium
        self.channel = channel
        self.adset = adset
        self.ad = ad
        self.afStatus = afStatus
        self.mediaSource = mediaSource
        self.deepLinkValue = deepLinkValue
        self.target = target
        self.rawParams = rawParams
        self.timestamp = timestamp ?? nowMillis()
    }
}

public struct DeepLinkResult: Equatable, Sendable {
    public var url: String
    public var source: String?
    public var campaign: String?
    public var medium: String?
    public var target: String?
    public var deepLinkValue: String?
    public var params: [String: String]
    public var timestamp: Int64
}

enum DeepLinkParser {
    static func parse(_ url: String) -> DeepLinkResult {
        let params = URLComponents(string: url)?.queryItems?.reduce(into: [String: String]()) {
            $0[$1.name] = $1.value ?? ""
        } ?? [:]
        return DeepLinkResult(
            url: url,
            source: first(params, "utm_source", "source", "media_source", "pid"),
            campaign: first(params, "utm_campaign", "campaign", "c"),
            medium: first(params, "utm_medium", "medium"),
            target: first(params, "target", "deep_link_sub1"),
            deepLinkValue: first(params, "deep_link_value", "deepLinkValue"),
            params: params,
            timestamp: nowMillis()
        )
    }

    static func attribution(from result: DeepLinkResult) -> AttributionData {
        AttributionData(
            source: result.source,
            campaign: result.campaign,
            medium: result.medium,
            channel: result.params["channel"],
            adset: result.params["adset"],
            ad: result.params["ad"],
            afStatus: result.params["af_status"],
            mediaSource: result.params["media_source"],
            deepLinkValue: result.deepLinkValue,
            target: result.target,
            rawParams: result.params,
            timestamp: result.timestamp
        )
    }

    static func attribution(from params: [String: String], timestamp: Int64 = nowMillis()) -> AttributionData {
        AttributionData(
            source: first(params, "utm_source", "source", "media_source", "pid"),
            campaign: first(params, "utm_campaign", "campaign", "c", "campaign_id"),
            medium: first(params, "utm_medium", "medium"),
            channel: first(params, "channel", "af_channel"),
            adset: first(params, "adset", "af_adset", "adset_id"),
            ad: first(params, "ad", "af_ad", "ad_id"),
            afStatus: first(params, "af_status", "afStatus"),
            mediaSource: first(params, "media_source", "pid"),
            deepLinkValue: first(params, "deep_link_value", "deepLinkValue", "af_dp"),
            target: first(params, "target", "deep_link_sub1", "af_sub1"),
            rawParams: params,
            timestamp: timestamp
        )
    }

    private static func first(_ params: [String: String], _ keys: String...) -> String? {
        keys.compactMap { params[$0] }.first { !$0.isEmpty }
    }
}

final class AttributionStorage: @unchecked Sendable {
    private var installSource: AttributionData?
    private var lastDeepLink: DeepLinkResult?

    func saveDeepLink(_ result: DeepLinkResult) {
        lastDeepLink = result
        installSource = DeepLinkParser.attribution(from: result)
    }

    func saveInstallSource(_ data: AttributionData) {
        installSource = data
    }

    func getInstallSource() -> AttributionData? { installSource }
    func getLastDeepLink() -> DeepLinkResult? { lastDeepLink }
}

func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
