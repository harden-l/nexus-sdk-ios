import Foundation
import NexusCoreUser

public struct AnalyticsConfig: Equatable, Sendable {
    public var productId: String
    public var platform: String
    public var enableBI: Bool
    public var enableFirebase: Bool
    public var enableAppsflyer: Bool
    public var enableAdMob: Bool
    public var dataEyeAppId: String?
    public var dataEyeServerUrl: String?
    public var appsflyerDevKey: String?
    public var queueMaxSize: Int
    public var debug: Bool

    public init(
        productId: String,
        platform: String = "ios",
        enableBI: Bool = true,
        enableFirebase: Bool = true,
        enableAppsflyer: Bool = true,
        enableAdMob: Bool = true,
        dataEyeAppId: String? = nil,
        dataEyeServerUrl: String? = nil,
        appsflyerDevKey: String? = nil,
        queueMaxSize: Int = 500,
        debug: Bool = false
    ) throws {
        guard !productId.isEmpty else { throw GrowthAnalyticsError.invalidConfig("productId is required") }
        guard !platform.isEmpty else { throw GrowthAnalyticsError.invalidConfig("platform is required") }
        guard queueMaxSize > 0 else { throw GrowthAnalyticsError.invalidConfig("queueMaxSize must be greater than 0") }
        self.productId = productId
        self.platform = platform
        self.enableBI = enableBI
        self.enableFirebase = enableFirebase
        self.enableAppsflyer = enableAppsflyer
        self.enableAdMob = enableAdMob
        self.dataEyeAppId = dataEyeAppId
        self.dataEyeServerUrl = dataEyeServerUrl
        self.appsflyerDevKey = appsflyerDevKey
        self.queueMaxSize = queueMaxSize
        self.debug = debug
    }
}

public struct AnalyticsEvent: Equatable, Sendable {
    public var eventName: String
    public var uid: String?
    public var deviceId: String?
    public var productId: String
    public var platform: String
    public var timestamp: Int64
    public var params: [String: AnySendable]

    public init(eventName: String, uid: String?, deviceId: String?, productId: String, platform: String, timestamp: Int64, params: [String: Any?]) {
        self.eventName = eventName
        self.uid = uid
        self.deviceId = deviceId
        self.productId = productId
        self.platform = platform
        self.timestamp = timestamp
        self.params = params.compactMapValues { $0.map(AnySendable.init) }
    }
}

public struct AnySendable: @unchecked Sendable, Equatable, CustomStringConvertible {
    public let value: Any
    public init(_ value: Any) { self.value = value }
    public var description: String { "\(value)" }
    public static func == (lhs: AnySendable, rhs: AnySendable) -> Bool { "\(lhs.value)" == "\(rhs.value)" }
}

public protocol AnalyticsProvider: AnyObject, Sendable {
    var name: String { get }
    func track(_ event: AnalyticsEvent)
    func flush()
}

public protocol UserIdentityAnalyticsProvider: AnyObject, Sendable {
    func setUserId(_ uid: String?)
}

public protocol UserPropertiesAnalyticsProvider: AnyObject, Sendable {
    func setUserProperties(_ properties: [String: Any?])
}

public final class MockAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
    public let name: String
    public private(set) var events: [AnalyticsEvent] = []

    public init(name: String) {
        self.name = name
    }

    public func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    public func flush() {}
}

public final class QueuedAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
    public let name: String
    private let wrapped: AnalyticsProvider
    private let maxSize: Int
    private var queue: [AnalyticsEvent] = []

    public init(wrapped: AnalyticsProvider, maxSize: Int = 500) {
        self.wrapped = wrapped
        self.name = "queued_\(wrapped.name)"
        self.maxSize = max(1, maxSize)
    }

    public func track(_ event: AnalyticsEvent) {
        queue.append(event)
        if queue.count > maxSize {
            queue.removeFirst(queue.count - maxSize)
        }
        wrapped.track(event)
    }

    public func flush() {
        queue.forEach { wrapped.track($0) }
        queue.removeAll()
        wrapped.flush()
    }

    public func pendingEvents() -> [AnalyticsEvent] {
        queue
    }
}

public final class PersistentQueuedAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
    public let name: String
    private let wrapped: AnalyticsProvider
    private let maxSize: Int
    private let storageKey: String
    private let defaults: UserDefaults
    private var queue: [AnalyticsEvent]

    public init(
        wrapped: AnalyticsProvider,
        productId: String,
        maxSize: Int = 500,
        defaults: UserDefaults = .standard
    ) {
        self.wrapped = wrapped
        self.name = "persistent_queued_\(wrapped.name)"
        self.maxSize = max(1, maxSize)
        self.storageKey = "nexus.growth.\(productId).queue.\(wrapped.name)"
        self.defaults = defaults
        self.queue = Self.loadEvents(defaults: defaults, key: storageKey)
    }

    public func track(_ event: AnalyticsEvent) {
        queue.append(event)
        if queue.count > maxSize {
            queue.removeFirst(queue.count - maxSize)
        }
        persist()
        wrapped.track(event)
    }

    public func flush() {
        queue.forEach { wrapped.track($0) }
        queue.removeAll()
        persist()
        wrapped.flush()
    }

    public func pendingEvents() -> [AnalyticsEvent] {
        queue
    }

    private func persist() {
        let records = queue.map(EventRecord.init(event:))
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func loadEvents(defaults: UserDefaults, key: String) -> [AnalyticsEvent] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([EventRecord].self, from: data) else {
            return []
        }
        return records.map(\.event)
    }

    private struct EventRecord: Codable {
        var eventName: String
        var uid: String?
        var deviceId: String?
        var productId: String
        var platform: String
        var timestamp: Int64
        var params: [String: String]

        init(event: AnalyticsEvent) {
            self.eventName = event.eventName
            self.uid = event.uid
            self.deviceId = event.deviceId
            self.productId = event.productId
            self.platform = event.platform
            self.timestamp = event.timestamp
            self.params = event.params.mapValues { "\($0.value)" }
        }

        var event: AnalyticsEvent {
            AnalyticsEvent(
                eventName: eventName,
                uid: uid,
                deviceId: deviceId,
                productId: productId,
                platform: platform,
                timestamp: timestamp,
                params: params
            )
        }
    }
}

extension PersistentQueuedAnalyticsProvider: UserIdentityAnalyticsProvider {
    public func setUserId(_ uid: String?) {
        (wrapped as? UserIdentityAnalyticsProvider)?.setUserId(uid)
    }
}

extension PersistentQueuedAnalyticsProvider: UserPropertiesAnalyticsProvider {
    public func setUserProperties(_ properties: [String: Any?]) {
        (wrapped as? UserPropertiesAnalyticsProvider)?.setUserProperties(properties)
    }
}

extension QueuedAnalyticsProvider: UserIdentityAnalyticsProvider {
    public func setUserId(_ uid: String?) {
        (wrapped as? UserIdentityAnalyticsProvider)?.setUserId(uid)
    }
}

extension QueuedAnalyticsProvider: UserPropertiesAnalyticsProvider {
    public func setUserProperties(_ properties: [String: Any?]) {
        (wrapped as? UserPropertiesAnalyticsProvider)?.setUserProperties(properties)
    }
}

public enum GrowthAnalyticsError: Error, LocalizedError, Equatable {
    case invalidConfig(String)
    case notInitialized
    case providerUnsupported(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let message), .providerUnsupported(let message): return message
        case .notInitialized: return "GrowthAnalyticsAdSDK is not initialized"
        }
    }
}
