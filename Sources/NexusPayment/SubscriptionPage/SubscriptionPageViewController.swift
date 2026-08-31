#if canImport(UIKit)
import NexusCoreUser
import UIKit

final class SubscriptionPageViewController: UIViewController, UIScrollViewDelegate, UIAdaptivePresentationControllerDelegate {
    private let sdk: NexusPayment
    private let pageConfig: SubscriptionPageConfig
    private let theme: SubscriptionPageTheme
    private var products: [Product] = []
    private var relatedProducts: [RelatedProduct] = []
    private var selectedProduct: Product?
    private var selectedChannel: PaymentChannel?
    private var displayedChannels: [PaymentChannel] = []
    private var weeklyPointsInfo: WeeklyPointsInfo?
    private var loadGeneration = 0

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let contentStack = UIStackView()
    private let actionHost = UIStackView()
    private let actionSummary = UILabel()
    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var productCards: [String: ProductOptionCard] = [:]
    private var channelCards: [PaymentChannel: ChannelOptionCard] = [:]

    private weak var relatedProductsScrollView: UIScrollView?
    private weak var relatedProductsPageControl: UIPageControl?
    private var relatedProductsCarouselStep: CGFloat = 0
    private var relatedProductsCurrentIndex = 0
    private var relatedProductsTimer: Timer?
    private let iconCache = NSCache<NSString, UIImage>()

    init(sdk: NexusPayment, config: SubscriptionPageConfig) {
        self.sdk = sdk
        self.pageConfig = config
        self.theme = SubscriptionPageTheme.resolve(config.templateId)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        relatedProductsTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pageConfig.title
        view.backgroundColor = theme.pageBackground
        buildSkeleton()
        buildFloatingCloseButton()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    private func buildSkeleton() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = theme.pageBackground
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 16
        stack.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 28, right: 18)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        contentStack.axis = .vertical
        contentStack.spacing = 14

