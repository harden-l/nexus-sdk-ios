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
        Analytics.logEvent(Self.adImpressionEventName, parameters: firebaseParameters(event.params))
    }

    public func flush() {}

    private func firebaseParameters(_ params: [String: AnySendable]) -> [String: Any] {
        params.reduce(into: [String: Any]()) { result, item in
            let value = item.value.value
            if let string = value as? String {
                result[item.key] = string
            } else if let number = value as? NSNumber {
                result[item.key] = number
            } else if let bool = value as? Bool {
                result[item.key] = bool
            } else if let int = value as? Int {
                result[item.key] = int
            } else if let double = value as? Double {
                result[item.key] = double
            } else {
                result[item.key] = "\(value)"
            }
        }
    }
}
