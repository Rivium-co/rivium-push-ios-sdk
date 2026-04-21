import UIKit

/// View for displaying in-app messages
public class InAppMessageView: UIView {
    private let message: InAppMessage
    private let content: InAppMessageContent
    private var onButtonClick: ((InAppButton) -> Void)?
    private var onDismiss: (() -> Void)?

    private let containerView = UIView()
    private let contentStackView = UIStackView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let buttonsStackView = UIStackView()
    private let closeButton = UIButton(type: .system)

    // MARK: - Initialization

    public init(message: InAppMessage, content: InAppMessageContent) {
        self.message = message
        self.content = content
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Methods

    public static func show(
        in viewController: UIViewController,
        message: InAppMessage,
        content: InAppMessageContent,
        onButtonClick: @escaping (InAppButton) -> Void,
        onDismiss: @escaping () -> Void
    ) -> InAppMessageView {
        let view = InAppMessageView(message: message, content: content)
        view.onButtonClick = onButtonClick
        view.onDismiss = onDismiss

        view.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            view.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            view.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ])

        view.animateIn()
        return view
    }

    public func dismiss() {
        animateOut { [weak self] in
            self?.removeFromSuperview()
        }
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(0.5)

        // Add tap gesture to dismiss on background tap (for modal only)
        if message.type == .modal {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
            tapGesture.delegate = self
            addGestureRecognizer(tapGesture)
        }

        setupContainer()
        setupContent()
        setupButtons()
        setupCloseButton()

        // Load image if present
        if let imageUrl = content.imageUrl, let url = URL(string: imageUrl) {
            loadImage(from: url)
        }
    }

    private func setupContainer() {
        containerView.backgroundColor = parseColor(content.backgroundColor) ?? .white
        containerView.layer.cornerRadius = 16
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOpacity = 0.2
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(containerView)

        switch message.type {
        case .modal, .card:
            NSLayoutConstraint.activate([
                containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
                containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
                containerView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.9),
                containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
            ])
        case .banner:
            NSLayoutConstraint.activate([
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                containerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16)
            ])
        case .fullscreen:
            NSLayoutConstraint.activate([
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                containerView.topAnchor.constraint(equalTo: topAnchor),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            containerView.layer.cornerRadius = 0
        }
    }

    private func setupContent() {
        contentStackView.axis = .vertical
        contentStackView.spacing = 12
        contentStackView.alignment = .fill
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(contentStackView)

        let padding: CGFloat = message.type == .banner ? 16 : 24

        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            contentStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            contentStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
            contentStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -padding)
        ])

        // Image view
        if content.imageUrl != nil {
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 8
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.heightAnchor.constraint(equalToConstant: 150).isActive = true
            contentStackView.addArrangedSubview(imageView)
        }

        // Title
        titleLabel.text = content.title
        titleLabel.font = .boldSystemFont(ofSize: message.type == .banner ? 16 : 20)
        titleLabel.textColor = parseColor(content.textColor) ?? .black
        titleLabel.numberOfLines = 0
        contentStackView.addArrangedSubview(titleLabel)

        // Body
        bodyLabel.text = content.body
        bodyLabel.font = .systemFont(ofSize: message.type == .banner ? 14 : 16)
        bodyLabel.textColor = parseColor(content.textColor)?.withAlphaComponent(0.8) ?? .darkGray
        bodyLabel.numberOfLines = 0
        contentStackView.addArrangedSubview(bodyLabel)
    }

    private func setupButtons() {
        guard !content.buttons.isEmpty else { return }

        buttonsStackView.axis = content.buttons.count > 2 ? .vertical : .horizontal
        buttonsStackView.spacing = 12
        buttonsStackView.distribution = .fillEqually
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false

        for (index, buttonConfig) in content.buttons.enumerated() {
            let button = createButton(for: buttonConfig, index: index)
            buttonsStackView.addArrangedSubview(button)
        }

        contentStackView.addArrangedSubview(buttonsStackView)
    }

    private func createButton(for config: InAppButton, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(config.text, for: .normal)
        button.tag = index
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)

        switch config.style {
        case .primary:
            button.backgroundColor = .systemBlue
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .boldSystemFont(ofSize: 16)
        case .secondary:
            button.backgroundColor = .systemGray5
            button.setTitleColor(.systemBlue, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16)
        case .text:
            button.backgroundColor = .clear
            button.setTitleColor(.systemBlue, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16)
        case .destructive:
            button.backgroundColor = .systemRed
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .boldSystemFont(ofSize: 16)
        }

        return button
    }

    private func setupCloseButton() {
        guard message.type != .banner else { return }

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = parseColor(content.textColor)?.withAlphaComponent(0.5) ?? .gray
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        containerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    // MARK: - Actions

    @objc private func buttonTapped(_ sender: UIButton) {
        let buttonConfig = content.buttons[sender.tag]
        onButtonClick?(buttonConfig)
    }

    @objc private func closeTapped() {
        dismiss()
        onDismiss?()
    }

    @objc private func backgroundTapped() {
        dismiss()
        onDismiss?()
    }

    // MARK: - Animation

    private func animateIn() {
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        alpha = 0

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.alpha = 1
            self.containerView.alpha = 1
            self.containerView.transform = .identity
        }
    }

    private func animateOut(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.2) {
            self.alpha = 0
            self.containerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        } completion: { _ in
            completion()
        }
    }

    // MARK: - Helpers

    private func parseColor(_ hex: String?) -> UIColor? {
        guard let hex = hex else { return nil }

        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.imageView.image = image
            }
        }.resume()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension InAppMessageView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only handle taps on the background, not the container
        return touch.view == self
    }
}
