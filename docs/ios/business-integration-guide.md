# Nexus SDK iOS 业务接入说明

本文面向接入 Nexus SDK 的 iOS 业务 App。SDK 按模块提供能力，业务方可以根据需求只接入其中 1 个或多个模块。

当前版本：`0.0.8`

## 1. 模块选择

| 模块 | Swift Package Product | 适用场景 | 前置依赖 |
| --- | --- | --- | --- |
| CoreUserSDK | `NexusCoreUser` | 设备 ID、游客登录、邮箱密码登录、用户信息、邮箱绑定、登录动态配置 | 无 |
| GrowthAnalyticsAdSDK | `NexusGrowthAnalyticsAd` + 按需 Provider | BI/Firebase/AppsFlyer 事件、AdMob 广告、归因 | 建议接入 CoreUserSDK，用于 uid/deviceId |
| PaymentSDK | `NexusPayment` | 商品、三套订阅页模板、App Store 支付、订单校验、权益 | 必须先初始化 CoreUserSDK |
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

- 最低支持 iOS 15。
- Swift Package tools version 为 5.9，建议使用支持 Swift 5.9 的 Xcode 版本。

```txt
https://github.com/harden-l/nexus-sdk-ios.git
```

推荐指定版本：`0.0.8`。

Xcode 接入：

1. `File` -> `Add Package Dependencies...`
2. 输入 `https://github.com/harden-l/nexus-sdk-ios.git`
3. Dependency Rule 选择 `Exact Version`，版本填 `0.0.8`
4. 按需勾选业务 App target 需要的 products

Package.swift 接入：

```swift
.package(url: "https://github.com/harden-l/nexus-sdk-ios.git", exact: "0.0.8")
```

按需添加 target product：

```swift
.product(name: "NexusCoreUser", package: "nexus-sdk-ios")
.product(name: "NexusGrowthAnalyticsAd", package: "nexus-sdk-ios")
.product(name: "NexusPayment", package: "nexus-sdk-ios")
.product(name: "NexusCrossPromo", package: "nexus-sdk-ios")
```

如果只需要登录，只添加 `NexusCoreUser` 即可。

三方 Provider 独立发布，业务 App 只添加实际需要的包：

| 能力 | Package URL | Product |
| --- | --- | --- |
| Firebase | `https://github.com/harden-l/nexus-sdk-ios-firebase-provider.git` | `NexusGrowthAnalyticsAdFirebase` |
| AppsFlyer | `https://github.com/harden-l/nexus-sdk-ios-appsflyer-provider.git` | `NexusGrowthAnalyticsAdAppsFlyer` |
| AdMob | `https://github.com/harden-l/nexus-sdk-ios-admob-provider.git` | `NexusGrowthAnalyticsAdAdMob` |
| DataEye | 主 SDK Package | `NexusGrowthAnalyticsAdDataEye` |

所有独立 Provider 当前版本均为 `0.0.8`。在 Xcode 中添加 Provider 时：

1. 再次选择 `File` -> `Add Package Dependencies...`
2. 输入上表对应的 Provider Package URL
3. Dependency Rule 选择 `Exact Version`，版本填 `0.0.8`
4. 只勾选业务 App 实际使用的 Provider product

例如只使用 AdMob，只需要添加主 SDK 的 `NexusGrowthAnalyticsAd` 和 AdMob 包的 `NexusGrowthAnalyticsAdAdMob`。不需要添加 Firebase 或 AppsFlyer Provider。

例如同时接入 Firebase、AppsFlyer 和 AdMob：

```swift
dependencies: [
    .package(url: "https://github.com/harden-l/nexus-sdk-ios.git", exact: "0.0.8"),
    .package(url: "https://github.com/harden-l/nexus-sdk-ios-firebase-provider.git", exact: "0.0.8"),
    .package(url: "https://github.com/harden-l/nexus-sdk-ios-appsflyer-provider.git", exact: "0.0.8"),
    .package(url: "https://github.com/harden-l/nexus-sdk-ios-admob-provider.git", exact: "0.0.8")
]
```

Target 按需添加：

```swift
.product(name: "NexusGrowthAnalyticsAd", package: "nexus-sdk-ios"),
.product(name: "NexusGrowthAnalyticsAdFirebase", package: "nexus-sdk-ios-firebase-provider"),
.product(name: "NexusGrowthAnalyticsAdAppsFlyer", package: "nexus-sdk-ios-appsflyer-provider"),
.product(name: "NexusGrowthAnalyticsAdAdMob", package: "nexus-sdk-ios-admob-provider")
```

