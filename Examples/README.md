# iOS Examples

This folder contains integration snippets for a host iOS demo app.

Recommended demo app structure:

- `NexusDemoApp.swift`: initializes CoreUser, GrowthAnalyticsAd, Payment, and CrossPromo.
- `NexusRemoteDemo`: lightweight simulator demo for CoreUser, Payment, CrossPromo, GrowthAnalyticsAd base SDK, and DataEye bridge.
- `NexusProviderDemo`: full provider simulator demo for Firebase, AppsFlyer, AdMob, and DataEye bridge.
- `DataEyeBridgeExample.swift`: shows how to bridge the CocoaPods DataEye SDK into `DataEyeAnalyticsProvider`.

Create an iOS app in Xcode, add the local Swift package at `../../`, then copy the snippets into the app target.

Provider packages are optional:

- Firebase: `../../Adapters/FirebaseProvider`
- AppsFlyer: `../../Adapters/AppsFlyerProvider`
- AdMob: `../../Adapters/AdMobProvider`
- DataEye: `../../Adapters/DataEyeProvider`
