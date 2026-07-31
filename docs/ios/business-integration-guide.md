# Nexus SDK iOS 业务接入说明

本文面向接入 Nexus SDK 的 iOS 业务 App。SDK 按模块提供能力，业务方可以根据需求只接入其中 1 个或多个模块。

当前版本：`0.0.4`

## 1. 模块选择

| 模块 | Swift Package Product | 适用场景 | 前置依赖 |
| --- | --- | --- | --- |
| CoreUserSDK | `NexusCoreUser` | 设备 ID、静默登录、用户信息、邮箱绑定、登录动态配置 | 无 |
| GrowthAnalyticsAdSDK | `NexusGrowthAnalyticsAd` | BI/Firebase/AppsFlyer 事件、AdMob 广告、归因 | 建议接入 CoreUserSDK，用于 uid/deviceId |
| PaymentSDK | `NexusPayment` | 商品、订阅页、App Store 支付、订单校验、权益 | 必须先初始化 CoreUserSDK |
| CrossPromoSDK | `NexusCrossPromo` | 应用互导推荐页、Deep Link、导量归因 | 必须先初始化 CoreUserSDK；如需事件上报，建议接入 GrowthAnalyticsAdSDK |

## 2. 通用准备

请按实际接入模块向后台或 SDK 提供方确认配置：

| 配置 | 用途 |
| --- | --- |
| `productId` | 后台产品 ID；接口 Header 中的 `ProductId`。 |
| `productName` | 接口 Header `Product`。 |
| `accountName` | App Store Connect 开发者账号名称；默认 `test` 仅供测试，生产上线前必须替换为真实值。 |
| `apiBaseUrl` | 接口域名；测试环境使用 `https://serverlf.stoahayaamhsothy.com/`，生产环境使用 `https://v8b.crypsiscollectiveinc.com`。 |
| `encryptionKey` | 生产环境必填，32 字节 AES key。 |
| AdMob App ID / Ad Unit ID | 仅广告模块需要。 |
| Firebase 配置 | 仅 Firebase 事件需要，业务 App 需要按 Firebase 官方方式接入真实配置。 |
| AppsFlyer Dev Key / Apple App ID | 仅 AppsFlyer 事件和归因需要。 |
| DataEye App ID / Server URL | 仅 BI(DataEye) 事件需要。 |
| `gt` | 登录注册赠送梯度码，非必填：`1` 赠送 10，`2` 赠送 20，`3` 赠送 30，其它值不赠送。 |
| App Store 商品 ID | 仅支付模块需要，后台商品 `market_product_id` 需要和 App Store Connect 商品 ID 一致。 |
| URL Scheme / Universal Link | 仅 CrossPromo 或归因 Deep Link 需要。 |

生产环境说明：

- `CoreUserConfig.encrypt` 默认是 `true`。
- `encrypt = true` 时必须传 `encryptionKey`。
- `gt` 为登录注册赠送梯度码，默认不传。
- 其它接口按 `encrypt` 配置加密请求并解密响应。
- iOS 网络 API 为 async/await，业务侧应在异步上下文调用。
- Firebase、AppsFlyer、AdMob、DataEye 的平台配置属于宿主业务 App，SDK 不写死这些配置。

## 3. Swift Package 依赖

当前 iOS SDK 通过 Swift Package Manager 提供：

```txt
https://github.com/harden-l/nexus-sdk-ios.git
```

推荐指定版本：`0.0.4`。

Xcode 接入：

1. `File` -> `Add Package Dependencies...`
2. 输入 `https://github.com/harden-l/nexus-sdk-ios.git`
3. Dependency Rule 选择 `Exact Version`，版本填 `0.0.4`
4. 按需勾选业务 App target 需要的 products

Package.swift 接入：

```swift
.package(url: "https://github.com/harden-l/nexus-sdk-ios.git", exact: "0.0.4")
```

按需添加 target product：

```swift
.product(name: "NexusCoreUser", package: "NexusSDK")
.product(name: "NexusGrowthAnalyticsAd", package: "NexusSDK")
.product(name: "NexusPayment", package: "NexusSDK")
.product(name: "NexusCrossPromo", package: "NexusSDK")
```

