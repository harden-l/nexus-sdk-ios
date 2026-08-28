# Nexus SDK iOS

This directory contains the Swift Package implementation of the Nexus SDK.

Current release: `0.0.11`

Current status:

- CoreUser implements v7 login, user info, bind account, related products, device id, login config, and AES/CBC encryption.
- GrowthAnalyticsAd implements event routing, attribution/deep link cache, user properties, persistent queued providers, ad frequency control, revenue events, and optional provider adapters.
- Payment implements product loading, StoreKit 2 App Store provider, server order verification, entitlement grant, restore handling, and a UIKit subscription page.
- CrossPromo implements related product loading, promo page, deep link attribution, user link event reporting, and iOS deep-link/App Store fallback opening.
- Provider adapters live under `Adapters/` and are optional.

Feature alignment notes:

- AdMob adapter supports app-open, interstitial, rewarded, rewarded-interstitial, banner, native ads, paid-event revenue callbacks, and app-open foreground lifecycle helper.
- StoreKit 2 provider sends `signedTransactionInfo` and `originalTransactionId` to server verification and observes `Transaction.updates` for renewals, refunds, and revoked entitlements.
- CrossPromo supports `ios_scheme` from related-products responses for installed-app detection/opening before falling back to App Store URLs.

## App Store order verification

`NexusPayment` uses StoreKit 2 for App Store purchases. When the provider purchase succeeds:

- `ProviderPurchaseResult.purchaseToken` is StoreKit's `signedTransactionInfo` JWS.
- `ProviderPurchaseResult.orderId` is `originalTransactionId`, used as `trade_order_id`.
- If the Nexus uid is a UUID string, it is passed to StoreKit as `appAccountToken`.

The server verification request is sent to `POST /pp/v7/apple/os` with `token`, `platform_product_id`, `uid`, `issub`, and `trade_order_id`.

## Targets

- `NexusCoreUser`
- `NexusGrowthAnalyticsAd`
- `NexusPayment`
- `NexusCrossPromo`

## Verification

```bash
swift build
swift test
```

In restricted local environments, use:

```bash
CLANG_MODULE_CACHE_PATH=.swift-cache/clang SWIFTPM_CACHE_PATH=.swift-cache/swiftpm swift build --disable-sandbox
CLANG_MODULE_CACHE_PATH=.swift-cache/clang SWIFTPM_CACHE_PATH=.swift-cache/swiftpm swift test --disable-sandbox
```

## Integration Guide

See [iOS business integration guide](../docs/ios/business-integration-guide.md).