Provider 与主 SDK 使用相同版本号。主 SDK 不强制拉取 Firebase、AppsFlyer、AdMob 官方 SDK；DataEye 通过 `DataEyeBridge` 对接官方 iOS SDK。

依赖规则：

- 每个 Provider 仓库只引入对应的官方 SDK，不会因为接入一个 Provider 而解析另外两个平台 SDK。
- 业务 App 需要同时添加主 SDK product `NexusGrowthAnalyticsAd` 和实际使用的 Provider product。
- 主 SDK 与 Provider 应保持相同版本，本版本统一使用 `0.0.8`。
- DataEye Provider 位于主 SDK 中，但 DataEye 官方 iOS SDK 仍由业务 App 按官方文档接入，再通过 `DataEyeBridge` 连接。

## 4. CoreUserSDK 接入
### 4.1 初始化

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
    encryptionKey: "<CURRENT_PRODUCT_32_BYTE_AES_KEY>"
)

NexusCoreUser.shared.initialize(config: coreConfig)
```

生产示例中的 `productId`、`productName`、`accountName` 和 `encryptionKey` 必须替换为当前产品的真实配置；不要直接使用占位值。`gt` 仅在业务需要注册赠送时传入。

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

### 4.2 登录

推荐账号流程：

1. 用户未主动选择邮箱登录时，调用 `silentLogin()` 创建或恢复游客用户。
2. 游客登录成功后根据 `SDKUser.emailBound` 决定是否展示绑定入口；登录本身不会强制弹出绑定页面。
3. 绑定邮箱时必须同时设置密码。绑定成功后，邮箱成为当前 UID 的登录凭证。
4. 用户在新设备、重装 App 或其他接入同一账号体系的 App 中主动登录时，直接调用 `loginWithEmail()`，不要先创建新的游客用户。
5. 邮箱登录成功后 SDK 会自动拉取用户信息，业务方使用返回的 `SDKUser` 更新登录态。

```swift
let user = try await NexusCoreUser.shared.silentLogin()
// user.uid
// user.deviceId
// user.emailBound
// user.phoneBound
// user.balance
// 登录不会强制绑定邮箱；需要绑定时由业务主动展示入口或调用 ensureEmailBound。
```

邮箱密码登录：

```swift
let user = try await NexusCoreUser.shared.loginWithEmail(
    email: "user@example.com",
    password: "user-password"
)
```

也可以使用 completion API：

```swift
NexusCoreUser.shared.loginWithEmail(
    email: "user@example.com",
    password: "user-password"
) { result in
    // 处理登录结果
}
```

`email` 和 `password` 均为必填。登录请求会携带本地已有 uid；本地没有 uid 时发送空字符串，服务端根据邮箱密码恢复对应用户。

登录后 SDK 会拉取一次用户信息。密码只用于当前绑定或登录请求，SDK 不会持久化密码；debug 日志中的密码会被脱敏。

### 4.3 获取登录动态配置

```swift
let loginConfig = try NexusCoreUser.shared.getConfig()
let value = loginConfig["example_key"]
```

`getConfig()` 返回最近一次登录接口响应中除 `uid` 之外的动态配置字段。登录接口返回字段是不固定的，SDK 不会为这些字段定义固定模型，业务方按后台配置约定读取即可。

说明：

- 首次登录成功前调用时可能返回空字典。
- `logout()` 会先注销服务端用户，成功后清空本地登录动态配置和用户资料缓存，但保留 uid，下一次登录请求仍会携带该 uid。
- `getConfig()` 返回的是登录动态配置，不是用户资料。

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

### 4.4 用户信息和邮箱绑定

```swift
let user = try await NexusCoreUser.shared.fetchUserInfo()
// user.balance 为当前用户余额
if !user.emailBound {
    // 可展示绑定入口
}
```

`fetchUserInfo()` 返回用户资料和当前余额 `balance`，并刷新 SDK 本地用户缓存。SDK 会将用户信息接口返回的 `balance` 乘以 `100` 后写入 `SDKUser.balance`，例如接口返回 `20` 时业务方读取到 `2000`。`SDKUser.balance` 类型为 `Double`，支持小数余额。

使用 SDK 内置邮箱绑定弹窗：

```swift
NexusCoreUser.shared.ensureEmailBound(presenting: viewController) { result in
    // alreadyBound / bound / cancelled / userInfoFailed / bindFailed
}
```

弹窗会同时要求用户输入邮箱和密码。密码用于设置邮箱登录凭证，绑定成功后可调用 `loginWithEmail()` 登录；SDK 不会在本地持久化密码。

调用绑定接口前应先完成游客登录或其他类型登录，确保 SDK 中存在当前用户 UID。同一邮箱只能按服务端账号规则绑定；邮箱已被占用、密码不符合规则等情况会通过失败结果返回，业务方应向用户展示可理解的错误提示。

直接调用绑定接口：

```swift
let result = try await NexusCoreUser.shared.bindEmail(
    "user@example.com",
    password: "user-password"
)
```

### 4.5 扣除金币

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

- SDK 会自动携带当前 uid；本地无用户时会先静默登录。
- `cost` 必须大于 `0`，金币数使用 `Double`，避免小数被截断。
- 该接口按 `CoreUserConfig.encrypt` 的通用策略加密请求和解密响应，不走登录接口免加密规则。
- `ConsumeChatCoinsResult` 中的 `cost`、`beforeCoins`、`afterCoins` 和 `balance` 保持扣金币接口返回的原始单位，不执行 `×100`。
- 扣除成功后 SDK 不直接修改本地 `SDKUser.balance` 缓存；业务方如需刷新余额，调用 `fetchUserInfo()`。

## 5. GrowthAnalyticsAdSDK 接入
### 5.1 iOS 工程配置

Firebase、AppsFlyer 和 DataEye 可以独立启用，也可以同时启用。iOS 端是否真实上报以传给 `NexusGrowthAnalyticsAd.shared.initialize(..., providers:)` 的 Provider 实例为准；只设置 `AnalyticsConfig.enableFirebase`、`enableAppsflyer` 或 `enableBI`，但没有传入对应真实 Provider，不会完成平台接入。

| 平台 | Package Product | 宿主 App 必须配置 | 初始化对象 |
| --- | --- | --- | --- |
| Firebase | `NexusGrowthAnalyticsAdFirebase` | 与 Bundle ID 匹配的 `GoogleService-Info.plist` | `FirebaseAnalyticsProvider` |
| AppsFlyer | `NexusGrowthAnalyticsAdAppsFlyer` | Dev Key、Apple App ID；归因场景配置 Universal Link/URL Scheme | `AppsFlyerAnalyticsProvider` |
| DataEye | `NexusGrowthAnalyticsAdDataEye` | 官方 DataEye iOS SDK、DataEye App ID、可选 Server URL、业务方 `DataEyeBridge` | `DataEyeAnalyticsProvider` |

Firebase：

- 将 Firebase Console 下载的真实 `GoogleService-Info.plist` 加入业务 App target。
- `BUNDLE_ID` 必须和业务 App 的 Bundle Identifier 一致。
- SDK 不内置 `GoogleService-Info.plist`。
- `FirebaseAnalyticsProvider()` 默认在 Firebase 尚未初始化时调用 `FirebaseApp.configure()`；如果业务 App 已自行初始化 Firebase，使用 `FirebaseAnalyticsProvider(configureIfNeeded: false)`。

AppsFlyer：

- 配置 Dev Key 和 Apple App ID。
- `appleAppID` 传 App Store 的纯数字应用 ID，不要传 Bundle ID。
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
- `NoopDataEyeBridge` 只用于开发测试，不会向 DataEye 发送数据，生产环境不得使用。

最小 Bridge 结构如下，方法体需要调用业务 App 实际接入版本的 DataEye 官方 API：

```swift
import NexusGrowthAnalyticsAdDataEye

