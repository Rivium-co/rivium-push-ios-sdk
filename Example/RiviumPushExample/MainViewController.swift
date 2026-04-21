import UIKit
import RiviumPush

// MARK: - Notification Names
extension Notification.Name {
    static let riviumPushRegistered = Notification.Name("riviumPushRegistered")
    static let riviumPushMessageReceived = Notification.Name("riviumPushMessageReceived")
    static let riviumPushNotificationTapped = Notification.Name("riviumPushNotificationTapped")
    static let riviumPushConnectionChanged = Notification.Name("riviumPushConnectionChanged")
}

class MainViewController: UIViewController {

    // MARK: - UI
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let connectionDot = UIView()
    private let connectionLabel = UILabel()
    private let deviceIdLabel = UILabel()
    private let logsTextView = UITextView()
    private var logs: [String] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Rivium Push"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"), style: .plain, target: self, action: #selector(copyDeviceId))
        setupUI()
        setupObservers()
        updateStatus()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateStatus()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Setup UI
    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])

        // Connection status card
        let statusCard = makeCard()
        let statusStack = UIStackView()
        statusStack.axis = .horizontal
        statusStack.spacing = 10
        statusStack.alignment = .center

        connectionDot.translatesAutoresizingMaskIntoConstraints = false
        connectionDot.layer.cornerRadius = 5
        connectionDot.backgroundColor = .systemGray
        NSLayoutConstraint.activate([
            connectionDot.widthAnchor.constraint(equalToConstant: 10),
            connectionDot.heightAnchor.constraint(equalToConstant: 10),
        ])

        connectionLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        connectionLabel.text = "Connecting..."
        connectionLabel.textColor = .label

        deviceIdLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        deviceIdLabel.textColor = .secondaryLabel
        deviceIdLabel.numberOfLines = 1
        deviceIdLabel.lineBreakMode = .byTruncatingMiddle

        let statusInner = UIStackView(arrangedSubviews: [connectionLabel, deviceIdLabel])
        statusInner.axis = .vertical
        statusInner.spacing = 2

        statusStack.addArrangedSubview(connectionDot)
        statusStack.addArrangedSubview(statusInner)
        statusCard.addArrangedSubview(statusStack)
        stack.addArrangedSubview(statusCard)

        // Quick Actions
        let actionsLabel = makeSectionLabel("Quick Actions")
        stack.addArrangedSubview(actionsLabel)

        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.spacing = 10
        row1.distribution = .fillEqually
        row1.addArrangedSubview(makeActionButton("Trigger Event", icon: "bolt.fill", color: .systemOrange, action: #selector(triggerEvent)))
        row1.addArrangedSubview(makeActionButton("Subscribe Topic", icon: "plus.circle.fill", color: .systemGreen, action: #selector(subscribeTopic)))
        stack.addArrangedSubview(row1)

        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.spacing = 10
        row2.distribution = .fillEqually
        row2.addArrangedSubview(makeActionButton("Unsubscribe", icon: "minus.circle.fill", color: .systemRed, action: #selector(unsubscribeTopic)))
        row2.addArrangedSubview(makeActionButton("Reconnect", icon: "arrow.clockwise", color: .systemBlue, action: #selector(reconnect)))
        stack.addArrangedSubview(row2)

        // Logs
        let logsHeader = UIStackView()
        logsHeader.axis = .horizontal
        let logsLabel = makeSectionLabel("Live Logs")
        let clearBtn = UIButton(type: .system)
        clearBtn.setTitle("Clear", for: .normal)
        clearBtn.titleLabel?.font = .systemFont(ofSize: 13)
        clearBtn.addTarget(self, action: #selector(clearLogs), for: .touchUpInside)
        logsHeader.addArrangedSubview(logsLabel)
        logsHeader.addArrangedSubview(UIView()) // spacer
        logsHeader.addArrangedSubview(clearBtn)
        stack.addArrangedSubview(logsHeader)

        logsTextView.isEditable = false
        logsTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logsTextView.backgroundColor = .secondarySystemBackground
        logsTextView.layer.cornerRadius = 10
        logsTextView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        logsTextView.translatesAutoresizingMaskIntoConstraints = false
        logsTextView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        stack.addArrangedSubview(logsTextView)

        addLog("App started")
    }

    // MARK: - Observers
    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(onRegistered(_:)), name: .riviumPushRegistered, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onMessageReceived(_:)), name: .riviumPushMessageReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onConnectionChanged(_:)), name: .riviumPushConnectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onNotificationTapped(_:)), name: .riviumPushNotificationTapped, object: nil)
    }

    @objc private func onRegistered(_ n: Notification) {
        let id = n.userInfo?["deviceId"] as? String ?? "?"
        addLog("Registered: \(id)")
        updateStatus()
    }

    @objc private func onMessageReceived(_ n: Notification) {
        if let msg = n.userInfo?["message"] as? RiviumPushMessage {
            addLog("Message: \(msg.title ?? "no title")")
        }
    }

    @objc private func onConnectionChanged(_ n: Notification) {
        updateStatus()
        let connected = n.userInfo?["connected"] as? Bool ?? false
        addLog(connected ? "Connected" : "Disconnected")
    }

    @objc private func onNotificationTapped(_ n: Notification) {
        if let msg = n.userInfo?["message"] as? RiviumPushMessage {
            addLog("Tapped: \(msg.title ?? "notification")")
        }
    }

    // MARK: - Actions
    @objc private func triggerEvent() {
        let alert = UIAlertController(title: "Trigger Event", message: "Enter event name", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "e.g. purchase_completed" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Trigger", style: .default) { [weak self] _ in
            let event = alert.textFields?.first?.text ?? "custom_event"
            RiviumPush.shared.triggerInAppEvent(event)
            self?.addLog("Triggered event: \(event)")
        })
        present(alert, animated: true)
    }

    @objc private func subscribeTopic() {
        let alert = UIAlertController(title: "Subscribe Topic", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "e.g. news" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Subscribe", style: .default) { [weak self] _ in
            let topic = alert.textFields?.first?.text ?? ""
            guard !topic.isEmpty else { return }
            RiviumPush.shared.subscribeTopic(topic)
            self?.addLog("Subscribed to: \(topic)")
        })
        present(alert, animated: true)
    }

    @objc private func unsubscribeTopic() {
        let alert = UIAlertController(title: "Unsubscribe Topic", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "e.g. news" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Unsubscribe", style: .destructive) { [weak self] _ in
            let topic = alert.textFields?.first?.text ?? ""
            guard !topic.isEmpty else { return }
            RiviumPush.shared.unsubscribeTopic(topic)
            self?.addLog("Unsubscribed from: \(topic)")
        })
        present(alert, animated: true)
    }

    @objc private func reconnect() {
        RiviumPush.shared.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            RiviumPush.shared.connect()
            self.addLog("Reconnecting...")
        }
    }

    @objc private func copyDeviceId() {
        let id = RiviumPush.shared.getDeviceId() ?? ""
        UIPasteboard.general.string = id
        addLog("Device ID copied")

        let toast = UIAlertController(title: nil, message: "Device ID copied", preferredStyle: .alert)
        present(toast, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { toast.dismiss(animated: true) }
    }

    @objc private func clearLogs() {
        logs.removeAll()
        logsTextView.text = ""
    }

    // MARK: - Status
    private func updateStatus() {
        let connected = RiviumPush.shared.isConnected
        connectionDot.backgroundColor = connected ? .systemGreen : .systemRed
        connectionLabel.text = connected ? "Connected" : "Disconnected"
        deviceIdLabel.text = RiviumPush.shared.getDeviceId() ?? "Not registered"
    }

    // MARK: - Logging
    func addLog(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(time)] \(text)"
        logs.append(entry)
        if logs.count > 100 { logs.removeFirst() }
        logsTextView.text = logs.joined(separator: "\n")
        let bottom = NSRange(location: logsTextView.text.count - 1, length: 1)
        logsTextView.scrollRangeToVisible(bottom)
    }

    // MARK: - Helpers
    private func makeCard() -> UIStackView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 8
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12
        card.clipsToBounds = true
        return card
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.textColor = .label
        return label
    }

    private func makeActionButton(_ title: String, icon: String, color: UIColor, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle("  \(title)", for: .normal)
        btn.setImage(UIImage(systemName: icon), for: .normal)
        btn.tintColor = color
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.backgroundColor = color.withAlphaComponent(0.12)
        btn.layer.cornerRadius = 10
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return btn
    }
}

// MARK: - CardView (reusable)
class CardView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 8
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        clipsToBounds = true
    }
    required init(coder: NSCoder) { fatalError() }
}
