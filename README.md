# Nexus SDK iOS

Swift Package for iOS business apps using the shared-account `/api/v1` service. Version: `0.1.0`. Requires iOS 15+ and Swift tools 5.9. Start with the [iOS Business Integration Guide](docs/ios/business-integration-guide.md) for configuration and usage by module.

## Products

| Product | Business capability |
| --- | --- |
| `NexusCoreUser` | Guest, email and phone sign-in; scoped sessions, account binding, profile, balance, coin consumption and weekly points |
| `NexusGrowthAnalyticsAd` | Analytics, attribution, user properties, ad control and revenue reporting with optional providers |
| `NexusPayment` | Products, StoreKit 2 purchases, order status, restore and three subscription-page templates |
| `NexusCrossPromo` | Related-app recommendations, incoming Deep Links and attribution |
| `NexusGrowthAnalyticsAdDataEye` | Bundled DataEye provider/bridge; the host supplies the official DataEye SDK and bridge implementation |

SPM resolves internal module dependencies. Payment and CrossPromo require CoreUser initialization; analytics reporting requires explicit Growth initialization with the actual providers. Payment does not initialize Growth automatically.

## Dependencies

Add the package using an exact version:

```swift
.package(url: "https://github.com/harden-l/nexus-sdk-ios.git", exact: "0.1.0")
```

Firebase, AppsFlyer and AdMob use separate optional provider packages. Use provider `0.1.0` with root SDK `0.1.0`. The older `0.0.16` providers pin root SDK `0.0.16` exactly and cannot be mixed with this version.

For DataEye, select `.product(name: "NexusGrowthAnalyticsAdDataEye", package: "nexus-sdk-ios")` from the root package and connect `DataEyeBridge` to the official SDK. A separate remote DataEye package is not required.

## Accounts And Amounts

- Set `apiBaseUrl` to the service origin without `/api/v1`. Login request bodies are plaintext JSON; encrypted mode still encrypts login responses. Other integrated requests use the configured encryption and Bearer authentication without a body UID.
- Token/session data is stored in Keychain, scoped by service address, product and App Group suite. `try getToken()` returns an optional raw Token without network access; `try getSessionInfo()` returns `uid`, `loginType`, Unix-second `expiresAt` and `isValid`, without exposing the Token. Old UID-only caches are not valid sessions.
- Expired or rejected email/phone sessions require account sign-in; 401 never silently falls back to a guest. Passwords must be 8-72 bytes of visible ASCII (33-126), without whitespace. Binding passwords are optional, but setting one on first bind is recommended for later account sign-in.
- `logout()` deregisters the current product user on the server and clears local UID, Token, session and profile on success. `clearLocalSession()` only signs out locally. Neither operation should be followed by an automatic guest fallback. Dynamic switch APIs are removed; `getSdkConfig()` only reads initialization parameters.
- Prefer exact `Decimal` fields over compatibility `Double`/`Int` values. `SDKUser.balanceDecimal` and `balance` are already raw balance ×100. Coin-consumption results, `coinsGrantedDecimal`, `weeklyPointsDecimal` and claim amounts remain raw coins; multiply once only when displaying them. Integer weekly compatibility fields truncate fractions.
- Use only no-argument `getWeeklyPointsInfo()` and `claimWeeklyPoints()`. Both send exactly `{}`; the server selects the eligible subscription. Eligibility comes from `canClaim`, with at most one claim per product/user per UTC week.

For `consumeChatCoins`, generate a UUID per business bill and persist it with the original amount and remark before sending. Success returns `ConsumeChatCoinsResult.idempotencyKey: String`. Network/API/decoding failures after validation are wrapped in `ConsumeChatCoinsError` with `idempotencyKey` and `underlyingError`; read business codes using `(error.underlyingError as? CoreUserError)?.businessCode`. Validation failures still require the ordinary error branch. If the key was omitted, the SDK-generated default UUID can be recovered from the result or wrapped error. Callers must retain and explicitly reuse that key with the same amount and remark on retry, never omit it again or generate a replacement. SDK errors do not automatically replay a bill; a later profile-refresh failure is not a debit failure.

Test configuration only: `https://aishare.stoahayaamhsothy.com`, product ID `7`, product name `TEST PRODUCT`, key `1b8df48c1fa64ce28a2e8133dffe600c`. Production values must come from the backend; do not reuse this test configuration.

## Payments And Benefits

`coins_granted` is the upfront coin benefit after purchase. Enabled `weekly_points` is an additional weekly claim benefit. Display both independently; enabling weekly points must not hide upfront coins. The three templates use this same rule. Membership is product-specific; the related-app section does not promise shared membership.

StoreKit details and a valid store price are required to enable purchasing. Backend `price_usd` is an integer number of USD cents, for reference only (199 means USD 1.99); checkout uses the store's actual localized price and currency.

Order queries use `POST /api/v1/order/apple/status` with a login Bearer Token:

| Purchase | Request fields |
| --- | --- |
| One-time | `issub=false`, `platform_product_id`, signed transaction JWS `token` and/or matching current `trade_order_id` (StoreKit transaction ID); no original transaction ID |
| Subscription | Only `issub=true` and `original_transaction_id`; no JWS token, current trade ID or SKU |

The SDK passes the system UID as StoreKit `appAccountToken`, accepting a standard UUID or a 32-character hexadecimal UID that can be represented losslessly as a UUID. Other formats fail; never substitute an unrelated generated UUID. `ProviderPurchaseResult.orderId` is the current transaction ID; subscription-chain identity is separate. Payment credentials are not login Tokens. Only order status `50` is successful; `10` is pending, `60` refunded, `70` cancelled and `80` expired. Unknown states are not successful. Payment amounts remain strings with their currency, without coin scaling; timestamps use Unix seconds.

Store notifications asynchronously maintain wallet balances and membership, so even a paid order can precede the account update. Status queries do not grant coins or rebuild subscription chains. Refresh `fetchUserInfo()` after purchase, restore or claims and allow delayed confirmation; do not add coins locally, infer membership solely from order status or ask users to repeat a pending purchase. StoreKit transaction updates and restore handling support reconciliation of pending transactions and renewals.
