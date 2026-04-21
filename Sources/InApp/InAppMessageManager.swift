import Foundation
import UIKit

/// Manages in-app messages: fetching, caching, triggering, and tracking
public class InAppMessageManager {
    private static let TAG = "InApp"
    private static let PREFS_NAME = "rivium_push_inapp"
    private static let KEY_IMPRESSIONS = "impressions"
    private static let KEY_SESSION_COUNT = "session_count"
    private static let KEY_CACHED_MESSAGES = "cached_messages"
    private static let KEY_LAST_FETCH = "last_fetch"
    private static let CACHE_TTL_MS: TimeInterval = 5 * 60 // 5 minutes

    private let apiClient: ApiClient
    private let appId: String
    private let deviceId: String
    private let prefs: UserDefaults

    // Thread-safe state access using a serial queue
    private let stateQueue = DispatchQueue(label: "co.rivium.push.inapp.state", qos: .userInitiated)

    // State properties - access must be synchronized
    private var _cachedMessages: [InAppMessage] = []
    private var _impressionCounts: [String: Int] = [:]
    private var _sessionCount: Int = 0
    private var _userId: String?
    private var _isShowingMessage = false

    // Thread-safe property accessors
    private var cachedMessages: [InAppMessage] {
        get { stateQueue.sync { _cachedMessages } }
        set { stateQueue.sync { _cachedMessages = newValue } }
    }

    private var impressionCounts: [String: Int] {
        get { stateQueue.sync { _impressionCounts } }
        set { stateQueue.sync { _impressionCounts = newValue } }
    }

    private var sessionCount: Int {
        get { stateQueue.sync { _sessionCount } }
        set { stateQueue.sync { _sessionCount = newValue } }
    }

    private var userId: String? {
        get { stateQueue.sync { _userId } }
        set { stateQueue.sync { _userId = newValue } }
    }

    private var isShowingMessage: Bool {
        get { stateQueue.sync { _isShowingMessage } }
        set { stateQueue.sync { _isShowingMessage = newValue } }
    }

    public weak var callback: InAppMessageCallback?
    private weak var currentViewController: UIViewController?
    private var currentMessageView: InAppMessageView?

    public static var shared: InAppMessageManager?

    init(apiClient: ApiClient, appId: String, deviceId: String) {
        self.apiClient = apiClient
        self.appId = appId
        self.deviceId = deviceId
        self.prefs = UserDefaults.standard

        // Load from disk on background queue, store directly to internal vars
        let loadedSessionCount = prefs.integer(forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_SESSION_COUNT)")
        _sessionCount = loadedSessionCount

        loadImpressionCounts()
        loadCachedMessages()

        InAppMessageManager.shared = self
    }

    // MARK: - Public API

    /// Set the current view controller for displaying messages
    public func setCurrentViewController(_ viewController: UIViewController?) {
        self.currentViewController = viewController
    }

    /// Set the user ID for targeting
    public func setUserId(_ userId: String?) {
        self.userId = userId
    }

    /// Increment session count (call when app starts)
    public func incrementSessionCount() {
        let newCount = stateQueue.sync { () -> Int in
            _sessionCount += 1
            return _sessionCount
        }
        // Save to UserDefaults on background queue
        RiviumPushDispatch.io { [weak self] in
            self?.prefs.set(newCount, forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_SESSION_COUNT)")
        }
        Log.d(InAppMessageManager.TAG, "Session count: \(newCount)")
    }

    /// Fetch all messages from server (Google/Firebase approach)
    /// Messages are fetched without trigger filter and filtered locally
    public func fetchMessages(completion: (([InAppMessage]) -> Void)? = nil) {
        Log.d(InAppMessageManager.TAG, "fetchMessages() called, deviceId=\(deviceId)")

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            // Fetch ALL messages without trigger filter (like Firebase)
            // Local filtering happens in findAndShowMessage()
            var params: [String: Any] = [
                "deviceId": self.deviceId,
                "sessionCount": self.sessionCount,
                "locale": Locale.current.identifier
            ]
            if let userId = self.userId {
                params["userId"] = userId
            }

            Log.d(InAppMessageManager.TAG, "Fetching in-app messages with params: \(params)")

            self.apiClient.getInAppMessages(params: params) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let json):
                    Log.d(InAppMessageManager.TAG, "API response received")
                    let messages = self.parseMessages(json)
                    self.cachedMessages = messages
                    self.saveCachedMessages()
                    // Save timestamp on background queue
                    RiviumPushDispatch.io {
                        self.prefs.set(Date().timeIntervalSince1970, forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_LAST_FETCH)")
                    }