final class OfficialDataEyeBridge: DataEyeBridge, @unchecked Sendable {
    func initialize(appId: String, serverUrl: String?) {
        // 调用 DataEye 官方 SDK 初始化 API
    }

    func setUserId(_ uid: String?) {
        // 调用 DataEye 登录或设置用户 ID API
    }

    func setUserProperties(_ properties: [String: Any?]) {
        // 按当前 DataEye SDK 能力设置或缓存用户属性
    }

    func track(eventName: String, parameters: [String: Any]) {
        // 调用 DataEye 官方事件上报 API
    }

    func flush() {
        // DataEye SDK 提供 flush API 时调用；否则可留空
    }
}
```

### 5.2 初始化

```swift
import NexusGrowthAnalyticsAd
import NexusGrowthAnalyticsAdAdMob
import NexusGrowthAnalyticsAdAppsFlyer
import NexusGrowthAnalyticsAdDataEye
import NexusGrowthAnalyticsAdFirebase

let analyticsConfig = try AnalyticsConfig(
    productId: "7",
    enableBI: true,
    enableFirebase: true,
    enableAppsflyer: true,
    enableAdMob: true,
    debug: true
)

let firebase = FirebaseAnalyticsProvider()
let appsFlyer = AppsFlyerAnalyticsProvider(
    devKey: "<APPSFLYER_DEV_KEY>",
    appleAppID: "<NUMERIC_APPLE_APP_ID>",
    startImmediately: true,
    isDebug: false
)
let dataEye = DataEyeAnalyticsProvider(
    appId: "<DATAEYE_APP_ID>",
    serverUrl: nil,
    bridge: OfficialDataEyeBridge()
)
let adMob = AdMobAdProvider(
    rootViewControllerProvider: { rootViewController },
    revenueReporter: { payload in
        _ = try? NexusGrowthAnalyticsAd.shared.reportAdRevenue(payload)
    }
)

