import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum AdFormat: String, Sendable {
    case appOpen = "app_open"
    case banner
    case interstitial
    case rewarded
    case rewardedInterstitial = "rewarded_interstitial"
    case native
}

public struct AdPlacement: Equatable, Sendable {
    public var placement: String
    public var adUnitId: String
    public var format: AdFormat
    public var frequencyCap: Int?
    public var adPlatform: String?
    public var adPlatformId: String?

    public init(placement: String, adUnitId: String, format: AdFormat, frequencyCap: Int? = nil, adPlatform: String? = nil, adPlatformId: String? = nil) throws {
        guard !placement.isEmpty else { throw GrowthAnalyticsError.invalidConfig("placement is required") }
        guard !adUnitId.isEmpty else { throw GrowthAnalyticsError.invalidConfig("adUnitId is required") }
        self.placement = placement
        self.adUnitId = adUnitId
        self.format = format
        self.frequencyCap = frequencyCap
        self.adPlatform = adPlatform
        self.adPlatformId = adPlatformId
    }

    public func eventParams() -> [String: Any?] {
        [
            "placement": placement,
            "ad_unit_id": adUnitId,
            "ad_format": format.rawValue,
            "frequency_cap": frequencyCap,
            "ad_platform": adPlatform,
            "ad_platform_id": adPlatformId
        ]
    }
}

public protocol AdCallbacks: AnyObject, Sendable {
    func onLoaded(_ placement: AdPlacement)
    func onShown(_ placement: AdPlacement)
    func onClicked(_ placement: AdPlacement)
    func onClosed(_ placement: AdPlacement)
    func onReward(_ placement: AdPlacement)
    func onFailed(_ placement: AdPlacement, error: Error)
}

public extension AdCallbacks {
    func onLoaded(_ placement: AdPlacement) {}
    func onShown(_ placement: AdPlacement) {}
    func onClicked(_ placement: AdPlacement) {}
    func onClosed(_ placement: AdPlacement) {}
    func onReward(_ placement: AdPlacement) {}
    func onFailed(_ placement: AdPlacement, error: Error) {}
}

public protocol NativeAdCallbacks: AnyObject, Sendable {
    func onLoaded(_ placement: AdPlacement, nativeAd: Any)
    func onFailed(_ placement: AdPlacement, error: Error)
}

public extension NativeAdCallbacks {
    func onLoaded(_ placement: AdPlacement, nativeAd: Any) {}
    func onFailed(_ placement: AdPlacement, error: Error) {}
}

public protocol AdProvider: AnyObject, Sendable {
    func loadAd(_ placement: AdPlacement, callbacks: AdCallbacks?)
    func showAd(_ placement: AdPlacement, callbacks: AdCallbacks?)
    #if canImport(UIKit)
    func loadBanner(_ placement: AdPlacement, container: UIView, callbacks: AdCallbacks?)
    func loadNative(_ placement: AdPlacement, callbacks: NativeAdCallbacks?)
    #endif
}

public extension AdProvider {
    #if canImport(UIKit)
    func loadBanner(_ placement: AdPlacement, container: UIView, callbacks: AdCallbacks?) {
        callbacks?.onFailed(placement, error: GrowthAnalyticsError.providerUnsupported("Current AdProvider does not support banner ads"))
    }

    func loadNative(_ placement: AdPlacement, callbacks: NativeAdCallbacks?) {
        callbacks?.onFailed(placement, error: GrowthAnalyticsError.providerUnsupported("Current AdProvider does not support native ads"))
    }
    #endif
}

public final class MockAdProvider: AdProvider, @unchecked Sendable {
    private var loadedAds = Set<MockAdCacheKey>()

    public init() {}
    public func loadAd(_ placement: AdPlacement, callbacks: AdCallbacks?) {
        loadedAds.insert(placement.mockCacheKey)
        callbacks?.onLoaded(placement)
    }

    public func showAd(_ placement: AdPlacement, callbacks: AdCallbacks?) {
        guard loadedAds.remove(placement.mockCacheKey) != nil else {
            loadAd(placement, callbacks: nil)
            callbacks?.onFailed(
                placement,
                error: GrowthAnalyticsError.providerUnsupported("Ad is not loaded")
            )
            return
        }
        callbacks?.onShown(placement)
        if placement.format == .rewarded || placement.format == .rewardedInterstitial {
            callbacks?.onReward(placement)
        }
        callbacks?.onClosed(placement)
        loadAd(placement, callbacks: nil)
    }

    #if canImport(UIKit)
    public func loadBanner(_ placement: AdPlacement, container: UIView, callbacks: AdCallbacks?) {
        container.backgroundColor = UIColor.systemGray5
        callbacks?.onLoaded(placement)
    }

