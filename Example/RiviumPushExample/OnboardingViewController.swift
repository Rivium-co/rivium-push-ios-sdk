import UIKit

class OnboardingViewController: UIViewController, UITextFieldDelegate {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let apiKeyField = UITextField()
    private let userIdField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()

        // Tap anywhere to dismiss keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == apiKeyField {
            userIdField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 60),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -32),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -64),
        ])

        // Logo
        let iconBg = UIView()
        iconBg.backgroundColor = UIColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 0.12)
        iconBg.layer.cornerRadius = 32
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "bell.badge.fill"))
        icon.tintColor = UIColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 1)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(icon)
        NSLayoutConstraint.activate([
            iconBg.widthAnchor.constraint(equalToConstant: 64),
            iconBg.heightAnchor.constraint(equalToConstant: 64),
            icon.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
        ])
        stack.addArrangedSubview(iconBg)

        // Title
        let title = UILabel()
        title.text = "Rivium Push"
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textAlignment = .center
        stack.addArrangedSubview(title)

        // Subtitle
        let subtitle = UILabel()
        subtitle.text = "Real-time push notifications\nfor your mobile apps"
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        stack.addArrangedSubview(subtitle)

        stack.addArrangedSubview(makeSpacer(20))

        // Steps
        let stepsCard = UIView()
        stepsCard.backgroundColor = .secondarySystemBackground
        stepsCard.layer.cornerRadius = 12
        stepsCard.translatesAutoresizingMaskIntoConstraints = false

        let stepsStack = UIStackView()
        stepsStack.axis = .vertical
        stepsStack.spacing = 12
        stepsStack.translatesAutoresizingMaskIntoConstraints = false
        stepsCard.addSubview(stepsStack)
        NSLayoutConstraint.activate([
            stepsStack.topAnchor.constraint(equalTo: stepsCard.topAnchor, constant: 16),
            stepsStack.leadingAnchor.constraint(equalTo: stepsCard.leadingAnchor, constant: 16),
            stepsStack.trailingAnchor.constraint(equalTo: stepsCard.trailingAnchor, constant: -16),
            stepsStack.bottomAnchor.constraint(equalTo: stepsCard.bottomAnchor, constant: -16),
        ])

        stepsStack.addArrangedSubview(makeStep("1", "Sign up at console.rivium.co", "person.badge.plus"))
        stepsStack.addArrangedSubview(makeStep("2", "Create a project and get your API key", "key.fill"))
        stepsStack.addArrangedSubview(makeStep("3", "Paste your API key below", "doc.on.clipboard"))
        stepsStack.addArrangedSubview(makeStep("4", "Send your first push notification!", "bell.fill"))

        stack.addArrangedSubview(stepsCard)
        stepsCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Open Console button
        let consoleBtn = UIButton(type: .system)
        consoleBtn.setTitle("  Open Rivium Console", for: .normal)
        consoleBtn.setImage(UIImage(systemName: "safari"), for: .normal)
        consoleBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        consoleBtn.tintColor = UIColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 1)
        consoleBtn.addTarget(self, action: #selector(openConsole), for: .touchUpInside)
        stack.addArrangedSubview(consoleBtn)

        stack.addArrangedSubview(makeSpacer(8))

        // API Key field
        let keyLabel = UILabel()
        keyLabel.text = "API Key"
        keyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        keyLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(keyLabel)
        keyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        apiKeyField.placeholder = "rv_live_xxxxxxxxxxxxxxxx"
        apiKeyField.borderStyle = .roundedRect
        apiKeyField.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        apiKeyField.autocorrectionType = .no
        apiKeyField.autocapitalizationType = .none
        apiKeyField.returnKeyType = .next
        apiKeyField.delegate = self
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.heightAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(apiKeyField)
        apiKeyField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // User ID field (optional)
        let userLabel = UILabel()
        userLabel.text = "User ID (optional)"
        userLabel.font = .systemFont(ofSize: 13, weight: .medium)
        userLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(userLabel)
        userLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        userIdField.placeholder = "e.g. user_123"
        userIdField.borderStyle = .roundedRect
        userIdField.font = .systemFont(ofSize: 14)
        userIdField.autocorrectionType = .no
        userIdField.autocapitalizationType = .none
        userIdField.returnKeyType = .done
        userIdField.delegate = self
        userIdField.translatesAutoresizingMaskIntoConstraints = false
        userIdField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(userIdField)
        userIdField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.addArrangedSubview(makeSpacer(8))

        // Connect button
        let connectBtn = UIButton(type: .system)
        connectBtn.setTitle("Connect", for: .normal)
        connectBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        connectBtn.backgroundColor = UIColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 1)
        connectBtn.setTitleColor(.white, for: .normal)
        connectBtn.layer.cornerRadius = 12
        connectBtn.translatesAutoresizingMaskIntoConstraints = false
        connectBtn.heightAnchor.constraint(equalToConstant: 50).isActive = true
        connectBtn.addTarget(self, action: #selector(connect), for: .touchUpInside)
        stack.addArrangedSubview(connectBtn)
        connectBtn.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: - Actions

    @objc private func openConsole() {
        if let url = URL(string: "https://console.rivium.co") {
            UIApplication.shared.open(url)
        }
    }

    @objc private func connect() {
        let key = apiKeyField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            shake(apiKeyField)
            return
        }

        AppDelegate.savedApiKey = key
        let userId = userIdField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let userId = userId, !userId.isEmpty {
            AppDelegate.savedUserId = userId
        }

        AppDelegate.initializeSDK()

        // Transition to main app
        guard let window = view.window else { return }
        let sceneDelegate = window.windowScene?.delegate as? SceneDelegate
        sceneDelegate?.showMainApp()
    }

    private func shake(_ view: UIView) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.4
        animation.values = [-8, 8, -6, 6, -4, 4, 0]
        view.layer.add(animation, forKey: "shake")
    }

    private func makeStep(_ number: String, _ text: String, _ icon: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        let badge = UILabel()
        badge.text = number
        badge.font = .systemFont(ofSize: 13, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = UIColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 1)
        badge.layer.cornerRadius = 12
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 24).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        label.numberOfLines = 0

        row.addArrangedSubview(badge)
        row.addArrangedSubview(label)
        return row
    }

    private func makeSpacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }
}
