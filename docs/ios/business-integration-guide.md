# Nexus SDK iOS 业务接入说明（共享账号 API v1）

本文面向接入 Nexus SDK 的 iOS 业务 App。SDK 按模块提供能力，业务方可以根据需求只接入其中 1 个或多个模块。

本文对应 iOS `0.1.0`，适用新版共享账号 `/api/v1` 协议，需要已开通 v1 路由的服务。不要与 `0.0.x` 模块混用。Provider 兼容版本要求见第 3 节。

## 1. 模块选择

| 模块 | Swift Package Product | 适用场景 | 前置依赖 |
| --- | --- | --- | --- |
| CoreUserSDK | `NexusCoreUser` | 设备 ID、游客/邮箱/手机号登录、会话、绑定、余额、扣费、周积分 | 无 |
| GrowthAnalyticsAdSDK | `NexusGrowthAnalyticsAd` + 按需 Provider | BI/Firebase/AppsFlyer 事件、AdMob 广告、归因 | 建议接入 CoreUserSDK，用于 uid/deviceId |
| PaymentSDK | `NexusPayment` | 商品、三套订阅页模板、App Store 支付、订单校验、权益 | 必须先初始化 CoreUserSDK |
| CrossPromoSDK | `NexusCrossPromo` | 应用互导推荐页、Deep Link、导量归因 | 必须先初始化 CoreUserSDK；如需事件上报，建议接入 GrowthAnalyticsAdSDK |

## 2. 通用准备

请按实际接入模块向后台或 SDK 提供方确认配置：

| 配置 | 用途 |
| --- | --- |
| `productId` | 后台产品 ID；明文模式使用请求头 `ProductId`。 |
| `productName` | 产品名称；加密模式使用请求头 `Product`，必须与后台匹配。 |
| `accountName` | 后台企业账号名称，用于查询关联应用；默认 `test` 仅供测试，上线前替换为真实值。 |
| `apiBaseUrl` | 已开通新版接口的服务域名，不带 `/api/v1`；SDK 自动拼接路径。 |
| `encryptionKey` | 加密时必填；原始字符串的 UTF-8 编码须为 16、24 或 32 字节，不按十六进制解码。 |
| AdMob App ID / Ad Unit ID | 仅广告模块需要。 |
| Firebase 配置 | 仅 Firebase 事件需要，业务 App 需要按 Firebase 官方方式接入真实配置。 |
| AppsFlyer Dev Key / Apple App ID | 仅 AppsFlyer 事件和归因需要。 |
| DataEye App ID / Server URL | 仅 BI(DataEye) 事件需要。 |
| `gt` | 可选注册赠送梯度：1/2/3 分别赠送原始金币 0.1/0.2/0.3，对应显示 10/20/30。 |
| App Store 商品 ID | 后台 `market_product_id` 与 App Store Connect 商品 ID 一致，并完成价格、订阅及服务端商店通知配置。 |
| URL Scheme / Universal Link | 仅 CrossPromo 或归因 Deep Link 需要。 |

测试服务：`https://aishare.stoahayaamhsothy.com`，产品 ID `7`，产品名称 `TEST PRODUCT`，测试密钥 `1b8df48c1fa64ce28a2e8133dffe600c`。这些参数仅用于该测试产品，不是生产配置。生产域名、产品、企业账号名和密钥由后台另行提供，不沿用旧版域名推断。

通信与调用约定：

- `CoreUserConfig.encrypt` 默认是 `true`。
- `encrypt = true` 时必须传 `encryptionKey`。
- AES-CBC，IV 为密钥前 16 字节，使用 AES 适用的 PKCS7 填充及标准 Base64。
- 登录请求体始终为明文 JSON；`encrypt=true` 时登录响应仍需解密，SDK 自动处理。务必使用 HTTPS。
- 其他已集成接口按 `encrypt` 配置加密请求并解密响应；SDK 兼容服务端明文错误对象。
- 除登录外，SDK 内置接口自动携带 Bearer Token，不在请求体传 UID。业务自有认证请求可通过 `getToken()` 获取 Token。
- `initialize(...)` 只初始化配置和本地会话，不自动登录、不获取远程开关。
- 网络 API 使用 async/await；也提供部分 completion 重载。普通 completion 不保证主线程，更新 UI 时切回 `MainActor`，页面展示由主线程发起。
- Firebase、AppsFlyer、AdMob、DataEye 的平台配置属于宿主业务 App，SDK 不写死这些配置。

## 3. Swift Package 依赖

当前 iOS SDK 通过 Swift Package Manager 提供：

- 最低支持 iOS 15。
- Swift Package tools version 为 5.9，建议使用支持 Swift 5.9 的 Xcode 版本。

```txt
https://github.com/harden-l/nexus-sdk-ios.git
```

主 SDK 版本：`0.1.0`。

Xcode 接入：

1. `File` -> `Add Package Dependencies...`
2. 输入 `https://github.com/harden-l/nexus-sdk-ios.git`
3. Dependency Rule 选择 `Exact Version`，版本填 `0.1.0`
4. 按需勾选业务 App target 需要的 products

Package.swift 接入：

```swift
.package(url: "https://github.com/harden-l/nexus-sdk-ios.git", exact: "0.1.0")
```

按需添加 target product：

