import UIKit
import NexusCoreUser
import NexusGrowthAnalyticsAd
import NexusPayment
import NexusCrossPromo

@main
final class NexusDemoAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: NexusDemoViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class NexusDemoViewController: UIViewController {
    private static let loginTypes: [LoginType] = [.guest, .email, .phone]

    private let apiBaseUrlField = UITextField()
    private let productIdField = UITextField()
    private let productNameField = UITextField()
    private let encryptionKeyField = UITextField()
    private let grantTierField = UITextField()
    private let bindEmailField = UITextField()
    private let encryptSwitch = UISwitch()
    private let loginTypeControl = UISegmentedControl(items: NexusDemoViewController.loginTypes.map(\.rawValue))
    private let stack = UIStackView()
    private let logView = UITextView()
    private let bannerContainer = UIView()
    private let adCallbacks = DemoAdCallbacks()
    private let nativeCallbacks = DemoNativeCallbacks()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Nexus SDK Demo"
        view.backgroundColor = .systemBackground
        buildLayout()
        bindLogs()
        initializeAllSdks()
    }

    private func buildLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 14
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 18, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        logView.isEditable = false
        logView.font = .systemFont(ofSize: 13)
        logView.backgroundColor = .secondarySystemBackground
        logView.layer.cornerRadius = 8
        logView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: logView.topAnchor, constant: -8),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            logView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            logView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            logView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            logView.heightAnchor.constraint(equalToConstant: 190)
        ])

        configureFields()
        stack.addArrangedSubview(section("Config", views: [
            labeledField("API Base URL", apiBaseUrlField),
            labeledField("Product ID", productIdField),
            labeledField("Product Name", productNameField),
            labeledField("Encryption Key", encryptionKeyField),
            labeledField("GT", grantTierField),
            toggleRow("Encrypt", encryptSwitch),
            button("Initialize SDKs", action: #selector(initializeTapped)),
            button("Clear Logs", action: #selector(clearLogsTapped))
        ]))

        stack.addArrangedSubview(section("CoreUserSDK", views: [
            labeledControl("Login Type", loginTypeControl),
            labeledField("Bind Email", bindEmailField),
            button("Run CoreUser Full Flow", action: #selector(runCoreUserFullFlowTapped)),
            button("Silent Login", action: #selector(loginTapped)),
            button("Fetch User Info", action: #selector(fetchUserInfoTapped)),
            button("Bind Email Directly", action: #selector(bindEmailDirectlyTapped)),
            button("Show Bind Email Dialog", action: #selector(bindEmailDialogTapped)),
            button("Get Current User Cache", action: #selector(getCurrentUserTapped)),
            button("Get Login Config", action: #selector(getLoginConfigTapped)),
            button("Get SDK Config", action: #selector(getSdkConfigTapped)),
            button("Get Device ID", action: #selector(getDeviceIdTapped)),
            button("Enable Login Attribution", action: #selector(enableLoginAttributionTapped)),
            button("Disable Login Attribution", action: #selector(disableLoginAttributionTapped)),
            button("Get Related Products", action: #selector(getRelatedProductsTapped)),
            button("Logout / Keep UID", action: #selector(logoutTapped))
        ]))

        bannerContainer.backgroundColor = .tertiarySystemBackground
        bannerContainer.layer.cornerRadius = 8
        bannerContainer.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(section("GrowthAnalyticsAdSDK", views: [
            button("Track demo_event", action: #selector(trackEventTapped)),
            button("Handle Deep Link", action: #selector(handleDeepLinkTapped)),
            button("Load Mock Interstitial", action: #selector(loadInterstitialTapped)),
            button("Show Mock Interstitial", action: #selector(showInterstitialTapped)),
            button("Load Mock Banner", action: #selector(loadBannerTapped)),
            bannerContainer,
            button("Load Mock Native", action: #selector(loadNativeTapped)),
            button("Report Ad Revenue", action: #selector(reportAdRevenueTapped))
        ]))

        stack.addArrangedSubview(section("PaymentSDK", views: [
            button("Load Products", action: #selector(loadProductsTapped)),
            button("Mock Purchase", action: #selector(mockPurchaseTapped)),
            button("Show Subscription Page", action: #selector(showSubscriptionTapped)),
            button("Restore Purchases", action: #selector(restoreTapped)),
            button("Get Entitlements", action: #selector(entitlementsTapped))
        ]))

        stack.addArrangedSubview(section("CrossPromoSDK", views: [
            button("Show Promo Page", action: #selector(showPromoTapped)),
            button("Open Demo Product", action: #selector(openPromoProductTapped)),
            button("Handle Incoming Link", action: #selector(handleIncomingPromoTapped)),
            button("Flush Attribution After Login", action: #selector(flushAttributionTapped))
        ]))
    }

    private func configureFields() {
        apiBaseUrlField.text = "https://serverlf.stoahayaamhsothy.com/"
        productIdField.text = "7"
        productNameField.text = "TEST PRODUCT"
        encryptionKeyField.text = "1b8df48c1fa64ce28a2e8133dffe600c"
        encryptionKeyField.placeholder = "32-byte key when encrypt=true"
        grantTierField.placeholder = "Optional: 1 / 2 / 3"
        bindEmailField.placeholder = "user@example.com"
        bindEmailField.text = "user@example.com"
        encryptSwitch.isOn = true
        loginTypeControl.selectedSegmentIndex = 0

        [apiBaseUrlField, productIdField, productNameField, encryptionKeyField, grantTierField, bindEmailField].forEach {
            $0.borderStyle = .roundedRect
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.clearButtonMode = .whileEditing
        }
    }

    private func bindLogs() {
        adCallbacks.log = { [weak self] in self?.append($0) }
        nativeCallbacks.log = { [weak self] in self?.append($0) }
        _ = NexusPayment.shared.onSubscriptionPageEvent { [weak self] event in
            self?.append("Subscription event: \(event.name.rawValue) \(event.analyticsParams())")
        }
    }

    @objc private func initializeTapped() {
        initializeAllSdks()
    }

    @objc private func runCoreUserFullFlowTapped() {
        Task {
            do {
                try ensureCoreUserInitialized()
                let deviceId = try NexusCoreUser.shared.getDeviceId()
                let loginType = selectedLoginType()
                await MainActor.run {
                    append("CoreUser full flow started. deviceId=\(deviceId), loginType=\(loginType.rawValue)")
                }

                let loggedInUser = try await NexusCoreUser.shared.silentLogin(loginType: loginType)
                await MainActor.run {
                    NexusGrowthAnalyticsAd.shared.setUser(loggedInUser)
                    append("Full flow login success: \(format(user: loggedInUser))")
                    append("Full flow login config: \((try? NexusCoreUser.shared.getConfig()) ?? [:])")
                }

                let refreshedUser = try await NexusCoreUser.shared.fetchUserInfo()
                await MainActor.run {
                    append("Full flow fetched user: \(format(user: refreshedUser))")
                }

                if refreshedUser.emailBound {
                    await MainActor.run {
                        append("Full flow email already bound: \(refreshedUser.email ?? "-")")
                    }
                } else if refreshedUser.userInfoSynced {
                    await MainActor.run {
                        append("Full flow user has no bound email. Use Show Bind Email Dialog to bind manually.")
                    }
                } else {
                    await MainActor.run {
                        append("Full flow user info sync failed; skip bind email dialog")
                    }
                }
            } catch {
                await MainActor.run {
                    append("CoreUser full flow failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func initializeAllSdks() {
        do {
            let coreConfig = try makeCoreConfig()
            let productId = coreConfig.productId
            NexusCoreUser.shared.initialize(config: coreConfig)
            append("CoreUser initialized productId=\(productId)")

            let analyticsConfig = try AnalyticsConfig(productId: productId, debug: true)
            NexusGrowthAnalyticsAd.shared.initialize(config: analyticsConfig)
            append("GrowthAnalyticsAd initialized")

            let paymentConfig = try PaymentConfig(productId: productId, defaultChannel: .mock, enabledChannels: [.mock, .appStore], fallbackChannels: [.appStore])
            NexusPayment.shared.initialize(config: paymentConfig)
            NexusPayment.shared.setProductsForTesting(demoProducts())
            NexusPayment.shared.setRelatedProductsForTesting(demoRelatedProducts())
            append("Payment initialized with mock products")

            NexusCrossPromo.shared.initialize(config: try CrossPromoConfig(sourceProductId: productId, campaign: "ios_demo", defaultPlacement: "demo_home"))
            NexusCrossPromo.shared.setProductsForTesting(demoPromoProducts())
            append("CrossPromo initialized with mock products")

            _ = try NexusGrowthAnalyticsAd.shared.track("demo_open", params: ["screen": "main"])
            append("Tracked demo_open")
        } catch {
            append("Initialize failed: \(error.localizedDescription)")
        }
    }

    private func ensureCoreUserInitialized() throws {
        do {
            _ = try NexusCoreUser.shared.getSdkConfig()
        } catch {
            let coreConfig = try makeCoreConfig()
            NexusCoreUser.shared.initialize(config: coreConfig)
            append("CoreUser initialized productId=\(coreConfig.productId)")
        }
    }

    private func makeCoreConfig() throws -> CoreUserConfig {
        try CoreUserConfig(
            productId: trimmedText(productIdField, fallback: "7"),
            productName: trimmedText(productNameField, fallback: "TEST PRODUCT"),
            apiBaseUrl: trimmedText(apiBaseUrlField, fallback: "https://serverlf.stoahayaamhsothy.com/"),
            encrypt: encryptSwitch.isOn,
            encryptionKey: trimmedOptionalText(encryptionKeyField),
            debug: true,
            gt: trimmedOptionalText(grantTierField).flatMap(Int.init)
        )
    }

    @objc private func loginTapped() {
        Task {
            do {
                try ensureCoreUserInitialized()
                let loginType = selectedLoginType()
                let user = try await NexusCoreUser.shared.silentLogin(loginType: loginType)
                await MainActor.run {
                    NexusGrowthAnalyticsAd.shared.setUser(user)
                    append("Login success type=\(loginType.rawValue) \(format(user: user))")
                }
            } catch {
                await MainActor.run { append("Login failed: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func fetchUserInfoTapped() {
        Task {
            do {
                try ensureCoreUserInitialized()
                let user = try await NexusCoreUser.shared.fetchUserInfo()
                await MainActor.run { append("User info \(format(user: user))") }
            } catch {
                await MainActor.run { append("Fetch user info failed: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func bindEmailDirectlyTapped() {
        let email = bindEmailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Task {
            do {
                try ensureCoreUserInitialized()
                let result = try await NexusCoreUser.shared.bindEmail(email)
                let user = try NexusCoreUser.shared.getCurrentUser()
                await MainActor.run {
                    append("Bind email success uid=\(result.uid), account=\(result.accountValue), bound=\(result.bound)")
                    append("Current user after bind: \(user.map(format(user:)) ?? "-")")
                }
            } catch {
                await MainActor.run { append("Bind email failed: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func bindEmailDialogTapped() {
        showBindEmailDialog()
    }

    private func showBindEmailDialog() {
        do {
            try ensureCoreUserInitialized()
        } catch {
            append("Bind email dialog failed: \(error.localizedDescription)")
            return
        }
        NexusCoreUser.shared.ensureEmailBound(presenting: self) { [weak self] result in
            DispatchQueue.main.async {
                let error = result.error.map { ", error=\($0.localizedDescription)" } ?? ""
                self?.append("Bind email dialog result: \(result.status.rawValue)\(error)")
                if let user = result.user {
                    self?.append("Bind email dialog user: \(self?.format(user: user) ?? "-")")
                }
            }
        }
    }

    @objc private func getCurrentUserTapped() {
        do {
            if let user = try NexusCoreUser.shared.getCurrentUser() {
                append("Current user cache: \(format(user: user))")
            } else {
                append("Current user cache is empty")
            }
        } catch {
            append("Get current user failed: \(error.localizedDescription)")
        }
    }

    @objc private func getLoginConfigTapped() {
        do {
            append("Login config: \(try NexusCoreUser.shared.getConfig())")
        } catch {
            append("Get login config failed: \(error.localizedDescription)")
        }
    }

    @objc private func getSdkConfigTapped() {
        do {
            let config = try NexusCoreUser.shared.getSdkConfig()
            append("SDK config productId=\(config.productId), productName=\(config.productName), version=\(config.version), country=\(config.country), language=\(config.language), encrypt=\(config.encrypt)")
        } catch {
            append("Get SDK config failed: \(error.localizedDescription)")
        }
    }

    @objc private func getDeviceIdTapped() {
        do {
            append("Device ID: \(try NexusCoreUser.shared.getDeviceId())")
        } catch {
            append("Get device ID failed: \(error.localizedDescription)")
        }
    }

    @objc private func enableLoginAttributionTapped() {
        setLoginAttribution(true)
    }

    @objc private func disableLoginAttributionTapped() {
        setLoginAttribution(false)
    }

    private func setLoginAttribution(_ enabled: Bool) {
        do {
            try NexusCoreUser.shared.setLoginAttributionEnabled(enabled)
            append("Login attribution enabled=\(try NexusCoreUser.shared.isLoginAttributionEnabled())")
        } catch {
            append("Set login attribution failed: \(error.localizedDescription)")
        }
    }

    @objc private func getRelatedProductsTapped() {
        Task {
            do {
                let products = try await NexusCoreUser.shared.getRelatedProducts(forceRefresh: true)
                await MainActor.run {
                    append("Related products count=\(products.count): \(products.map { "\($0.productId):\($0.productName)" }.joined(separator: ", "))")
                }
            } catch {
                await MainActor.run { append("Get related products failed: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func logoutTapped() {
        do {
            try NexusCoreUser.shared.logout()
            append("Logout success: cleared cached user details and login config; uid retained for next login")
        } catch {
            append("Logout failed: \(error.localizedDescription)")
        }
    }

    @objc private func trackEventTapped() {
        do {
            let event = try NexusGrowthAnalyticsAd.shared.track("demo_event", params: ["source": "button", "value": 1])
            append("Tracked \(event.eventName)")
        } catch {
            append("Track failed: \(error.localizedDescription)")
        }
    }

    @objc private func handleDeepLinkTapped() {
        let result = NexusGrowthAnalyticsAd.shared.handleDeepLink("nexus://open?utm_source=demo&utm_campaign=summer&deep_link_value=home")
        append("Deep link source=\(result.source ?? "-"), campaign=\(result.campaign ?? "-")")
    }

    @objc private func loadInterstitialTapped() {
        do {
            try NexusGrowthAnalyticsAd.shared.loadAd(demoPlacement(), callbacks: adCallbacks)
        } catch {
            append("Load ad failed: \(error.localizedDescription)")
        }
    }

    @objc private func showInterstitialTapped() {
        do {
            try NexusGrowthAnalyticsAd.shared.showAd(demoPlacement(), callbacks: adCallbacks)
        } catch {
            append("Show ad failed: \(error.localizedDescription)")
        }
    }

    @objc private func loadBannerTapped() {
        do {
            try NexusGrowthAnalyticsAd.shared.loadBanner(
                try AdPlacement(placement: "demo_banner", adUnitId: "demo_banner", format: .banner),
                container: bannerContainer,
                callbacks: adCallbacks
            )
        } catch {
            append("Load banner failed: \(error.localizedDescription)")
        }
    }

    @objc private func loadNativeTapped() {
        do {
            try NexusGrowthAnalyticsAd.shared.loadNative(
                try AdPlacement(placement: "demo_native", adUnitId: "demo_native", format: .native),
                callbacks: nativeCallbacks
            )
        } catch {
            append("Load native failed: \(error.localizedDescription)")
        }
    }

    @objc private func reportAdRevenueTapped() {
        do {
            let payload = try AdRevenuePayload(adPlatform: "admob", adUnitId: "demo_unit", placement: "demo_interstitial", adFormat: .interstitial, currency: "USD", revenue: 0.0123, networkName: "Google", networkFirmId: "admob", scene: "demo")
            _ = try NexusGrowthAnalyticsAd.shared.reportAdRevenue(payload)
            append("Reported ad revenue")
        } catch {
            append("Report ad revenue failed: \(error.localizedDescription)")
        }
    }

    @objc private func loadProductsTapped() {
        Task {
            do {
                let products = try await NexusPayment.shared.getProducts(forceRefresh: true)
                await MainActor.run { append("Products: \(products.map { $0.marketProductId }.joined(separator: ", "))") }
            } catch {
                await MainActor.run { append("Load products failed: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func mockPurchaseTapped() {
        Task {
            do {
                let product = demoProducts()[0]
                let result = try await NexusPayment.shared.mockPurchase(product: product)
                await MainActor.run { append("Mock purchase success=\(result.success), order=\(result.orderId ?? "-")") }
            } catch {
                await MainActor.run { append("Mock purchase failed: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func showSubscriptionTapped() {
        do {
            let config = try SubscriptionPageConfig(
                templateId: "ios_demo",
                scene: "demo",
                title: "Nexus Pro",
                benefitDescription: "One membership unlocks every app in this account.",
                benefits: ["No ads", "Shared VIP", "Bonus coins"],
                sharedApps: SubscriptionSharedAppsConfig(title: "Membership Share", description: "Use the same entitlement across related apps."),
                paymentChannels: [.mock],
                ctaText: "Continue",
                restoreText: "Restore"
            )
            NexusPayment.shared.showSubscriptionPage(presenting: self, config: config)
            append("Opened subscription page")
        } catch {
            append("Show subscription failed: \(error.localizedDescription)")
        }
    }

    @objc private func restoreTapped() {
        Task {
            do {
                let result = try await NexusPayment.shared.restore(channel: .mock)
                await MainActor.run { append("Restore count=\(result.purchases.count)") }
            } catch {
                await MainActor.run { append("Restore failed: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func entitlementsTapped() {
        append("Entitlements: \(NexusPayment.shared.getEntitlements().map { $0.entitlementId })")
    }

    @objc private func showPromoTapped() {
        do {
            try NexusCrossPromo.shared.showPromoPage(
                presenting: self,
                options: ShowPromoPageOptions(placement: "demo_home", campaign: "ios_demo", title: "More Nexus Apps", description: "Install another product and keep attribution linked.")
            )
            append("Opened promo page")
        } catch {
            append("Show promo failed: \(error.localizedDescription)")
        }
    }

    @objc private func openPromoProductTapped() {
        Task {
            do {
                let opened = try await NexusCrossPromo.shared.openProduct(OpenProductOptions(productId: "8", placement: "demo_home", campaign: "ios_demo"))
                await MainActor.run { append("Open promo product result=\(opened)") }
            } catch {
                await MainActor.run { append("Open promo failed: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func handleIncomingPromoTapped() {
        do {
            let result = try NexusCrossPromo.shared.handleIncomingPromoLink("nexus://promo?click_id=demo_click&source_product_id=8&target_product_id=7&source_uid=source_user&source_device_id=source_device&placement=demo")
            append("Incoming promo click=\(result.clickId ?? "-") source=\(result.sourceProductId ?? "-")")
        } catch {
            append("Incoming promo failed: \(error.localizedDescription)")
        }
    }

    @objc private func flushAttributionTapped() {
        do {
            let payload = try NexusCrossPromo.shared.flushPendingAttributionAfterLogin()
            append("Flush attribution: \(String(describing: payload?.clickId))")
        } catch {
            append("Flush attribution failed: \(error.localizedDescription)")
        }
    }

    @objc private func clearLogsTapped() {
        logView.text = ""
    }

    private func demoPlacement() throws -> AdPlacement {
        try AdPlacement(placement: "demo_interstitial", adUnitId: "demo_interstitial", format: .interstitial, frequencyCap: 5)
    }

    private func demoProducts() -> [Product] {
        [
            Product(marketProductId: "nexus_vip_month", name: "Monthly VIP", description: "VIP for one month", productType: .subscription, coinsGranted: 300, price: "4.99", currency: "USD", localizedPrice: "$4.99", subscriptionPeriod: "P1M", hasTrial: true, entitlementId: "vip", benefits: ["No ads", "300 coins"]),
            Product(marketProductId: "nexus_coins_100", name: "100 Coins", description: "Coin pack", productType: .iap, coinsGranted: 100, price: "0.99", currency: "USD", localizedPrice: "$0.99", entitlementId: "coins_100", benefits: ["100 coins"])
        ]
    }

    private func demoRelatedProducts() -> [RelatedProduct] {
        [
            RelatedProduct(productId: "8", productName: "Nexus Notes", description: "Shared VIP notes app", icon: "", downloadUrl: "https://apps.apple.com/app/id123456789", packageName: "123456789"),
            RelatedProduct(productId: "9", productName: "Nexus Cleaner", description: "Another product under this account", icon: "", downloadUrl: "https://apps.apple.com/app/id987654321", packageName: "987654321")
        ]
    }

    private func demoPromoProducts() -> [CrossPromoProduct] {
        [
            try! CrossPromoProduct(productId: "8", title: "Nexus Notes", description: "Try the related notes product.", iconUrl: "", iosBundleId: "123456789", deepLinkUrl: "nexusnotes://promo", storeUrl: "https://apps.apple.com/app/id123456789", campaign: "ios_demo"),
            try! CrossPromoProduct(productId: "9", title: "Nexus Cleaner", description: "Discover another app in the same account.", iconUrl: "", iosBundleId: "987654321", deepLinkUrl: nil, storeUrl: "https://apps.apple.com/app/id987654321", campaign: "ios_demo")
        ]
    }

    private func section(_ title: String, views: [UIView]) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 10
        container.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        container.isLayoutMarginsRelativeArrangement = true
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 8

        let label = UILabel()
        label.text = title
        label.font = .boldSystemFont(ofSize: 18)
        container.addArrangedSubview(label)
        views.forEach { container.addArrangedSubview($0) }
        return container
    }

    private func labeledField(_ title: String, _ field: UITextField) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel

        let row = UIStackView(arrangedSubviews: [label, field])
        row.axis = .vertical
        row.spacing = 5
        return row
    }

    private func labeledControl(_ title: String, _ control: UIControl) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel

        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .vertical
        row.spacing = 5
        return row
    }

    private func toggleRow(_ title: String, _ toggle: UISwitch) -> UIView {
        let label = UILabel()
        label.text = title
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        return row
    }

    private func button(_ title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .fill
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func append(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(text)"
        logView.text = [logView.text, line].filter { !$0.isEmpty }.joined(separator: "\n")
        let range = NSRange(location: max(logView.text.count - 1, 0), length: 1)
        logView.scrollRangeToVisible(range)
    }

    private func selectedLoginType() -> LoginType {
        guard loginTypeControl.selectedSegmentIndex >= 0,
              loginTypeControl.selectedSegmentIndex < Self.loginTypes.count else {
            return .guest
        }
        return Self.loginTypes[loginTypeControl.selectedSegmentIndex]
    }

    private func format(user: SDKUser) -> String {
        "uid=\(user.uid), deviceId=\(user.deviceId), email=\(user.email ?? "-"), phone=\(user.phone ?? "-"), emailBound=\(user.emailBound), phoneBound=\(user.phoneBound), balance=\(user.balance), synced=\(user.userInfoSynced)"
    }

    private func trimmedText(_ field: UITextField, fallback: String) -> String {
        let value = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    private func trimmedOptionalText(_ field: UITextField) -> String? {
        let value = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

private final class DemoAdCallbacks: AdCallbacks, @unchecked Sendable {
    var log: ((String) -> Void)?

    func onLoaded(_ placement: AdPlacement) { log?("Ad loaded: \(placement.placement)") }
    func onShown(_ placement: AdPlacement) { log?("Ad shown: \(placement.placement)") }
    func onClicked(_ placement: AdPlacement) { log?("Ad clicked: \(placement.placement)") }
    func onClosed(_ placement: AdPlacement) { log?("Ad closed: \(placement.placement)") }
    func onReward(_ placement: AdPlacement) { log?("Ad reward: \(placement.placement)") }
    func onFailed(_ placement: AdPlacement, error: Error) { log?("Ad failed: \(placement.placement), \(error.localizedDescription)") }
}

private final class DemoNativeCallbacks: NativeAdCallbacks, @unchecked Sendable {
    var log: ((String) -> Void)?

    func onLoaded(_ placement: AdPlacement, nativeAd: Any) { log?("Native loaded: \(placement.placement)") }
    func onFailed(_ placement: AdPlacement, error: Error) { log?("Native failed: \(error.localizedDescription)") }
}
