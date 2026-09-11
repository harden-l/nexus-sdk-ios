import FirebaseAnalytics
import FirebaseCore
import Foundation
import NexusGrowthAnalyticsAd

public final class FirebaseAnalyticsProvider: AnalyticsProvider, UserIdentityAnalyticsProvider, UserPropertiesAnalyticsProvider, @unchecked Sendable {
    public let name = "firebase"
    private static let adRevenueEventName = "ad_revenue"
    private static let adImpressionEventName = "ad_imp"

    public init(configureIfNeeded: Bool = true) {
        if configureIfNeeded && FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    public func setUserId(_ uid: String?) {
        Analytics.setUserID(uid)
    }

    public func setUserProperties(_ properties: [String: Any?]) {
        properties.forEach { key, value in
            Analytics.setUserProperty(value.map { "\($0)" }, forName: key)
        }
    }

    public func track(_ event: AnalyticsEvent) {
        guard event.eventName == Self.adRevenueEventName else { return }
        Analytics.logEvent(Self.adImpressionEventName, parameters: [
            "ad_source": firstString(event.params, keys: "network_name", "ad_platform"),
            "ad_platform": stringValue(event.params["ad_platform"]?.value),
            "ad_format": stringValue(event.params["ad_format"]?.value),
            "ad_unit_name": stringValue(event.params["ad_unit_id"]?.value),
            "currency": stringValue(event.params["currency"]?.value),
            "value": doubleValue(event.params["revenue"]?.value) ?? 0
        ])
    }

    public func flush() {}

    private func firstString(_ params: [String: AnySendable], keys: String...) -> String {
        for key in keys {
            let value = stringValue(params[key]?.value)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private func stringValue(_ value: Any?) -> String {
        guard let value else { return "" }
        return value as? String ?? "\(value)"
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
