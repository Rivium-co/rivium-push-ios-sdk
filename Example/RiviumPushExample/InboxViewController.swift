import UIKit
import RiviumPush

class InboxViewController: UIViewController {

    // MARK: - UI Elements
    private let tableView = UITableView()
    private let refreshControl = UIRefreshControl()
    private let emptyLabel = UILabel()

    private var messages: [InboxMessage] = []
    private var isLoading = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchMessages()
        updateBadge()
    }

    private func updateBadge() {
        let count = RiviumPush.shared.getInboxManager().getUnreadCount()
        tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup
    private func setupUI() {
        title = "Inbox"
        view.backgroundColor = .systemBackground

        // Navigation items
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )

        // Table view setup
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(InboxMessageCell.self, forCellReuseIdentifier: InboxMessageCell.identifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        // Refresh control
        refreshControl.addTarget(self, action: #selector(refreshTapped), for: .valueChanged)
        tableView.refreshControl = refreshControl

        // Empty state label
        emptyLabel.text = "No messages in your inbox"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupObservers() {
        // Listen for inbox updates
        RiviumPush.shared.setInboxCallback(InboxCallbackHandler(viewController: self, onUpdate: { [weak self] in
            self?.fetchMessages()
        }))
    }

    // MARK: - Actions
    @objc private func refreshTapped() {
        fetchMessages()
    }

    private func fetchMessages() {
        guard !isLoading else { return }
        isLoading = true

        let filter = InboxFilter()
        RiviumPush.shared.getInboxMessages(
            filter: filter,
            onSuccess: { [weak self] response in
                DispatchQueue.main.async {
                    self?.messages = response.messages
                    self?.tableView.reloadData()
                    self?.refreshControl.endRefreshing()
                    self?.isLoading = false
                    self?.updateEmptyState()
                    self?.updateBadge()
                }
            },
            onError: { [weak self] error in
                DispatchQueue.main.async {
                    self?.refreshControl.endRefreshing()
                    self?.isLoading = false
                    self?.showError(error)
                }
            }
        )
    }

    private func markAsRead(_ message: InboxMessage) {
        RiviumPush.shared.markInboxMessageAsRead(
            messageId: message.id,
            onSuccess: { [weak self] in
                self?.fetchMessages()
            },
            onError: { [weak self] error in
                self?.showError(error)
            }
        )
    }

    private func archiveMessage(_ message: InboxMessage) {
        RiviumPush.shared.archiveInboxMessage(
            messageId: message.id,
            onSuccess: { [weak self] in
                self?.fetchMessages()
            },
            onError: { [weak self] error in
                self?.showError(error)
            }
        )
    }

    private func deleteMessage(_ message: InboxMessage) {
        let alert = UIAlertController(
            title: "Delete Message",
            message: "Are you sure you want to delete this message?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            RiviumPush.shared.deleteInboxMessage(
                messageId: message.id,
                onSuccess: {
                    self?.fetchMessages()
                },
                onError: { error in
                    self?.showError(error)
                }
            )
        })
        present(alert, animated: true)
    }

    private func showMessageDetail(_ message: InboxMessage) {
        let detailVC = InboxDetailViewController(message: message)
        detailVC.delegate = self
        navigationController?.pushViewController(detailVC, animated: true)
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !messages.isEmpty
        tableView.isHidden = messages.isEmpty
    }

    private func showError(_ error: String) {
        let alert = UIAlertController(title: "Error", message: error, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension InboxViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: InboxMessageCell.identifier, for: indexPath) as! InboxMessageCell
        cell.configure(with: messages[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate
extension InboxViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let message = messages[indexPath.row]
        showMessageDetail(message)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let message = messages[indexPath.row]

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.deleteMessage(message)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        let archiveAction = UIContextualAction(style: .normal, title: "Archive") { [weak self] _, _, completion in
            self?.archiveMessage(message)
            completion(true)
        }
        archiveAction.backgroundColor = .systemOrange
        archiveAction.image = UIImage(systemName: "archivebox")

        return UISwipeActionsConfiguration(actions: [deleteAction, archiveAction])
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let message = messages[indexPath.row]

        if message.status == .unread {
            let readAction = UIContextualAction(style: .normal, title: "Read") { [weak self] _, _, completion in
                self?.markAsRead(message)
                completion(true)
            }
            readAction.backgroundColor = .systemGreen
            readAction.image = UIImage(systemName: "envelope.open")
            return UISwipeActionsConfiguration(actions: [readAction])
        }

        return nil
    }
}

// MARK: - InboxDetailViewControllerDelegate
extension InboxViewController: InboxDetailViewControllerDelegate {
    func inboxDetailDidUpdate() {
        fetchMessages()
    }
}

// MARK: - InboxCallbackHandler
class InboxCallbackHandler: InboxCallback {
    private let onUpdateHandler: () -> Void
    private weak var viewController: UIViewController?

    init(viewController: UIViewController? = nil, onUpdate: @escaping () -> Void) {
        self.viewController = viewController
        self.onUpdateHandler = onUpdate
    }

    func inboxMessageReceived(_ message: InboxMessage) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdateHandler()
            self?.updateBadge()
        }
    }

    func inboxMessageStatusChanged(messageId: String, status: InboxMessageStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdateHandler()
            self?.updateBadge()
        }
    }

    private func updateBadge() {
        let count = RiviumPush.shared.getInboxManager().getUnreadCount()
        viewController?.tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
    }
}

// MARK: - InboxMessageCell
class InboxMessageCell: UITableViewCell {
    static let identifier = "InboxMessageCell"

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let dateLabel = UILabel()
    private let unreadIndicator = UIView()
    private let categoryLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none

        containerView.backgroundColor = .secondarySystemBackground
        containerView.layer.cornerRadius = 12
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        unreadIndicator.backgroundColor = .systemBlue
        unreadIndicator.layer.cornerRadius = 4
        unreadIndicator.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(unreadIndicator)

        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        bodyLabel.font = .systemFont(ofSize: 14)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(bodyLabel)

        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = .tertiaryLabel
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(dateLabel)

        categoryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        categoryLabel.textColor = .white
        categoryLabel.backgroundColor = .systemBlue
        categoryLabel.layer.cornerRadius = 4
        categoryLabel.clipsToBounds = true
        categoryLabel.textAlignment = .center
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(categoryLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            unreadIndicator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            unreadIndicator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            unreadIndicator.widthAnchor.constraint(equalToConstant: 8),
            unreadIndicator.heightAnchor.constraint(equalToConstant: 8),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: unreadIndicator.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: dateLabel.leadingAnchor, constant: -8),

            dateLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            dateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            categoryLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 8),
            categoryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            categoryLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            categoryLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    func configure(with message: InboxMessage) {
        titleLabel.text = message.content.title
        bodyLabel.text = message.content.body
        dateLabel.text = formatDateString(message.createdAt)
        unreadIndicator.isHidden = message.status != .unread

        if let category = message.category, !category.isEmpty {
            categoryLabel.isHidden = false
            categoryLabel.text = "  \(category)  "
        } else {
            categoryLabel.isHidden = true
        }
    }

    private func formatDateString(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .abbreviated
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .abbreviated
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }

        return dateString
    }
}
