import AppsFlyerLib
import Foundation
import NexusGrowthAnalyticsAd
import UIKit

public final class AppsFlyerAnalyticsProvider: NSObject, AnalyticsProvider, UserIdentityAnalyticsProvider, @unchecked Sendable {
    public let name = "appsflyer"
    private static let adRevenueEventName = "ad_revenue"
    private static let adImpressionEventName = "ad_imp"
    public var onAttributionResolved: (@Sendable (AttributionData) -> Void)?
    public var onAttributionFailed: (@Sendable (Error) -> Void)?
    private var attributionProxy: AppsFlyerAttributionDelegateProxy?

    public init(
        devKey: String,
        appleAppID: String? = nil,
        startImmediately: Bool = true,
        isDebug: Bool = false,
        onAttributionResolved: (@Sendable (AttributionData) -> Void)? = nil,
        onAttributionFailed: (@Sendable (Error) -> Void)? = nil
    ) {
        self.onAttributionResolved = onAttributionResolved
        self.onAttributionFailed = onAttributionFailed
        super.init()
        AppsFlyerLib.shared().appsFlyerDevKey = devKey
        if let appleAppID, !appleAppID.isEmpty {
            AppsFlyerLib.shared().appleAppID = appleAppID
        }
        AppsFlyerLib.shared().isDebug = isDebug
        let proxy = AppsFlyerAttributionDelegateProxy(
            onAttribution: { [weak self] params in
                self?.saveAttribution(params)
            },
            onFailure: { [weak self] error in
                self?.onAttributionFailed?(error)
            }
        )
        attributionProxy = proxy
        AppsFlyerLib.shared().delegate = proxy
        AppsFlyerLib.shared().deepLinkDelegate = proxy
        if startImmediately {
            AppsFlyerLib.shared().start()
        }
    }

    public func setUserId(_ uid: String?) {
        AppsFlyerLib.shared().customerUserID = uid
    }

    public func track(_ event: AnalyticsEvent) {
        guard event.eventName == Self.adRevenueEventName else { return }
        AppsFlyerLib.shared().logEvent(Self.adImpressionEventName, withValues: appsFlyerValues(event.params))
    }

    public func flush() {}

    public func handleOpen(url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) {
        AppsFlyerLib.shared().handleOpen(url, options: options)
    }

    @discardableResult
    public func continueUserActivity(
        _ userActivity: NSUserActivity,
        restorationHandler: (([Any]?) -> Void)? = nil
    ) -> Bool {
        AppsFlyerLib.shared().`continue`(userActivity, restorationHandler: restorationHandler)
    }

    private func appsFlyerValues(_ params: [String: AnySendable]) -> [AnyHashable: Any] {
        params.reduce(into: [AnyHashable: Any]()) { result, item in
            result[item.key] = item.value.value
        }
    }

    private func saveAttribution(_ params: [String: Any?]) {
        let data = NexusGrowthAnalyticsAd.shared.handleAttribution(params: params)
        onAttributionResolved?(data)
    }
}
