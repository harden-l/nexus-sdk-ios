# Nexus AppsFlyer Provider

AppsFlyer analytics, attribution, and deep-link Provider for `NexusGrowthAnalyticsAd`.

## Swift Package Manager

Add this package and select the `NexusGrowthAnalyticsAdAppsFlyer` product:

```text
https://github.com/harden-l/nexus-sdk-ios-appsflyer-provider.git
```

Initialize with credentials owned by the host App:

```swift
import NexusGrowthAnalyticsAd
import NexusGrowthAnalyticsAdAppsFlyer

let appsFlyer = AppsFlyerAnalyticsProvider(
    devKey: "<APPSFLYER_DEV_KEY>",
    appleAppID: "<APPLE_APP_ID>"
)
NexusGrowthAnalyticsAd.shared.initialize(
    config: try AnalyticsConfig(productId: "<PRODUCT_ID>"),
    providers: [appsFlyer]
)
```

Forward URL Scheme and Universal Link callbacks to `AppsFlyerAnalyticsProvider`. The provider version is aligned with the Nexus iOS SDK version.