NexusGrowthAnalyticsAd.shared.initialize(
    config: analyticsConfig,
    providers: [firebase, appsFlyer, dataEye],
    adProvider: adMob
)
```

需要 AppsFlyer OneLink 或 Deep Link 归因时，将系统回调转发给同一个 `AppsFlyerAnalyticsProvider` 实例：

```swift
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
) -> Bool {
    appsFlyer.handleOpen(url: url, options: options)
    return true
}

func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    appsFlyer.continueUserActivity(userActivity) { objects in
        restorationHandler(objects?.compactMap { $0 as? UIUserActivityRestoring })
    }
}
```

配置检查：

- 只启用 Firebase：只创建并传入 `FirebaseAnalyticsProvider`，同时将 `enableFirebase = true`、`enableBI = false`、`enableAppsflyer = false`。
- 只启用 AppsFlyer：只创建并传入 `AppsFlyerAnalyticsProvider`，同时将 `enableAppsflyer = true`，其余事件平台开关设为 `false`。
- 只启用 DataEye：只创建并传入 `DataEyeAnalyticsProvider`，同时将 `enableBI = true`，其余事件平台开关设为 `false`。
- 同时启用：把三个真实 Provider 都加入 `providers`；不要加入未配置的平台，也不要在生产环境使用 Mock/Noop Provider。
- Provider 构造参数中的 AppsFlyer Dev Key、Apple App ID、DataEye App ID 和 Server URL 是实际生效配置；`AnalyticsConfig` 中同名字段不会替代 Provider 构造参数。
- `debug = true` 只控制 Nexus SDK 日志；AppsFlyer 使用 `isDebug`，Firebase/DataEye 调试日志按各自官方 SDK 配置。

如果已接入 CoreUserSDK：

```swift
let user = try await NexusCoreUser.shared.silentLogin()
NexusGrowthAnalyticsAd.shared.setUser(user)
```

### 5.3 事件和用户属性

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

广告收益由 AdMob Paid Event 触发 `reportAdRevenue()`。SDK 内部事件名是 `ad_revenue`，发送到 Firebase、AppsFlyer 和 DataEye 时均映射为 `ad_imp`。Firebase / AppsFlyer 当前只发送该事件；BI(DataEye) 继续按 Nexus/BI 事件模型处理其它 BI 事件。

### 5.4 Deep Link 和归因

```swift
let result = NexusGrowthAnalyticsAd.shared.handleDeepLink(url.absoluteString)

let installSource = NexusGrowthAnalyticsAd.shared.getInstallSource()
let lastDeepLink = NexusGrowthAnalyticsAd.shared.getLastDeepLink()
```

### 5.5 AdMob 广告

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

全屏广告按 `format + adUnitId` 管理缓存。重复调用 `loadAd()` 时，如果已有缓存或正在加载，SDK 不会再次发起广告请求；并发传入的加载回调会在本次加载完成后统一返回。

`showAd()` 会先检查缓存：有缓存时立即展示；无缓存时自动开始加载，本次通过 `onFailed` 返回广告未就绪，业务方可在后续时机再次调用 `showAd()`。开屏、插屏、激励和激励插屏广告展示成功或展示失败后，SDK 会自动预加载下一条。同一广告正在展示时不会重复展示。频控次数仅在收到实际展示回调后累计。

## 6. PaymentSDK 接入
### 6.1 初始化

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

### 6.2 订阅页

```swift
let pageConfig = try SubscriptionPageConfig(
    templateId: SubscriptionPageTemplateId.aurora.rawValue,
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
    restoreText: "Restore"
)