```swift
.product(name: "NexusCoreUser", package: "nexus-sdk-ios")
.product(name: "NexusGrowthAnalyticsAd", package: "nexus-sdk-ios")
.product(name: "NexusPayment", package: "nexus-sdk-ios")
.product(name: "NexusCrossPromo", package: "nexus-sdk-ios")
```

如果只需要登录，只添加 `NexusCoreUser` 即可。

Firebase、AppsFlyer、AdMob Provider 独立发布，业务 App 只添加实际需要的包；DataEye bridge product 已随主 SDK 提供：

| 能力 | Package URL | Product |
| --- | --- | --- |
| Firebase | `https://github.com/harden-l/nexus-sdk-ios-firebase-provider.git` | `NexusGrowthAnalyticsAdFirebase` |
| AppsFlyer | `https://github.com/harden-l/nexus-sdk-ios-appsflyer-provider.git` | `NexusGrowthAnalyticsAdAppsFlyer` |
| AdMob | `https://github.com/harden-l/nexus-sdk-ios-admob-provider.git` | `NexusGrowthAnalyticsAdAdMob` |
| DataEye | 主 SDK `https://github.com/harden-l/nexus-sdk-ios.git`，另由宿主接入官方 DataEye SDK | `NexusGrowthAnalyticsAdDataEye` |

Firebase、AppsFlyer、AdMob 使用各自的 `0.1.0` Provider，依赖的主 SDK 版本为 `0.1.0`。旧 `0.0.16` Provider 精确依赖主 SDK `0.0.16`，不能混用；升级时同时修改所使用的 Provider 版本。

待兼容版本发布并验证后，在 Xcode 中添加需要的 Provider：

1. 再次选择 `File` -> `Add Package Dependencies...`
2. 输入上表对应的 Provider Package URL
3. Dependency Rule 选择 `Exact Version`，版本填 `0.1.0`
4. 只勾选业务 App 实际使用的 Provider product

例如只使用 AdMob，只需要添加主 SDK 的 `NexusGrowthAnalyticsAd` 和 AdMob 包的 `NexusGrowthAnalyticsAdAdMob`。不需要添加 Firebase 或 AppsFlyer Provider。

例如同时接入 Firebase、AppsFlyer 和 AdMob：

```swift
dependencies: [
    .package(url: "https://github.com/harden-l/nexus-sdk-ios.git", exact: "0.1.0"),
    .package(url: "https://github.com/harden-l/nexus-sdk-ios-firebase-provider.git", exact: "0.1.0"),
    .package(url: "https://github.com/harden-l/nexus-sdk-ios-appsflyer-provider.git", exact: "0.1.0"),
    .package(url: "https://github.com/harden-l/nexus-sdk-ios-admob-provider.git", exact: "0.1.0")
]
```

Target 按需添加：

```swift
.product(name: "NexusGrowthAnalyticsAd", package: "nexus-sdk-ios"),
.product(name: "NexusGrowthAnalyticsAdFirebase", package: "nexus-sdk-ios-firebase-provider"),
.product(name: "NexusGrowthAnalyticsAdAppsFlyer", package: "nexus-sdk-ios-appsflyer-provider"),
.product(name: "NexusGrowthAnalyticsAdAdMob", package: "nexus-sdk-ios-admob-provider")
```

使用 DataEye 时，target 从主 SDK 添加：

```swift
.product(name: "NexusGrowthAnalyticsAdDataEye", package: "nexus-sdk-ios")
```

该 product 提供 `DataEyeAnalyticsProvider` 和 `DataEyeBridge`，不包含官方 DataEye SDK。宿主按第 5 节接入官方 SDK 并实现 bridge。远程 DataEye Provider 仓库已确认返回 `RepoNotFound`，本指南不依赖该仓库，也不将其标为已发布；随主 SDK 提供的 bridge 仍可使用。

`NexusPayment.shared.initialize(...)` 不会初始化 `NexusGrowthAnalyticsAd`。宿主 App 已主动初始化 Growth 时，PaymentSDK 会复用它上报支付和订阅页事件；未初始化时跳过这些事件上报，不影响商品加载、订阅页展示和购买流程。

依赖规则：

- Firebase、AppsFlyer、AdMob 每个独立 Provider 只引入对应的官方 SDK，不会因为接入一个 Provider 而解析另外两个平台 SDK。
- 业务 App 需要同时添加主 SDK product `NexusGrowthAnalyticsAd` 和实际使用的 Provider product。
- 主 SDK 的模块依赖由 SPM 自动解析；Payment、CrossPromo 依赖 CoreUser 和 Growth，但无需为了支付或推荐页面而启用统计平台。
- 主 SDK 不强制拉取 Firebase、AppsFlyer、AdMob 或 DataEye 官方 SDK；只选择当前业务需要的 Provider。

## 4. CoreUserSDK 接入

### 4.1 初始化

以下仅为测试产品配置；不需要注册赠送时不传 `gt`：

```swift
import NexusCoreUser

let coreConfig = try CoreUserConfig(
    productId: "7",
    productName: "TEST PRODUCT",
    accountName: "test",
    apiBaseUrl: "https://aishare.stoahayaamhsothy.com",
    encrypt: true,
    encryptionKey: "1b8df48c1fa64ce28a2e8133dffe600c",
    debug: false,
    gt: 1
)

NexusCoreUser.shared.initialize(config: coreConfig)
```

