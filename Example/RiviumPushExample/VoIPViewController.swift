import UIKit
import RiviumPush

class VoIPViewController: UIViewController {

    // MARK: - UI
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let voipStatusDot = UIView()
    private let voipStatusLabel = UILabel()
    private let voipTokenLabel = UILabel()
    private let callLogTextView = UITextView()
    private var callLogs: [String] = []

    // MARK: - State
    private var isVoIPEnabled: Bool {
        UserDefaults.standard.bool(forKey: "voip_enabled")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "VoIP"
        view.backgroundColor = .systemBackground
        setupUI()
        setupObservers()
        updateVoIPStatus()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateVoIPStatus()
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

        // VoIP Status Card
        let statusCard = makeCard()

        let statusHeader = UIStackView()
        statusHeader.axis = .horizontal
        statusHeader.spacing = 10
        statusHeader.alignment = .center

        voipStatusDot.translatesAutoresizingMaskIntoConstraints = false
        voipStatusDot.layer.cornerRadius = 5
        voipStatusDot.backgroundColor = .systemGray
        NSLayoutConstraint.activate([
            voipStatusDot.widthAnchor.constraint(equalToConstant: 10),
            voipStatusDot.heightAnchor.constraint(equalToConstant: 10),
        ])

        voipStatusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        voipStatusLabel.text = "VoIP Disabled"

        voipTokenLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        voipTokenLabel.textColor = .secondaryLabel
        voipTokenLabel.numberOfLines = 2
        voipTokenLabel.lineBreakMode = .byTruncatingMiddle

        let statusInner = UIStackView(arrangedSubviews: [voipStatusLabel, voipTokenLabel])
        statusInner.axis = .vertical
        statusInner.spacing = 2

        statusHeader.addArrangedSubview(voipStatusDot)
        statusHeader.addArrangedSubview(statusInner)
        statusCard.addArrangedSubview(statusHeader)
        stack.addArrangedSubview(statusCard)

        // VoIP Mode Toggle Card
        let toggleCard = makeCard()
        let toggleLabel = UILabel()
        toggleLabel.text = "VoIP Push (PushKit)"
        toggleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        let toggleDesc = UILabel()
        toggleDesc.text = "Enable VoIP push for instant delivery even when app is killed. Required for calling apps (Jitsi, WebRTC)."
        toggleDesc.font = .systemFont(ofSize: 12)
        toggleDesc.textColor = .secondaryLabel
        toggleDesc.numberOfLines = 0

        let toggle = UISwitch()
        toggle.isOn = isVoIPEnabled
        toggle.onTintColor = UIColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 1)
        toggle.addTarget(self, action: #selector(toggleVoIP(_:)), for: .valueChanged)

        let toggleRow = UIStackView(arrangedSubviews: [toggleLabel, toggle])
        toggleRow.axis = .horizontal
        toggleRow.alignment = .center

        toggleCard.addArrangedSubview(toggleRow)
        toggleCard.addArrangedSubview(toggleDesc)

        let warningLabel = UILabel()
        warningLabel.text = "Requires real calling feature for App Store. Re-initialize SDK after toggling."
        warningLabel.font = .systemFont(ofSize: 11)
        warningLabel.textColor = .systemOrange
        warningLabel.numberOfLines = 0
        toggleCard.addArrangedSubview(warningLabel)

        stack.addArrangedSubview(toggleCard)

        // Actions
        let actionsLabel = makeSectionLabel("VoIP Actions")
        stack.addArrangedSubview(actionsLabel)

        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.spacing = 10
        row1.distribution = .fillEqually
        row1.addArrangedSubview(makeActionButton("Simulate Call", icon: "phone.arrow.down.left.fill", color: .systemGreen, action: #selector(simulateIncomingCall)))
        row1.addArrangedSubview(makeActionButton("Copy VoIP Token", icon: "doc.on.clipboard", color: .systemBlue, action: #selector(copyVoIPToken)))
        stack.addArrangedSubview(row1)

        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.spacing = 10
        row2.distribution = .fillEqually
        row2.addArrangedSubview(makeActionButton("Re-Init SDK", icon: "arrow.clockwise", color: .systemOrange, action: #selector(reinitializeSDK)))
        row2.addArrangedSubview(makeActionButton("Check Status", icon: "info.circle.fill", color: .systemTeal, action: #selector(checkStatus)))
        stack.addArrangedSubview(row2)

        // Info Card
        let infoCard = makeCard()
        let infoTitle = UILabel()
        infoTitle.text = "How VoIP Push Works"
        infoTitle.font = .systemFont(ofSize: 15, weight: .bold)
        infoCard.addArrangedSubview(infoTitle)

        let infos: [(String, String, UIColor)] = [
            ("Standard APNs (usePushKit: false)", "Works like Firebase. 100% App Store compliant. Limited when app is killed.", .systemBlue),
            ("VoIP Push (usePushKit: true)", "Instant delivery even when app is killed. Requires real calling feature (Jitsi, WebRTC).", .systemGreen),
            ("CallKit Required", "iOS 13+ requires CallKit for VoIP. The SDK handles CallKit reporting automatically.", .systemOrange),
        ]

        for (title, desc, color) in infos {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.alignment = .top

            let dot = UIView()
            dot.backgroundColor = color
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8),
            ])

            let dotContainer = UIView()
            dotContainer.addSubview(dot)
            dot.centerYAnchor.constraint(equalTo: dotContainer.centerYAnchor).isActive = true
            dot.leadingAnchor.constraint(equalTo: dotContainer.leadingAnchor).isActive = true
            dot.trailingAnchor.constraint(equalTo: dotContainer.trailingAnchor).isActive = true
            dotContainer.translatesAutoresizingMaskIntoConstraints = false
            dotContainer.heightAnchor.constraint(equalToConstant: 20).isActive = true

            let textStack = UIStackView()
            textStack.axis = .vertical
            textStack.spacing = 2

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = color

            let descLabel = UILabel()
            descLabel.text = desc
            descLabel.font = .systemFont(ofSize: 12)
            descLabel.textColor = .secondaryLabel
            descLabel.numberOfLines = 0

            textStack.addArrangedSubview(titleLabel)
            textStack.addArrangedSubview(descLabel)

            row.addArrangedSubview(dotContainer)
            row.addArrangedSubview(textStack)
            infoCard.addArrangedSubview(row)
        }

        stack.addArrangedSubview(infoCard)

        // Comparison Table
        let compCard = makeCard()
        let compTitle = UILabel()
        compTitle.text = "Comparison"
        compTitle.font = .systemFont(ofSize: 15, weight: .bold)
        compCard.addArrangedSubview(compTitle)

        let compData: [(String, String, String)] = [
            ("Mode", "Standard APNs", "VoIP Push"),
            ("App Killed", "Limited", "Instant"),
            ("Compliance", "100%", "Needs Calls"),
            ("Setup", "Easy", "CallKit Req."),
        ]

        for (label, standard, voip) in compData {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually

            let l = UILabel()
            l.text = label
            l.font = .systemFont(ofSize: 12, weight: .semibold)
            l.textColor = .secondaryLabel

            let s = UILabel()
            s.text = standard
            s.font = .systemFont(ofSize: 12)
            s.textColor = .label
            s.textAlignment = .center

            let v = UILabel()
            v.text = voip
            v.font = .systemFont(ofSize: 12)
            v.textColor = .label
            v.textAlignment = .center

            row.addArrangedSubview(l)
            row.addArrangedSubview(s)
            row.addArrangedSubview(v)
            compCard.addArrangedSubview(row)
        }

        stack.addArrangedSubview(compCard)

        // Call Log
        let logHeader = UIStackView()
        logHeader.axis = .horizontal
        let logLabel = makeSectionLabel("Call Log")
        let clearBtn = UIButton(type: .system)
        clearBtn.setTitle("Clear", for: .normal)
        clearBtn.titleLabel?.font = .systemFont(ofSize: 13)
        clearBtn.addTarget(self, action: #selector(clearLogs), for: .touchUpInside)
        logHeader.addArrangedSubview(logLabel)
        logHeader.addArrangedSubview(UIView())
        logHeader.addArrangedSubview(clearBtn)
        stack.addArrangedSubview(logHeader)

        callLogTextView.isEditable = false
        callLogTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        callLogTextView.backgroundColor = .secondarySystemBackground
        callLogTextView.layer.cornerRadius = 10
        callLogTextView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        callLogTextView.translatesAutoresizingMaskIntoConstraints = false
        callLogTextView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        stack.addArrangedSubview(callLogTextView)

        addLog("VoIP tab loaded")
    }

    // MARK: - Observers
    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(onVoIPTokenReceived(_:)), name: NSNotification.Name("riviumPushVoIPToken"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onVoIPPayloadReceived(_:)), name: NSNotification.Name("riviumPushVoIPPayload"), object: nil)
    }

    @objc private func onVoIPTokenReceived(_ n: Notification) {
        let token = n.userInfo?["token"] as? String ?? "?"
        addLog("VoIP token received: \(String(token.prefix(20)))...")
        updateVoIPStatus()
    }

    @objc private func onVoIPPayloadReceived(_ n: Notification) {
        addLog("VoIP push received!")
        updateVoIPStatus()
    }

    // MARK: - Actions
    @objc private func toggleVoIP(_ toggle: UISwitch) {
        UserDefaults.standard.set(toggle.isOn, forKey: "voip_enabled")
        addLog("VoIP mode \(toggle.isOn ? "enabled" : "disabled")")

        // Auto re-initialize SDK with new VoIP setting
        guard let apiKey = AppDelegate.savedApiKey, !apiKey.isEmpty else {
            addLog("No API key configured")
            updateVoIPStatus()
            return
        }

        RiviumPush.shared.disconnect()

        let config = RiviumPushConfig.builder(apiKey: apiKey)
            .usePushKit(toggle.isOn)
            .showNotificationInForeground(true)
            .autoConnect(true)
            .build()

        RiviumPush.shared.initialize(config: config)

        // Delay registration to allow PushKit token to arrive first
        let delaySeconds = toggle.isOn ? 3.0 : 0.5
        addLog("SDK re-initialized with VoIP: \(toggle.isOn), registering in \(delaySeconds)s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
            RiviumPush.shared.register(userId: AppDelegate.savedUserId)
            self?.addLog("Registration sent")
            self?.updateVoIPStatus()
        }
    }

    @objc private func simulateIncomingCall() {
        guard isVoIPEnabled else {
            let alert = UIAlertController(title: "VoIP Disabled", message: "Enable VoIP mode first and re-initialize the SDK.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        addLog("Simulating incoming call via CallKit...")

        // This demonstrates how the SDK's VoIP manager reports calls
        let alert = UIAlertController(title: "Incoming Call", message: "This simulates a VoIP push triggering CallKit.\n\nIn production, a VoIP push from your server would trigger this automatically.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it", style: .default) { [weak self] _ in
            self?.addLog("Call simulation completed")
        })
        present(alert, animated: true)
    }

    @objc private func copyVoIPToken() {
        let token = RiviumPush.shared.getVoIPToken()
        if let token = token {
            UIPasteboard.general.string = token
            addLog("VoIP token copied")
            showToast("VoIP token copied to clipboard")
        } else {
            showToast("No VoIP token available")
            addLog("No VoIP token available")
        }
    }

    @objc private func reinitializeSDK() {
        let alert = UIAlertController(
            title: "Re-initialize SDK",
            message: "This will re-initialize the SDK with VoIP \(isVoIPEnabled ? "enabled" : "disabled"). The app will reconnect.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Re-Init", style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard let apiKey = AppDelegate.savedApiKey, !apiKey.isEmpty else {
                self.addLog("No API key configured")
                return
            }

            RiviumPush.shared.disconnect()

            let config = RiviumPushConfig.builder(apiKey: apiKey)
                .usePushKit(self.isVoIPEnabled)
                .showNotificationInForeground(true)
                .autoConnect(true)
                .build()

            RiviumPush.shared.initialize(config: config)
            RiviumPush.shared.register(userId: AppDelegate.savedUserId)

            self.addLog("SDK re-initialized with VoIP: \(self.isVoIPEnabled)")
            self.updateVoIPStatus()
        })
        present(alert, animated: true)
    }

    @objc private func checkStatus() {
        let connected = RiviumPush.shared.isConnected
        let deviceId = RiviumPush.shared.getDeviceId() ?? "N/A"
        let voipToken = RiviumPush.shared.getVoIPToken()

        var status = "Connection: \(connected ? "Connected" : "Disconnected")\n"
        status += "Device ID: \(deviceId)\n"
        status += "VoIP Mode: \(isVoIPEnabled ? "Enabled" : "Disabled")\n"
        status += "VoIP Token: \(voipToken != nil ? "Available (\(voipToken!.count) chars)" : "Not available")"

        let alert = UIAlertController(title: "SDK Status", message: status, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)

        addLog("Status checked")
    }

    @objc private func clearLogs() {
        callLogs.removeAll()
        callLogTextView.text = ""
    }

    // MARK: - Status
    private func updateVoIPStatus() {
        let voipToken = RiviumPush.shared.getVoIPToken()
        let enabled = isVoIPEnabled

        if enabled && voipToken != nil {
            voipStatusDot.backgroundColor = .systemGreen
            voipStatusLabel.text = "VoIP Active"
            voipTokenLabel.text = "Token: \(String(voipToken!.prefix(30)))..."
        } else if enabled {
            voipStatusDot.backgroundColor = .systemOrange
            voipStatusLabel.text = "VoIP Enabled (No Token)"
            voipTokenLabel.text = "Re-initialize SDK to get VoIP token"
        } else {
            voipStatusDot.backgroundColor = .systemGray
            voipStatusLabel.text = "VoIP Disabled (Standard APNs)"
            voipTokenLabel.text = "Enable VoIP for instant delivery"
        }
    }

    // MARK: - Logging
    private func addLog(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(time)] \(text)"
        callLogs.append(entry)
        if callLogs.count > 50 { callLogs.removeFirst() }
        callLogTextView.text = callLogs.joined(separator: "\n")
        if !callLogTextView.text.isEmpty {
            let bottom = NSRange(location: callLogTextView.text.count - 1, length: 1)
            callLogTextView.scrollRangeToVisible(bottom)
        }
    }

    // MARK: - Helpers
    private func showToast(_ message: String) {
        let toast = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(toast, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { toast.dismiss(animated: true) }
    }

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