        actionHost.axis = .vertical
        actionHost.spacing = 8
        actionHost.layoutMargins = UIEdgeInsets(top: 9, left: 18, bottom: 11, right: 18)
        actionHost.isLayoutMarginsRelativeArrangement = true
        actionHost.backgroundColor = theme.id == .midnight ? theme.elevatedSurface : theme.surface
        actionHost.layer.borderWidth = 1
        actionHost.layer.borderColor = theme.border.cgColor
        actionHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionHost)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionHost.topAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            actionHost.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -1),
            actionHost.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 1),
            actionHost.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        stack.addArrangedSubview(header())
        stack.addArrangedSubview(contentStack)

        statusLabel.textColor = theme.muted
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        contentStack.addArrangedSubview(statusLabel)
    }

    private func buildFloatingCloseButton() {
        let button = closeButton
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)), for: .normal)
        button.tintColor = theme.title
        button.backgroundColor = theme.surface.withAlphaComponent(theme.dark ? 0.96 : 0.94)
        button.layer.cornerRadius = theme.id == .midnight ? 8 : 20
        button.layer.borderWidth = 1
        button.layer.borderColor = theme.border.cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = theme.dark ? 0.3 : 0.14
        button.layer.shadowRadius = 8
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.accessibilityLabel = "Close"
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func header() -> UIView {
        switch theme.id {
        case .aurora: auroraHeader()
        case .midnight: midnightHeader()
        case .minimal: minimalHeader()
        }
    }

    private func auroraHeader() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 10

        let mark = paywallImageView(for: .subscription, cornerRadius: 18)
        mark.widthAnchor.constraint(equalToConstant: 88).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 88).isActive = true
        content.addArrangedSubview(mark)

        let eyebrow = PaddingLabel(insets: UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12))
        eyebrow.text = templateEyebrow()
        eyebrow.font = .boldSystemFont(ofSize: 11)
        eyebrow.textColor = theme.primary
        eyebrow.backgroundColor = theme.tagSurface
        eyebrow.layer.cornerRadius = 14
        eyebrow.clipsToBounds = true
        content.addArrangedSubview(eyebrow)
        content.setCustomSpacing(2, after: eyebrow)

        content.addArrangedSubview(textLabel(pageConfig.title, size: 30, color: theme.title, weight: .bold, alignment: .center))
        content.addArrangedSubview(textLabel(templateSubhead(), size: 15, color: theme.muted, alignment: .center))
        return card(content, background: theme.elevatedSurface, radius: 24, padding: UIEdgeInsets(top: 24, left: 22, bottom: 26, right: 22), border: theme.primary)
    }

    private func midnightHeader() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 18

        let brand = UIStackView()
        brand.axis = .vertical
        brand.alignment = .center
        brand.spacing = 7
        let mark = paywallImageView(for: .subscription, cornerRadius: 16)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 78),
            mark.heightAnchor.constraint(equalToConstant: 78)
        ])
        brand.addArrangedSubview(mark)
        brand.addArrangedSubview(textLabel("NEXUS", size: 10, color: theme.accent, weight: .bold, alignment: .center))
        brand.widthAnchor.constraint(equalToConstant: 84).isActive = true
        row.addArrangedSubview(brand)

        let copy = UIStackView()
        copy.axis = .vertical
        copy.spacing = 9
        copy.addArrangedSubview(textLabel(templateEyebrow(), size: 12, color: theme.accent, weight: .bold))
        copy.addArrangedSubview(textLabel(pageConfig.title, size: 27, color: theme.title, weight: .bold, maxLines: 2))
        copy.addArrangedSubview(textLabel(templateSubhead(), size: 14, color: theme.muted, maxLines: 3))
        row.addArrangedSubview(copy)

        return card(row, background: theme.elevatedSurface, radius: 8, padding: UIEdgeInsets(top: 22, left: 18, bottom: 24, right: 18), border: theme.primary)
    }

    private func minimalHeader() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 10

        let top = UIStackView()
        top.axis = .horizontal
        top.alignment = .center
        top.addArrangedSubview(textLabel(templateEyebrow(), size: 11, color: theme.accent, weight: .bold))
        let mark = paywallImageView(for: .subscription, cornerRadius: 8)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 46),
            mark.heightAnchor.constraint(equalToConstant: 46)
        ])
        let closeClearance = UIView()
        closeClearance.widthAnchor.constraint(equalToConstant: 48).isActive = true
        top.addArrangedSubview(mark)
        top.addArrangedSubview(closeClearance)
        content.addArrangedSubview(top)

        let rule = UIView()
        rule.backgroundColor = theme.accent
        rule.widthAnchor.constraint(equalToConstant: 54).isActive = true
        rule.heightAnchor.constraint(equalToConstant: 3).isActive = true
        content.addArrangedSubview(rule)
        content.addArrangedSubview(textLabel(pageConfig.title, size: 30, color: theme.title, weight: .bold, maxLines: 2))
        content.addArrangedSubview(textLabel(templateSubhead(), size: 14, color: theme.muted, maxLines: 3))
        return inset(content, UIEdgeInsets(top: 12, left: 2, bottom: 8, right: 2))
    }

    private func templateEyebrow() -> String {
        switch theme.id {
        case .aurora: "NEXUS CREATIVE STUDIO"
        case .midnight: "CREATIVE WORKSPACE"
        case .minimal: "PREMIUM STUDIO"
        }
    }

    private func templateSubhead() -> String {
        switch theme.id {
        case .aurora: "Create, edit, and share premium work across your creative apps."
        case .midnight: "Generate, refine, and export with a faster creative workflow."
        case .minimal: "Professional tools, shared access, and flexible creation credits."
        }
    }

    private func loadData() {
        loadGeneration += 1
        let generation = loadGeneration
        renderLoading()
        Task {
            do {
                let loadedProducts = try await sdk.getAPIProducts(forceRefresh: true)
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    do {
                        self.applyProducts(loadedProducts, preserveSelection: false)
                        self.displayedChannels = try self.resolvedChannels()
                        self.selectedChannel = try self.resolvedInitialChannel()
                        loadedProducts.isEmpty ? self.renderEmpty() : self.render(preserveScrollPosition: false)
                    } catch {
                        self.renderError(error)
                    }
                }

                async let enrichedProducts = sdk.enrichProductsWithAppStore(loadedProducts)
                async let loadedRelated = loadRelatedProducts()
                async let loadedWeeklyPoints = loadWeeklyPointsInfo()
                let (enriched, related, weeklyPoints) = await (enrichedProducts, loadedRelated, loadedWeeklyPoints)
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    let changed = enriched != self.products ||
                        related != self.relatedProducts ||
                        weeklyPoints != self.weeklyPointsInfo
                    guard changed else { return }
                    self.applyProducts(enriched, preserveSelection: true)
                    self.relatedProducts = related
                    self.weeklyPointsInfo = weeklyPoints
                    self.render(preserveScrollPosition: true)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.renderError(error)
                }
            }
        }
    }

    private func loadRelatedProducts() async -> [RelatedProduct] {
        (try? await sdk.getRelatedProducts(forceRefresh: true)) ?? []
    }

    private func loadWeeklyPointsInfo() async -> WeeklyPointsInfo? {
        try? await sdk.getWeeklyPointsInfo()
    }

    private func applyProducts(_ loadedProducts: [Product], preserveSelection: Bool) {
        let selectedId = selectedProduct?.marketProductId
        products = loadedProducts
        selectedProduct = preserveSelection && selectedId != nil
            ? loadedProducts.first { $0.marketProductId == selectedId } ?? loadedProducts.first
            : loadedProducts.first
    }

    private func render(preserveScrollPosition: Bool) {
        let offset = preserveScrollPosition ? scrollView.contentOffset : .zero
        resetDynamicContent(preserveCarouselPosition: preserveScrollPosition)

        let subscriptions = products.filter { $0.productType == .subscription }
        let oneTimeProducts = products.filter { $0.productType != .subscription }
        switch theme.id {
        case .midnight:
            addCurrentAppBenefits()
            addProductGroup(title: "Membership plans", subtitle: "Recurring access to premium creative tools", products: subscriptions)
            addWeeklyPointsSection()
            addProductGroup(title: "Creation credits", subtitle: "One-time credits for premium generations and exports", products: oneTimeProducts)
            addSharedApps()
        case .minimal:
            addMembershipStatus()
            addCurrentAppBenefits()
            addWeeklyPointsSection()
            addProductGroup(title: "Membership plans", subtitle: "Recurring access to premium creative tools", products: subscriptions)
            addProductGroup(title: "Creation credits", subtitle: "One-time credits for premium generations and exports", products: oneTimeProducts)
            addSharedApps()
        case .aurora:
            addMembershipStatus()
            addCurrentAppBenefits()
            addWeeklyPointsSection()
            addProductGroup(title: "Membership plans", subtitle: "Recurring access to premium creative tools", products: subscriptions)
            addProductGroup(title: "Creation credits", subtitle: "One-time credits for premium generations and exports", products: oneTimeProducts)
            addSharedApps()
        }

        if pageConfig.showPaymentChannel { addPaymentChannels() }
        addBottomActions()
        buildStickyAction()
        view.layoutIfNeeded()
        if preserveScrollPosition {
            let maximumY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            scrollView.setContentOffset(CGPoint(x: 0, y: min(offset.y, maximumY)), animated: false)
        }
    }

    private func addCurrentAppBenefits() {
        let hasDescription = !pageConfig.benefitDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasBenefits = pageConfig.benefits.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasDescription || hasBenefits else { return }
        contentStack.addArrangedSubview(currentAppBenefitsCard())
    }

    private func currentAppBenefitsCard() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 11
        content.addArrangedSubview(textLabel(currentBenefitHeading(), size: 17, color: theme.primary, weight: .bold))
        if !pageConfig.benefitDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content.addArrangedSubview(textLabel(pageConfig.benefitDescription, size: 16, color: theme.body))
        }
        if !pageConfig.benefits.filter({ !$0.isEmpty }).isEmpty {
            content.addArrangedSubview(benefitTags())
        }

        switch theme.id {
        case .aurora:
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 0
            let stripe = UIView()
            stripe.backgroundColor = theme.accent
            stripe.widthAnchor.constraint(equalToConstant: 5).isActive = true
            row.addArrangedSubview(stripe)
            row.addArrangedSubview(inset(content, UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)))
            return card(row, background: theme.surface, radius: 20, padding: .zero, border: theme.border)
        case .midnight:
            return card(content, background: theme.elevatedSurface, radius: 8, padding: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18), border: theme.border)
        case .minimal:
            return card(content, background: theme.surface, radius: 4, padding: UIEdgeInsets(top: 17, left: 17, bottom: 17, right: 17), border: theme.border)
        }
    }

    private func currentBenefitHeading() -> String {
        switch theme.id {
        case .aurora: "CREATE WITHOUT LIMITS"
        case .midnight: "CREATIVE POWER UNLOCKED"
        case .minimal: "CURRENT STUDIO BENEFITS"
        }
    }

    private func benefitTags() -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        let tags = UIStackView()
        tags.axis = .horizontal
        tags.spacing = 8
        tags.translatesAutoresizingMaskIntoConstraints = false
        pageConfig.benefits.filter { !$0.isEmpty }.forEach { value in
            let tag = PaddingLabel(insets: UIEdgeInsets(top: 6, left: 11, bottom: 6, right: 11))
            tag.text = value
            tag.font = .boldSystemFont(ofSize: 12)
            tag.textColor = theme.primary
            tag.backgroundColor = theme.tagSurface
            tag.layer.cornerRadius = theme.id == .midnight ? 6 : 14
            tag.layer.borderWidth = theme.id == .minimal ? 1 : 0
            tag.layer.borderColor = theme.border.cgColor
            tag.clipsToBounds = true
            tags.addArrangedSubview(tag)
        }
        scroll.addSubview(tags)
        NSLayoutConstraint.activate([
            tags.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            tags.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            tags.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            tags.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            tags.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 31)
        ])
        return scroll
    }

    private func addMembershipStatus() {
        guard let user = try? NexusCoreUser.shared.getCurrentUser() else { return }
        let icon = UIImageView(image: UIImage(systemName: user.isVip ? "diamond.fill" : "person.crop.circle"))
        icon.tintColor = theme.primary
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42)
        ])

        let membership = UIStackView(arrangedSubviews: [
            textLabel(user.isVip ? "VIP active" : "Current membership", size: 16, color: theme.title, weight: .bold),
            textLabel(user.isVip ? "Your premium benefits are active" : "Choose a plan to unlock more", size: 13, color: theme.muted)
        ])
        membership.axis = .vertical
        membership.spacing = 3

        let divider = UIView()
        divider.backgroundColor = theme.border
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let balance = UIStackView(arrangedSubviews: [
            textLabel("Balance", size: 12, color: theme.muted, alignment: .right),
            textLabel(Self.balanceText(user.balance), size: 18, color: theme.primary, weight: .bold, alignment: .right)
        ])
        balance.axis = .vertical
        balance.spacing = 2
        balance.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, membership, divider, balance])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        contentStack.addArrangedSubview(card(
            row,
            background: theme.surface,
            radius: theme.id == .minimal ? 4 : 18,
            padding: UIEdgeInsets(top: 14, left: 15, bottom: 14, right: 15),
            border: user.isVip ? theme.primary : theme.border
        ))
    }

    private static func balanceText(_ value: Double) -> String {
        value.rounded() == value ? String(Int64(value)) : String(format: "%.2f", value)
    }

    private func addWeeklyPointsSection() {
        guard let info = weeklyPointsInfo else { return }
        let configuredPoints = products
            .filter { $0.productType == .subscription && $0.weeklyPointsEnabled }
            .map(\.weeklyPoints)
            .max() ?? 0
        guard configuredPoints > 0 || info.weeklyPoints > 0 else { return }
        let points = max(configuredPoints, info.weeklyPoints)
        let displayedPoints = points * 100

        let iconName = theme.id == .midnight ? "gift.fill" : "calendar.badge.clock"
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.tintColor = theme.id == .minimal ? theme.accent : theme.primary
        icon.backgroundColor = theme.tagSurface
        icon.contentMode = .center
        icon.layer.cornerRadius = theme.id == .minimal ? 10 : 16
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52)
        ])

        let detail: String
        if info.canClaim {
            detail = "\(displayedPoints) points ready to claim"
        } else if info.cannotClaimReason == "already_claimed" {
            detail = "Claimed for this week"
        } else if info.cannotClaimReason == "no_valid_subscription" {
            detail = "Subscribe to earn \(displayedPoints) points weekly"
        } else {
            detail = "\(displayedPoints) points per week"
        }
        let copy = UIStackView(arrangedSubviews: [
            textLabel("Weekly points", size: 16, color: theme.title, weight: .bold),
            textLabel(detail, size: 13, color: theme.muted, maxLines: 2)
        ])
        copy.axis = .vertical
        copy.spacing = 4

        let needsSubscription = !info.canClaim && info.cannotClaimReason == "no_valid_subscription"
        let claim = UIButton(type: .system)
        claim.setTitle(info.canClaim ? "Claim" : (needsSubscription ? "Subscribe" : "View status"), for: .normal)
        claim.titleLabel?.font = .boldSystemFont(ofSize: 14)
        claim.tintColor = (info.canClaim || needsSubscription) ? (theme.dark ? theme.pageBackground : .white) : theme.muted
        claim.backgroundColor = (info.canClaim || needsSubscription) ? theme.primary : theme.elevatedSurface
        claim.layer.cornerRadius = theme.id == .midnight ? 7 : 14
        claim.layer.borderWidth = 1
        claim.layer.borderColor = ((info.canClaim || needsSubscription) ? theme.primary : theme.border).cgColor
        claim.isEnabled = info.canClaim || needsSubscription
        claim.widthAnchor.constraint(equalToConstant: 94).isActive = true
        claim.heightAnchor.constraint(equalToConstant: 44).isActive = true
        claim.addAction(UIAction { [weak self] _ in
            if info.canClaim { self?.claimWeeklyPointsTapped() } else { self?.guideToWeeklySubscription() }
        }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [icon, copy, claim])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        let panel = card(
            row,
            background: theme.id == .midnight ? theme.elevatedSurface : theme.surface,
            radius: theme.id == .aurora ? 18 : (theme.id == .midnight ? 8 : 4),
            padding: UIEdgeInsets(top: 13, left: 14, bottom: 13, right: 12),
            border: info.canClaim ? theme.primary : theme.border
        )
        contentStack.addArrangedSubview(panel)
        if info.canClaim {
            UIView.animate(withDuration: 0.7, delay: 0, options: [.autoreverse, .curveEaseInOut]) {
                panel.alpha = 0.88
            } completion: { _ in
                panel.alpha = 1
            }
        }
    }

    private func claimWeeklyPointsTapped() {
        guard let info = weeklyPointsInfo, info.canClaim else { return }
        dispatchEvent(name: .weeklyPointsClaimClick, productId: info.marketProductId, state: .ready)
        Task {
            do {
                let result = try await sdk.claimWeeklyPoints(marketProductId: info.marketProductId)
                await MainActor.run {
                    self.weeklyPointsInfo = WeeklyPointsInfo(
                        isVip: info.isVip,
                        marketProductId: info.marketProductId,
                        weeklyPoints: info.weeklyPoints,
                        canClaim: false,
                        cannotClaimReason: "already_claimed"
                    )
                    self.render(preserveScrollPosition: true)
                    self.dispatchEvent(
                        name: .weeklyPointsClaimSuccess,
                        productId: info.marketProductId,
                        state: .success,
                        params: ["points": result.points, "transaction_id": result.transactionId]
                    )
                }
            } catch {
                await MainActor.run {
                    self.dispatchEvent(
                        name: .weeklyPointsClaimFailed,
                        productId: info.marketProductId,
                        state: .failed,
                        params: ["message": error.localizedDescription]
                    )
                    let alert = UIAlertController(title: "Unable to claim points", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func guideToWeeklySubscription() {
        guard let product = products.first(where: {
            $0.productType == .subscription && $0.weeklyPointsEnabled && $0.weeklyPoints > 0
        }) else { return }
        selectProduct(product)
        guard let card = productCards[product.marketProductId] else { return }
        let rect = card.convert(card.bounds, to: scrollView)
        scrollView.setContentOffset(CGPoint(x: 0, y: max(0, rect.minY - 24)), animated: true)
    }

    private func addSharedApps() {
        guard !relatedProducts.isEmpty else { return }
        switch theme.id {
        case .aurora: contentStack.addArrangedSubview(auroraSharedApps())
        case .midnight: contentStack.addArrangedSubview(midnightSharedApps())
        case .minimal: contentStack.addArrangedSubview(minimalSharedApps())
        }
    }

    private func sharedAppsHeader() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        let title = textLabel(
            theme.id == .minimal ? pageConfig.sharedApps.title : pageConfig.sharedApps.title.uppercased(),
            size: theme.id == .minimal ? 17 : 18,
            color: theme.primary,
            weight: .bold
        )
        row.addArrangedSubview(title)
        let count = PaddingLabel(insets: UIEdgeInsets(top: 6, left: 11, bottom: 6, right: 11))
        count.text = "\(relatedProducts.count) apps included"
        count.font = .boldSystemFont(ofSize: 13)
        count.textColor = theme.primary
        count.backgroundColor = theme.id == .midnight ? theme.elevatedSurface : theme.surface
        count.layer.cornerRadius = theme.id == .midnight ? 6 : 16
        count.layer.borderWidth = 1
        count.layer.borderColor = (theme.id == .minimal ? theme.accent : theme.border).cgColor
        count.clipsToBounds = true
        count.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(count)
        return row
    }

    private func sharedAppsIntro() -> UILabel {
        textLabel(pageConfig.sharedApps.description, size: 15, color: theme.muted)
    }

    private func auroraSharedApps() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 11
        content.addArrangedSubview(sharedAppsHeader())
        if !pageConfig.sharedApps.description.isEmpty { content.addArrangedSubview(sharedAppsIntro()) }

        let carousel = horizontalScrollView()
        carousel.decelerationRate = .fast
        carousel.delegate = self
        let cards = UIStackView()
        cards.axis = .horizontal
        cards.spacing = 12
        cards.translatesAutoresizingMaskIntoConstraints = false
        carousel.addSubview(cards)
        let width = max(248, min(300, view.bounds.width - 72))
        relatedProducts.forEach { product in
            let item = sharedAppCard(product, style: .aurora)
            item.widthAnchor.constraint(equalToConstant: width).isActive = true
            cards.addArrangedSubview(item)
        }
        NSLayoutConstraint.activate([
            cards.leadingAnchor.constraint(equalTo: carousel.contentLayoutGuide.leadingAnchor),
            cards.trailingAnchor.constraint(equalTo: carousel.contentLayoutGuide.trailingAnchor),
            cards.topAnchor.constraint(equalTo: carousel.contentLayoutGuide.topAnchor),
            cards.bottomAnchor.constraint(equalTo: carousel.contentLayoutGuide.bottomAnchor),
            cards.heightAnchor.constraint(equalTo: carousel.frameLayoutGuide.heightAnchor),
            carousel.heightAnchor.constraint(equalToConstant: 146)
        ])
        content.addArrangedSubview(carousel)

        let page = UIPageControl()
        page.numberOfPages = relatedProducts.count
        page.currentPage = clampedRelatedProductsIndex(relatedProductsCurrentIndex)
        page.currentPageIndicatorTintColor = theme.primary
        page.pageIndicatorTintColor = theme.border
        page.isUserInteractionEnabled = false
        page.heightAnchor.constraint(equalToConstant: 20).isActive = true
        content.addArrangedSubview(page)

        relatedProductsScrollView = carousel
        relatedProductsPageControl = page
        relatedProductsCarouselStep = width + 12
        let wrapper = card(content, background: theme.elevatedSurface, radius: 18, padding: UIEdgeInsets(top: 18, left: 18, bottom: 12, right: 18), border: theme.border)
        DispatchQueue.main.async { [weak self, weak carousel] in
            guard let self, let carousel else { return }
            carousel.setContentOffset(CGPoint(x: CGFloat(self.relatedProductsCurrentIndex) * self.relatedProductsCarouselStep, y: 0), animated: false)
            self.startRelatedProductsCarousel()
        }
        return wrapper
    }

    private func midnightSharedApps() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 11
        content.addArrangedSubview(sharedAppsHeader())
        if !pageConfig.sharedApps.description.isEmpty { content.addArrangedSubview(sharedAppsIntro()) }
        let rail = horizontalScrollView()
        let cards = UIStackView()
        cards.axis = .horizontal
        cards.spacing = 12
        cards.translatesAutoresizingMaskIntoConstraints = false
        rail.addSubview(cards)
        relatedProducts.forEach { product in
            let item = sharedAppCard(product, style: .midnight)
            item.widthAnchor.constraint(equalToConstant: 190).isActive = true
            cards.addArrangedSubview(item)
        }
        NSLayoutConstraint.activate([
            cards.leadingAnchor.constraint(equalTo: rail.contentLayoutGuide.leadingAnchor),
            cards.trailingAnchor.constraint(equalTo: rail.contentLayoutGuide.trailingAnchor),
            cards.topAnchor.constraint(equalTo: rail.contentLayoutGuide.topAnchor),
            cards.bottomAnchor.constraint(equalTo: rail.contentLayoutGuide.bottomAnchor),
            cards.heightAnchor.constraint(equalTo: rail.frameLayoutGuide.heightAnchor),
            rail.heightAnchor.constraint(equalToConstant: 172)
        ])
        content.addArrangedSubview(rail)
        return inset(content, UIEdgeInsets(top: 10, left: 4, bottom: 4, right: 0))
    }

    private func minimalSharedApps() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 10
        content.addArrangedSubview(sharedAppsHeader())
        if !pageConfig.sharedApps.description.isEmpty { content.addArrangedSubview(sharedAppsIntro()) }

        let scroll = horizontalScrollView()
        let grid = UIStackView()
        grid.axis = .vertical
        grid.alignment = .leading
        grid.spacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        let rows = [UIStackView(), UIStackView()]
        rows.forEach {
            $0.axis = .horizontal
            $0.spacing = 8
            grid.addArrangedSubview($0)
        }
        relatedProducts.enumerated().forEach { index, product in
            let item = sharedAppCard(product, style: .minimal)
            item.widthAnchor.constraint(equalToConstant: 266).isActive = true
            rows[index % 2].addArrangedSubview(item)
        }
        scroll.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: relatedProducts.count == 1 ? 78 : 164)
        ])
        content.addArrangedSubview(scroll)
        return inset(content, UIEdgeInsets(top: 10, left: 4, bottom: 4, right: 0))
    }

    private enum SharedAppStyle { case aurora, midnight, minimal }

    private func sharedAppCard(_ product: RelatedProduct, style: SharedAppStyle) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "sparkles"))
        icon.contentMode = .scaleAspectFit
        icon.tintColor = theme.accent
        icon.backgroundColor = theme.tagSurface
        icon.clipsToBounds = true

        let title = textLabel(product.productName.isEmpty ? product.productId : product.productName, size: style == .midnight ? 17 : 16, color: theme.title, weight: .bold, maxLines: 2)
        let detail = textLabel(product.description, size: 13, color: theme.muted, maxLines: style == .minimal ? 2 : 3)

        let content: UIView
        switch style {
        case .aurora:
            icon.layer.cornerRadius = 14
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 54), icon.heightAnchor.constraint(equalToConstant: 54)])
            let heading = UIStackView(arrangedSubviews: [icon, title])
            heading.axis = .horizontal
            heading.alignment = .center
            heading.spacing = 13
            let column = UIStackView(arrangedSubviews: [heading, detail])
            column.axis = .vertical
            column.spacing = 10
            content = column
        case .midnight:
            icon.layer.cornerRadius = 16
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 58), icon.heightAnchor.constraint(equalToConstant: 58)])
            let column = UIStackView(arrangedSubviews: [icon, title, detail])
            column.axis = .vertical
            column.spacing = 9
            content = column
        case .minimal:
            icon.layer.cornerRadius = 8
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 46), icon.heightAnchor.constraint(equalToConstant: 46)])
            let copy = UIStackView(arrangedSubviews: [title, detail])
            copy.axis = .vertical
            copy.spacing = 3
            let row = UIStackView(arrangedSubviews: [icon, copy])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 11
            content = row
        }

        let radius: CGFloat = style == .aurora ? 16 : (style == .midnight ? 8 : 4)
        let padding = style == .minimal
            ? UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            : UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        let wrapper = card(content, background: theme.surface, radius: radius, padding: padding, border: theme.border)
        loadIcon(product.icon, into: icon)
        return wrapper
    }

    private func addProductGroup(title: String, subtitle: String, products: [Product]) {
        guard !products.isEmpty else { return }
        contentStack.addArrangedSubview(sectionHeading(title, subtitle: subtitle))
        products.forEach { product in
            let card = ProductOptionCard(
                product: product,
                theme: theme,
                image: paywallImage(for: product.productType),
                purchaseBadge: purchaseStateBadge(product)
            )
            card.isSelected = product.marketProductId == selectedProduct?.marketProductId
            card.addAction(UIAction { [weak self] _ in self?.selectProduct(product) }, for: .touchUpInside)
            productCards[product.marketProductId] = card
            contentStack.addArrangedSubview(card)
        }
    }

    private func purchaseStateBadge(_ product: Product) -> String? {
        if product.productType == .subscription,
           weeklyPointsInfo?.isVip == true,
           weeklyPointsInfo?.marketProductId == product.marketProductId {
            return "CURRENT PLAN"
        }
        guard let entitlement = sdk.getEntitlements().first(where: {
            $0.productId == product.marketProductId ||
                (product.entitlementId != nil && $0.entitlementId == product.entitlementId)
        }), entitlement.active else { return nil }
        return product.productType == .subscription ? "CURRENT PLAN" : "OWNED"
    }

    private func selectProduct(_ product: Product) {
        selectedProduct = product
        productCards.forEach { id, card in card.isSelected = id == product.marketProductId }
        updateActionSummary()
        dispatchEvent(name: .productSelect, productId: product.marketProductId, state: .ready)
    }

    private func addPaymentChannels() {
        guard !displayedChannels.isEmpty else { return }
        contentStack.addArrangedSubview(sectionHeading("Payment method", subtitle: "Secure checkout through your app store"))
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        displayedChannels.forEach { channel in
            let option = ChannelOptionCard(channel: channel, title: channelDisplayName(channel), theme: theme)
            option.isSelected = channel == selectedChannel
            option.addAction(UIAction { [weak self] _ in self?.selectChannel(channel) }, for: .touchUpInside)
            channelCards[channel] = option
            row.addArrangedSubview(option)
        }
        contentStack.addArrangedSubview(row)
    }

    private func selectChannel(_ channel: PaymentChannel) {
        selectedChannel = channel
        channelCards.forEach { value, card in card.isSelected = value == channel }
        dispatchEvent(name: .channelSelect, paymentChannel: channel, state: .ready)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> UIView {
        let labels = UIStackView()
        labels.axis = .vertical
        labels.spacing = 3
        labels.addArrangedSubview(textLabel(title, size: theme.id == .minimal ? 18 : 19, color: theme.title, weight: .bold))
        labels.addArrangedSubview(textLabel(subtitle, size: 13, color: theme.muted))
        if theme.id == .midnight {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 12
            let line = UIView()
            line.backgroundColor = theme.accent
            NSLayoutConstraint.activate([line.widthAnchor.constraint(equalToConstant: 3), line.heightAnchor.constraint(equalToConstant: 44)])
            row.addArrangedSubview(line)
            row.addArrangedSubview(labels)
            return row
        }
        return labels
    }

    private func buildStickyAction() {
        actionHost.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionSummary.font = .systemFont(ofSize: 12, weight: .medium)
        actionSummary.textColor = theme.muted
        actionSummary.textAlignment = .center
        actionSummary.numberOfLines = 1
        actionHost.addArrangedSubview(actionSummary)
        updateActionSummary()

        let cta = UIButton(type: .system)
        cta.setTitle(pageConfig.ctaText, for: .normal)
        cta.titleLabel?.font = .boldSystemFont(ofSize: 17)
        cta.backgroundColor = theme.primary
        cta.tintColor = theme.dark ? UIColor(red: 16/255, green: 22/255, blue: 28/255, alpha: 1) : .white
        cta.layer.cornerRadius = theme.id == .aurora ? 16 : (theme.id == .midnight ? 8 : 10)
        cta.heightAnchor.constraint(equalToConstant: 54).isActive = true
        cta.addAction(UIAction { [weak self] _ in self?.purchaseTapped() }, for: .touchUpInside)
        actionHost.addArrangedSubview(cta)
    }

    private func updateActionSummary() {
        guard let product = selectedProduct else {
            actionSummary.text = nil
            return
        }
        actionSummary.text = [productDisplayName(product), product.localizedPrice ?? product.price]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "  •  ")
    }

    private func addBottomActions() {
        guard pageConfig.showRestore || pageConfig.showTerms || pageConfig.showPrivacy else { return }
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        if pageConfig.showRestore {
            let restore = linkButton(pageConfig.restoreText)
            restore.addAction(UIAction { [weak self] _ in self?.restoreTapped() }, for: .touchUpInside)
            row.addArrangedSubview(restore)
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        if pageConfig.showTerms {
            let terms = linkButton(pageConfig.termsText)
            terms.addAction(UIAction { [weak self] _ in self?.openUrl(self?.pageConfig.termsUrl) }, for: .touchUpInside)
            row.addArrangedSubview(terms)
        }
        if pageConfig.showPrivacy {
            let privacy = linkButton(pageConfig.privacyText)
            privacy.addAction(UIAction { [weak self] _ in self?.openUrl(self?.pageConfig.privacyUrl) }, for: .touchUpInside)
            row.addArrangedSubview(privacy)
        }
        contentStack.addArrangedSubview(row)
    }

    private func linkButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.tintColor = theme.id == .midnight ? theme.primary : theme.muted
        button.titleLabel?.font = .systemFont(ofSize: 13)
        button.titleLabel?.numberOfLines = 0
        return button
    }

    private func openUrl(_ value: String?) {
        guard let value, let url = URL(string: value) else { return }
        UIApplication.shared.open(url)
    }

    private func renderLoading() {
        resetDynamicContent()
        statusLabel.text = "Loading products..."
        contentStack.addArrangedSubview(statusLabel)
    }

    private func renderEmpty() {
        resetDynamicContent()
        statusLabel.text = "No products available."
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(retryButton())
    }

    private func renderError(_ error: Error) {
        resetDynamicContent()
        statusLabel.text = "Failed to load products.\n\(error.localizedDescription)"
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(retryButton())
    }

    private func retryButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Retry", for: .normal)
        button.tintColor = theme.primary
        button.addAction(UIAction { [weak self] _ in self?.loadData() }, for: .touchUpInside)
        return button
    }

    private func resetDynamicContent(preserveCarouselPosition: Bool = false) {
        relatedProductsTimer?.invalidate()
        relatedProductsTimer = nil
        relatedProductsScrollView = nil
        relatedProductsPageControl = nil
        relatedProductsCarouselStep = 0
        if !preserveCarouselPosition { relatedProductsCurrentIndex = 0 }
        productCards.removeAll()
        channelCards.removeAll()
        actionHost.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func resolvedChannels() throws -> [PaymentChannel] {
        let available = try sdk.getAvailableChannels()
        let resolved = try sdk.resolvePaymentChannel()
        let channels = pageConfig.paymentChannels.isEmpty ? resolved.enabledChannels : pageConfig.paymentChannels
        let invalid = channels.filter { !available.contains($0) }
        guard invalid.isEmpty else {
            throw PaymentError.invalidConfig("Payment channel config error: \(invalid.map(\.rawValue).joined(separator: ", "))")
        }
        return channels
    }

    private func resolvedInitialChannel() throws -> PaymentChannel {
        if let configured = pageConfig.paymentChannels.first { return configured }
        return try sdk.resolvePaymentChannel().defaultChannel
    }

    private func channelDisplayName(_ channel: PaymentChannel) -> String {
        switch channel {
        case .googlePlay: "Google Play"
        case .appStore: "App Store"
        case .stripe: "Stripe"
        case .paypal: "PayPal"
        case .webCheckout: "Web Checkout"
        case .mock: "Mock"
        }
    }

    private func productDisplayName(_ product: Product) -> String {
        let value = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? product.marketProductId : value
    }

    private func horizontalScrollView() -> UIScrollView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        return scroll
    }

    private func loadIcon(_ source: String, into imageView: UIImageView) {
        guard !source.isEmpty, let url = URL(string: source) else { return }
        if let cached = iconCache.object(forKey: source as NSString) {
            imageView.image = cached
            imageView.contentMode = .scaleAspectFill
            return
        }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
            await MainActor.run {
                self.iconCache.setObject(image, forKey: source as NSString)
                imageView.image = image
                imageView.contentMode = .scaleAspectFill
            }
        }
    }

    private func startRelatedProductsCarousel() {
        relatedProductsTimer?.invalidate()
        guard theme.id == .aurora, relatedProducts.count > 1 else { return }
        relatedProductsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, let carousel = self.relatedProductsScrollView else { return }
            self.relatedProductsCurrentIndex = (self.relatedProductsCurrentIndex + 1) % self.relatedProducts.count
            self.relatedProductsPageControl?.currentPage = self.relatedProductsCurrentIndex
            carousel.setContentOffset(
                CGPoint(x: CGFloat(self.relatedProductsCurrentIndex) * self.relatedProductsCarouselStep, y: 0),
                animated: true
            )
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { updateRelatedProductsPage(for: scrollView) }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { updateRelatedProductsPage(for: scrollView) }

    private func updateRelatedProductsPage(for scrollView: UIScrollView) {
        guard scrollView === relatedProductsScrollView, relatedProductsCarouselStep > 0 else { return }
        relatedProductsCurrentIndex = clampedRelatedProductsIndex(Int(round(scrollView.contentOffset.x / relatedProductsCarouselStep)))
        relatedProductsPageControl?.currentPage = relatedProductsCurrentIndex
    }

    private func clampedRelatedProductsIndex(_ index: Int) -> Int {
        guard !relatedProducts.isEmpty else { return 0 }
        return min(max(index, 0), relatedProducts.count - 1)
    }

    private func paywallImage(for type: ProductType) -> UIImage? {
        let template = theme.id.rawValue
        let kind: String
        switch type {
        case .subscription: kind = "subscription"
        case .consumable: kind = "consumable"
        case .iap, .unknown: kind = "iap"
        }
        let name = "ic_paywall_\(template)_\(kind)"
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Paywall"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return UIImage(named: name, in: Bundle.module, compatibleWith: nil)
    }

    private func paywallImageView(for type: ProductType, cornerRadius: CGFloat) -> UIImageView {
        let image = UIImageView(image: paywallImage(for: type))
        image.contentMode = .scaleAspectFill
        image.layer.cornerRadius = cornerRadius
        image.clipsToBounds = true
        return image
    }

    private func textLabel(
        _ text: String,
        size: CGFloat,
        color: UIColor,
        weight: UIFont.Weight = .regular,
        alignment: NSTextAlignment = .left,
        maxLines: Int = 0
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = maxLines
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func card(_ content: UIView, background: UIColor, radius: CGFloat, padding: UIEdgeInsets, border: UIColor) -> UIView {
        let wrapper = UIView()
        wrapper.backgroundColor = background
        wrapper.layer.cornerRadius = radius
        wrapper.layer.borderWidth = 1
        wrapper.layer.borderColor = border.cgColor
        wrapper.clipsToBounds = true
        wrapper.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: padding.left),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -padding.right),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: padding.top),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -padding.bottom)
        ])
        return wrapper
    }

    private func inset(_ content: UIView, _ padding: UIEdgeInsets) -> UIView {
        let wrapper = UIView()
        wrapper.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: padding.left),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -padding.right),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: padding.top),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -padding.bottom)
        ])
        return wrapper
    }

    private func purchaseTapped() {
        guard let product = selectedProduct else {
            dispatchEvent(name: .purchaseFailed, state: .failed, params: ["message": "No product selected"])
            return
        }
        let channel = selectedChannel
        dispatchEvent(name: .purchaseClick, productId: product.marketProductId, paymentChannel: channel, state: .purchasing)
        Task {
            do {
                let result = try await sdk.purchase(product: product, channel: channel)
                await MainActor.run {
                    self.dispatchEvent(
                        name: result.success ? .purchaseSuccess : .purchaseFailed,
                        productId: product.marketProductId,
                        paymentChannel: result.channel,
                        state: result.success ? .success : .failed,
                        params: ["order_id": result.orderId, "message": result.message]
                    )
                }
            } catch {
                await MainActor.run {
                    self.dispatchEvent(name: .purchaseFailed, productId: product.marketProductId, paymentChannel: channel, state: .failed, params: ["message": error.localizedDescription])
                }
            }
        }
    }

    private func restoreTapped() {
        guard let selectedChannel else {
            dispatchEvent(name: .restoreFailed, state: .failed, params: ["message": "No payment channel selected"])
            return
        }
        dispatchEvent(name: .restoreClick, paymentChannel: selectedChannel, state: .purchasing)
        Task {
            do {
                let result = try await sdk.restore(channel: selectedChannel)
                await MainActor.run {
                    self.dispatchEvent(
                        name: .restoreSuccess,
                        paymentChannel: result.channel,
                        state: .ready,
                        params: ["restored_count": result.purchases.filter(\.success).count, "message": result.message]
                    )
                }
            } catch {
                await MainActor.run {
                    self.dispatchEvent(name: .restoreFailed, paymentChannel: selectedChannel, state: .failed, params: ["message": error.localizedDescription])
                }
            }
        }
    }

    private func dispatchEvent(
        name: SubscriptionPageEventName,
        productId: String? = nil,
        paymentChannel: PaymentChannel? = nil,
        state: SubscriptionPageState? = nil,
        params: [String: Any?] = [:]
    ) {
        var values = params
        values["template_id"] = pageConfig.templateId
        values["scene"] = pageConfig.scene
        sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(
            name: name,
            productId: productId ?? selectedProduct?.marketProductId,
            paymentChannel: paymentChannel ?? selectedChannel,
            state: state,
            params: values
        ))
    }

    @objc private func closeTapped() {
        sdk.closeSubscriptionPage()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        dispatchEvent(name: .purchaseCancel, state: .cancelled)
        sdk.subscriptionPageWasDismissed()
    }
}