生产接入必须将 `apiBaseUrl`、`productId`、`productName`、`accountName` 和 `encryptionKey` 全部替换为后台提供的正式配置，不使用上述测试参数。

`CoreUserConfig` 字段说明：

| 字段 | 是否必填 | 说明 |
| --- | --- | --- |
| `appId` | 否 | 兼容保留字段，默认空字符串；不替代 productId，也不用于共享登录态。 |
| `productId` | 是 | 后台产品 ID；明文模式请求头 `ProductId`。 |
| `productName` | 是 | 产品名称；加密模式请求头 `Product`。 |
| `accountName` | 否 | 默认 `test`，仅供测试；关联应用查询使用的后台企业账号名，生产必须替换。 |
| `apiBaseUrl` | 是 | 已开通 v1 的服务域名，不含 `/api/v1`。 |
| `version` | 否 | App 版本号；默认读取 `CFBundleShortVersionString`，读取失败时为 `1.0.0`。 |
| `country` | 否 | 国家/地区；不传时 SDK 自动使用设备 Locale。 |
| `language` | 否 | 语言；不传时 SDK 自动使用设备 Locale。 |
| `encrypt` | 否 | 默认 `true`，控制请求加密与响应解密；仅登录请求体例外，登录响应仍遵循此配置。 |
| `encryptionKey` | `encrypt=true` 时必填 | 当前产品 AES key，UTF-8 编码为 16/24/32 字节。 |
| `debug` | 否 | 是否输出 SDK debug log，默认 `false`。 |
| `gt` | 否 | 1/2/3 对应原始金币 0.1/0.2/0.3，显示 10/20/30；其他值不赠送，不传时登录请求不携带。 |

`gt` 只在游客首次创建用户且首次创建钱包时生效；已有钱包、重复登录、邮箱/手机号登录不补赠。

SDK 不提供动态开关获取 API；旧 `fetchSwitchConfig()`、`getSwitchConfig()` 已移除。业务远程配置由宿主自行管理，`getSdkConfig()` 仅返回初始化参数。

### 4.2 登录

推荐账号流程：

1. 已有有效会话时复用；首次使用可通过 `silentLogin()` 建立游客会话。
2. 有账号的用户直接调用 `loginWithEmail()` 或 `loginWithPhone()`，无需先创建游客。
3. 登录不会强制绑定；用户资料同步后，根据 `emailBound` / `phoneBound` 展示绑定入口。建议首次绑定同时设置密码。
4. 游客会话到期后允许重新游客登录；邮箱/手机号会话到期或收到 401 后，须重新输入账号密码，**不会自动降级为游客**。
5. 登录成功后 SDK 尝试获取用户资料。若 `userInfoSynced == false`，表示登录已成功但资料未同步；稍后调用 `fetchUserInfo()`，不要按默认字段判断会员、余额或绑定状态。

```swift
let user = try await NexusCoreUser.shared.silentLogin()
// user.uid / user.deviceId / user.userInfoSynced
// 需要绑定时由业务主动调用 ensureEmailBound。
```

邮箱密码登录：

```swift
let user = try await NexusCoreUser.shared.loginWithEmail(
    email: "user@example.com",
    password: "user-password"
)
```

手机号登录：

```swift
let user = try await NexusCoreUser.shared.loginWithPhone(
    phonePrefix: "86",
    phone: "<PHONE_NUMBER>",
    password: "user-password"
)
```

也可以使用 completion API，更新 UI 时切回主线程：

```swift
NexusCoreUser.shared.loginWithEmail(
    email: "user@example.com",
    password: "user-password"
) { result in
    // 处理登录结果
}
```

邮箱/手机号登录只验证已绑定且已设密的账号，不自动注册。邮箱会去除首尾空白并转小写；密码必须为 **8～72 字节、ASCII 33～126 可见字符**，空格不合法，不要 trim 密码后提交。SDK 不持久化密码。当前协议没有验证码、修改密码或找回密码接口。

会话与本地用户：

```swift
let session: SessionInfo? = try NexusCoreUser.shared.getSessionInfo()
let cachedUser = try NexusCoreUser.shared.getCurrentUser()
// session.uid / session.loginType / session.expiresAt / session.isValid
// expiresAt 为 Unix 秒；SessionInfo 不包含 Token 原文。
// cachedUser 为当前会话的本地快照，最新资料需 fetchUserInfo()。
```

Token 及会话保存在设备 Keychain，按 `apiBaseUrl + productId + appGroupSuiteName` 隔离；用户资料缓存与会话作用域一致。指定 App Group 不会自动授予跨 App Keychain 共享权限。只有 UID 的旧缓存不构成有效登录，升级后应重新建立会话。并发游客登录会合并；不要反复调用邮箱/手机号登录作健康检查，同产品同用户再次登录会替换旧 Token。

获取 Token，供业务自行调用同一账号服务的认证接口：

```swift
if let token = try NexusCoreUser.shared.getToken() {
    let authorization = "Bearer \(token)"
    // 将 authorization 用于同一服务、当前产品请求的 Authorization 头。
} else {
    // 没有本地有效会话，展示合适的登录入口。
}
```