                    Log.d(InAppMessageManager.TAG, "Fetched \(messages.count) in-app messages")
                    // Return only messages that haven't reached their impression limit
                    let availableMessages = self.filterAvailableMessages(messages)
                    Log.d(InAppMessageManager.TAG, "Available messages (after filtering consumed): \(availableMessages.count)")
                    completion?(availableMessages)

                case .failure(let error):
                    Log.e(InAppMessageManager.TAG, "Failed to fetch messages", error: error)
                    self.callback?.inAppMessageError("Failed to fetch messages: \(error.localizedDescription)")
                    let availableMessages = self.filterAvailableMessages(self.cachedMessages)
                    completion?(availableMessages)
                }
            }
        }
    }

    /// Filter messages that are still available (haven't reached impression limit)
    private func filterAvailableMessages(_ messages: [InAppMessage]) -> [InAppMessage] {
        let now = Date().timeIntervalSince1970
        // Read impression counts once (thread-safe)
        let currentCounts = impressionCounts
        Log.d(InAppMessageManager.TAG, "filterAvailableMessages: currentCounts = \(currentCounts)")

        return messages.filter { message in
            // Check impression limit
            let impressions = currentCounts[message.id] ?? 0
            Log.d(InAppMessageManager.TAG, "Checking message \(message.id): impressions=\(impressions), maxImpressions=\(message.maxImpressions)")
            if impressions >= message.maxImpressions {
                Log.d(InAppMessageManager.TAG, "Filtering out \(message.id): impression limit reached (\(impressions)/\(message.maxImpressions))")
                return false
            }

            // Check date range
            if let startDate = message.startDate, now < startDate {
                return false
            }
            if let endDate = message.endDate, now > endDate {
                return false
            }

            return true
        }
    }

    /// Trigger messages for app open event
    public func triggerOnAppOpen() {
        Log.d(InAppMessageManager.TAG, "Triggering on_app_open")
        triggerMessages(triggerType: .onAppOpen)
    }

    /// Trigger messages for a custom event
    public func triggerEvent(_ eventName: String, properties: [String: Any]? = nil) {
        Log.d(InAppMessageManager.TAG, "Triggering event: \(eventName)")
        triggerMessages(triggerType: .onEvent, eventName: eventName)
    }

    /// Trigger messages for session start
    public func triggerOnSessionStart() {
        Log.d(InAppMessageManager.TAG, "Triggering on_session_start")
        incrementSessionCount()
        triggerMessages(triggerType: .onSessionStart)
    }

    /// Show a specific message manually
    public func showMessage(_ messageId: String) {
        if let message = cachedMessages.first(where: { $0.id == messageId }) {
            showMessageInternal(message)
        } else {
            Log.w(InAppMessageManager.TAG, "Message not found: \(messageId)")
        }
    }

    /// Dismiss the currently displayed message
    public func dismissCurrentMessage() {
        currentMessageView?.dismiss()
        currentMessageView = nil
        isShowingMessage = false
    }

    /// Record an impression
    public func recordImpression(messageId: String, action: InAppImpressionAction, buttonId: String? = nil) {
        Log.d(InAppMessageManager.TAG, "recordImpression called: action=\(action.rawValue), messageId=\(messageId)")

        // Update local impression count SYNCHRONOUSLY first, so it's immediately available for filtering
        if action == .impression {
            // Use stateQueue directly for atomic update
            let newCount = stateQueue.sync { () -> Int in
                let oldCount = _impressionCounts[messageId] ?? 0
                let count = oldCount + 1
                _impressionCounts[messageId] = count
                Log.d(InAppMessageManager.TAG, "Inside stateQueue: old=\(oldCount), new=\(count), all counts=\(self._impressionCounts)")
                return count
            }
            Log.d(InAppMessageManager.TAG, "Updated local impression count for \(messageId): \(newCount)")

            // Save to disk asynchronously (but the in-memory state is already updated)
            saveImpressionCounts()
        }

        // Then send to server asynchronously
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            let params: [String: Any] = [
                "messageId": messageId,
                "deviceId": self.deviceId,
                "action": action.rawValue,
                "buttonId": buttonId ?? "",
                "userId": self.userId ?? ""
            ]

            self.apiClient.recordInAppImpression(params: params)
            Log.d(InAppMessageManager.TAG, "Sent impression to server: \(action.rawValue) for \(messageId)")
        }
    }

    /// Clear all cached data
    public func clearCache() {
        cachedMessages = []
        impressionCounts = [:]
        // Clear UserDefaults on background queue
        RiviumPushDispatch.io { [weak self] in
            self?.prefs.removeObject(forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_CACHED_MESSAGES)")
            self?.prefs.removeObject(forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_IMPRESSIONS)")
            self?.prefs.removeObject(forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_LAST_FETCH)")
        }
        Log.d(InAppMessageManager.TAG, "Cache cleared")
    }

    /// Get cached messages (filtered to only show available ones)
    public func getCachedMessages() -> [InAppMessage] {
        return filterAvailableMessages(cachedMessages)
    }

    // MARK: - Private Methods

    private func triggerMessages(triggerType: InAppTriggerType, eventName: String? = nil) {
        Log.d(InAppMessageManager.TAG, "triggerMessages() - triggerType=\(triggerType.rawValue), eventName=\(eventName ?? "nil")")

        if isShowingMessage {
            Log.d(InAppMessageManager.TAG, "Already showing a message, skipping trigger")
            return
        }

        // Check if cache is fresh enough
        let lastFetch = prefs.double(forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_LAST_FETCH)")
        let cacheAge = Date().timeIntervalSince1970 - lastFetch

        if cacheAge > InAppMessageManager.CACHE_TTL_MS {
            Log.d(InAppMessageManager.TAG, "Cache expired, fetching fresh messages...")
            fetchMessages { [weak self] messages in
                self?.findAndShowMessage(messages: messages, triggerType: triggerType, eventName: eventName)
            }
        } else {
            Log.d(InAppMessageManager.TAG, "Using cached messages (\(cachedMessages.count) messages)")
            findAndShowMessage(messages: cachedMessages, triggerType: triggerType, eventName: eventName)
        }
    }

    private func findAndShowMessage(messages: [InAppMessage], triggerType: InAppTriggerType, eventName: String?) {
        Log.d(InAppMessageManager.TAG, "findAndShowMessage() - triggerType=\(triggerType.rawValue)")
        Log.d(InAppMessageManager.TAG, "Total messages to check: \(messages.count)")

        let now = Date().timeIntervalSince1970

        let eligibleMessages = messages.filter { message in
            Log.d(InAppMessageManager.TAG, "Checking message: \(message.id) (\(message.name))")

            // Check trigger type
            if message.triggerType != triggerType {
                Log.d(InAppMessageManager.TAG, "  - SKIP: trigger type mismatch")
                return false
            }

            // Check event name for ON_EVENT trigger
            if triggerType == .onEvent {
                if message.triggerEvent != eventName {
                    Log.d(InAppMessageManager.TAG, "  - SKIP: event name mismatch")
                    return false
                }
            }

            // Check session count
            if sessionCount < message.minSessionCount {
                Log.d(InAppMessageManager.TAG, "  - SKIP: session count too low")
                return false
            }

            // Check impression limit
            let impressions = impressionCounts[message.id] ?? 0
            if impressions >= message.maxImpressions {
                Log.d(InAppMessageManager.TAG, "  - SKIP: impression limit reached")
                return false
            }

            // Check date range
            if let startDate = message.startDate, now < startDate {
                Log.d(InAppMessageManager.TAG, "  - SKIP: before start date")
                return false
            }
            if let endDate = message.endDate, now > endDate {
                Log.d(InAppMessageManager.TAG, "  - SKIP: after end date")
                return false
            }

            Log.d(InAppMessageManager.TAG, "  - ELIGIBLE: message passes all checks")
            return true
        }.sorted { $0.priority > $1.priority }

        Log.d(InAppMessageManager.TAG, "Eligible messages: \(eligibleMessages.count)")

        if let messageToShow = eligibleMessages.first {
            Log.d(InAppMessageManager.TAG, "Will show message: \(messageToShow.id) (\(messageToShow.name))")

            if messageToShow.delaySeconds > 0 {
                Log.d(InAppMessageManager.TAG, "Delaying message display by \(messageToShow.delaySeconds) seconds")
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(messageToShow.delaySeconds)) { [weak self] in
                    self?.showMessageInternal(messageToShow)
                }
            } else {
                showMessageInternal(messageToShow)
            }
        } else {
            Log.d(InAppMessageManager.TAG, "No eligible messages to show")
        }
    }

    private func showMessageInternal(_ message: InAppMessage) {
        Log.d(InAppMessageManager.TAG, "showMessageInternal() called for message: \(message.id)")

        isShowingMessage = true

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let content = message.getLocalizedContent()
            Log.d(InAppMessageManager.TAG, "Showing message with content: title='\(content.title)', backgroundColor='\(content.backgroundColor ?? "nil")', textColor='\(content.textColor ?? "nil")'")

            // Check if a callback is set (Flutter/React Native manages UI)
            if self.callback != nil {
                // Callback is set - let the wrapper (Flutter/RN) handle the UI
                // We only record impression and notify callback, no native UI shown
                Log.d(InAppMessageManager.TAG, "Callback is set - delegating UI to wrapper (Flutter/React Native)")

                // Record impression
                self.recordImpression(messageId: message.id, action: .impression)

                // Notify callback - wrapper will show its own UI
                self.callback?.inAppMessageReady(message)
            } else {
                // No callback - show native iOS UI
                Log.d(InAppMessageManager.TAG, "No callback set - showing native iOS UI")

                guard let viewController = self.currentViewController else {
                    Log.w(InAppMessageManager.TAG, "No view controller available to show message")
                    self.isShowingMessage = false
                    return
                }

                if viewController.isBeingDismissed {
                    Log.w(InAppMessageManager.TAG, "View controller is being dismissed, cannot show message")
                    self.isShowingMessage = false
                    return
                }

                // Create and show the native message view
                self.currentMessageView = InAppMessageView.show(
                    in: viewController,
                    message: message,
                    content: content,
                    onButtonClick: { [weak self] button in
                        self?.handleButtonClick(message: message, button: button)
                    },
                    onDismiss: { [weak self] in
                        self?.handleDismiss(message: message)
                    }
                )

                // Record impression
                self.recordImpression(messageId: message.id, action: .impression)
            }
        }
    }

    private func handleButtonClick(message: InAppMessage, button: InAppButton) {
        Log.d(InAppMessageManager.TAG, "Button clicked: \(button.id) - \(button.action.rawValue)")

        recordImpression(messageId: message.id, action: .buttonClick, buttonId: button.id)

        switch button.action {
        case .dismiss:
            dismissCurrentMessage()
        case .deepLink:
            if let value = button.value, let url = URL(string: value) {
                UIApplication.shared.open(url)
            }
            dismissCurrentMessage()
        case .url:
            if let value = button.value, let url = URL(string: value) {
                UIApplication.shared.open(url)
            }
            dismissCurrentMessage()
        case .custom:
            callback?.inAppMessageButtonClicked(message, button: button)
        }
    }

    private func handleDismiss(message: InAppMessage) {
        Log.d(InAppMessageManager.TAG, "Message dismissed: \(message.id)")
        isShowingMessage = false
        currentMessageView = nil

        recordImpression(messageId: message.id, action: .dismiss)
        callback?.inAppMessageDismissed(message)
    }

    private func parseMessages(_ json: String) -> [InAppMessage] {
        guard let data = json.data(using: .utf8) else { return [] }

        do {
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let messages = array.compactMap { InAppMessage.fromJson($0) }
                // Log each message's maxImpressions for debugging
                for msg in messages {
                    Log.d(InAppMessageManager.TAG, "Parsed message \(msg.id) (\(msg.name)): maxImpressions=\(msg.maxImpressions)")
                }
                return messages
            }
        } catch {
            Log.e(InAppMessageManager.TAG, "Failed to parse messages", error: error)
        }

        return []
    }

    private func loadCachedMessages() {
        guard let json = prefs.string(forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_CACHED_MESSAGES)") else {
            return
        }
        _cachedMessages = parseMessages(json)
    }

    private func saveCachedMessages() {
        // Capture current state
        let messagesToSave = cachedMessages
        // Save to UserDefaults on background queue
        RiviumPushDispatch.io { [weak self] in
            guard let data = try? JSONEncoder().encode(messagesToSave),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            self?.prefs.set(json, forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_CACHED_MESSAGES)")
        }
    }

    private func loadImpressionCounts() {
        guard let data = prefs.data(forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_IMPRESSIONS)"),
              let counts = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return
        }
        _impressionCounts = counts
    }

    private func saveImpressionCounts() {
        // Capture current state
        let countsToSave = impressionCounts
        // Save to UserDefaults on background queue
        RiviumPushDispatch.io { [weak self] in
            guard let data = try? JSONEncoder().encode(countsToSave) else { return }
            self?.prefs.set(data, forKey: "\(InAppMessageManager.PREFS_NAME).\(InAppMessageManager.KEY_IMPRESSIONS)")
        }
    }
}
