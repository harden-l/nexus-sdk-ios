import Foundation
import NexusCoreUser
import NexusGrowthAnalyticsAd
#if canImport(UIKit)
import UIKit
#endif

public protocol CrossPromoURLOpener: AnyObject, Sendable {
    func canOpen(url: URL) -> Bool
    func open(url: URL) -> Bool
}

public final class DefaultCrossPromoURLOpener: CrossPromoURLOpener, @unchecked Sendable {
    public init() {}
    public func canOpen(url: URL) -> Bool {
        #if canImport(UIKit)
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return true
        }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    public func open(url: URL) -> Bool {
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
        #else
        return false
        #endif
    }
}

public final class NexusCrossPromo: @unchecked Sendable {
    public static let shared = NexusCrossPromo()
    public static let version = "0.0.12"

    private var config: CrossPromoConfig?
    private var activePageOptions = ShowPromoPageOptions()
    private var relatedProducts: [CrossPromoProduct] = []
    private let attributionStorage = CrossPromoAttributionStorage()
    private var urlOpener: CrossPromoURLOpener = DefaultCrossPromoURLOpener()
    private weak var promoPageViewController: AnyObject?

    private init() {}

    public func initialize(config: CrossPromoConfig, urlOpener: CrossPromoURLOpener? = nil) {
        self.config = config
        self.relatedProducts = []
        if let urlOpener { self.urlOpener = urlOpener }
    }

    public func showPromoPage(options: ShowPromoPageOptions = ShowPromoPageOptions()) throws {
        _ = try requireConfig()
        activePageOptions = options
        track("cross_promo_show", params: baseParams(placement: options.placement, campaign: options.campaign))
    }

    #if canImport(UIKit)
    public func showPromoPage(presenting viewController: UIViewController, options: ShowPromoPageOptions = ShowPromoPageOptions()) throws {
        try showPromoPage(options: options)
        let page = CrossPromoPageViewController(sdk: self, options: options)
        promoPageViewController = page
        let navigation = UINavigationController(rootViewController: page)
        navigation.modalPresentationStyle = .formSheet
        viewController.present(navigation, animated: true)
    }

    public func closePromoPage() {
        (promoPageViewController as? UIViewController)?.dismiss(animated: true)
        promoPageViewController = nil
    }
    #endif

    public func getActivePageOptions() -> ShowPromoPageOptions {
        activePageOptions
    }

    public func getProductsForDisplay(forceRefresh: Bool = false) async throws -> [CrossPromoProduct] {
        if !forceRefresh && !relatedProducts.isEmpty { return relatedProducts }
        let config = try requireConfig()
        let products = try await NexusCoreUser.shared.getRelatedProducts(forceRefresh: forceRefresh)
        relatedProducts = products.filter { $0.productId != config.sourceProductId }.compactMap { product in
            try? CrossPromoProduct(
                productId: product.productId,
                title: product.productName,
                description: product.description,
                iconUrl: product.icon,
                iosBundleId: product.packageName,
                iosScheme: product.iosScheme,
                deepLinkUrl: nil,
                storeUrl: product.downloadUrl.isEmpty ? nil : product.downloadUrl,
                campaign: config.campaign
            )
        }
        return relatedProducts
    }

    public func setProductsForTesting(_ products: [CrossPromoProduct]) {
        relatedProducts = products
    }

    @discardableResult
    public func openProduct(_ options: OpenProductOptions) async throws -> Bool {
        let product = try await getProductsForDisplay().first { $0.productId == options.productId }
        guard let product else { throw CrossPromoError.productNotFound("Cross promo product not found: \(options.productId)") }
        return try openProduct(product, placement: options.placement, campaign: options.campaign)
    }

    @discardableResult
    public func handleIncomingPromoLink(_ url: String) throws -> CrossPromoLinkResult {
        let result = CrossPromoLinkParser.parse(url)
        attributionStorage.save(result)
        try? NexusCoreUser.shared.setLoginAttributionEnabled(true)
        track("cross_promo_activate", params: [
            "click_id": result.clickId,
            "source_product_id": result.sourceProductId,
            "target_product_id": result.targetProductId,
            "placement": result.placement,
            "campaign": result.campaign,
            "source_uid": result.sourceUid,
            "source_device_id": result.sourceDeviceId,
            "raw_url": result.rawUrl
        ])
        return result
    }

    public func getPendingAttribution() -> CrossPromoLinkResult? {
        attributionStorage.get()
    }

    public func clearPendingAttribution() {
        attributionStorage.clear()
        try? NexusCoreUser.shared.setLoginAttributionEnabled(false)
    }