如果只需要登录，只添加 `NexusCoreUser` 即可。

三方 Provider 说明：

- 主 SDK 默认不强制拉取 Firebase / AppsFlyer / AdMob 官方 SDK，避免只接 CoreUser/Payment 的业务方被迫下载大体积三方依赖。
- 需要真实 Firebase、AppsFlyer、AdMob 上报或广告能力时，请向 SDK 提供方获取对应 Provider Package 接入方式。
- DataEye 通过 `DataEyeBridge` 对接官方 iOS SDK，避免基础包强制依赖 CocoaPods。

## 4. CoreUserSDK 接入

### 4.1 适用场景

接入 CoreUserSDK 后，业务方可以获得：

- 设备唯一 ID。
- 静默登录 uid。
- 用户信息：邮箱、手机号绑定状态、余额 `balance`。
- 登录动态配置。
- 聊天账单扣除金币。
- SDK 内置绑定邮箱弹窗。

### 4.2 依赖

```swift
.product(name: "NexusCoreUser", package: "NexusSDK")
```

### 4.3 初始化

```swift
import NexusCoreUser

let coreConfig = try CoreUserConfig(
    productId: "7",
    productName: "TEST PRODUCT",
    accountName: "test",
    apiBaseUrl: "https://serverlf.stoahayaamhsothy.com/",
    encrypt: false,
    encryptionKey: "1b8df48c1fa64ce28a2e8133dffe600c",
    debug: true,
    gt: 1
)

NexusCoreUser.shared.initialize(config: coreConfig)
```

生产环境需要打开加密并传入当前产品的 `encryptionKey`：

```swift
let coreConfig = try CoreUserConfig(
    productId: "7",
    productName: "TEST PRODUCT",
    accountName: "real-app-store-account-name",
    apiBaseUrl: "https://v8b.crypsiscollectiveinc.com",
    encrypt: true,
    encryptionKey: "32-byte-product-encryption-key",
    gt: 1
)

NexusCoreUser.shared.initialize(config: coreConfig)
```

`CoreUserConfig` 字段说明：

| 字段 | 是否必填 | 说明 |
| --- | --- | --- |
| `appId` | 否 | 预留字段，当前业务接入可不传。 |
| `productId` | 是 | 后台产品 ID；接口 Header 中的 `ProductId`。 |
| `productName` | 是 | 产品名称；接口 Header 中的 `Product`。 |
| `accountName` | 否 | 默认 `test`，仅供测试；`apiBaseUrl + /related_products` 接口使用它查询同账号应用，生产上线前必须设置真实的 App Store Connect 开发者账号名称。 |
| `apiBaseUrl` | 是 | Nexus 后台接口域名；测试环境使用 `https://serverlf.stoahayaamhsothy.com/`，生产环境使用 `https://v8b.crypsiscollectiveinc.com`。 |
| `version` | 否 | App 版本号；默认读取 `CFBundleShortVersionString`，读取失败时为 `1.0.0`。 |
| `country` | 否 | 国家/地区；不传时 SDK 自动使用设备 Locale。 |
| `language` | 否 | 语言；不传时 SDK 自动使用设备 Locale。 |
| `encrypt` | 否 | 是否加密非登录接口，默认 `true`；登录接口固定不加密。 |
| `encryptionKey` | `encrypt=true` 时必填 | 当前产品的 32 字节 AES key。 |
| `debug` | 否 | 是否输出 SDK debug log，默认 `false`。 |
| `gt` | 否 | 登录注册赠送梯度码：`1` 赠送 10，`2` 赠送 20，`3` 赠送 30，其它值不赠送；不传时登录请求不携带。<br />仅本次首次创建用户且新建共享钱包时生效 |

### 4.4 登录

```swift
let user = try await NexusCoreUser.shared.silentLogin()
// user.uid
// user.deviceId
// user.emailBound
// user.phoneBound
// user.balance
// 登录不会强制绑定邮箱；需要绑定时由业务主动展示入口或调用 ensureEmailBound。
```

登录类型：

```swift
let user = try await NexusCoreUser.shared.silentLogin(loginType: .guest)
```

当前枚举值：

- `.guest`
- `.email`
- `.phone`

