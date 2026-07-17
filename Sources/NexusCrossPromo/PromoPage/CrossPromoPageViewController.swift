#if canImport(UIKit)
import UIKit

final class CrossPromoPageViewController: UIViewController {
    private let sdk: NexusCrossPromo
    private let options: ShowPromoPageOptions
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private var products: [CrossPromoProduct] = []

    init(sdk: NexusCrossPromo, options: ShowPromoPageOptions) {
        self.sdk = sdk
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = options.title
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        buildLayout()
        loadProducts()
    }

    private func buildLayout() {
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

        if !options.description.isEmpty {
            stack.addArrangedSubview(descriptionCard(options.description))
        }
        statusLabel.text = "Loading..."
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        stack.addArrangedSubview(statusLabel)
    }

    private func loadProducts() {
        Task {
            do {
                let values = try await sdk.getProductsForDisplay(forceRefresh: true)
                await MainActor.run {
                    products = values
                    render()
                }
            } catch {
                await MainActor.run {
                    statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if !options.description.isEmpty {
            stack.addArrangedSubview(descriptionCard(options.description))
        }
        if products.isEmpty {
            statusLabel.text = "No recommendations"
            stack.addArrangedSubview(statusLabel)
            return
        }
        products.forEach { product in
            stack.addArrangedSubview(productCard(product))
        }
    }

    private func descriptionCard(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
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

    private func productCard(_ product: CrossPromoProduct) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = product.title
        config.subtitle = product.description
        config.titleAlignment = .leading
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Task {
                _ = try? await self.sdk.openProduct(OpenProductOptions(
                    productId: product.productId,
                    placement: self.options.placement,
                    campaign: self.options.campaign
                ))
            }
        }, for: .touchUpInside)
        return button
    }

    @objc private func closeTapped() {
        sdk.closePromoPage()
    }
}
#endif
