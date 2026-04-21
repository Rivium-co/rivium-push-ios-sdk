import UIKit
import RiviumPush

class InAppMessagesViewController: UIViewController {

    // MARK: - UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let triggerCard = CardView()
    private let appOpenButton = UIButton(type: .system)
    private let sessionStartButton = UIButton(type: .system)
    private let eventTextField = UITextField()
    private let triggerEventButton = UIButton(type: .system)

    private let messagesCard = CardView()
    private let messagesTableView = UITableView()
    private let refreshButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let emptyStateLabel = UILabel()

    private let infoCard = CardView()

    private var messages: [InAppMessage] = []
    private var isLoading = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        fetchMessages()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Set this view controller for in-app message display
        RiviumPush.shared.setCurrentViewController(self)
    }

    // MARK: - Setup
    private func setupUI() {
        title = "In-App Messages"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(fetchMessages)
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        setupTriggerCard()
        setupMessagesCard()
        setupInfoCard()
    }

    private func setupTriggerCard() {
        triggerCard.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(triggerCard)

        let headerStack = createCardHeader(icon: "play.fill", title: "Trigger Events")

        let descLabel = UILabel()
        descLabel.text = "Trigger in-app messages based on events:"
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = UIStackView()
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        configureButton(appOpenButton, title: "App Open", color: .systemBlue)
        appOpenButton.addTarget(self, action: #selector(triggerAppOpen), for: .touchUpInside)

        configureButton(sessionStartButton, title: "Session Start", color: .systemBlue)
        sessionStartButton.addTarget(self, action: #selector(triggerSessionStart), for: .touchUpInside)

        buttonStack.addArrangedSubview(appOpenButton)
        buttonStack.addArrangedSubview(sessionStartButton)

        eventTextField.placeholder = "e.g., purchase_complete, level_up"
        eventTextField.borderStyle = .roundedRect
        eventTextField.translatesAutoresizingMaskIntoConstraints = false

        let eventLabel = UILabel()
        eventLabel.text = "Custom Event Name"
        eventLabel.font = .systemFont(ofSize: 12)
        eventLabel.textColor = .secondaryLabel
        eventLabel.translatesAutoresizingMaskIntoConstraints = false

        configureButton(triggerEventButton, title: "Trigger Custom Event", color: .systemBlue)
        triggerEventButton.addTarget(self, action: #selector(triggerCustomEvent), for: .touchUpInside)

        let divider = createDivider()

        triggerCard.addSubview(headerStack)
        triggerCard.addSubview(divider)
        triggerCard.addSubview(descLabel)
        triggerCard.addSubview(buttonStack)
        triggerCard.addSubview(eventLabel)
        triggerCard.addSubview(eventTextField)
        triggerCard.addSubview(triggerEventButton)

        NSLayoutConstraint.activate([
            triggerCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            triggerCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            triggerCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            headerStack.topAnchor.constraint(equalTo: triggerCard.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: triggerCard.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: triggerCard.trailingAnchor, constant: -16),

            divider.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: triggerCard.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: triggerCard.trailingAnchor, constant: -16),

            descLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            descLabel.leadingAnchor.constraint(equalTo: triggerCard.leadingAnchor, constant: 16),
            descLabel.trailingAnchor.constraint(equalTo: triggerCard.trailingAnchor, constant: -16),

            buttonStack.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 12),
            buttonStack.leadingAnchor.constraint(equalTo: triggerCard.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: triggerCard.trailingAnchor, constant: -16),

            eventLabel.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 16),
            eventLabel.leadingAnchor.constraint(equalTo: triggerCard.leadingAnchor, constant: 16),

            eventTextField.topAnchor.constraint(equalTo: eventLabel.bottomAnchor, constant: 4),
            eventTextField.leadingAnchor.constraint(equalTo: triggerCard.leadingAnchor, constant: 16),
            eventTextField.trailingAnchor.constraint(equalTo: triggerCard.trailingAnchor, constant: -16),
            eventTextField.heightAnchor.constraint(equalToConstant: 44),

            triggerEventButton.topAnchor.constraint(equalTo: eventTextField.bottomAnchor, constant: 12),
            triggerEventButton.leadingAnchor.constraint(equalTo: triggerCard.leadingAnchor, constant: 16),
            triggerEventButton.trailingAnchor.constraint(equalTo: triggerCard.trailingAnchor, constant: -16),
            triggerEventButton.bottomAnchor.constraint(equalTo: triggerCard.bottomAnchor, constant: -16)
        ])
    }

    private func setupMessagesCard() {
        messagesCard.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(messagesCard)

        let headerStack = createCardHeader(icon: "message.fill", title: "Available Messages")

        let divider = createDivider()

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true

        emptyStateLabel.text = "No in-app messages\nCreate one in the console"
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.font = .systemFont(ofSize: 14)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.isHidden = true

        messagesTableView.translatesAutoresizingMaskIntoConstraints = false
        messagesTableView.delegate = self
        messagesTableView.dataSource = self
        messagesTableView.register(MessageCell.self, forCellReuseIdentifier: "MessageCell")
        messagesTableView.isScrollEnabled = false
        messagesTableView.separatorStyle = .none

        messagesCard.addSubview(headerStack)
        messagesCard.addSubview(divider)
        messagesCard.addSubview(loadingIndicator)
        messagesCard.addSubview(emptyStateLabel)
        messagesCard.addSubview(messagesTableView)

        NSLayoutConstraint.activate([
            messagesCard.topAnchor.constraint(equalTo: triggerCard.bottomAnchor, constant: 16),
            messagesCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            messagesCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            headerStack.topAnchor.constraint(equalTo: messagesCard.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: messagesCard.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: messagesCard.trailingAnchor, constant: -16),

            divider.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: messagesCard.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: messagesCard.trailingAnchor, constant: -16),

            loadingIndicator.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 32),
            loadingIndicator.centerXAnchor.constraint(equalTo: messagesCard.centerXAnchor),

            emptyStateLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 32),
            emptyStateLabel.centerXAnchor.constraint(equalTo: messagesCard.centerXAnchor),
            emptyStateLabel.bottomAnchor.constraint(equalTo: messagesCard.bottomAnchor, constant: -32),

            messagesTableView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            messagesTableView.leadingAnchor.constraint(equalTo: messagesCard.leadingAnchor),
            messagesTableView.trailingAnchor.constraint(equalTo: messagesCard.trailingAnchor),
            messagesTableView.bottomAnchor.constraint(equalTo: messagesCard.bottomAnchor, constant: -8),
            messagesTableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
    }

    private func setupInfoCard() {
        infoCard.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoCard)

        let headerStack = createCardHeader(icon: "info.circle", title: "Message Types")
        let divider = createDivider()

        let types = [
            ("square", "Modal", "Centered dialog with overlay", UIColor.systemBlue),
            ("minus", "Banner", "Top or bottom banner", UIColor.systemGreen),
            ("arrow.up.left.and.arrow.down.right", "Fullscreen", "Full screen takeover", UIColor.systemPurple),
            ("creditcard", "Card", "Floating card style", UIColor.systemOrange)
        ]

        let typeStack = UIStackView()
        typeStack.axis = .vertical
        typeStack.spacing = 8
        typeStack.translatesAutoresizingMaskIntoConstraints = false

        for (icon, title, desc, color) in types {
            let row = createInfoRow(icon: icon, title: title, description: desc, color: color)
            typeStack.addArrangedSubview(row)
        }

        infoCard.addSubview(headerStack)
        infoCard.addSubview(divider)
        infoCard.addSubview(typeStack)

        NSLayoutConstraint.activate([
            infoCard.topAnchor.constraint(equalTo: messagesCard.bottomAnchor, constant: 16),
            infoCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            infoCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            infoCard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            headerStack.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),

            divider.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),

            typeStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            typeStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            typeStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),
            typeStack.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Helpers
    private func createCardHeader(icon: String, title: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 16)

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)

        return stack
    }

    private func createDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func createInfoRow(icon: String, title: String, description: String, color: UIColor) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconBg = UIView()
        iconBg.backgroundColor = color.withAlphaComponent(0.15)
        iconBg.layer.cornerRadius = 18
        iconBg.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = description
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconBg)
        iconBg.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(descLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 50),

            iconBg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconBg.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 36),
            iconBg.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),

            descLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2)
        ])

        return container
    }

    private func configureButton(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.backgroundColor = color
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func updateMessagesUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if self.isLoading {
                self.loadingIndicator.startAnimating()
                self.emptyStateLabel.isHidden = true
                self.messagesTableView.isHidden = true
            } else {
                self.loadingIndicator.stopAnimating()
                if self.messages.isEmpty {
                    self.emptyStateLabel.isHidden = false
                    self.messagesTableView.isHidden = true
                } else {
                    self.emptyStateLabel.isHidden = true
                    self.messagesTableView.isHidden = false
                    self.messagesTableView.reloadData()

                    // Update table height
                    let height = CGFloat(self.messages.count * 70)
                    self.messagesTableView.constraints.first { $0.firstAttribute == .height }?.constant = height
                }
            }
        }
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            alert.dismiss(animated: true)
        }
    }

    // MARK: - Actions
    @objc private func fetchMessages() {
        isLoading = true
        updateMessagesUI()

        RiviumPush.shared.fetchInAppMessages { [weak self] messages in
            DispatchQueue.main.async {
                self?.messages = messages
                self?.isLoading = false
                self?.updateMessagesUI()
            }
        }
    }

    @objc private func triggerAppOpen() {
        RiviumPush.shared.triggerInAppOnAppOpen()
        showToast("Triggered: App Open")
    }

    @objc private func triggerSessionStart() {
        RiviumPush.shared.triggerInAppOnSessionStart()
        showToast("Triggered: Session Start")
    }

    @objc private func triggerCustomEvent() {
        guard let event = eventTextField.text, !event.isEmpty else { return }
        RiviumPush.shared.triggerInAppEvent(event)
        showToast("Triggered: \(event)")
        eventTextField.resignFirstResponder()
    }
}

