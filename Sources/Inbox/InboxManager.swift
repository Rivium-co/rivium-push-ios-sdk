import Foundation

/// Manager for inbox messages
public class InboxManager {
    private static let TAG = "Inbox"
    private static let PREFS_NAME = "rivium_push_inbox"
    private static let KEY_CACHED_MESSAGES = "cached_messages"
    private static let KEY_UNREAD_COUNT = "unread_count"

    private let config: RiviumPushConfig
    private let apiClient: ApiClient
    private let deviceId: String
    private let prefs: UserDefaults

    // Thread-safe state access using a serial queue
    private let stateQueue = DispatchQueue(label: "co.rivium.push.inbox.state", qos: .userInitiated)

    // State properties - access must be synchronized
    private var _userId: String?
    private var _cachedMessages: [InboxMessage] = []
    private var _unreadCount: Int = 0

    // Thread-safe property accessors
    private var userId: String? {
        get { stateQueue.sync { _userId } }
        set { stateQueue.sync { _userId = newValue } }
    }

    private var cachedMessages: [InboxMessage] {
        get { stateQueue.sync { _cachedMessages } }
        set { stateQueue.sync { _cachedMessages = newValue } }
    }

    private var unreadCount: Int {
        get { stateQueue.sync { _unreadCount } }
        set { stateQueue.sync { _unreadCount = newValue } }
    }

    public weak var callback: InboxCallback?

    public static var shared: InboxManager?

    init(config: RiviumPushConfig, apiClient: ApiClient, deviceId: String, userId: String? = nil) {
        self.config = config
        self.apiClient = apiClient
        self.deviceId = deviceId
        self.prefs = UserDefaults.standard

        // Store userId directly to internal var during init
        _userId = userId

        loadCachedData()
        InboxManager.shared = self
    }

    // MARK: - Public API

    /// Update the user ID for inbox queries
    public func setUserId(_ userId: String?) {
        self.userId = userId
    }

    /// Get inbox messages with optional filters
    public func getMessages(
        filter: InboxFilter = InboxFilter(),
        onSuccess: @escaping (InboxMessagesResponse) -> Void,
        onError: @escaping (String) -> Void
    ) {
        var params = filter.toDictionary()

        // Use userId if available, otherwise deviceId
        if let userId = userId {
            params["userId"] = userId
        } else {
            params["deviceId"] = deviceId
        }

        Log.d(InboxManager.TAG, "Fetching inbox messages")

        apiClient.getInboxMessages(params: params) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let json):
                let response = self.parseMessagesResponse(json)

                // Cache the messages
                if filter.offset == 0 {
                    self.cachedMessages = response.messages
                } else {
                    self.cachedMessages.append(contentsOf: response.messages)
                }
                self.unreadCount = response.unreadCount
                self.saveCachedData()

                onSuccess(response)