    @discardableResult
    public func flushPendingAttributionAfterLogin() throws -> CrossProductUserLinkPayload? {
        guard let pending = getPendingAttribution(), let user = try NexusCoreUser.shared.getCurrentUser() else { return nil }
        let target: String
        if let pendingTarget = pending.targetProductId {
            target = pendingTarget
        } else {
            target = try requireConfig().sourceProductId
        }
        guard let source = pending.sourceProductId else { return nil }
        let payload = CrossProductUserLinkPayload(
            clickId: pending.clickId,
            sourceProductId: source,
            targetProductId: target,
            sourceUid: pending.sourceUid,
            targetUid: user.uid,
            sourceDeviceId: pending.sourceDeviceId,
            targetDeviceId: user.deviceId,
            email: user.email,
            placement: pending.placement,
            campaign: pending.campaign
        )
        linkCrossProductUser(payload)
        clearPendingAttribution()
        return payload
    }

    @discardableResult
    public func linkCrossProductUser(_ payload: CrossProductUserLinkPayload) -> CrossProductUserLinkPayload {
        track("cross_promo_user_link", params: [
            "click_id": payload.clickId,
            "source_product_id": payload.sourceProductId,
            "target_product_id": payload.targetProductId,
            "source_uid": payload.sourceUid,
            "target_uid": payload.targetUid,
            "source_device_id": payload.sourceDeviceId,
            "target_device_id": payload.targetDeviceId,
            "email": payload.email,
            "placement": payload.placement,
            "campaign": payload.campaign
        ])
        return payload
    }

    private func openProduct(_ product: CrossPromoProduct, placement: String?, campaign: String?) throws -> Bool {
        let clickId = "cp_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString)"
        let params = baseParams(placement: placement, campaign: campaign).merging([
            "click_id": clickId,
            "target_product_id": product.productId
        ]) { _, new in new }
        track("cross_promo_click", params: params)
        if let deepLinkUrl = product.deepLinkUrl ?? schemeDeepLink(for: product),
           let url = withParams(deepLinkUrl, params),
           urlOpener.canOpen(url: url),
           urlOpener.open(url: url) {
            track("cross_promo_open", params: params.merging(["link_type": "deep_link"]) { _, new in new })
            return true
        }
        if let storeUrl = product.storeUrl ?? appStoreUrl(for: product),
           let url = withStoreReferrer(storeUrl, params),
           urlOpener.open(url: url) {
            track("cross_promo_store_open", params: params.merging(["link_type": "store"]) { _, new in new })
            return true
        }
        track("cross_promo_open_failed", params: params.merging(["message": "No deep link or store url configured"]) { _, new in new })
        return false
    }

    private func baseParams(placement: String?, campaign: String?) -> [String: Any?] {
        let config = try? requireConfig()
        let user = (try? NexusCoreUser.shared.getCurrentUser()) ?? nil
        return [
            "source_product_id": config?.sourceProductId,
            "placement": placement ?? config?.defaultPlacement,
            "campaign": campaign ?? config?.campaign,
            "source_uid": user?.uid,
            "source_device_id": user?.deviceId
        ]
    }

    private func withParams(_ url: String, _ params: [String: Any?]) -> URL? {
        guard var components = URLComponents(string: url) else { return nil }
        var items = components.queryItems ?? []
        let existing = Set(items.map(\.name))
        for (key, value) in params where value != nil && !existing.contains(key) {
            items.append(URLQueryItem(name: key, value: "\(value!)"))
        }
        components.queryItems = items
        return components.url
    }

    private func withStoreReferrer(_ url: String, _ params: [String: Any?]) -> URL? {
        guard var components = URLComponents(string: url) else { return nil }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "referrer" }) {
            let referrer = params.compactMap { key, value -> String? in
                guard let value else { return nil }
                return "\(key)=\(value)"
            }.joined(separator: "&")
            items.append(URLQueryItem(name: "referrer", value: referrer))
        }
        components.queryItems = items
        return components.url
    }

    private func appStoreUrl(for product: CrossPromoProduct) -> String? {
        guard let value = product.iosBundleId?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.allSatisfy(\.isNumber) {
            return "https://apps.apple.com/app/id\(value)"
        }
        return nil
    }

    private func schemeDeepLink(for product: CrossPromoProduct) -> String? {
        guard let scheme = product.iosScheme?.trimmingCharacters(in: .whitespacesAndNewlines), !scheme.isEmpty else {
            return nil
        }
        if scheme.contains("://") {
            return scheme
        }
        return "\(scheme)://"
    }

    func track(_ eventName: String, params: [String: Any?]) {
        if NexusGrowthAnalyticsAd.shared.isInitialized() {
            _ = try? NexusGrowthAnalyticsAd.shared.track(eventName, params: params.compactMapValues { $0 })
        }
    }

    private func requireConfig() throws -> CrossPromoConfig {
        guard let config else { throw CrossPromoError.notInitialized }
        return config
    }
}
