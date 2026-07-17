import Foundation

enum CrossPromoLinkParser {
    static func parse(_ url: String) -> CrossPromoLinkResult {
        let params = URLComponents(string: url)?.queryItems?.reduce(into: [String: String]()) {
            $0[$1.name] = $1.value ?? ""
        } ?? [:]
        return CrossPromoLinkResult(
            clickId: first(params, "click_id", "clickId"),
            sourceProductId: first(params, "source_product_id", "source", "src"),
            targetProductId: first(params, "target_product_id", "target", "dst"),
            placement: first(params, "placement", "entrance"),
            campaign: first(params, "campaign", "utm_campaign"),
            sourceUid: first(params, "source_uid", "uid"),
            sourceDeviceId: first(params, "source_device_id", "device_id"),
            rawUrl: url
        )
    }

    private static func first(_ params: [String: String], _ keys: String...) -> String? {
        keys.compactMap { params[$0] }.first { !$0.isEmpty }
    }
}
