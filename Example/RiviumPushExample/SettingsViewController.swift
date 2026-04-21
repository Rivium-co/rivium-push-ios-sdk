import UIKit
import RiviumPush

class SettingsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private struct Row {
        let title: String
        let detail: String?
        let action: (() -> Void)?
        let destructive: Bool

        init(_ title: String, detail: String? = nil, destructive: Bool = false, action: (() -> Void)? = nil) {
            self.title = title
            self.detail = detail
            self.action = action
            self.destructive = destructive
        }
    }

    private var sections: [(title: String, rows: [Row])] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemBackground

        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        buildSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        buildSections()
        tableView.reloadData()
    }

    private func buildSections() {
        let deviceId = RiviumPush.shared.getDeviceId() ?? "Not registered"
        let connected = RiviumPush.shared.isConnected
        let unread = RiviumPush.shared.getInboxManager().getUnreadCount()
        let apnsToken = RiviumPush.shared.getAPNsToken() ?? "Not available"

        sections = [
            ("Device Information", [
                Row("Device ID", detail: deviceId),
                Row("Connection", detail: connected ? "Connected" : "Disconnected"),
                Row("APNs Token", detail: String(apnsToken.prefix(20)) + "..."),
                Row("Inbox Unread", detail: "\(unread)"),
            ]),
            ("User Management", [
                Row("Set User ID", action: { [weak self] in self?.setUserId() }),
                Row("Clear User ID", destructive: true, action: { [weak self] in self?.clearUserId() }),
            ]),
            ("Debugging", [
                Row("Reconnect", action: {
                    RiviumPush.shared.disconnect()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        RiviumPush.shared.connect()
                    }
                }),
                Row("Clear Inbox Cache", destructive: true, action: {
                    RiviumPush.shared.getInboxManager().clearCache()
                }),
            ]),
            ("About", [
                Row("SDK Version", detail: "0.1.0"),
                Row("Platform", detail: "iOS \(UIDevice.current.systemVersion)"),
                Row("Model", detail: UIDevice.current.model),
            ]),
            ("Account", [
                Row("API Key", detail: String((AppDelegate.savedApiKey ?? "").prefix(16)) + "..."),
                Row("Change API Key", destructive: true, action: { [weak self] in self?.resetApiKey() }),
            ]),
        ]
    }

    private func setUserId() {
        let alert = UIAlertController(title: "Set User ID", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "e.g. user_123" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Set", style: .default) { [weak self] _ in
            let id = alert.textFields?.first?.text ?? ""
            guard !id.isEmpty else { return }
            RiviumPush.shared.setUserId(id)
            AppDelegate.savedUserId = id
            self?.showToast("User ID set to: \(id)")
        })
        present(alert, animated: true)
    }

    private func clearUserId() {
        RiviumPush.shared.clearUserId()
        AppDelegate.savedUserId = nil
        showToast("User ID cleared")
    }

    private func resetApiKey() {
        let alert = UIAlertController(title: "Change API Key", message: "This will disconnect and return to setup.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { _ in
            RiviumPush.shared.unregister()
            AppDelegate.savedApiKey = nil
            AppDelegate.savedUserId = nil
            if let scene = UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate {
                scene.showOnboarding()
            }
        })
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { alert.dismiss(animated: true) }
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = row.destructive ? .systemRed : .label
        cell.detailTextLabel?.text = row.detail
        cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.accessoryType = row.action != nil ? .disclosureIndicator : .none
        cell.selectionStyle = row.action != nil ? .default : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        sections[indexPath.section].rows[indexPath.row].action?()
        buildSections()
        tableView.reloadData()
    }
}