`getToken()` 必须在初始化后调用，未初始化抛 `CoreUserError.notInitialized`；Keychain 读取失败也会抛错。该方法可同步读取，不发网络请求，不自动登录或刷新 Token。返回无 `Bearer ` 前缀的原始字符串；未登录、本地到期、注销、清理本地会话或 SDK 已处理 401 后返回 `nil`。

非空只表示本地未到期，不保证服务端尚未吊销。业务自有请求的 401 不会自动通知 SDK：应停止使用旧凭证，按明确的账号重登流程处理，不能清理后立即调用游客登录作为兜底。Token 按请求读取，不长期缓存、打印或上报，也不发送到无关域名。

业务错误通过 `CoreUserError` 返回：

```swift
do {
    let user = try await NexusCoreUser.shared.fetchUserInfo()
    // 使用 user 刷新业务界面。
} catch let error as CoreUserError {
    if error.businessCode == 401 {
        // 会话失效，提示重新登录；不自动重放扣费、领取、绑定或注销。
    }
    // error.traceId 可用于向后台定位问题；同时处理其他失败分支。
} catch {
    // 网络失败等其他错误。
}
```

HTTP 200 不代表业务成功；SDK 同时检查业务 `code`。业务或 HTTP 401 会使对应会话失效。账号会话失效后调用 `silentLogin()` 也会返回需要账号重登的 401。`sessionChanged` 表示操作期间切换了会话，应丢弃旧结果；SDK 不自动重放有副作用的请求。

### 4.3 获取用户信息

```swift
import Foundation

let user = try await NexusCoreUser.shared.fetchUserInfo()
let balanceText = NSDecimalNumber(decimal: user.balanceDecimal).stringValue
if user.userInfoSynced && !user.emailBound {
    // 可展示绑定入口
}
```

`fetchUserInfo()` 调用 `/api/v1/account/info` 并更新本地缓存：

| 字段 | 含义 |
| --- | --- |
| `uid` / `deviceId` | 服务端用户 ID / SDK 设备标识 |
| `email` / `emailBound` | 邮箱及绑定状态 |
| `phonePrefix` / `phone` / `phoneBound` | 手机区号、号码及绑定状态 |
| `balanceDecimal` | 精确 Decimal 展示余额，已为服务端原始余额 ×100，优先使用 |
| `balance` | Double 兼容字段，同样已 ×100 |
| `isVip` / `vipExpiredAt` | 当前产品会员状态 / 到期 Unix 秒 |
| `userInfoSynced` | 是否成功同步资料；false 时不根据默认值判断权益 |

**用户余额不要再次乘以 100。** 服务端返回 `20` 时 SDK 返回 `2000`；返回 `0.099` 时 SDK 返回 `9.9`。查询失败不能视为余额归零或会员失效。共享钱包依赖后台企业配置，会员仍按产品管理。

### 4.4 绑定邮箱

使用 SDK 内置邮箱绑定弹窗：

```swift
NexusCoreUser.shared.ensureEmailBound(presenting: viewController) { result in
    // result.status: alreadyBound / bound / cancelled / userInfoFailed / bindFailed
}
```

弹窗提供邮箱和密码输入框，提示用户设置后续登录密码；空密码仍按“不设密”处理。业务应引导首次绑定同时设密，设置成功后才能调用 `loginWithEmail()` 登录；SDK 不会在本地持久化密码。

调用绑定接口前应确认当前登录账号。绑定不是邮箱或手机号所有权验证，也不代表跨产品会员共享。身份已占用、密码不符合规则等失败应展示清晰提示；绑定超时先查询用户资料确认结果，不自动重复提交。

直接调用绑定接口：

```swift
let result = try await NexusCoreUser.shared.bindEmail(
    "user@example.com",
    password: "user-password"
)
```

API 的 `password` 可省略或传 `nil`（空字符串也表示不设密），但**建议首次绑定同时设置密码**；未设密不能进行邮箱/手机号密码登录。不要传空白字符串代替省略。已有密码时仅校验一致性，不会修改；不能重复绑定相同身份来补设密码。

手机号绑定使用 `bindPhone(phonePrefix:phone:password:)`，密码同样可选；也可使用 `bindAccount(_:)` 和 `BindAccountParams`。

### 4.5 扣除聊天金币

`cost` 使用服务端原始金币单位，精确计费优先使用 Decimal。推荐业务方为每笔账单生成 UUID，**发送前持久保存键、金额和备注；显式重试必须复用同一组值**，不能生成新键或修改金额、备注：

```swift
import Foundation

// 创建账单时生成一次；发送前将以下三个值一起保存到业务账单。
let billKey = UUID().uuidString
let cost = Decimal(string: "0.025")!
let remark = "chat billing"
do {
    let consume = try await NexusCoreUser.shared.consumeChatCoins(
        cost: cost,
        remark: remark,
        idempotencyKey: billKey
    )
    // consume.idempotencyKey 为本次实际使用的键，保存到对应账单。
    // consume.costDecimal 为 0.025 原始金币，对应显示 2.5。
    // 扣费已确认；余额刷新应单独处理，刷新失败不能当作扣费失败。
} catch let error as ConsumeChatCoinsError {
    let retryKey = error.idempotencyKey
    let businessCode = (error.underlyingError as? CoreUserError)?.businessCode
    // 将 retryKey 与原 cost、remark 一起保存；不在 catch 中自动重试。
    if businessCode == 401 {
        // 先恢复正确账号的登录态；不要降级为游客或自动重放账单。
    }
} catch {
    // 参数校验等其他失败；处理错误，不自动新建账单重试。
}
```