默认使用 `.guest`。登录请求会携带本地已有 uid；首次登录时 uid 为空字符串。

登录后SDK会拉取一次用户信息。


### 4.5 获取登录动态配置

```swift
let loginConfig = try NexusCoreUser.shared.getConfig()
let value = loginConfig["example_key"]
```

`getConfig()` 返回最近一次登录接口响应中除 `uid` 之外的动态配置字段。登录接口返回字段是不固定的，SDK 不会为这些字段定义固定模型，业务方按后台配置约定读取即可。

说明：

- 首次登录成功前调用时可能返回空字典。
- `logout()` 会先调用 `POST /m/v7/coins/deregister` 注销接口，成功后清空本地保存的登录动态配置和用户资料缓存，但保留 uid，下一次登录请求仍会携带该 uid。
- `getConfig()` 返回的是登录动态配置，不是 `/m/v7/user/info` 的用户信息。

退出登录示例：

```swift
NexusCoreUser.shared.logout { result in
    switch result {
    case .success:
        // 退出成功
    case .failure(let error):
        // 注销接口失败，本地用户缓存不会被清理
    }
}
```

### 4.6 用户信息和邮箱绑定

```swift
let user = try await NexusCoreUser.shared.fetchUserInfo()
// user.balance 为当前用户余额
if !user.emailBound {
    // 可展示绑定入口
}
```

`fetchUserInfo()` 会请求 `/m/v7/user/info`，返回用户资料和当前余额 `balance`，并刷新 SDK 本地用户缓存。业务方展示金币余额或扣金币后刷新余额时，可以读取返回的 `user.balance`。

使用 SDK 内置邮箱绑定弹窗：

```swift
NexusCoreUser.shared.ensureEmailBound(presenting: viewController) { result in
    // alreadyBound / bound / cancelled / userInfoFailed / bindFailed
}
```

直接调用绑定接口：

```swift
let result = try await NexusCoreUser.shared.bindEmail("user@example.com")
```

### 4.7 扣除金币

```swift
NexusCoreUser.shared.consumeChatCoins(cost: 2.5, remark: "chat billing") { result in
    switch result {
    case .success(let consume):
        // consume.beforeCoins
        // consume.afterCoins
        // consume.balance
    case .failure(let error):
        // 扣除失败处理
    }
}
```

也可以使用 async API：

```swift
let consume = try await NexusCoreUser.shared.consumeChatCoins(
    cost: 2.5,
    remark: "chat billing"
)
```

说明：

- 该能力调用 `/m/v7/coins/consume_chat`，SDK 会自动携带当前 uid；本地无用户时会先静默登录。
- `cost` 必须大于 `0`，金币数使用 `Double`，避免小数被截断。
- 该接口按 `CoreUserConfig.encrypt` 的通用策略加密请求和解密响应，不走登录接口免加密规则。
- 扣除成功后 SDK 不直接修改本地 `SDKUser.balance` 缓存；业务方如需刷新余额，调用 `fetchUserInfo()`。

### 4.8 CoreUser 验收

- 初始化不抛异常。
- `silentLogin()` 返回 uid。
- 配置 `gt` 后，登录请求能携带注册赠送梯度码；未配置时不携带。
- `NexusCoreUser.shared.getConfig()` 能读取登录接口返回的动态配置。
- 再次登录时请求体带上本地已有 uid。
- `/m/v7/user/info` 返回的 `email_bound`、`phone_bound`、`balance` 解析正确。
- `/m/v7/coins/consume_chat` 能返回并解析 `before_coins`、`after_coins`、`balance`。
- 未绑定邮箱时弹出 SDK 内置绑定邮箱弹窗。

## 5. GrowthAnalyticsAdSDK 接入

### 5.1 适用场景

接入 GrowthAnalyticsAdSDK 后，业务方可以使用：

- BI(DataEye) 事件上报。
- Firebase 事件上报。
- AppsFlyer 事件上报。
- AdMob 广告加载和展示。
- 归因、Deep Link 解析和缓存。

如果业务方需要事件带 uid/deviceId，建议同时接入 CoreUserSDK 并调用 `setUser(user)`。

### 5.2 依赖