private final class ProductOptionCard: UIControl {
    private let theme: SubscriptionPageTheme
    private let radio = SelectionIndicatorView()
    private let purchaseBadge: String?

    init(product: Product, theme: SubscriptionPageTheme, image: UIImage?, purchaseBadge: String?) {
        self.theme = theme
        self.purchaseBadge = purchaseBadge
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = product.name.isEmpty ? product.marketProductId : product.name
        build(product: product, image: image)
        applySelection(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isSelected: Bool {
        didSet { applySelection(animated: oldValue != isSelected) }
    }

    private func build(product: Product, image: UIImage?) {
        let icon = UIImageView(image: image)
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        let content: UIView
        switch theme.id {
        case .aurora:
            icon.layer.cornerRadius = 16
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 76), icon.heightAnchor.constraint(equalToConstant: 76)])
            let row = UIStackView(arrangedSubviews: [radio, productCopy(product, layout: .feature), icon])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 12
            content = row
        case .midnight:
            icon.layer.cornerRadius = 22
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 58), icon.heightAnchor.constraint(equalToConstant: 58)])
            let row = UIStackView(arrangedSubviews: [radio, icon, productCopy(product, layout: .offer)])
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 11
            content = row
        case .minimal:
            icon.layer.cornerRadius = 8
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 46), icon.heightAnchor.constraint(equalToConstant: 46)])
            let row = UIStackView(arrangedSubviews: [radio, icon, productCopy(product, layout: .compact)])
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 10
            content = row
        }
        radio.widthAnchor.constraint(equalToConstant: 22).isActive = true
        addSubview(content)
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        let vertical: CGFloat = theme.id == .aurora ? 17 : 14
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical)
        ])
    }

    private enum CopyLayout { case feature, offer, compact }

    private func productCopy(_ product: Product, layout: CopyLayout) -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = layout == .compact ? 4 : 6
        let title = label(displayName(product), size: layout == .offer ? 20 : 17, color: theme.title, weight: .bold, lines: 2)
        let price = label(product.localizedPrice ?? product.price ?? "", size: layout == .offer ? 17 : 16, color: layout == .offer ? theme.primary : theme.title, weight: .bold, lines: 1)
        price.setContentHuggingPriority(.required, for: .horizontal)
        let badge = badgeLabel(badgeText(product))

        if layout == .offer {
            let top = UIStackView(arrangedSubviews: [badge, UIView(), price])
            top.axis = .horizontal
            top.alignment = .center
            top.spacing = 8
            column.addArrangedSubview(top)
            column.addArrangedSubview(title)
        } else {
            let top = UIStackView(arrangedSubviews: [title, price])
            top.axis = .horizontal
            top.alignment = .top
            top.spacing = 8
            column.addArrangedSubview(top)
            if layout == .feature { column.addArrangedSubview(badge) }
        }

        if !product.description.isEmpty {
            column.addArrangedSubview(label(product.description, size: layout == .compact ? 12 : 13, color: theme.muted, lines: layout == .feature ? 3 : 2))
        }
        if layout == .compact { column.addArrangedSubview(badge) }

        let metadata = [
            product.subscriptionPeriod.map { "Renews \($0)" },
            product.trialPeriod.map { "Trial \($0)" }
        ].compactMap { $0 }.joined(separator: "  •  ")
        if !metadata.isEmpty { column.addArrangedSubview(label(metadata, size: 12, color: theme.muted, lines: 2)) }
        column.addArrangedSubview(label(productValueLine(product), size: 12, color: theme.muted, weight: .semibold, lines: 2))
        if product.productType == .subscription, product.weeklyPointsEnabled, product.weeklyPoints > 0 {
            column.addArrangedSubview(label("\(product.weeklyPoints * 100) points every week", size: layout == .feature ? 13 : 12, color: theme.primary, weight: .bold, lines: 2))
        } else if let coins = product.coinsGranted, coins > 0 {
            column.addArrangedSubview(label("Get \(CoinAmountFormatter.displayText(coins)) credits after purchase", size: layout == .feature ? 13 : 12, color: theme.primary, weight: .bold, lines: 2))
        }
        return column
    }

    private func displayName(_ product: Product) -> String {
        product.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? product.marketProductId : product.name
    }

    private func badgeText(_ product: Product) -> String {
        if let purchaseBadge { return purchaseBadge }
        return switch product.productType {
        case .subscription: product.hasTrial ? "FREE TRIAL" : "MEMBERSHIP"
        case .consumable: "CREATION CREDITS"
        case .iap: "ONE TIME"
        case .unknown: "PRODUCT"
        }
    }

    private func productValueLine(_ product: Product) -> String {
        switch product.productType {
        case .subscription: "Premium access, renewed automatically"
        case .consumable: "Instant credits with no recurring charge"
        case .iap: "Unlock once and keep access"
        case .unknown: "Secure purchase through your app store"
        }
    }

    private func badgeLabel(_ value: String) -> UILabel {
        let badge = PaddingLabel(insets: UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8))
        badge.text = value
        badge.font = .boldSystemFont(ofSize: 10)
        badge.textColor = theme.primary
        badge.backgroundColor = theme.tagSurface
        badge.layer.cornerRadius = theme.id == .midnight ? 5 : 11
        badge.clipsToBounds = true
        badge.setContentHuggingPriority(.required, for: .horizontal)
        return badge
    }

    private func label(_ value: String, size: CGFloat, color: UIColor, weight: UIFont.Weight = .regular, lines: Int) -> UILabel {
        let label = UILabel()
        label.text = value
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = lines
        label.lineBreakMode = .byWordWrapping
        label.isHidden = value.isEmpty
        return label
    }

    private func applySelection(animated: Bool) {
        let changes = {
            self.backgroundColor = self.isSelected ? self.theme.selectedSurface : self.theme.surface
            self.layer.borderWidth = self.isSelected ? 2 : 1
            self.layer.borderColor = (self.isSelected ? self.theme.primary : self.theme.border).cgColor
            self.radio.color = self.theme.primary
            self.radio.selected = self.isSelected
            self.transform = self.isSelected ? .identity : CGAffineTransform(scaleX: 0.995, y: 0.995)
            self.alpha = self.isSelected ? 1 : 0.96
        }
        layer.cornerRadius = theme.id == .aurora ? 18 : (theme.id == .midnight ? 8 : 4)
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: changes)
        } else {
            changes()
        }
    }
}