// MARK: - UITableViewDelegate & DataSource
extension InAppMessagesViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as! MessageCell
        cell.configure(with: messages[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let message = messages[indexPath.row]
        RiviumPush.shared.showInAppMessage(message.id)
    }
}

// MARK: - MessageCell
class MessageCell: UITableViewCell {
    private let iconBg = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let triggerLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        iconBg.layer.cornerRadius = 20
        iconBg.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        triggerLabel.font = .systemFont(ofSize: 11)
        triggerLabel.textColor = .tertiaryLabel
        triggerLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconBg)
        iconBg.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(triggerLabel)

        NSLayoutConstraint.activate([
            iconBg.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconBg.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 40),
            iconBg.heightAnchor.constraint(equalToConstant: 40),

            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            subtitleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            triggerLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12),
            triggerLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 2)
        ])
    }

    func configure(with message: InAppMessage) {
        titleLabel.text = message.name

        let typeStr = message.type.rawValue
        subtitleLabel.text = "Type: \(typeStr)"
        triggerLabel.text = "Trigger: \(message.triggerType.rawValue)"

        switch message.type {
        case .modal:
            iconBg.backgroundColor = .systemBlue
            iconView.image = UIImage(systemName: "square")
        case .banner:
            iconBg.backgroundColor = .systemGreen
            iconView.image = UIImage(systemName: "minus")
        case .fullscreen:
            iconBg.backgroundColor = .systemPurple
            iconView.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right")
        case .card:
            iconBg.backgroundColor = .systemOrange
            iconView.image = UIImage(systemName: "creditcard")
        }
    }
}