```swift
.product(name: "NexusGrowthAnalyticsAd", package: "NexusSDK")

// 推荐同时接入，用于用户关联
.product(name: "NexusCoreUser", package: "NexusSDK")
```

如需真实三方能力，请额外接入对应 Provider：

- Firebase Provider：对接 Firebase Analytics 官方 SDK。
- AppsFlyer Provider：对接 AppsFlyer 官方 SDK。
- AdMob Provider：对接 Google Mobile Ads 官方 SDK。
- DataEye Provider：通过 `DataEyeBridge` 对接 DataEye 官方 SDK。

### 5.3 iOS 工程配置

Firebase：

- 将 Firebase Console 下载的真实 `GoogleService-Info.plist` 加入业务 App target。
- `BUNDLE_ID` 必须和业务 App 的 Bundle Identifier 一致。
- SDK 不内置 `GoogleService-Info.plist`。

AppsFlyer：

- 配置 Dev Key 和 Apple App ID。
- 配置 Universal Link / URL Scheme。
- 在 AppDelegate / SceneDelegate 中将 URL 回调转发给 AppsFlyer Provider。

AdMob：

- 在业务 App `Info.plist` 配置 `GADApplicationIdentifier`。
- 配置 Google 要求的 `SKAdNetworkItems`。
- 使用真实广告位 ID。

示例：

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy</string>
<key>SKAdNetworkItems</key>
<array>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cstr6suwn9.skadnetwork</string>
  </dict>
</array>
```

完整 `SKAdNetworkIdentifier` 列表以 Google 官方文档为准。

DataEye：

- 业务 App 按 DataEye 官方文档接入官方 iOS SDK。
- 实现 `DataEyeBridge`，把 `initialize`、`setUserId`、`setUserProperties`、`track`、`flush` 转发到官方 SDK。
- SDK 负责 Nexus 事件到 BI(DataEye) 参数的映射，真正发送由业务方 bridge 调官方 DataEye SDK 完成。

### 5.4 初始化

```swift
import NexusGrowthAnalyticsAd

let analyticsConfig = try AnalyticsConfig(
    productId: "7",
    enableBI: true,
    enableFirebase: true,
    enableAppsflyer: true,
    enableAdMob: true,
    debug: true
)

NexusGrowthAnalyticsAd.shared.initialize(
    config: analyticsConfig,
    providers: [
        // 按需注入 BI / Firebase / AppsFlyer Provider
    ],
    adProvider: nil // 如启用 AdMob，传入 AdMob Provider
)
```

如果已接入 CoreUserSDK：

```swift
let user = try await NexusCoreUser.shared.silentLogin()
NexusGrowthAnalyticsAd.shared.setUser(user)
```

### 5.5 事件和用户属性

```swift
try NexusGrowthAnalyticsAd.shared.track("button_click", params: [
    "scene": "home"
])
```

```swift
NexusGrowthAnalyticsAd.shared.setUserProperties([
    "vip_level": 1
])
```

当前 Firebase 和 AppsFlyer 只按需求处理 `ad_impression` 的正式字段映射；BI(DataEye) 按 Nexus/BI 事件模型上报。

### 5.6 Deep Link 和归因

```swift
let result = NexusGrowthAnalyticsAd.shared.handleDeepLink(url.absoluteString)

let installSource = NexusGrowthAnalyticsAd.shared.getInstallSource()
let lastDeepLink = NexusGrowthAnalyticsAd.shared.getLastDeepLink()
```

### 5.7 AdMob 广告

```swift
let interstitial = try AdPlacement(
    placement: "level_end",
    adUnitId: "ca-app-pub-xxx/interstitial",
    format: .interstitial
)