说明：

- 接口为 `/api/v1/coins/consume`，使用当前 Token；不要在业务请求体手动传 UID。
- `cost > 0`。Double 重载兼容保留，新业务使用 Decimal，避免先经 Double 损失精度。
- `idempotencyKey` 为 1～128 位 ASCII 字母、数字、`-`、`_`。不传时 SDK 默认生成 UUID；成功的 `ConsumeChatCoinsResult.idempotencyKey: String` 返回实际使用的键。
- 参数校验通过后的网络、API、响应解码等错误包装为 `ConsumeChatCoinsError`，包含 `idempotencyKey: String` 和 `underlyingError: Error`。业务码从 `(error.underlyingError as? CoreUserError)?.businessCode` 读取，不能将包装错误直接当作 CoreUserError；底层网络或解码错误不一定有业务码。
- 即使首次省略键，失败后也能从 `ConsumeChatCoinsError.idempotencyKey` 取回自动生成的键。调用方必须保存该键及原金额、备注，显式重试时传回 `idempotencyKey`，不能再次省略。推荐预先生成并持久保存 UUID，避免应用中断导致未收到结果或错误而丢失键。
- 参数校验错误不属于上述包装范围；业务仍须处理普通错误分支。completion 调用的失败结果也应先识别 `ConsumeChatCoinsError`。
- `remark` 可省略，最大 255 字符；同键重试的金额和备注须一致。
- `costDecimal / beforeCoinsDecimal / afterCoinsDecimal / balanceDecimal` 均为原始金币单位；对应 Double 兼容字段也不做 ×100。
- 成功不会直接覆盖 `SDKUser.balanceDecimal` 缓存；刷新展示余额请调用 `fetchUserInfo()`。
- 网络超时不等于未扣款；同键重试返回原账单结果，不代表当前余额。SDK 不自动重放扣费请求。

用户明确重试原账单时，从持久账单恢复原 `billKey`、`cost`、`remark`，再次调用 `consumeChatCoins(cost: cost, remark: remark, idempotencyKey: billKey)`。若键来自包装错误，则恢复其 `idempotencyKey` 作为 `billKey`。不要重新执行上例创建 UUID 的步骤；收到成功结果后单独调用 `fetchUserInfo()` 更新展示余额。

### 4.6 用户注销

```swift
NexusCoreUser.shared.logout { result in
    switch result {
    case .success:
        // 服务端当前产品用户注销成功，本地 UID、Token、会话和用户资料已清理。
        break
    case .failure(let error):
        // 处理失败，不提前显示注销成功；401 会使旧会话失效。
        break
    }
}
```

`logout()` 调用 `POST /api/v1/account/deregister`，是**服务端注销当前产品用户**，不是仅本地退出。成功后清除用于恢复会话的 UID 和 Token，保留设备标识；不会因此清空共享钱包或注销其他产品用户。重复注销可能返回 401，不能当作幂等成功。

仅本地退出或切换账号时，使用 `try NexusCoreUser.shared.clearLocalSession()`。它清理本地会话和资料，不注销服务端用户、不撤销服务端 Token；随后应明确展示账号选择/登录入口，不立即游客登录来替代用户选择。

### 4.7 查询和领取订阅周积分

使用内置订阅页时由页面处理；自定义入口可直接使用 CoreUser，无需初始化 Payment：

```swift
let info = try await NexusCoreUser.shared.getWeeklyPointsInfo()
let displayPoints = info.weeklyPointsDecimal * Decimal(100)
if info.canClaim {
    // 展示 displayPoints，等待用户点击领取后才调用 claimWeeklyPoints()。
} else {
    // 根据 info.cannotClaimReason 展示当前状态。
}
```

| WeeklyPointsInfo 字段 | 含义 |
| --- | --- |
| `isVip` | 当前产品是否有有效会员 |
| `marketProductId` | 服务端所选订阅 SKU；无有效订阅时可能为空 |
| `weeklyPointsDecimal` | Decimal 原始金币领取额度；显示时仅 ×100 一次 |
| `canClaim` | 当前领取资格，不由商品配置或 isVip 单独决定 |
| `cannotClaimReason` | 可领时为空；其他状态见下表 |
| `weeklyPoints` | 已弃用的 Int 兼容字段，小数会截断，新接入不使用 |

| 不可领取原因 | 业务处理 |
| --- | --- |
| `no_valid_subscription` | 引导订阅，不调用领取 |
| `already_claimed` | 显示本周已领取 |
| `product_not_configured` | 当前订阅未配置周积分，不展示可领取操作 |

这些状态都是查询成功的业务结果。查询和领取分别调用 `/api/v1/weekly-points/info`、`/api/v1/weekly-points/claim`，请求严格为单个 `{}`，不能带 SKU、UID 或任何其他字段。使用**无参数**方法：

```swift
// 仅在用户点击且已查询到 canClaim 时执行。
let claim = try await NexusCoreUser.shared.claimWeeklyPoints()
let grantedDisplayPoints = claim.pointsDecimal * Decimal(100)
let refreshedUser = try await NexusCoreUser.shared.fetchUserInfo()
let refreshedInfo = try await NexusCoreUser.shared.getWeeklyPointsInfo()
```