            case .failure(let error):
                Log.e(InboxManager.TAG, "Fetch messages failed", error: error)
                onError("Failed to fetch messages: \(error.localizedDescription)")
            }
        }
    }

    /// Get a single message by ID
    public func getMessage(
        messageId: String,
        onSuccess: @escaping (InboxMessage) -> Void,
        onError: @escaping (String) -> Void
    ) {
        Log.d(InboxManager.TAG, "Fetching inbox message: \(messageId)")

        apiClient.getInboxMessage(messageId: messageId) { result in
            switch result {
            case .success(let json):
                guard let data = json.data(using: .utf8),
                      let message = try? JSONDecoder().decode(InboxMessage.self, from: data) else {
                    onError("Failed to parse message")
                    return
                }
                onSuccess(message)

            case .failure(let error):
                Log.e(InboxManager.TAG, "Fetch message failed", error: error)
                onError("Failed to fetch message: \(error.localizedDescription)")
            }
        }
    }

    /// Mark a message as read
    public func markAsRead(
        messageId: String,
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        updateMessageStatus(messageId: messageId, status: .read, onSuccess: onSuccess, onError: onError)
    }

    /// Archive a message
    public func archiveMessage(
        messageId: String,
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        updateMessageStatus(messageId: messageId, status: .archived, onSuccess: onSuccess, onError: onError)
    }

    /// Delete a message
    public func deleteMessage(
        messageId: String,
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        Log.d(InboxManager.TAG, "Deleting inbox message: \(messageId)")

        apiClient.deleteInboxMessage(messageId: messageId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // Update local cache
                self.cachedMessages.removeAll { $0.id == messageId }
                self.saveCachedData()

                self.callback?.inboxMessageStatusChanged(messageId: messageId, status: .deleted)
                onSuccess?()

            case .failure(let error):
                Log.e(InboxManager.TAG, "Delete message failed", error: error)
                onError?("Failed to delete message: \(error.localizedDescription)")
            }
        }
    }

    /// Mark multiple messages with a status
    public func markMultiple(
        messageIds: [String],
        status: InboxMessageStatus,
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        Log.d(InboxManager.TAG, "Marking \(messageIds.count) messages as \(status.rawValue)")

        apiClient.markMultipleInboxMessages(messageIds: messageIds, status: status.rawValue) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // Update local cache
                for id in messageIds {
                    if let index = self.cachedMessages.firstIndex(where: { $0.id == id }) {
                        var message = self.cachedMessages[index]
                        message.status = status
                        self.cachedMessages[index] = message
                    }
                }
                if status == .read {
                    self.unreadCount = max(0, self.unreadCount - messageIds.count)
                }
                self.saveCachedData()

                messageIds.forEach { id in
                    self.callback?.inboxMessageStatusChanged(messageId: id, status: status)
                }
                onSuccess?()

            case .failure(let error):
                Log.e(InboxManager.TAG, "Mark multiple failed", error: error)
                onError?("Failed to mark messages: \(error.localizedDescription)")
            }
        }
    }

    /// Mark all messages as read
    public func markAllAsRead(
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        Log.d(InboxManager.TAG, "Marking all messages as read")

        apiClient.markAllInboxMessagesAsRead(deviceId: deviceId, userId: userId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // Update local cache
                for i in 0..<self.cachedMessages.count {
                    if self.cachedMessages[i].status == .unread {
                        var message = self.cachedMessages[i]
                        message.status = .read
                        self.cachedMessages[i] = message
                    }
                }
                self.unreadCount = 0
                self.saveCachedData()

                onSuccess?()

            case .failure(let error):
                Log.e(InboxManager.TAG, "Mark all read failed", error: error)
                onError?("Failed to mark all as read: \(error.localizedDescription)")
            }
        }
    }

    /// Get the unread count (from cache)
    public func getUnreadCount() -> Int {
        return unreadCount
    }

    /// Fetch the unread count from server
    public func fetchUnreadCount(
        onSuccess: @escaping (Int) -> Void,
        onError: ((String) -> Void)? = nil
    ) {
        let filter = InboxFilter(status: .unread, limit: 1)
        getMessages(filter: filter, onSuccess: { [weak self] response in
            self?.unreadCount = response.unreadCount
            self?.saveCachedData()
            onSuccess(response.unreadCount)
        }, onError: { error in
            onError?(error)
        })
    }

    /// Get cached messages without network call
    public func getCachedMessages() -> [InboxMessage] {
        return cachedMessages
    }

    /// Handle incoming inbox message from MQTT/push
    public func handleIncomingMessage(_ message: InboxMessage) {
        Log.d(InboxManager.TAG, "Received new inbox message: \(message.id)")

        // Add to cache
        cachedMessages.insert(message, at: 0)
        if message.status == .unread {
            unreadCount += 1
        }
        saveCachedData()

        // Notify callback
        callback?.inboxMessageReceived(message)
    }

    /// Clear all cached data
    public func clearCache() {
        cachedMessages = []
        unreadCount = 0
        // Clear UserDefaults on background queue
        RiviumPushDispatch.io { [weak self] in
            self?.prefs.removeObject(forKey: "\(InboxManager.PREFS_NAME).\(InboxManager.KEY_CACHED_MESSAGES)")
            self?.prefs.removeObject(forKey: "\(InboxManager.PREFS_NAME).\(InboxManager.KEY_UNREAD_COUNT)")
        }
        Log.d(InboxManager.TAG, "Cache cleared")
    }

    // MARK: - Private Methods

    private func updateMessageStatus(
        messageId: String,
        status: InboxMessageStatus,
        onSuccess: (() -> Void)?,
        onError: ((String) -> Void)?
    ) {
        Log.d(InboxManager.TAG, "Updating message \(messageId) status to \(status.rawValue)")

        apiClient.updateInboxMessage(messageId: messageId, status: status.rawValue) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // Update local cache
                if let index = self.cachedMessages.firstIndex(where: { $0.id == messageId }) {
                    let oldStatus = self.cachedMessages[index].status
                    var message = self.cachedMessages[index]
                    message.status = status
                    self.cachedMessages[index] = message

                    // Update unread count
                    if oldStatus == .unread && status != .unread {
                        self.unreadCount = max(0, self.unreadCount - 1)
                    }
                }
                self.saveCachedData()

                self.callback?.inboxMessageStatusChanged(messageId: messageId, status: status)
                onSuccess?()

            case .failure(let error):
                Log.e(InboxManager.TAG, "Update status failed", error: error)
                onError?("Failed to update message status: \(error.localizedDescription)")
            }
        }
    }

    private func parseMessagesResponse(_ json: String) -> InboxMessagesResponse {
        guard let data = json.data(using: .utf8) else {
            return InboxMessagesResponse(messages: [], total: 0, unreadCount: 0)
        }

        // Try parsing as a response object first
        if let response = try? JSONDecoder().decode(InboxMessagesResponse.self, from: data) {
            return response
        }

        // Try parsing as an array
        if let messages = try? JSONDecoder().decode([InboxMessage].self, from: data) {
            let unread = messages.filter { $0.status == .unread }.count
            return InboxMessagesResponse(messages: messages, total: messages.count, unreadCount: unread)
        }

        Log.e(InboxManager.TAG, "Failed to parse messages response")
        return InboxMessagesResponse(messages: [], total: 0, unreadCount: 0)
    }

    private func loadCachedData() {
        // Load directly to internal vars during init (no need for queue sync)
        if let data = prefs.data(forKey: "\(InboxManager.PREFS_NAME).\(InboxManager.KEY_CACHED_MESSAGES)"),
           let messages = try? JSONDecoder().decode([InboxMessage].self, from: data) {
            _cachedMessages = messages
        }
        _unreadCount = prefs.integer(forKey: "\(InboxManager.PREFS_NAME).\(InboxManager.KEY_UNREAD_COUNT)")
        Log.d(InboxManager.TAG, "Loaded \(_cachedMessages.count) cached messages, unread: \(_unreadCount)")
    }

    private func saveCachedData() {
        // Capture current state for async save
        let messagesToSave = cachedMessages
        let countToSave = unreadCount

        // Save to UserDefaults on background queue
        RiviumPushDispatch.io { [weak self] in
            if let data = try? JSONEncoder().encode(messagesToSave) {
                self?.prefs.set(data, forKey: "\(InboxManager.PREFS_NAME).\(InboxManager.KEY_CACHED_MESSAGES)")
            }
            self?.prefs.set(countToSave, forKey: "\(InboxManager.PREFS_NAME).\(InboxManager.KEY_UNREAD_COUNT)")
        }
    }
}