try NexusGrowthAnalyticsAd.shared.loadAd(interstitial)
try NexusGrowthAnalyticsAd.shared.showAd(interstitial)
```

支持广告类型：

- `.appOpen`
- `.banner`
- `.interstitial`
- `.rewarded`
- `.rewardedInterstitial`
- `.native`

开屏和插屏支持预加载，展示成功或展示失败后 SDK 会自动尝试加载下一条。

### 5.8 Growth/Ad 验收

- Growth 事件能在 debug log 中看到。
- BI(DataEye) 后台能收到事件。
- Firebase、AppsFlyer 后台能收到 `ad_impression`。Firebase 必须使用真实 `GoogleService-Info.plist` 才能做后台收数验证。
- AdMob App ID 已配置在业务 App `Info.plist`。
- AdMob 各广告位能加载和展示。
- 开屏、插屏展示后能继续预加载下一条。

## 6. PaymentSDK 接入

### 6.1 适用场景

接入 PaymentSDK 后，业务方可以使用：

- `/m/v7/iap/list` 获取后台商品。
- StoreKit 2 查询 App Store 商品信息。
- 订阅页。
- App Store 购买。
- `/pp/v7/apple/os` 订单校验。
- 本地权益和收入上报。

PaymentSDK 必须先初始化 CoreUserSDK。

### 6.2 依赖

```swift
.product(name: "NexusCoreUser", package: "NexusSDK")
.product(name: "NexusPayment", package: "NexusSDK")
```

### 6.3 初始化

```swift
import NexusPayment

let paymentConfig = try PaymentConfig(
    productId: "7",
    defaultChannel: .appStore,
    enabledChannels: [.appStore],
    fallbackChannels: []
)

NexusPayment.shared.initialize(config: paymentConfig)
```

### 6.4 获取商品

```swift
let products = try await NexusPayment.shared.getProducts(forceRefresh: true)
```

商品展示信息来自两部分：

- 后台 `/m/v7/iap/list`：`market_product_id`、`product_type`、`coins_granted`。
- StoreKit 2：价格、币种、本地化价格、订阅周期、试用信息。

### 6.5 订阅页

```swift
let pageConfig = try SubscriptionPageConfig(
    templateId: "default",
    scene: "home",
    title: "Premium",
    benefitDescription: "Unlock premium benefits.",
    benefits: ["No ads", "Bonus coins"],
    sharedApps: SubscriptionSharedAppsConfig(
        title: "Membership Share",
        description: "Use membership across related apps."
    ),
    paymentChannels: [.appStore],
    ctaText: "Continue",
    restoreText: "Restore",
    showTerms: true,
    showPrivacy: true,
    termsUrl: "https://example.com/terms",
    privacyUrl: "https://example.com/privacy"
)

NexusPayment.shared.showSubscriptionPage(
    presenting: viewController,
    config: pageConfig
)
```

校验规则：

- `showTerms = true` 时 `termsUrl` 必填。
- `showPrivacy = true` 时 `privacyUrl` 必填。
- 支付方式配置错误时不自动兜底。

### 6.6 购买和恢复

```swift
let result = try await NexusPayment.shared.purchase(
    product: product,
    channel: .appStore
)
```

```swift
let restoreResult = try await NexusPayment.shared.restore(channel: .appStore)
```

权益：

```swift
let entitlements = NexusPayment.shared.getEntitlements()
```

### 6.7 App Store 订单校验

StoreKit 2 购买成功后：

- `purchaseToken` 为 `signedTransactionInfo`。
- `orderId` 为 `originalTransactionId`，对应接口 `trade_order_id`。
- 如果 uid 是 UUID 字符串，会作为 `appAccountToken` 传给 StoreKit。

SDK 会调用：

```txt
POST /pp/v7/apple/os
```

并携带：

```json
{
  "token": "signedTransactionInfo",
  "platform_product_id": "store_product_id",
  "uid": "uid",
  "issub": true,
  "trade_order_id": "originalTransactionId"
}
```

SDK 会监听 `Transaction.updates`，处理续费、退款、撤销和权益状态更新。

### 6.8 Payment 验收

- CoreUserSDK 已初始化并能取到 uid。
- `/m/v7/iap/list` 能返回商品。
- StoreKit 2 能查询到商品价格。
- 商品 ID 和 App Store Connect 商品 ID 一致。
- 购买成功后调用 `/pp/v7/apple/os`。
- 订阅页能展示商品、共享应用、协议入口和恢复购买。

## 7. CrossPromoSDK 接入

### 7.1 适用场景

接入 CrossPromoSDK 后，业务方可以使用：

- 同账号应用推荐页。
- 排除当前 App。
- 已安装 App 跳转。
- 未安装 App Store 跳转。
- Deep Link 参数解析。
- 导量归因和用户关联事件。

CrossPromoSDK 必须先初始化 CoreUserSDK；如果需要上报互导事件，建议同时初始化 GrowthAnalyticsAdSDK。

### 7.2 依赖

```swift
.product(name: "NexusCoreUser", package: "NexusSDK")
.product(name: "NexusCrossPromo", package: "NexusSDK")