`claim.pointsDecimal` 为实际到账原始金币；`beforeCoinsDecimal / afterCoinsDecimal / balanceDecimal` 也为原始单位。`transactionId` 是领取记录字符串 ID，`claimTimeSeconds` 为 Unix 秒，`claimTime` 为兼容日期字符串；旧 `points: Int` 会截断小数。

同产品同用户每个 **UTC 周一 00:00 至下周一 00:00** 最多领取一次，未领不累计、不补领。多个有效订阅由服务端选择，不按额度最高选择，不允许客户端切换 SKU。已弃用的带 `marketProductId` 重载会拒绝非空值，不应用于新接入。Payment 也提供同名无参数方法。

查询不预留额度，领取以当时服务端资格和配置为准。`2130` 表示已领，`2131` 表示无有效订阅，`2132` 表示未配置；超时或这些错误应重新查询领取状态和余额，必要时结合服务端流水确认，不能提示重复到账或自动重领。

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

- 从主 SDK 选择随包提供的 `NexusGrowthAnalyticsAdDataEye` product，无需依赖尚未验证发布的远程 DataEye Provider 仓库。
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
    },
    eventReporter: { eventName, params in
        _ = try? NexusGrowthAnalyticsAd.shared.track(eventName, params: params)
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

如果已接入 CoreUserSDK，在游客、邮箱或手机号登录成功后设置同一个返回用户：

```swift
// user 为第 4.2 节登录成功返回的 SDKUser。
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

`ad_show` 只在广告实际展示成功后上报：开屏、插屏、激励和激励插屏对应 AdMob 的 `adWillPresentFullScreenContent(_:)` 展示回调链路，Banner 和 Native 对应曝光回调。仅调用 `showAd()`、广告未就绪、加载失败或展示失败时不会上报 `ad_show`。

## 6. PaymentSDK 接入

`PaymentSDK` 只负责支付与订阅能力。业务方不需要自行请求商品列表、拼装订阅页或手动处理订单校验；页面会根据配置自动完成商品加载、商店信息合并、购买、恢复和权益交付。

### 6.1 接入顺序

按以下顺序接入：

1. 初始化 `NexusCoreUser`。
2. 初始化 `NexusPayment`。
3. 在需要展示订阅入口时调用 `showSubscriptionPage(...)`。
4. 监听支付结果或页面事件，按业务需要刷新会员状态和余额。

### 6.2 初始化

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

### 6.3 展示订阅页

```swift
let pageConfig = try SubscriptionPageConfig(
    templateId: SubscriptionPageTemplateId.aurora.rawValue,
    scene: "home",
    title: "Premium",
    benefitDescription: "Unlock premium benefits.",
    benefits: ["No ads", "Bonus coins"],
    sharedApps: SubscriptionSharedAppsConfig(
        title: "Related apps",
        description: "Explore more apps. Membership benefits are specific to each app."
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
| `aurora` | `SubscriptionPageTemplateId.aurora.rawValue` | 明亮现代风格，突出当前权益、关联应用和购买选项；默认模板。 |
| `midnight` | `SubscriptionPageTemplateId.midnight.rawValue` | 深色沉浸风格，适合会员、内容和创作类产品。 |
| `minimal` | `SubscriptionPageTemplateId.minimal.rawValue` | 清爽紧凑风格，适合工具类应用或商品较多的页面。 |

未传、传空值或传入未知模板 ID 时会回退到 `aurora`。Android 与 iOS 使用相同模板 ID，业务方可直接由远程配置控制两端样式。

切换模板只需要修改 `templateId`，其余页面配置和调用方式不变。

`SubscriptionPageConfig` 参数：

| 参数 | 说明 |
| --- | --- |
| `templateId` | 页面模板：`aurora`、`midnight`、`minimal`。 |
| `title` | 页面标题。 |
| `benefitDescription` | 当前产品权益描述。 |
| `benefits` | 权益字符串数组，按标签展示。 |
| `sharedApps` | 关联应用区域标题和描述；不表示跨产品共享会员。 |
| `paymentChannels` | 支付渠道列表。 |
| `showPaymentChannel` | 是否展示支付渠道选择。 |
| `showRestore` | 是否展示恢复购买入口。 |
| `termsUrl` / `privacyUrl` | 服务条款和隐私协议地址；对应入口开启时不能为空。 |
| `showTerms` / `showPrivacy` | 是否展示对应协议入口，默认均为 `true`。 |
| `ctaText` | 购买按钮文案。 |
| `restoreText` / `termsText` / `privacyText` | 底部入口文案，默认分别为 `Restore`、`Terms`、`Privacy`。 |

### 6.4 页面自动处理流程

打开订阅页后，SDK 会自动完成以下流程，业务方不需要提前获取商品或手动调用购买接口：

- 从 `/api/v1/iap/products` 获取商品并按 `sort` 稳定排序；`product_type=2` 为订阅，`1` 为金币包或一次性内购。
- **`coins_granted` 是购买成功后直接到账的金币（upfront）；`weekly_points` 是开启周积分后额外可领取的额度（additional）。两项独立，必须同时展示，不能二选一。** `weekly_points_enabled=1` 表示开启，`2` 表示关闭；SDK 映射为 `Product.weeklyPointsEnabled: Bool`。
- 三套模板均展示正数 `coinsGrantedDecimal ×100` 的购买到账权益；订阅同时开启周积分且额度大于 0 时，另展示 `weeklyPointsDecimal ×100` 的每周额外权益。例如原始赠币 `20`、周积分 `0.5` 时，展示“购买后到账 2000”及“每周额外可领 50”。关闭周积分不隐藏购买到账权益。
- 从 StoreKit 2 合并本地化价格、币种、订阅周期和试用信息；没有有效商店详情时可以展示后台权益及参考价，但不能购买。
- 查询用户周积分资格，以 `canClaim` 和资格响应中的额度控制领取。商品权益说明不代表当前用户已具备资格；无订阅时可引导订阅，已领取或未配置时不允许领取。
- 用户点击领取后调用无参数 `claimWeeklyPoints()`，成功后刷新用户资料及领取状态；自定义入口见第 4.7 节。
- 获取关联应用；`sharedApps` 名称为兼容保留字段，该区域不承诺跨产品共享会员。
- 购买后查询服务端订单状态；仅确认 `50` 已支付后按成功处理。订单查询本身不会发币。
- 恢复购买并处理待确认交易；Pending 时等待确认，不提示用户重新支付同一订单。
- 权益和交付记录按 `productId + uid` 持久化，重新初始化 SDK 或切换用户后仍能正确隔离和恢复。
- 服务条款和隐私协议默认展示，分别使用 `https://www.crypsiscollectiveinc.com/terms.html` 和 `https://www.crypsiscollectiveinc.com/privacy.html`；点击后由系统默认浏览器打开。

商品数值与价格：

| 字段 | 单位与使用方式 |
| --- | --- |
| `Product.coinsGrantedDecimal` | Decimal 原始金币；购买到账权益显示时 ×100 一次 |
| `Product.weeklyPointsDecimal` | Decimal 原始金币；额外每周权益显示时 ×100 一次 |
| `Product.coinsGranted` / `weeklyPoints` | Double? / Int 兼容字段；后者截断小数，新业务使用 Decimal 字段 |
| `Product.priceUsd` | 后台 `price_usd`，美元分整数；199 仅表示 USD 1.99 参考价 |
| `localizedPrice` / `currency` | StoreKit 实际本地化价格及币种，实际结账以商店为准 |
| `storeDetailsAvailable` | 是否已获取有效商店详情；购买按钮还需有有效价格且商品不处于待确认状态 |

`priceUsd` 不能当成本地货币，也不能作为可购买凭据。用户余额 `SDKUser.balanceDecimal` 已是展示单位，**不要**再套用上述商品原始金币的 ×100。支付金额字符串 `amount` 和 `currency` 不执行金币倍率转换。

### 6.5 页面事件与余额刷新

```swift
let removePageListener = NexusPayment.shared.onSubscriptionPageEvent { event in
    switch event.name {
    case .purchaseSuccess, .restoreSuccess, .weeklyPointsClaimSuccess:
        Task { @MainActor in
            do {
                let user = try await NexusCoreUser.shared.fetchUserInfo()
                // 使用 user.isVip / user.vipExpiredAt / user.balanceDecimal 更新业务界面。
            } catch {
                // 保持待刷新状态，稍后重试查询；不重复购买或领取。
            }
        }
    default:
        break
    }
}

// 所属业务组件结束监听时调用：removePageListener()
```

监听不依赖 Growth 初始化，页面还提供展示、商品/渠道选择、购买点击/失败/取消、恢复和领取失败、关闭事件。刷新失败不表示权益消失；会员以 `fetchUserInfo()` 的 `isVip / vipExpiredAt` 为准，余额以其 `balanceDecimal` 为准，不能仅根据订单或本地权益缓存推导服务端会员。

配置注意事项：

- `showTerms`、`showPrivacy` 默认均为 `true`，业务方可显式设为 `false` 隐藏对应入口。
- `termsUrl`、`privacyUrl` 已提供上述默认值；业务方可以覆盖，但入口开启时不能传空字符串。
- 支付方式配置错误时不自动兜底。
- 没有内置动态支付配置接口，页面配置由宿主通过 `SubscriptionPageConfig` 提供。
- `PaymentConfig.productId` 与 CoreUser 使用同一后台产品 ID；启用真实购买前须完成 App Store 商品及服务端通知配置。

### 6.6 订单状态与到账确认

StoreKit 2 购买成功后：

- `ProviderPurchaseResult.purchaseToken` 为 Apple signed transaction JWS，与登录 Bearer Token 不同。
- `orderId` 是本次 StoreKit `transaction.id`；订阅链 ID 单独保留为 `original_transaction_id`。
- 当前系统 UID 作为 `appAccountToken` 传给 StoreKit；SDK 接受标准 UUID 或可无损转为 UUID 的 32 位十六进制 UID。其他格式会报错，不能自行生成无关 UUID 替代账号。

SDK 自动向 `POST /api/v1/order/apple/status` 发送符合商品类型的请求，业务不需要手动拼装：

| 类型 | 请求字段 |
| --- | --- |
| 一次性内购 | `issub=false`、`platform_product_id`、JWS `token` 和本次交易 `trade_order_id`；协议要求凭证与 ID 至少一个，同时传时必须匹配。不传 original_transaction_id。 |
| 订阅 | 只传 `issub=true` 和 `original_transaction_id`；不能夹带 token、trade_order_id 或 platform_product_id。 |

两个请求均通过 Authorization 传登录 Token，不在请求体添加 UID。服务端响应中的 `amount` 保持字符串、`currency` 保持币种，`startedTime / endsTime` 为 Unix 秒。

| 服务端 status | Swift 状态 | 业务处理 |
| --- | --- | --- |
| `10` | `.pending` | 待支付或待确认；保留交易，等待通知或恢复查询，不引导重复付款 |
| `50` | `.success` | 唯一支付成功状态；刷新用户资料确认余额及会员 |
| `60` | `.refunded` | 已退款，刷新资料，不继续按成功授予权益 |
| `70` | `.cancelled` | 已取消，不交付 |
| `80` | `.expired` | 订阅已过期，刷新会员状态 |
| 其他值 | `.unknown` | 未确认，不能当作成功交付 |

外层 `code=1` 只代表查询成功，不代表订单支付成功；`OrderVerificationResult.isSuccessful` 仅在 status 为 `50` 时为真。订阅链尚未到达服务端时可返回正常 Pending 视图，不能当作无权限订单或已支付。

SDK 监听 `Transaction.updates`，配合服务端查询处理续订、退款、撤销和本地权益更新；本地交付按每次交易 ID 去重。确认成功才完成对应商店交易，Pending/未确认交易保留用于后续处理。

SDK 对待确认交易进行有限次数的只读重查。自定义购买页面可使用以下方法继续核对状态；它们不会重新打开付款或重复领取积分：

```swift
let pendingIds = NexusPayment.shared.getPendingProductIds()
// 对 pendingIds 中的商品显示“确认中”，不要引导再次购买。
try await NexusPayment.shared.reconcilePendingPurchases()
```

待确认商品按服务、产品及账号隔离保存。应用重启后，可通过恢复购买重新取得商店交易并核对；不要把网络超时当作付款失败。内置页面会显示待确认状态，并在交易更新后刷新。

**商店通知异步完成金币到账及会员维护，订单已支付与余额/会员更新之间可能存在延迟。** 订单状态查询不直接发币；订阅查询也不会向商店补建订阅链或恢复服务端权益。购买、恢复后刷新 `fetchUserInfo()`，必要时稍后再次查询并由后台核对流水。不得按 `coinsGrantedDecimal` 在业务端自行加币，也不能将支付成功回调直接视为服务端会员已生效；“购买后直接到账”说明权益类型，不承诺通知零延迟。

## 7. CrossPromoSDK 接入

### 7.1 iOS Scheme 要求

iOS 无法通过 packageName 直接判断 App 是否安装。目标 App 需注册自己的 URL Scheme；宿主若查询目标 Scheme，需在 `Info.plist` 配置 `LSApplicationQueriesSchemes`。

当前 v1 关联产品响应不承诺 `ios_scheme`，当前加载流程也不映射该字段；不能假定仅设置查询白名单就能打开已安装应用。标准关联产品接入应提供有效 `download_url`，作为商店/下载入口；业务自有 Deep Link 的接收处理见第 7.4 节。

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

- SDK 调用 `/api/v1/product/related-products`，通过当前 Token 认证，`account_name` 使用 CoreUserConfig.accountName。
- SDK 排除当前 `sourceProductId`。
- 当前标准关联产品使用可用的 `download_url` 跳转；应由后台配置有效商店地址。无数据时按空列表处理，关联应用不表示共享会员。

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

真实归因上报需初始化 Growth 并传入相应 Provider。Deep Link 的来源 UID 仅用于归因，不是目标 App 的登录凭证；目标 App 必须完成自己的游客或账号登录。邮箱/手机号登录成功后同样可以处理待关联归因，不能因账号重登失败转为游客。

## 8. 推荐初始化顺序

```swift
func initializeNexusSDK(coreConfig: CoreUserConfig) async throws {
    // 使用第 4.1 节配置；正式环境由后台提供全部正式参数。
    NexusCoreUser.shared.initialize(config: coreConfig)

    // 复用有效会话；首次游客建立会话。账号会话失效会抛错，交由业务展示账号重登入口。
    let user = try await NexusCoreUser.shared.ensureAuthenticatedUser()

    // 需要事件或广告时，按第 5 节传入真实 Provider 初始化 Growth，
    // 再调用 NexusGrowthAnalyticsAd.shared.setUser(user)。

    let paymentConfig = try PaymentConfig(
        productId: coreConfig.productId,
        defaultChannel: .appStore,
        enabledChannels: [.appStore]
    )
    NexusPayment.shared.initialize(config: paymentConfig)

    NexusCrossPromo.shared.initialize(
        config: try CrossPromoConfig(sourceProductId: coreConfig.productId)
    )
}
```

只接单模块时：

- 只做登录：只接 CoreUserSDK。
- 只做事件/广告：可以只接 GrowthAnalyticsAdSDK，但事件里没有 uid/deviceId；建议同时接 CoreUserSDK。
- 只做支付：必须接 CoreUserSDK + PaymentSDK。
- 只做互导：必须接 CoreUserSDK + CrossPromoSDK；需要事件归因时再接 GrowthAnalyticsAdSDK。
