import Foundation
import NexusGrowthAnalyticsAdDataEye

// Add the official DataEye iOS SDK with CocoaPods in the host app target.
//
// Podfile example:
// target 'YourApp' do
//   pod '<DataEye official pod name>'
// end
//
// Keep this bridge in the host app target. The Nexus adapter maps Nexus events
// to BI/DataEye event names first, then calls this bridge.
final class OfficialDataEyeBridge: DataEyeBridge, @unchecked Sendable {
    private let queue = DispatchQueue(label: "nexus.dataeye.bridge")
    private var pendingUserProperties: [String: Any?] = [:]

    func initialize(appId: String, serverUrl: String?) {
        queue.async {
            // Replace with the official DataEye SDK initialization API.
            //
            // Example shape:
            // DataEyeAnalyticsSDK.sharedInstance(appId, serverUrl: serverUrl)
            // DataEyeAnalyticsSDK.sharedInstance()?.enableDebugLog(true)
        }
    }

    func setUserId(_ uid: String?) {
        queue.async {
            guard let uid, !uid.isEmpty else { return }
            // Replace with the official login/user-id API.
            //
            // Example shape:
            // DataEyeAnalyticsSDK.sharedInstance()?.login(uid)
            // or:
            // DataEyeAnalyticsSDK.sharedInstance()?.setAccountId(uid)
        }
    }

    func setUserProperties(_ properties: [String: Any?]) {
        queue.async {
            self.pendingUserProperties.merge(properties) { _, new in new }
            let values = self.pendingUserProperties.compactMapValues { $0 }
            guard !values.isEmpty else { return }
            // Replace with the official user property API if available.
            //
            // Example shape:
            // DataEyeAnalyticsSDK.sharedInstance()?.setUserProperties(values)
        }
    }

    func track(eventName: String, parameters: [String: Any]) {
        queue.async {
            // Replace with the official event API.
            //
            // Example shape:
            // DataEyeAnalyticsSDK.sharedInstance()?.track(eventName, parameters: parameters)
        }
    }

    func flush() {
        queue.async {
            // Replace with the official flush/upload API if available.
            //
            // Example shape:
            // DataEyeAnalyticsSDK.sharedInstance()?.flush()
        }
    }
}