// 如果需要事件上报，建议接入
.product(name: "NexusGrowthAnalyticsAd", package: "NexusSDK")
```

### 7.3 iOS Scheme 要求

iOS 无法像 Android 一样通过 packageName 直接判断 App 是否安装。业务方需要为互导目标 App 配置 URL Scheme，并在接口返回中提供：

```json
{
  "ios_scheme": "targetapp"
}
```

业务 App 还需要在 `Info.plist` 中配置 `LSApplicationQueriesSchemes`，否则 `canOpenURL` 会失败。

### 7.4 初始化

```swift
import NexusCrossPromo

NexusCrossPromo.shared.initialize(
    config: try CrossPromoConfig(
        sourceProductId: "7",
        campaign: "internal_cross_promo",
        defaultPlacement: "home"
    )
)
```

### 7.5 展示推荐页

```swift
try NexusCrossPromo.shared.showPromoPage(
    presenting: viewController,
    options: ShowPromoPageOptions(
        placement: "home",
        campaign: "internal_cross_promo",
        title: "More Apps",
        description: "Try more apps from this account."
    )
)
```

推荐页数据来源：

- SDK 调用同账号应用列表接口。
- SDK 排除当前 `sourceProductId`。
- 点击应用时优先打开已安装应用，再 fallback 到 App Store。

### 7.6 处理 Deep Link

```swift
let result = try NexusCrossPromo.shared.handleIncomingPromoLink(url.absoluteString)
```

登录成功后可尝试处理待关联归因：

```swift
let payload = try NexusCrossPromo.shared.flushPendingAttributionAfterLogin()
```

SDK 会上报：

- `cross_promo_activate`
- `cross_promo_user_link`
- `cross_promo_click`
- `cross_promo_open`
- `cross_promo_store_open`
- `cross_promo_open_failed`

### 7.7 CrossPromo 验收

- CoreUserSDK 已初始化并能取到 uid。
- 推荐页能展示同账号应用列表。
- 当前 App 已从列表中排除。
- 已安装目标 App 能直接跳转。
- 未安装目标 App 能跳转 App Store。
- Deep Link 打开目标 App 后能解析并缓存归因参数。
- 登录后能触发用户关联事件。

## 8. 推荐初始化顺序

```swift
func initializeNexusSDK() async throws {
    let coreConfig = try CoreUserConfig(
        productId: "7",
        productName: "TEST PRODUCT",
        accountName: "real-app-store-account-name",
        apiBaseUrl: "https://v8b.crypsiscollectiveinc.com",
        encrypt: true,
        encryptionKey: "32-byte-product-encryption-key",
        gt: 1
    )
    NexusCoreUser.shared.initialize(config: coreConfig)

    let user = try await NexusCoreUser.shared.silentLogin()

    let analyticsConfig = try AnalyticsConfig(productId: "7")
    NexusGrowthAnalyticsAd.shared.initialize(config: analyticsConfig)
    NexusGrowthAnalyticsAd.shared.setUser(user)

    let paymentConfig = try PaymentConfig(
        productId: "7",
        defaultChannel: .appStore,
        enabledChannels: [.appStore]
    )
    NexusPayment.shared.initialize(config: paymentConfig)

    NexusCrossPromo.shared.initialize(
        config: try CrossPromoConfig(sourceProductId: "7")
    )
}
```

只接单模块时：

- 只做登录：只接 CoreUserSDK。
- 只做事件/广告：可以只接 GrowthAnalyticsAdSDK，但事件里没有 uid/deviceId；建议同时接 CoreUserSDK。
- 只做支付：必须接 CoreUserSDK + PaymentSDK。
- 只做互导：必须接 CoreUserSDK + CrossPromoSDK；需要事件归因时再接 GrowthAnalyticsAdSDK。
