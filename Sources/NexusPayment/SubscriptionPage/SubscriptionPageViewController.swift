#if canImport(UIKit)
import NexusCoreUser
import UIKit

final class SubscriptionPageViewController: UIViewController, UIScrollViewDelegate, UIAdaptivePresentationControllerDelegate {
    private let sdk: NexusPayment
    private let pageConfig: SubscriptionPageConfig
    private var products: [Product] = []
    private var relatedProducts: [RelatedProduct] = []
    private var selectedProduct: Product?
    private var selectedChannel: PaymentChannel?
    private let stack = UIStackView()
    private let contentStack = UIStackView()
    private let statusLabel = UILabel()
    private var displayedChannels: [PaymentChannel] = []
    private var productButtons: [String: UIButton] = [:]
    private var channelButtons: [PaymentChannel: UIButton] = [:]
    private weak var relatedProductsScrollView: UIScrollView?
    private weak var relatedProductsPageControl: UIPageControl?
    private var relatedProductsCarouselStep: CGFloat = 0
    private var relatedProductsCurrentIndex = 0
    private var relatedProductsTimer: Timer?
    private let iconCache = NSCache<NSString, UIImage>()

    init(sdk: NexusPayment, config: SubscriptionPageConfig) {
        self.sdk = sdk
        self.pageConfig = config
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
        view.backgroundColor = .systemBackground
        buildSkeleton()
        buildFloatingCloseButton()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    private func buildSkeleton() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        stack.axis = .vertical
        stack.spacing = 14
        stack.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 24, right: 18)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .top
        header.spacing = 12

        let titleLabel = UILabel()
        titleLabel.text = pageConfig.title
        titleLabel.font = .boldSystemFont(ofSize: 28)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        header.addArrangedSubview(titleLabel)

        let closeButtonSpace = UIView()
        closeButtonSpace.widthAnchor.constraint(equalToConstant: 44).isActive = true
        header.addArrangedSubview(closeButtonSpace)
        stack.addArrangedSubview(header)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        stack.addArrangedSubview(contentStack)