    public func loadNative(_ placement: AdPlacement, callbacks: NativeAdCallbacks?) {
        callbacks?.onLoaded(placement, nativeAd: ["placement": placement.placement])
    }
    #endif
}

private struct MockAdCacheKey: Hashable {
    let format: String
    let adUnitId: String
}

private extension AdPlacement {
    var mockCacheKey: MockAdCacheKey {
        MockAdCacheKey(format: format.rawValue, adUnitId: adUnitId)
    }
}

public final class AdFrequencyController: @unchecked Sendable {
    private var impressionsByPlacement: [String: Int] = [:]

    public init() {}

    public func canShow(_ placement: AdPlacement) -> Bool {
        guard let cap = placement.frequencyCap, cap > 0 else { return true }
        return (impressionsByPlacement[placement.placement] ?? 0) < cap
    }

    public func recordShown(_ placement: AdPlacement) {
        impressionsByPlacement[placement.placement, default: 0] += 1
    }

    public func reset(placement: String? = nil) {
        if let placement {
            impressionsByPlacement.removeValue(forKey: placement)
        } else {
            impressionsByPlacement.removeAll()
        }
    }

    public func shownCount(for placement: String) -> Int {
        impressionsByPlacement[placement] ?? 0
    }
}

public struct AdRevenuePayload: Equatable, Sendable {
    public var adPlatform: String
    public var mediationPlatform: String?
    public var adUnitId: String
    public var placement: String
    public var adFormat: AdFormat
    public var currency: String
    public var revenue: Double
    public var country: String?
    public var networkName: String?
    public var networkFirmId: String?
    public var scene: String?
    public var precision: String?

    public init(adPlatform: String, mediationPlatform: String? = nil, adUnitId: String, placement: String, adFormat: AdFormat, currency: String, revenue: Double, country: String? = nil, networkName: String? = nil, networkFirmId: String? = nil, scene: String? = nil, precision: String? = nil) throws {
        guard !adUnitId.isEmpty else { throw GrowthAnalyticsError.invalidConfig("adUnitId is required") }
        guard !currency.isEmpty else { throw GrowthAnalyticsError.invalidConfig("currency is required") }
        guard revenue >= 0 else { throw GrowthAnalyticsError.invalidConfig("revenue must not be negative") }
        self.adPlatform = adPlatform
        self.mediationPlatform = mediationPlatform
        self.adUnitId = adUnitId
        self.placement = placement
        self.adFormat = adFormat
        self.currency = currency
        self.revenue = revenue
        self.country = country
        self.networkName = networkName
        self.networkFirmId = networkFirmId
        self.scene = scene
        self.precision = precision
    }
}

public enum GrowthPaymentChannel: String, Sendable {
    case googlePlay = "google_play"
    case appStore = "app_store"
    case stripe
    case paypal
    case webCheckout = "web_checkout"
    case mock
}

public enum PurchaseType: String, Sendable {
    case oneTime = "one_time"
    case subscription
}

public struct PurchaseRevenuePayload: Equatable, Sendable {
    public var paymentChannel: GrowthPaymentChannel
    public var orderId: String
    public var transactionId: String?
    public var storeProductId: String
    public var purchaseType: PurchaseType
    public var subscriptionPeriod: String?
    public var currency: String
    public var revenue: Double
    public var country: String?
    public var isTrial: Bool
    public var isRenewal: Bool

    public init(paymentChannel: GrowthPaymentChannel, orderId: String, transactionId: String? = nil, storeProductId: String, purchaseType: PurchaseType, subscriptionPeriod: String? = nil, currency: String, revenue: Double, country: String? = nil, isTrial: Bool = false, isRenewal: Bool = false) throws {
        guard !orderId.isEmpty else { throw GrowthAnalyticsError.invalidConfig("orderId is required") }
        guard !storeProductId.isEmpty else { throw GrowthAnalyticsError.invalidConfig("storeProductId is required") }
        guard !currency.isEmpty else { throw GrowthAnalyticsError.invalidConfig("currency is required") }
        guard revenue >= 0 else { throw GrowthAnalyticsError.invalidConfig("revenue must not be negative") }
        self.paymentChannel = paymentChannel
        self.orderId = orderId
        self.transactionId = transactionId
        self.storeProductId = storeProductId
        self.purchaseType = purchaseType
        self.subscriptionPeriod = subscriptionPeriod
        self.currency = currency
        self.revenue = revenue
        self.country = country
        self.isTrial = isTrial
        self.isRenewal = isRenewal
    }

    public func dedupeKey() -> String {
        transactionId?.isEmpty == false ? transactionId! : orderId
    }
}
