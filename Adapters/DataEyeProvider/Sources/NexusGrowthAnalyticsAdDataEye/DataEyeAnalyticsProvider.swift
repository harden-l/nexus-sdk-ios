import Foundation
import NexusGrowthAnalyticsAd

public struct BIEyeEvent: Equatable, Sendable {
    public let name: String
    public let parameters: [String: AnySendable]

    public init(name: String, parameters: [String: Any?]) {
        self.name = name
        self.parameters = parameters.compactMapValues { $0.map(AnySendable.init) }
    }
}

public enum BIEventMapper {
    public static func map(_ event: AnalyticsEvent) -> BIEyeEvent {
        switch event.eventName {
        case "ad_load":
            return adEvent(name: "ad_request", event: event)
        case "ad_inventory":
            return adEvent(name: "ad_inventory", event: event)
        case "ad_revenue":
            return adImpressionEvent(event)
        case "ad_click":
            return adEvent(name: "ad_click", event: event)
        case "purchase_order":
            return purchaseEvent(event, status: "order")
        case "purchase_paid":
            return purchaseEvent(event, status: "paid")
        case "purchase_paid_err":
            return purchaseEvent(event, status: "paid_err")
        case "purchase_revenue":
            return purchaseEvent(event, status: "paid")
        default:
            return BIEyeEvent(name: event.eventName, parameters: event.params.mapValues(\.value))
        }
    }

    private static func adEvent(name: String, event: AnalyticsEvent) -> BIEyeEvent {
        BIEyeEvent(
            name: name,
            parameters: [
                "ad_type": adType(event.params["ad_format"]?.value),
                "PlacementId": placementId(event),
                "NetworkFirmId": networkFirmId(event)
            ]
        )
    }

    private static func adImpressionEvent(_ event: AnalyticsEvent) -> BIEyeEvent {
        let revenue = doubleValue(event.params["revenue"]?.value) ?? 0
        return BIEyeEvent(
            name: "ad_imp",
            parameters: [
                "ad_type": adType(event.params["ad_format"]?.value),
                "Ecpm": doubleValue(event.params["ecpm"]?.value),
                "Revenue": revenue,
                "Currency": stringValue(event.params["currency"]?.value),
                "PlacementId": placementId(event),
                "scene": stringValue(event.params["scene"]?.value).isEmpty ? placementId(event) : stringValue(event.params["scene"]?.value),
                "NetworkFirmId": networkFirmId(event)
            ]
        )
    }

    private static func purchaseEvent(_ event: AnalyticsEvent, status: String) -> BIEyeEvent {
        BIEyeEvent(
            name: "purchase",
            parameters: [
                "item_id": firstString(event.params, keys: "item_id", "store_product_id"),
                "item_name": firstString(event.params, keys: "item_name", "store_product_id"),
                "revenue": doubleValue(event.params["revenue"]?.value),
                "currency": stringValue(event.params["currency"]?.value),
                "order_num": firstString(event.params, keys: "order_num", "order_id"),
                "purchase_status": stringValue(event.params["purchase_status"]?.value).isEmpty ? status : stringValue(event.params["purchase_status"]?.value),
                "msg": firstString(event.params, keys: "msg", "error_msg")
            ]
        )
    }

    private static func placementId(_ event: AnalyticsEvent) -> String {
        firstString(event.params, keys: "PlacementId", "placement", "ad_unit_id")
    }

    private static func networkFirmId(_ event: AnalyticsEvent) -> String {
        let value = firstString(
            event.params,
            keys: "network_firm_id",
            "ad_platform_id",
            "ad_source_id",
            "ad_source_name",
            "ad_platform"
        )
        return value.isEmpty ? "admob" : value
    }

    private static func adType(_ value: Any?) -> String {
        switch stringValue(value) {
        case "native": return "Native"
        case "rewarded": return "RewardedVideo"
        case "banner": return "Banner"
        case "interstitial": return "Interstitial"
        case "app_open": return "Splash"
        default: return stringValue(value)
        }
    }

    private static func firstString(_ params: [String: AnySendable], keys: String...) -> String {
        for key in keys {
            let value = stringValue(params[key]?.value)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        return "\(value)"
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

public protocol DataEyeBridge: AnyObject, Sendable {
    func initialize(appId: String, serverUrl: String?)
    func setUserId(_ uid: String?)
    func setUserProperties(_ properties: [String: Any?])
    func track(eventName: String, parameters: [String: Any])
    func flush()
}

public final class DataEyeAnalyticsProvider: AnalyticsProvider, UserIdentityAnalyticsProvider, UserPropertiesAnalyticsProvider, @unchecked Sendable {
    public let name = "dataeye"
    private let bridge: DataEyeBridge
    private var userProperties: [String: Any?] = [:]

    public init(appId: String, serverUrl: String? = nil, bridge: DataEyeBridge) {
        self.bridge = bridge
        bridge.initialize(appId: appId, serverUrl: serverUrl)
    }

    public func setUserId(_ uid: String?) {
        bridge.setUserId(uid)
    }

    public func setUserProperties(_ properties: [String: Any?]) {
        userProperties.merge(properties) { _, new in new }
        bridge.setUserProperties(properties)
    }

    public func track(_ event: AnalyticsEvent) {
        if let uid = event.uid {
            bridge.setUserId(uid)
        }
        let biEvent = BIEventMapper.map(event)
        let parameters = (userProperties.merging(biEvent.parameters.mapValues(\.value)) { _, new in new })
            .compactMapValues { $0 }
        bridge.track(eventName: biEvent.name, parameters: parameters)
    }

    public func flush() {
        bridge.flush()
    }
}

public final class NoopDataEyeBridge: DataEyeBridge, @unchecked Sendable {
    public private(set) var events: [(name: String, parameters: [String: Any])] = []

    public init() {}
    public func initialize(appId: String, serverUrl: String?) {}
    public func setUserId(_ uid: String?) {}
    public func setUserProperties(_ properties: [String: Any?]) {}
    public func track(eventName: String, parameters: [String: Any]) {
        events.append((eventName, parameters))
    }
    public func flush() {}
}