NexusPayment.shared.showSubscriptionPage(
    presenting: viewController,
    config: pageConfig
)
```

`templateId` 用于切换 SDK 内置页面模板：

| 模板 ID | Swift 枚举值 | 模板说明 |
| --- | --- | --- |
| `aurora` | `SubscriptionPageTemplateId.aurora.rawValue` | 明亮现代风格，突出当前权益、共享应用和购买选项；默认模板。 |
| `midnight` | `SubscriptionPageTemplateId.midnight.rawValue` | 深色沉浸风格，适合会员、内容和创作类产品。 |
| `minimal` | `SubscriptionPageTemplateId.minimal.rawValue` | 清爽紧凑风格，适合工具类应用或商品较多的页面。 |

未传、传空值或传入未知模板 ID 时会回退到 `aurora`。Android 与 iOS 使用相同模板 ID，业务方可直接由远程配置控制两端样式。

切换模板只需要修改 `templateId`，其余页面配置和调用方式不变。

打开订阅页后，SDK 会自动完成以下流程，业务方不需要提前获取商品或手动调用购买接口：

- 从 Nexus 后台 `/m/v6/iap/list` 获取商品的 `market_product_id`、`product_type` 和 `coins_granted`；`Product.coinsGranted` 类型为 `Double?`，保留接口原始值并支持小数赠币。
- 页面按 `product_type` 自动分组：`2` 展示为订阅方案，`1` 展示为积分包或一次性内购。
- 订阅页展示金币时统一使用 `coins_granted × 100`，例如接口返回 `20` 时页面展示 `2000`；购买判断和订单处理仍使用接口原始值。
- 从 StoreKit 2 获取价格、币种、本地化价格、订阅周期和试用信息，并与后台商品合并。
- 获取关联应用并展示 Membership Share 区域。
- 用户点击 CTA 后发起购买，购买成功后完成服务端订单校验和权益处理。
- 页面开启恢复入口时，由页面执行恢复流程。
- 权益和交付记录按 `productId + uid` 持久化，重新初始化 SDK 或切换用户后仍能正确隔离和恢复。
- 服务条款和隐私协议默认展示，分别使用 `https://www.crypsiscollectiveinc.com/terms.html` 和 `https://www.crypsiscollectiveinc.com/privacy.html`；点击后由系统默认浏览器打开。

校验规则：

- `showTerms`、`showPrivacy` 默认均为 `true`，业务方可显式设为 `false` 隐藏对应入口。
- `termsUrl`、`privacyUrl` 已提供上述默认值；业务方可以覆盖，但入口开启时不能传空字符串。
- 支付方式配置错误时不自动兜底。

### 6.3 订单和权益自动处理

StoreKit 2 购买成功后：

- `purchaseToken` 为 `signedTransactionInfo`。
- `orderId` 为 `originalTransactionId`，对应接口 `trade_order_id`。
- 如果 uid 是 UUID 字符串，会作为 `appAccountToken` 传给 StoreKit。

SDK 会自动完成服务端订单校验，并监听 `Transaction.updates`，处理续费、退款、撤销和权益状态更新。服务端校验继续使用 `originalTransactionId`，本地交付去重使用每次续订唯一的 StoreKit `transaction.id`，因此同一订阅的后续续订不会被误判为重复订单。

## 7. CrossPromoSDK 接入
### 7.1 iOS Scheme 要求

iOS 无法像 Android 一样通过 packageName 直接判断 App 是否安装。业务方需要为互导目标 App 配置 URL Scheme，并在接口返回中提供：

```json
{
  "ios_scheme": "targetapp"
}
```

业务 App 还需要在 `Info.plist` 中配置 `LSApplicationQueriesSchemes`，否则 `canOpenURL` 会失败。

### 7.2 初始化

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

### 7.3 展示推荐页

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

### 7.4 处理 Deep Link

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

## 8. 推荐初始化顺序

```swift
func initializeNexusSDK() async throws {
    let coreConfig = try CoreUserConfig(
        productId: "7",
        productName: "TEST PRODUCT",
        accountName: "real-app-store-account-name",
        apiBaseUrl: "https://v8b.crypsiscollectiveinc.com",
        encrypt: true,
        encryptionKey: "<CURRENT_PRODUCT_32_BYTE_AES_KEY>"
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
