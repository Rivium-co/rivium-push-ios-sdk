import UIKit
import RiviumPush

class ABTestingViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refreshControl = UIRefreshControl()
    private var activeTests: [ABTestSummary] = []
    private var assignedVariants: [String: ABTestVariant] = [:]
    private var isLoading = false

    private var abTestingManager: ABTestingManager {
        RiviumPush.shared.getABTestingManager()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "A/B Tests"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(refresh)),
            UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(lookupTest)),
            UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(clearCache)),
        ]

        tableView.delegate = self
        tableView.dataSource = self
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        loadTests()
    }

    // MARK: - Data Loading

    @objc private func refresh() {
        loadTests()
    }

    private func loadTests() {
        isLoading = true
        tableView.reloadData()

        abTestingManager.getActiveTests { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.refreshControl.endRefreshing()
                switch result {
                case .success(let tests):
                    self.activeTests = tests
                    for test in tests {
                        self.loadVariant(testId: test.id)
                    }
                case .failure(let error):
                    self.showToast("Failed: \(error.localizedDescription)")
                }
                self.tableView.reloadData()
            }
        }
    }

    private func loadVariant(testId: String) {
        abTestingManager.getVariant(testId: testId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let variant) = result {
                    self?.assignedVariants[testId] = variant
                    self?.tableView.reloadData()
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func lookupTest() {
        let alert = UIAlertController(title: "Lookup Test", message: "Enter test ID to get variant assignment", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "test_id" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Get Variant", style: .default) { [weak self] _ in
            let testId = alert.textFields?.first?.text ?? ""
            guard !testId.isEmpty else { return }
            self?.getVariant(testId: testId, forceRefresh: false)
        })
        alert.addAction(UIAlertAction(title: "Force Refresh", style: .default) { [weak self] _ in
            let testId = alert.textFields?.first?.text ?? ""
            guard !testId.isEmpty else { return }
            self?.getVariant(testId: testId, forceRefresh: true)
        })
        present(alert, animated: true)
    }

    @objc private func clearCache() {
        abTestingManager.clearCache()
        assignedVariants.removeAll()
        tableView.reloadData()
        showToast("Cache cleared")
    }

    private func getVariant(testId: String, forceRefresh: Bool) {
        abTestingManager.getVariant(testId: testId, forceRefresh: forceRefresh) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let variant):
                    self?.assignedVariants[testId] = variant
                    self?.tableView.reloadData()
                    self?.showToast("Assigned: \(variant.variantName)")
                case .failure(let error):
                    self?.showToast("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func trackEvent(_ event: ABTestEvent, testId: String, variantId: String) {
        abTestingManager.trackEvent(testId: testId, variantId: variantId, event: event) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.showToast("\(event.rawValue) tracked")
                case .failure(let error):
                    self?.showToast("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showTrackMenu(testId: String, variantId: String, sourceView: UIView) {
        let sheet = UIAlertController(title: "Track Event", message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.sourceView = sourceView

        let events: [(String, ABTestEvent, String)] = [
            ("Track Impression", .impression, "eye"),
            ("Track Opened", .opened, "envelope.open"),
            ("Track Clicked", .clicked, "hand.tap"),
            ("Track Converted", .converted, "checkmark.circle"),
        ]
        for (title, event, _) in events {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.trackEvent(event, testId: testId, variantId: variantId)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { alert.dismiss(animated: true) }
    }
}

// MARK: - UITableView
extension ABTestingViewController: UITableViewDataSource, UITableViewDelegate {

    // Section 0: Active tests, Section 1: Assigned variants, Section 2: How it works
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Active Tests"
        case 1: return assignedVariants.isEmpty ? nil : "Your Assigned Variants"
        case 2: return "How It Works"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            if isLoading { return 1 }
            return max(activeTests.count, 1) // at least 1 for empty state
        case 1: return assignedVariants.count
        case 2: return 4
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0: return activeTestCell(indexPath)
        case 1: return variantCell(indexPath)
        case 2: return infoCell(indexPath)
        default: return UITableViewCell()
        }
    }

    private func activeTestCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)

        if isLoading {
            cell.textLabel?.text = "Loading..."
            cell.textLabel?.textColor = .secondaryLabel
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
            return cell
        }

        if activeTests.isEmpty {
            cell.textLabel?.text = "No active tests"
            cell.textLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.text = "Create one in the Rivium Console"
            cell.selectionStyle = .none
            cell.imageView?.image = UIImage(systemName: "flask")
            cell.imageView?.tintColor = .secondaryLabel
            return cell
        }

        let test = activeTests[indexPath.row]
        let hasVariant = assignedVariants.keys.contains(test.id)

        cell.textLabel?.text = test.name
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cell.detailTextLabel?.text = "\(test.variantCount) variants\(test.hasControlGroup ? " + control" : "") · \(String(test.id.prefix(8)))..."
        cell.detailTextLabel?.textColor = .secondaryLabel

        let dot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        dot.backgroundColor = hasVariant ? .systemGreen : .systemGray
        dot.layer.cornerRadius = 5
        cell.accessoryView = dot

        cell.imageView?.image = UIImage(systemName: "flask.fill")
        cell.imageView?.tintColor = hasVariant ? .systemTeal : .systemGray

        return cell
    }

    private func variantCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let testId = Array(assignedVariants.keys)[indexPath.row]
        let variant = assignedVariants[testId]!

        let isControl = variant.isControlGroup
        cell.textLabel?.text = variant.variantName
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cell.detailTextLabel?.text = "\(isControl ? "Control" : "Test Variant") · \(String(testId.prefix(8)))..."
        cell.detailTextLabel?.textColor = isControl ? .systemBlue : .systemOrange

        cell.imageView?.image = UIImage(systemName: isControl ? "shield.fill" : "target")
        cell.imageView?.tintColor = isControl ? .systemBlue : .systemOrange

        cell.accessoryType = .detailButton

        return cell
    }

    private func infoCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none

        let infos: [(String, String, String, UIColor)] = [
            ("shuffle", "Random Assignment", "Users are randomly assigned to variants", .systemTeal),
            ("chart.bar.fill", "Event Tracking", "Track impressions, opens, clicks, conversions", .systemIndigo),
            ("internaldrive.fill", "Local Caching", "Variants cached for consistent experience", .systemOrange),
            ("chart.pie.fill", "Statistics", "View results and significance in console", .systemGreen),
        ]

        let (icon, title, desc, color) = infos[indexPath.row]
        cell.textLabel?.text = title
        cell.textLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        cell.detailTextLabel?.text = desc
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: icon)
        cell.imageView?.tintColor = color

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 && !activeTests.isEmpty && indexPath.row < activeTests.count {
            let test = activeTests[indexPath.row]
            loadVariant(testId: test.id)
        }
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        if indexPath.section == 1 {
            let testId = Array(assignedVariants.keys)[indexPath.row]
            let variant = assignedVariants[testId]!
            if let cell = tableView.cellForRow(at: indexPath) {
                showTrackMenu(testId: testId, variantId: variant.variantId, sourceView: cell)
            }
        }
    }
}