private final class ChannelOptionCard: UIControl {
    private let theme: SubscriptionPageTheme
    private let radio = SelectionIndicatorView()

    init(channel: PaymentChannel, title: String, theme: SubscriptionPageTheme) {
        self.theme = theme
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button

        radio.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let iconName = channel == .appStore ? "apple.logo" : "creditcard.fill"
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.tintColor = theme.primary
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let label = UILabel()
        label.text = title
        label.textColor = theme.title
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.numberOfLines = 2
        let row = UIStackView(arrangedSubviews: [radio, icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 9
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 62)
        ])
        applySelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isSelected: Bool { didSet { applySelection() } }

    private func applySelection() {
        backgroundColor = isSelected ? theme.selectedSurface : theme.surface
        layer.cornerRadius = theme.id == .midnight ? 8 : (theme.id == .minimal ? 4 : 16)
        layer.borderWidth = isSelected ? 2 : 1
        layer.borderColor = (isSelected ? theme.primary : theme.border).cgColor
        radio.color = theme.primary
        radio.selected = isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

private final class SelectionIndicatorView: UIView {
    var color: UIColor = .systemBlue { didSet { setNeedsDisplay() } }
    var selected = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: 20, height: 20) }

    override func draw(_ rect: CGRect) {
        let bounds = CGRect(x: 2, y: (rect.height - 18) / 2, width: 18, height: 18)
        let stroke = selected ? color : UIColor(red: 139/255, green: 164/255, blue: 156/255, alpha: 1)
        stroke.setStroke()
        let outer = UIBezierPath(ovalIn: bounds)
        outer.lineWidth = 1.6
        outer.stroke()
        if selected {
            color.setFill()
            UIBezierPath(ovalIn: bounds.insetBy(dx: 4.5, dy: 4.5)).fill()
        }
    }
}

private final class PaddingLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}
#endif
