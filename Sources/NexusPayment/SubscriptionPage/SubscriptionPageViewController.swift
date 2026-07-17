#if canImport(UIKit)
import NexusCoreUser
import UIKit

final class SubscriptionPageViewController: UIViewController {
    private let sdk: NexusPayment
    private let pageConfig: SubscriptionPageConfig
    private var products: [Product] = []
    private var relatedProducts: [RelatedProduct] = []
    private var selectedProduct: Product?
    private var selectedChannel: PaymentChannel?
    private let stack = UIStackView()
    private let statusLabel = UILabel()

    init(sdk: NexusPayment, config: SubscriptionPageConfig) {
        self.sdk = sdk
        self.pageConfig = config
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pageConfig.title
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        buildSkeleton()
        loadData()
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

        statusLabel.text = "Loading..."
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        stack.addArrangedSubview(statusLabel)
    }

    private func loadData() {
        Task {
            do {
                async let loadedProducts = sdk.getProducts(forceRefresh: true)
                async let loadedRelated = sdk.getRelatedProducts(forceRefresh: true)
                let values = try await (loadedProducts, loadedRelated)
                await MainActor.run {
                    products = values.0
                    relatedProducts = values.1
                    selectedProduct = products.first
                    selectedChannel = pageConfig.paymentChannels.first ?? (try? sdk.getAvailableChannels().first) ?? .appStore
                    render()
                    sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .pageShow, state: .ready))
                }
            } catch {
                await MainActor.run {
                    statusLabel.text = error.localizedDescription
                    sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .purchaseFailed, state: .failed, params: ["message": error.localizedDescription]))
                }
            }
        }
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(card(title: pageConfig.benefitDescription, detail: pageConfig.benefits.joined(separator: "  ")))
        if !relatedProducts.isEmpty {
            stack.addArrangedSubview(sectionTitle(pageConfig.sharedApps.title))
            relatedProducts.forEach {
                stack.addArrangedSubview(card(title: $0.productName, detail: $0.description))
            }
        }

        stack.addArrangedSubview(sectionTitle("Products"))
        products.forEach { product in
            let button = radioButton(
                title: product.name,
                detail: productDetail(product),
                selected: product.marketProductId == selectedProduct?.marketProductId
            )
            button.addAction(UIAction { [weak self] _ in
                self?.selectedProduct = product
                self?.sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .productSelect, productId: product.marketProductId, state: .ready))
                self?.render()
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        if pageConfig.showPaymentChannel {
            stack.addArrangedSubview(sectionTitle("Payment Method"))
            let channels = pageConfig.paymentChannels.isEmpty ? ((try? sdk.getAvailableChannels()) ?? []) : pageConfig.paymentChannels
            channels.forEach { channel in
                let button = radioButton(title: channel.rawValue, detail: "", selected: channel == selectedChannel)
                button.addAction(UIAction { [weak self] _ in
                    self?.selectedChannel = channel
                    self?.sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .channelSelect, paymentChannel: channel, state: .ready))
                    self?.render()
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
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
        stack.addArrangedSubview(cta)

        if pageConfig.showRestore {
            let restore = UIButton(type: .system)
            restore.setTitle(pageConfig.restoreText, for: .normal)
            restore.addAction(UIAction { [weak self] _ in self?.restoreTapped() }, for: .touchUpInside)
            stack.addArrangedSubview(restore)
        }
    }

    private func productDetail(_ product: Product) -> String {
        [
            product.localizedPrice ?? product.price,
            product.coinsGranted.map { "\($0) coins" },
            product.subscriptionPeriod,
            product.hasTrial ? "trial" : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private func card(title: String, detail: String) -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.text = detail.isEmpty ? title : "\(title)\n\(detail)"
        label.font = .systemFont(ofSize: 15)
        let wrapper = UIView()
        wrapper.backgroundColor = .secondarySystemBackground
        wrapper.layer.cornerRadius = 8
        wrapper.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12)
        ])
        return wrapper
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 18)
        return label
    }

    private func radioButton(title: String, detail: String, selected: Bool) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = "\(selected ? "●" : "○") \(title)"
        config.subtitle = detail
        config.titleAlignment = .leading
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.layer.cornerRadius = 8
        button.layer.borderWidth = selected ? 2 : 1
        button.layer.borderColor = selected ? UIColor.label.cgColor : UIColor.separator.cgColor
        return button
    }

    private func purchaseTapped() {
        guard let product = selectedProduct else { return }
        let channel = selectedChannel
        sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .purchaseClick, productId: product.marketProductId, paymentChannel: channel, state: .purchasing))
        Task {
            do {
                let result = try await sdk.purchase(product: product, channel: channel)
                await MainActor.run {
                    sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(
                        name: result.success ? .purchaseSuccess : .purchaseFailed,
                        productId: product.marketProductId,
                        paymentChannel: result.channel,
                        state: result.success ? .success : .failed,
                        params: ["order_id": result.orderId, "message": result.message]
                    ))
                    if result.success { dismiss(animated: true) }
                }
            } catch {
                await MainActor.run {
                    sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .purchaseFailed, productId: product.marketProductId, paymentChannel: channel, state: .failed, params: ["message": error.localizedDescription]))
                }
            }
        }
    }

    private func restoreTapped() {
        sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .restoreClick, paymentChannel: selectedChannel, state: .loading))
        Task {
            do {
                let result = try await sdk.restore(channel: selectedChannel ?? .appStore)
                await MainActor.run {
                    sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .restoreSuccess, paymentChannel: result.channel, state: .success, params: ["count": result.purchases.count]))
                }
            } catch {
                await MainActor.run {
                    sdk.dispatchSubscriptionPageEvent(SubscriptionPageEvent(name: .restoreFailed, paymentChannel: selectedChannel, state: .failed, params: ["message": error.localizedDescription]))
                }
            }
        }
    }

    @objc private func closeTapped() {
        sdk.closeSubscriptionPage()
    }
}
#endif
