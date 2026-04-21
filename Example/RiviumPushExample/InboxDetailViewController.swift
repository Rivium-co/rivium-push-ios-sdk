import UIKit
import RiviumPush

protocol InboxDetailViewControllerDelegate: AnyObject {
    func inboxDetailDidUpdate()
}

class InboxDetailViewController: UIViewController {

    // MARK: - Properties
    private let message: InboxMessage
    weak var delegate: InboxDetailViewControllerDelegate?

    // MARK: - UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let imageView = UIImageView()
    private let statusLabel = UILabel()
    private let categoryLabel = UILabel()
    private let dateLabel = UILabel()
    private let deepLinkButton = UIButton(type: .system)

    // MARK: - Init
    init(message: InboxMessage) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureContent()
        markAsReadIfNeeded()
    }

    // MARK: - Setup
    private func setupUI() {
        title = "Message"
        view.backgroundColor = .systemBackground

        // Navigation items
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(deleteTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = .systemRed

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        // Image view
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = .secondarySystemBackground
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        // Status label
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.layer.cornerRadius = 4
        statusLabel.clipsToBounds = true
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // Category label
        categoryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        categoryLabel.textColor = .white
        categoryLabel.backgroundColor = .systemBlue
        categoryLabel.layer.cornerRadius = 4
        categoryLabel.clipsToBounds = true
        categoryLabel.textAlignment = .center
        categoryLabel.isHidden = true
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(categoryLabel)

        // Title label
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Date label
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dateLabel)

        // Body label
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textColor = .label
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bodyLabel)

        // Deep link button
        deepLinkButton.setTitle("Open Link", for: .normal)
        deepLinkButton.backgroundColor = .systemBlue
        deepLinkButton.setTitleColor(.white, for: .normal)
        deepLinkButton.layer.cornerRadius = 8
        deepLinkButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        deepLinkButton.addTarget(self, action: #selector(openDeepLink), for: .touchUpInside)
        deepLinkButton.isHidden = true
        deepLinkButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(deepLinkButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(equalToConstant: 200),

            statusLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.heightAnchor.constraint(equalToConstant: 24),

            categoryLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            categoryLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            categoryLabel.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            bodyLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 16),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            deepLinkButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 24),
            deepLinkButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            deepLinkButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            deepLinkButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func configureContent() {
        titleLabel.text = message.content.title
        bodyLabel.text = message.content.body
        dateLabel.text = formatDateString(message.createdAt)

        // Status
        switch message.status {
        case .unread:
            statusLabel.text = "  Unread  "
            statusLabel.backgroundColor = .systemYellow
        case .read:
            statusLabel.text = "  Read  "
            statusLabel.backgroundColor = .systemGreen
        case .archived:
            statusLabel.text = "  Archived  "
            statusLabel.backgroundColor = .systemGray
        case .deleted:
            statusLabel.text = "  Deleted  "
            statusLabel.backgroundColor = .systemRed
        @unknown default:
            statusLabel.text = "  Unknown  "
            statusLabel.backgroundColor = .systemGray
        }

        // Category
        if let category = message.category, !category.isEmpty {
            categoryLabel.isHidden = false
            categoryLabel.text = "  \(category)  "
        }

        // Image
        if let imageUrlString = message.content.imageUrl, let imageUrl = URL(string: imageUrlString) {
            imageView.isHidden = false
            loadImage(from: imageUrl)
        }

        // Deep link
        if let deepLink = message.content.deepLink, !deepLink.isEmpty {
            deepLinkButton.isHidden = false
        }
    }

    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.imageView.image = image
            }
        }.resume()
    }

    private func markAsReadIfNeeded() {
        if message.status == .unread {
            RiviumPush.shared.markInboxMessageAsRead(
                messageId: message.id,
                onSuccess: { [weak self] in
                    self?.delegate?.inboxDetailDidUpdate()
                },
                onError: { error in
                    print("Failed to mark as read: \(error)")
                }
            )
        }
    }

    private func formatDateString(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date: Date?
        date = isoFormatter.date(from: dateString)

        // Try without fractional seconds
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: dateString)
        }

        if let date = date {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        return dateString
    }

    // MARK: - Actions
    @objc private func deleteTapped() {
        let alert = UIAlertController(
            title: "Delete Message",
            message: "Are you sure you want to delete this message?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            RiviumPush.shared.deleteInboxMessage(
                messageId: self.message.id,
                onSuccess: { [weak self] in
                    self?.delegate?.inboxDetailDidUpdate()
                    DispatchQueue.main.async {
                        self?.navigationController?.popViewController(animated: true)
                    }
                },
                onError: { error in
                    print("Failed to delete: \(error)")
                }
            )
        })
        present(alert, animated: true)
    }

    @objc private func openDeepLink() {
        if let deepLink = message.content.deepLink,
           let url = URL(string: deepLink),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
