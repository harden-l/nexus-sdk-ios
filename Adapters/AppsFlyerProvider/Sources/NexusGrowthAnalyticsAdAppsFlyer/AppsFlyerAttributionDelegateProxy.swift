import AppsFlyerLib
import Foundation

final class AppsFlyerAttributionDelegateProxy: NSObject, DeepLinkDelegate, AppsFlyerLibDelegate {
    private let onAttribution: @Sendable ([String: Any?]) -> Void
    private let onFailure: @Sendable (Error) -> Void

    init(
        onAttribution: @escaping @Sendable ([String: Any?]) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        self.onAttribution = onAttribution
        self.onFailure = onFailure
        super.init()
    }

    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        onAttribution(stringKeyed(conversionInfo))
    }

    func onConversionDataFail(_ error: Error) {
        onFailure(error)
    }

    func onAppOpenAttribution(_ attributionData: [AnyHashable: Any]) {
        onAttribution(stringKeyed(attributionData))
    }

    func onAppOpenAttributionFailure(_ error: Error) {
        onFailure(error)
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        switch result.status {
        case .found:
            guard let deepLink = result.deepLink else { return }
            var params = deepLink.clickEvent.reduce(into: [String: Any?]()) { output, item in
                output[item.key] = item.value
            }
            params["deep_link_value"] = deepLink.deeplinkValue
            params["media_source"] = deepLink.mediaSource
            params["campaign"] = deepLink.campaign
            params["campaign_id"] = deepLink.campaignId
            params["match_type"] = deepLink.matchType
            params["click_http_referrer"] = deepLink.clickHTTPReferrer
            params["af_sub1"] = deepLink.afSub1
            params["af_sub2"] = deepLink.afSub2
            params["af_sub3"] = deepLink.afSub3
            params["af_sub4"] = deepLink.afSub4
            params["af_sub5"] = deepLink.afSub5
            params["is_deferred"] = deepLink.isDeferred
            onAttribution(params)
        case .failure:
            if let error = result.error {
                onFailure(error)
            }
        case .notFound:
            break
        @unknown default:
            break
        }
    }

    private func stringKeyed(_ values: [AnyHashable: Any]) -> [String: Any?] {
        values.reduce(into: [String: Any?]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = item.value
        }
    }
}
