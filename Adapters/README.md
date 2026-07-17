# iOS Growth Analytics Ad Providers

Each provider is an optional Swift Package. Integrators add only the packages they need:

- `FirebaseProvider` -> `NexusGrowthAnalyticsAdFirebase`
- `AppsFlyerProvider` -> `NexusGrowthAnalyticsAdAppsFlyer`
- `AdMobProvider` -> `NexusGrowthAnalyticsAdAdMob`
- `DataEyeProvider` -> `NexusGrowthAnalyticsAdDataEye`

The base `ios/Package.swift` stays free of third-party analytics and ad dependencies.

## Usage

Add the base package first:

```swift
.package(path: "path/to/sdk-platform/ios")
```

Then add only the provider packages needed by the host app:

```swift
.package(path: "path/to/sdk-platform/ios/Adapters/FirebaseProvider")
.package(path: "path/to/sdk-platform/ios/Adapters/AppsFlyerProvider")
.package(path: "path/to/sdk-platform/ios/Adapters/AdMobProvider")
.package(path: "path/to/sdk-platform/ios/Adapters/DataEyeProvider")
```

Initialize with provider injection:

```swift
let firebase = FirebaseAnalyticsProvider()
let appsFlyer = AppsFlyerAnalyticsProvider(
    devKey: "<dev-key>",
    appleAppID: "<apple-app-id>",
    onAttributionResolved: { attribution in
        print("AppsFlyer attribution:", attribution)
    }
)
let dataEye = DataEyeAnalyticsProvider(appId: "<dataeye-app-id>", bridge: YourDataEyeBridge())
let adMob = AdMobAdProvider(
    rootViewControllerProvider: { UIApplication.shared.keyWindow?.rootViewController },
    revenueReporter: { payload in
        _ = try? NexusGrowthAnalyticsAd.shared.reportAdRevenue(payload)
    }
)

let config = try AnalyticsConfig(productId: "7")
NexusGrowthAnalyticsAd.shared.initialize(
    config: config,
    providers: [firebase, appsFlyer, dataEye],
    adProvider: adMob
)
```

Firebase requires `GoogleService-Info.plist` in the host app. AdMob requires `GADApplicationIdentifier` and SKAdNetwork entries in the host app `Info.plist`. AppsFlyer Universal Link and URL Scheme callbacks should be forwarded to `AppsFlyerAnalyticsProvider`.

`AppsFlyerAnalyticsProvider` registers as the AppsFlyer conversion and deep-link delegate. Conversion data, OneLink app-open attribution, and UDL deep-link data are saved into `NexusGrowthAnalyticsAd.getInstallSource()`.

`AdMobAdProvider` listens to Google Mobile Ads paid events for app-open, interstitial, rewarded, banner, and native ads. Pass a `revenueReporter` closure to forward the generated `AdRevenuePayload` to `NexusGrowthAnalyticsAd.reportAdRevenue`.

`FirebaseProvider` uses Firebase's official Swift Package dependency:

```swift
.package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0")
```

`DataEyeProvider` uses a `DataEyeBridge`. DataEye's iOS SDK document describes CocoaPods integration, so the provider does not force a CocoaPods dependency into the base Swift Package. Implement `DataEyeBridge` in the host app or a thin internal adapter target, then forward `initialize`, `setUserId`, `setUserProperties`, `track`, and `flush` to the official DataEye SDK. The provider maps Nexus events to BI/DataEye event names and parameters before calling the bridge. A copyable template is available at `ios/Examples/DataEyeBridgeExample.swift`.

```swift
final class OfficialDataEyeBridge: DataEyeBridge {
    func initialize(appId: String, serverUrl: String?) {
        // Initialize the official DataEye iOS SDK here.
    }

    func setUserId(_ uid: String?) {
        // Forward login/user id to DataEye.
    }

    func setUserProperties(_ properties: [String: Any?]) {
        // Cache or forward user properties as supported by DataEye.
    }

    func track(eventName: String, parameters: [String: Any]) {
        // Forward mapped BI event to DataEye.
    }

    func flush() {
        // Flush if the official SDK exposes a flush API.
    }
}
```
