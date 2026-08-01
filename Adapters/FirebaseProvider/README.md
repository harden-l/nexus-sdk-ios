# Nexus Firebase Provider

Firebase Analytics Provider for `NexusGrowthAnalyticsAd`.

## Swift Package Manager

Add this package and select the `NexusGrowthAnalyticsAdFirebase` product:

```text
https://github.com/harden-l/nexus-sdk-ios-firebase-provider.git
```

Add a `GoogleService-Info.plist` matching the host App bundle identifier, then initialize the provider:

```swift
import NexusGrowthAnalyticsAd
import NexusGrowthAnalyticsAdFirebase

let firebase = FirebaseAnalyticsProvider()
NexusGrowthAnalyticsAd.shared.initialize(
    config: try AnalyticsConfig(productId: "<PRODUCT_ID>"),
    providers: [firebase]
)
```

The provider version is aligned with the Nexus iOS SDK version.