        statusLabel.text = "Loading..."
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        contentStack.addArrangedSubview(statusLabel)
    }

    private func buildFloatingCloseButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 20
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.14
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

    private func loadData() {
        renderLoading()
        Task {
            do {
                let loadedProducts = try await sdk.getProducts(forceRefresh: true)
                let loadedRelated = (try? await sdk.getRelatedProducts(forceRefresh: true)) ?? []
                await MainActor.run {
                    products = loadedProducts
                    relatedProducts = loadedRelated
                    selectedProduct = products.first
                    do {
                        displayedChannels = try resolvedChannels()
                        selectedChannel = try resolvedInitialChannel()
                        if products.isEmpty {
                            renderEmpty()
                        } else {
                            render()
                        }
                    } catch {
                        renderError(error)
                    }
                }
            } catch {
                await MainActor.run {
                    renderError(error)
                }
            }
        }
    }

    private func render() {
        resetDynamicContent()
        if !pageConfig.benefitDescription.isEmpty {
            contentStack.addArrangedSubview(currentAppCard())
        }
        if !relatedProducts.isEmpty {
            contentStack.addArrangedSubview(sharedAppsSection())
        }

        contentStack.addArrangedSubview(sectionTitle("Products"))
        products.forEach { product in
            let button = radioButton(
                title: productDisplayName(product),
                detail: productDetail(product),
                selected: product.marketProductId == selectedProduct?.marketProductId
            )
            button.addAction(UIAction { [weak self] _ in
                self?.selectedProduct = product
                self?.dispatchEvent(name: .productSelect, productId: product.marketProductId, state: .ready)
                self?.updateProductSelection()
            }, for: .touchUpInside)
            productButtons[product.marketProductId] = button
            contentStack.addArrangedSubview(button)
        }

        if pageConfig.showPaymentChannel {
            contentStack.addArrangedSubview(sectionTitle("Payment Method"))
            displayedChannels.forEach { channel in
                let button = radioButton(title: channelDisplayName(channel), detail: "", selected: channel == selectedChannel)
                button.addAction(UIAction { [weak self] _ in
                    self?.selectedChannel = channel
                    self?.dispatchEvent(name: .channelSelect, paymentChannel: channel, state: .ready)
                    self?.updateChannelSelection()
                }, for: .touchUpInside)
                channelButtons[channel] = button
                contentStack.addArrangedSubview(button)
            }
        }

        let cta = UIButton(type: .system)
        cta.setTitle(pageConfig.ctaText, for: .normal)
        cta.titleLabel?.font = .boldSystemFont(ofSize: 17)
        cta.backgroundColor = .label
        cta.tintColor = .systemBackground
        cta.layer.cornerRadius = 8
        cta.heightAnchor.constraint(equalToConstant: 52).isActive = true
        cta.addAction(UIAction { [weak self] _ in self?.purchaseTapped() }, for: .touchUpInside)
        contentStack.addArrangedSubview(cta)
        addBottomActions()
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

    private func resetDynamicContent() {
        relatedProductsTimer?.invalidate()
        relatedProductsTimer = nil
        relatedProductsScrollView = nil
        relatedProductsPageControl = nil
        productButtons.removeAll()
        channelButtons.removeAll()
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func retryButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Retry", for: .normal)
        button.addAction(UIAction { [weak self] _ in self?.loadData() }, for: .touchUpInside)
        return button
    }

    private func resolvedChannels() throws -> [PaymentChannel] {
        let available = try sdk.getAvailableChannels()
        let resolved = try sdk.resolvePaymentChannel()
        let channels = pageConfig.paymentChannels.isEmpty ? resolved.enabledChannels : pageConfig.paymentChannels
        let invalid = channels.filter { !available.contains($0) }
        guard invalid.isEmpty else {
            throw PaymentError.invalidConfig(
                "Payment channel config error: \(invalid.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return channels
    }

    private func resolvedInitialChannel() throws -> PaymentChannel {
        if let configured = pageConfig.paymentChannels.first { return configured }
        return try sdk.resolvePaymentChannel().defaultChannel
    }

    private func addBottomActions() {
        guard pageConfig.showRestore || pageConfig.showTerms || pageConfig.showPrivacy else { return }
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12

        if pageConfig.showRestore {
            let restore = linkButton(title: pageConfig.restoreText)
            restore.addAction(UIAction { [weak self] _ in self?.restoreTapped() }, for: .touchUpInside)
            row.addArrangedSubview(restore)
        }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        if pageConfig.showTerms {
            let terms = linkButton(title: pageConfig.termsText)
            terms.addAction(UIAction { [weak self] _ in self?.openUrl(self?.pageConfig.termsUrl) }, for: .touchUpInside)
            row.addArrangedSubview(terms)
        }
        if pageConfig.showPrivacy {
            let privacy = linkButton(title: pageConfig.privacyText)
            privacy.addAction(UIAction { [weak self] _ in self?.openUrl(self?.pageConfig.privacyUrl) }, for: .touchUpInside)
            row.addArrangedSubview(privacy)
        }
        contentStack.addArrangedSubview(row)
    }

    private func linkButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.numberOfLines = 0
        return button
    }

    private func openUrl(_ value: String?) {
        guard let value, let url = URL(string: value) else { return }
        UIApplication.shared.open(url)
    }

    private func sharedAppsSection() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 12

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10

        let titleLabel = UILabel()
        titleLabel.text = pageConfig.sharedApps.title.uppercased()
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.textColor = UIColor(red: 17 / 255, green: 106 / 255, blue: 69 / 255, alpha: 1)
        titleLabel.numberOfLines = 0
        header.addArrangedSubview(titleLabel)

        let countLabel = UILabel()
        countLabel.text = "\(relatedProducts.count) apps included"
        countLabel.font = .boldSystemFont(ofSize: 14)
        countLabel.textColor = titleLabel.textColor
        countLabel.textAlignment = .center
        countLabel.backgroundColor = .systemBackground
        countLabel.layer.cornerRadius = 18
        countLabel.layer.borderWidth = 1
        countLabel.layer.borderColor = UIColor.separator.cgColor
        countLabel.clipsToBounds = true
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
        header.addArrangedSubview(countLabel)
        content.addArrangedSubview(header)

        if !pageConfig.sharedApps.description.isEmpty {
            let descriptionLabel = UILabel()
            descriptionLabel.text = pageConfig.sharedApps.description
            descriptionLabel.font = .systemFont(ofSize: 16)
            descriptionLabel.textColor = .secondaryLabel
            descriptionLabel.numberOfLines = 0
            content.addArrangedSubview(descriptionLabel)
        }

        let carousel = UIScrollView()
        carousel.showsHorizontalScrollIndicator = false
        carousel.alwaysBounceHorizontal = relatedProducts.count > 1
        carousel.decelerationRate = .fast
        carousel.delegate = self
        carousel.translatesAutoresizingMaskIntoConstraints = false

        let cards = UIStackView()
        cards.axis = .horizontal
        cards.alignment = .fill
        cards.spacing = 12
        cards.translatesAutoresizingMaskIntoConstraints = false
        carousel.addSubview(cards)

        let availableWidth = max(240, view.bounds.width - 72)
        let cardWidth = min(288, availableWidth)
        var cardHeight: CGFloat = 150
        relatedProducts.forEach { product in
            let productCard = sharedAppCard(product)
            productCard.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
            cards.addArrangedSubview(productCard)
            let fittingSize = productCard.systemLayoutSizeFitting(
                CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            cardHeight = max(cardHeight, ceil(fittingSize.height))
        }

        NSLayoutConstraint.activate([
            cards.leadingAnchor.constraint(equalTo: carousel.contentLayoutGuide.leadingAnchor),
            cards.trailingAnchor.constraint(equalTo: carousel.contentLayoutGuide.trailingAnchor),
            cards.topAnchor.constraint(equalTo: carousel.contentLayoutGuide.topAnchor),
            cards.bottomAnchor.constraint(equalTo: carousel.contentLayoutGuide.bottomAnchor),
            cards.heightAnchor.constraint(equalTo: carousel.frameLayoutGuide.heightAnchor),
            carousel.heightAnchor.constraint(equalToConstant: cardHeight)
        ])
        content.addArrangedSubview(carousel)

        let pageControl = UIPageControl()
        pageControl.numberOfPages = relatedProducts.count
        pageControl.currentPage = clampedRelatedProductsIndex(relatedProductsCurrentIndex)
        pageControl.currentPageIndicatorTintColor = titleLabel.textColor
        pageControl.pageIndicatorTintColor = UIColor(red: 181 / 255, green: 204 / 255, blue: 198 / 255, alpha: 1)
        pageControl.isUserInteractionEnabled = false
        content.addArrangedSubview(pageControl)

        let wrapper = UIView()
        wrapper.backgroundColor = UIColor(red: 235 / 255, green: 246 / 255, blue: 242 / 255, alpha: 1)
        wrapper.layer.cornerRadius = 18
        wrapper.layer.borderWidth = 1
        wrapper.layer.borderColor = UIColor.separator.cgColor
        wrapper.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14)
        ])

        relatedProductsScrollView = carousel
        relatedProductsPageControl = pageControl
        relatedProductsCarouselStep = cardWidth + cards.spacing
        DispatchQueue.main.async { [weak self, weak carousel] in
            guard let self, let carousel else { return }
            self.relatedProductsCurrentIndex = self.clampedRelatedProductsIndex(self.relatedProductsCurrentIndex)
            carousel.setContentOffset(
                CGPoint(x: CGFloat(self.relatedProductsCurrentIndex) * self.relatedProductsCarouselStep, y: 0),
                animated: false
            )
            self.relatedProductsPageControl?.currentPage = self.relatedProductsCurrentIndex
        }
        startRelatedProductsCarousel()
        return wrapper
    }

    private func sharedAppCard(_ product: RelatedProduct) -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 12

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 14

        let iconView = UIImageView(image: UIImage(systemName: "sparkles"))
        iconView.contentMode = .scaleAspectFill
        iconView.tintColor = UIColor(red: 1, green: 128 / 255, blue: 90 / 255, alpha: 1)
        iconView.backgroundColor = UIColor(red: 224 / 255, green: 241 / 255, blue: 236 / 255, alpha: 1)
        iconView.layer.cornerRadius = 14
        iconView.clipsToBounds = true
        iconView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 56).isActive = true
        header.addArrangedSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = product.productName
        titleLabel.font = .boldSystemFont(ofSize: 19)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        header.addArrangedSubview(titleLabel)
        content.addArrangedSubview(header)

        if !product.description.isEmpty {
            let descriptionLabel = UILabel()
            descriptionLabel.text = product.description
            descriptionLabel.font = .systemFont(ofSize: 16)
            descriptionLabel.textColor = .secondaryLabel
            descriptionLabel.numberOfLines = 0
            content.addArrangedSubview(descriptionLabel)
        }

        let wrapper = UIView()
        wrapper.backgroundColor = .systemBackground
        wrapper.layer.cornerRadius = 16
        wrapper.layer.borderWidth = 1
        wrapper.layer.borderColor = UIColor.separator.cgColor
        wrapper.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -16)
        ])
        loadIcon(product.icon, into: iconView)
        return wrapper
    }

    private func loadIcon(_ source: String, into imageView: UIImageView) {
        guard let url = URL(string: source), !source.isEmpty else { return }
        if let cached = iconCache.object(forKey: source as NSString) {
            imageView.image = cached
            return
        }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data)
            else { return }
            await MainActor.run {
                self.iconCache.setObject(image, forKey: source as NSString)
                imageView.image = image
            }
        }
    }

    private func startRelatedProductsCarousel() {
        relatedProductsTimer?.invalidate()
        guard relatedProducts.count > 1 else { return }
        relatedProductsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, let scrollView = self.relatedProductsScrollView else { return }
            self.relatedProductsCurrentIndex = (self.relatedProductsCurrentIndex + 1) % self.relatedProducts.count
            self.relatedProductsPageControl?.currentPage = self.relatedProductsCurrentIndex
            scrollView.setContentOffset(
                CGPoint(x: CGFloat(self.relatedProductsCurrentIndex) * self.relatedProductsCarouselStep, y: 0),
                animated: true
            )
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateRelatedProductsPage(for: scrollView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateRelatedProductsPage(for: scrollView)
    }

    private func updateRelatedProductsPage(for scrollView: UIScrollView) {
        guard scrollView === relatedProductsScrollView, relatedProductsCarouselStep > 0 else { return }
        relatedProductsCurrentIndex = clampedRelatedProductsIndex(
            Int(round(scrollView.contentOffset.x / relatedProductsCarouselStep))
        )
        relatedProductsPageControl?.currentPage = relatedProductsCurrentIndex
    }

    private func clampedRelatedProductsIndex(_ index: Int) -> Int {
        guard !relatedProducts.isEmpty else { return 0 }
        return min(max(index, 0), relatedProducts.count - 1)
    }

    private func updateProductSelection() {
        products.forEach { product in
            guard let button = productButtons[product.marketProductId] else { return }
            configureRadioButton(
                button,
                title: productDisplayName(product),
                detail: productDetail(product),
                selected: product.marketProductId == selectedProduct?.marketProductId
            )
        }
    }

    private func updateChannelSelection() {
        channelButtons.forEach { channel, button in
            configureRadioButton(
                button,
                title: channelDisplayName(channel),
                detail: "",
                selected: channel == selectedChannel
            )
        }
    }

    private func productDetail(_ product: Product) -> String {
        var lines: [String] = []
        if !product.description.isEmpty {
            lines.append(product.description)
        }
        let metadata = [
            product.localizedPrice ?? product.price,
            product.subscriptionPeriod,
            product.hasTrial ? "trial" : nil
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !metadata.isEmpty {
            lines.append(metadata)
        }
        if let coins = product.coinsGranted, coins > 0 {
            lines.append("Get \(coins) coins after purchase")
        }
        return lines.joined(separator: "\n")
    }

    private func productDisplayName(_ product: Product) -> String {
        let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? product.marketProductId : name
    }

    private func currentAppCard() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 12

        let heading = UILabel()
        heading.text = "CURRENT APP UNLOCKED"
        heading.font = .boldSystemFont(ofSize: 18)
        heading.textColor = UIColor(red: 17 / 255, green: 106 / 255, blue: 69 / 255, alpha: 1)
        heading.numberOfLines = 0
        content.addArrangedSubview(heading)

        let description = UILabel()
        description.text = pageConfig.benefitDescription
        description.font = .systemFont(ofSize: 17)
        description.textColor = .secondaryLabel
        description.numberOfLines = 0
        content.addArrangedSubview(description)

        let benefits = pageConfig.benefits.filter { !$0.isEmpty }
        if !benefits.isEmpty {
            let scrollView = UIScrollView()
            scrollView.showsHorizontalScrollIndicator = false
            let tags = UIStackView()
            tags.axis = .horizontal
            tags.spacing = 8
            tags.translatesAutoresizingMaskIntoConstraints = false
            benefits.forEach { value in
                let label = PaddingLabel(insets: UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12))
                label.text = value
                label.font = .boldSystemFont(ofSize: 13)
                label.textColor = heading.textColor
                label.backgroundColor = UIColor(red: 235 / 255, green: 246 / 255, blue: 242 / 255, alpha: 1)
                label.layer.cornerRadius = 16
                label.clipsToBounds = true
                tags.addArrangedSubview(label)
            }
            scrollView.addSubview(tags)
            NSLayoutConstraint.activate([
                tags.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                tags.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                tags.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                tags.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                tags.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
                scrollView.heightAnchor.constraint(equalToConstant: 34)
            ])
            content.addArrangedSubview(scrollView)
        }

        let wrapper = UIView()
        wrapper.backgroundColor = .systemBackground
        wrapper.layer.cornerRadius = 16
        wrapper.layer.borderWidth = 1
        wrapper.layer.borderColor = UIColor.separator.cgColor
        wrapper.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -16)
        ])
        return wrapper
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

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 18)
        return label
    }

    private func radioButton(title: String, detail: String, selected: Bool) -> UIButton {
        let button = UIButton(type: .system)
        configureRadioButton(button, title: title, detail: detail, selected: selected)
        return button
    }

    private func configureRadioButton(
        _ button: UIButton,
        title: String,
        detail: String,
        selected: Bool
    ) {
        var config = UIButton.Configuration.plain()
        config.title = "\(selected ? "●" : "○") \(title)"
        config.subtitle = detail.isEmpty ? nil : detail
        config.titleAlignment = .leading
        config.titleLineBreakMode = .byWordWrapping
        config.subtitleLineBreakMode = .byWordWrapping
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.layer.cornerRadius = 8
        button.layer.borderWidth = selected ? 2 : 1
        button.layer.borderColor = selected ? UIColor.label.cgColor : UIColor.separator.cgColor
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
                    dispatchEvent(
                        name: result.success ? .purchaseSuccess : .purchaseFailed,
                        productId: product.marketProductId,
                        paymentChannel: result.channel,
                        state: result.success ? .success : .failed,
                        params: ["order_id": result.orderId, "message": result.message]
                    )
                }
            } catch {
                await MainActor.run {
                    dispatchEvent(name: .purchaseFailed, productId: product.marketProductId, paymentChannel: channel, state: .failed, params: ["message": error.localizedDescription])
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
                    dispatchEvent(
                        name: .restoreSuccess,
                        paymentChannel: result.channel,
                        state: .ready,
                        params: ["restored_count": result.purchases.filter(\.success).count, "message": result.message]
                    )
                }
            } catch {
                await MainActor.run {
                    dispatchEvent(name: .restoreFailed, paymentChannel: selectedChannel, state: .failed, params: ["message": error.localizedDescription])
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

private final class PaddingLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}
#endif
