import Foundation
import UIKit
import UserNotifications

/// Main entry point for Rivium Push SDK
///
/// Usage:
/// ```swift
/// let config = RiviumPushConfig(
///     apiKey: "rv_live_your_api_key"
/// )
///
/// RiviumPush.shared.initialize(config: config)
/// RiviumPush.shared.delegate = self
/// RiviumPush.shared.register()
/// ```
public class RiviumPush: NSObject, UNUserNotificationCenterDelegate {
    private static let TAG = "RiviumPush"
    private static let PREFS_NAME = "co.rivium.push"
    private static let KEY_DEVICE_ID = "deviceId"
    private static let KEY_SUBSCRIPTION_ID = "subscriptionId"
    private static let KEY_APP_VERSION = "appVersion"
    private static let KEY_USER_ID = "userId"

    /// Shared instance
    public static let shared = RiviumPush()

    /// Delegate for push events
    public weak var delegate: RiviumPushDelegate?

    private var config: RiviumPushConfig?
    private var apiClient: ApiClient?
    private var socketManager: PNSocketManager?
    private var voipManager: VoIPManager?
    private var inAppMessageManager: InAppMessageManager?
    private var inboxManager: InboxManager?

    private var deviceId: String?
    private var subscriptionId: String?
    private var voipToken: String?
    private var apnsToken: String?
    private var appId: String?
    private var userId: String?
    private var isInitialized = false
    private var abTestingManager: ABTestingManager?

    private override init() {
        super.init()
        setupAppLifecycleObservers()
    }

    // MARK: - Initialization

    /// Initialize the SDK
    public func initialize(config: RiviumPushConfig) {
        self.config = config
        self.apiClient = ApiClient(config: config)
        self.deviceId = getOrCreateDeviceId()
        // Restore previously-issued subscriptionId so the socket can subscribe to
        // the new topic immediately on launch — register() will refresh it.
        self.subscriptionId = UserDefaults.standard.string(forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_SUBSCRIPTION_ID)")
        // Use saved appId from server if available, otherwise fallback to apiKey prefix
        self.appId = loadSavedAppId() ?? String(config.apiKey.prefix(16))
        self.userId = UserDefaults.standard.string(forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_USER_ID)")
        self.isInitialized = true

        Log.d(RiviumPush.TAG, "Initialized with deviceId: \(deviceId ?? "nil"), appId: \(appId ?? "nil")")

        // Set as UNUserNotificationCenter delegate for foreground notification display
        if config.showNotificationInForeground {
            DispatchQueue.main.async {
                let center = UNUserNotificationCenter.current()
                if center.delegate == nil {
                    center.delegate = self
                    Log.d(RiviumPush.TAG, "Set as UNUserNotificationCenter delegate for foreground notifications")
                }
            }
        }

        // Check for app update
        checkForAppUpdate()
    }

    /// Set log level for SDK logging
    public func setLogLevel(_ level: RiviumPushLogLevel) {
        RiviumPushLogger.logLevel = level
        Log.d(RiviumPush.TAG, "Log level set to: \(level.name)")
    }

    // MARK: - Registration

    /// Register for push notifications.
    ///
    /// If `userId` is nil, the SDK falls back to the persisted userId from a
    /// previous session (matches OneSignal/Airship). Pass an explicit userId
    /// only when associating a new identity. Use `clearUserId()` to dissociate.
    /// - Parameters:
    ///   - userId: Optional user identifier
    ///   - metadata: Optional metadata dictionary
    public func register(userId: String? = nil, metadata: [String: String]? = nil) {
        guard let config = config else {
            let error = RiviumPushError.notInitialized
            delegate?.riviumPush(self, didFailWithError: error)
            delegate?.riviumPush(self, didFailWithDetailedError: error)
            return
        }

        // Store userId if provided; otherwise fall back to the previously
        // persisted userId restored at init.
        if let userId = userId {
            self.userId = userId
            // Save to UserDefaults on background queue to avoid blocking main thread
            RiviumPushDispatch.io {
                UserDefaults.standard.set(userId, forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_USER_ID)")
            }
        }
        let effectiveUserId = self.userId

        // Request notification permission
        NotificationManager.shared.requestPermission { [weak self] granted in
            guard let self = self else { return }

            if !granted {
                Log.w(RiviumPush.TAG, "Notification permission not granted")
            }

            if config.usePushKit {
                self.voipToken = nil // Reset so we detect new token
                self.registerForVoIP(userId: effectiveUserId, metadata: metadata)
            } else if config.useAPNs {
                self.voipToken = nil
                self.registerForAPNs(userId: effectiveUserId, metadata: metadata)
            } else {
                self.voipToken = nil
                self.registerDevice(userId: effectiveUserId, metadata: metadata, pushToken: "", apnsToken: nil)
            }
        }
    }

    /// Unregister from push notifications
    public func unregister() {
        socketManager?.disconnect()
        socketManager = nil
        voipManager = nil

        // Clear user ID
        userId = nil
        RiviumPushDispatch.io {
            UserDefaults.standard.removeObject(forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_USER_ID)")
        }

        Log.d(RiviumPush.TAG, "Unregistered")
    }

    // MARK: - PN Protocol Connection

    /// Start PN Protocol connection (call when app enters foreground)
    public func connect() {
        guard let config = config,
              let appId = appId,
              let deviceId = deviceId else {
            Log.d(RiviumPush.TAG, "connect() skipped - not initialized yet")
            return
        }

        // Don't connect without a token — wait for registration to complete
        guard config.pnToken != nil else {
            Log.d(RiviumPush.TAG, "connect() skipped - waiting for registration to provide token")
            return
        }

        Log.d(RiviumPush.TAG, "Connecting to pn-protocol (appId: \(appId))")

        if let existing = socketManager {
            if existing.isConnected {
                // Already connected — nothing to do
                Log.d(RiviumPush.TAG, "Socket manager already connected - reusing")
                return
            }

            // Exists but disconnected — try reconnecting without recreating.
            // Only recreate if the config has changed (e.g., new JWT token from registration).
            if existing.hasMatchingConfig(config) {
                Log.d(RiviumPush.TAG, "Socket manager exists but disconnected - reconnecting")
                existing.reconnectNow()
                return
            }

            // Config changed (new JWT token, etc.) — must recreate
            Log.d(RiviumPush.TAG, "Config changed - disconnecting existing socket manager")
            existing.disconnect()
            socketManager = nil
        }

        // First time or config changed — create new socket manager
        let appIdentifier = Bundle.main.bundleIdentifier ?? "_default"
        Log.d(RiviumPush.TAG, "Creating new PNSocketManager with appIdentifier: \(appIdentifier), subscriptionId: \(subscriptionId ?? "nil")")
        socketManager = PNSocketManager(config: config, appId: appId, deviceId: deviceId, appIdentifier: appIdentifier, subscriptionId: subscriptionId)
        socketManager?.delegate = self

        Log.d(RiviumPush.TAG, "Calling socketManager.connect()")
        socketManager?.connect()
    }

    /// Stop PN Protocol connection (call when app enters background)
    public func disconnect() {
        socketManager?.disconnect()
    }

    /// Check if PN Protocol is connected
    public var isConnected: Bool {
        return socketManager?.isConnected ?? false
    }

    // MARK: - Device Info

    /// Get current device ID
    public func getDeviceId() -> String? {
        return deviceId
    }

    /// Get the per-install subscription ID issued by the server during register().
    /// This is the canonical addressing key for inbox/A-B/in-app calls and the new
    /// MQTT topic. Returns `nil` until register() succeeds at least once.
    public func getSubscriptionId() -> String? {
        return subscriptionId
    }

    /// Get the currently-stored userId, if any. Survives app restarts —
    /// matches OneSignal/Airship behaviour. Returns `nil` if `setUserId` has
    /// never been called (or if `clearUserId` was called since).
    public func getUserId() -> String? {
        return userId
    }

    /// Get VoIP token (for debugging)
    public func getVoIPToken() -> String? {
        return voipToken
    }

    /// Get APNs device token (for debugging)
    public func getAPNsToken() -> String? {
        return apnsToken
    }

    /// Pass APNs device token from AppDelegate's didRegisterForRemoteNotificationsWithDeviceToken
    public func setAPNsToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.apnsToken = token
        Log.d(RiviumPush.TAG, "APNs token received: \(token)")
        delegate?.riviumPush(self, didReceiveAPNsToken: token)

        // If we were waiting for the APNs token during registration, complete it now
        let userId = UserDefaults.standard.string(forKey: "\(RiviumPush.PREFS_NAME).pendingUserId")
        let metadata = UserDefaults.standard.dictionary(forKey: "\(RiviumPush.PREFS_NAME).pendingMetadata") as? [String: String]

        // If not in VoIP mode, clear the VoIP token on server
        let clearVoip = !(config?.usePushKit ?? false)
        registerDevice(userId: userId, metadata: metadata, pushToken: clearVoip ? "" : nil, apnsToken: token)

        // Clean up
        RiviumPushDispatch.io {
            UserDefaults.standard.removeObject(forKey: "\(RiviumPush.PREFS_NAME).pendingUserId")
            UserDefaults.standard.removeObject(forKey: "\(RiviumPush.PREFS_NAME).pendingMetadata")
        }
    }

    // MARK: - Topic Subscriptions

    /// Subscribe to a topic
    public func subscribeTopic(_ topic: String) {
        guard let apiClient = apiClient, let deviceId = deviceId else {
            Log.e(RiviumPush.TAG, "SDK not initialized")
            return
        }

        Log.d(RiviumPush.TAG, "Subscribing to topic: \(topic)")

        apiClient.subscribeTopic(deviceId: deviceId, topic: topic) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                Log.d(RiviumPush.TAG, "Subscribed to topic: \(topic)")
            case .failure(let error):
                Log.e(RiviumPush.TAG, "Failed to subscribe to topic", error: error)
                self.delegate?.riviumPush(self, didFailWithError: error)
                self.delegate?.riviumPush(self, didFailWithDetailedError: RiviumPushError(errorCode: .subscriptionFailed, cause: error))
            }
        }
    }

    /// Unsubscribe from a topic
    public func unsubscribeTopic(_ topic: String) {
        guard let apiClient = apiClient, let deviceId = deviceId else {
            Log.e(RiviumPush.TAG, "SDK not initialized")
            return
        }

        Log.d(RiviumPush.TAG, "Unsubscribing from topic: \(topic)")

        apiClient.unsubscribeTopic(deviceId: deviceId, topic: topic) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                Log.d(RiviumPush.TAG, "Unsubscribed from topic: \(topic)")
            case .failure(let error):
                Log.e(RiviumPush.TAG, "Failed to unsubscribe from topic", error: error)
                self.delegate?.riviumPush(self, didFailWithError: error)
                self.delegate?.riviumPush(self, didFailWithDetailedError: RiviumPushError(errorCode: .unsubscriptionFailed, cause: error))
            }
        }
    }

    // MARK: - User Management

    /// Set user ID for the current device
    public func setUserId(_ userId: String) {
        guard let apiClient = apiClient, let deviceId = deviceId else {
            Log.e(RiviumPush.TAG, "SDK not initialized")
            return
        }

        Log.d(RiviumPush.TAG, "Setting user ID: \(userId)")

        self.userId = userId
        // Save to UserDefaults on background queue
        RiviumPushDispatch.io {
            UserDefaults.standard.set(userId, forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_USER_ID)")
        }

        apiClient.setUserId(deviceId: deviceId, userId: userId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                Log.d(RiviumPush.TAG, "User ID set: \(userId)")
                // Update in-app and inbox managers
                self.inAppMessageManager?.setUserId(userId)
                self.inboxManager?.setUserId(userId)
            case .failure(let error):
                Log.e(RiviumPush.TAG, "Failed to set user ID", error: error)
                self.delegate?.riviumPush(self, didFailWithError: error)
            }
        }
    }

    /// Clear user ID for the current device
    public func clearUserId() {
        guard let apiClient = apiClient, let deviceId = deviceId else {
            Log.e(RiviumPush.TAG, "SDK not initialized")
            return
        }

        Log.d(RiviumPush.TAG, "Clearing user ID")

        self.userId = nil
        // Clear from UserDefaults on background queue
        RiviumPushDispatch.io {
            UserDefaults.standard.removeObject(forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_USER_ID)")
        }

        apiClient.clearUserId(deviceId: deviceId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                Log.d(RiviumPush.TAG, "User ID cleared")
                self.inAppMessageManager?.setUserId(nil)
                self.inboxManager?.setUserId(nil)
            case .failure(let error):
                Log.e(RiviumPush.TAG, "Failed to clear user ID", error: error)
                self.delegate?.riviumPush(self, didFailWithError: error)
            }
        }
    }

    // MARK: - Initial Message & Actions

    /// Get the message that launched the app (when user tapped a notification)
    public func getInitialMessage() -> RiviumPushMessage? {
        return NotificationManager.shared.getInitialMessage()
    }

    /// Clear the initial message after handling
    public func clearInitialMessage() {
        NotificationManager.shared.clearInitialMessage()
    }

    /// Get the clicked action from a notification
    public func getClickedAction() -> (action: NotificationAction, message: RiviumPushMessage)? {
        return NotificationManager.shared.getClickedAction()
    }

    /// Clear the clicked action after handling
    public func clearClickedAction() {
        NotificationManager.shared.clearClickedAction()
    }

    // MARK: - In-App Messages

    /// Get the in-app message manager instance
    public func getInAppMessageManager() -> InAppMessageManager {
        if inAppMessageManager == nil {
            guard let apiClient = apiClient,
                  let appId = appId,
                  let deviceId = deviceId else {
                fatalError("RiviumPush not initialized")
            }
            inAppMessageManager = InAppMessageManager(apiClient: apiClient, appId: appId, deviceId: deviceId)
            inAppMessageManager?.setUserId(userId)
        }
        return inAppMessageManager!
    }

    /// Set the current view controller for in-app message display
    public func setCurrentViewController(_ viewController: UIViewController?) {
        getInAppMessageManager().setCurrentViewController(viewController)
    }

    /// Set callback for in-app message events
    public func setInAppMessageCallback(_ callback: InAppMessageCallback?) {
        getInAppMessageManager().callback = callback
    }

    /// Fetch in-app messages from server
    public func fetchInAppMessages(completion: (([InAppMessage]) -> Void)? = nil) {
        getInAppMessageManager().fetchMessages(completion: completion)
    }

    /// Trigger in-app messages for app open
    public func triggerInAppOnAppOpen() {
        if isInitialized {
            getInAppMessageManager().triggerOnAppOpen()
        }
    }

    /// Trigger in-app messages for a custom event
    public func triggerInAppEvent(_ eventName: String, properties: [String: Any]? = nil) {
        if isInitialized {
            getInAppMessageManager().triggerEvent(eventName, properties: properties)
        }
    }

    /// Trigger in-app messages for session start
    public func triggerInAppOnSessionStart() {
        if isInitialized {
            getInAppMessageManager().triggerOnSessionStart()
        }
    }

    /// Show a specific in-app message by ID
    public func showInAppMessage(_ messageId: String) {
        if isInitialized {
            getInAppMessageManager().showMessage(messageId)
        }
    }

    /// Dismiss the currently displayed in-app message
    public func dismissInAppMessage() {
        inAppMessageManager?.dismissCurrentMessage()
    }

    // MARK: - Inbox

    /// Get the inbox manager instance
    public func getInboxManager() -> InboxManager {
        if inboxManager == nil {
            guard let config = config,
                  let apiClient = apiClient,
                  let deviceId = deviceId else {
                fatalError("RiviumPush not initialized")
            }
            inboxManager = InboxManager(config: config, apiClient: apiClient, deviceId: deviceId, userId: userId)
        }
        return inboxManager!
    }

    /// Set callback for inbox events
    public func setInboxCallback(_ callback: InboxCallback?) {
        getInboxManager().callback = callback
    }

    /// Get inbox messages
    public func getInboxMessages(
        filter: InboxFilter = InboxFilter(),
        onSuccess: @escaping (InboxMessagesResponse) -> Void,
        onError: @escaping (String) -> Void
    ) {
        getInboxManager().getMessages(filter: filter, onSuccess: onSuccess, onError: onError)
    }

    /// Get a single inbox message
    public func getInboxMessage(
        messageId: String,
        onSuccess: @escaping (InboxMessage) -> Void,
        onError: @escaping (String) -> Void
    ) {
        getInboxManager().getMessage(messageId: messageId, onSuccess: onSuccess, onError: onError)
    }

    /// Mark an inbox message as read
    public func markInboxMessageAsRead(
        messageId: String,
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        getInboxManager().markAsRead(messageId: messageId, onSuccess: onSuccess, onError: onError)
    }

    /// Archive an inbox message
    public func archiveInboxMessage(
        messageId: String,
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        getInboxManager().archiveMessage(messageId: messageId, onSuccess: onSuccess, onError: onError)
    }

    /// Delete an inbox message
    public func deleteInboxMessage(
        messageId: String,
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        getInboxManager().deleteMessage(messageId: messageId, onSuccess: onSuccess, onError: onError)
    }

    /// Mark multiple inbox messages
    public func markMultipleInboxMessages(
        messageIds: [String],
        status: InboxMessageStatus,
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        getInboxManager().markMultiple(messageIds: messageIds, status: status, onSuccess: onSuccess, onError: onError)
    }

    /// Mark all inbox messages as read
    public func markAllInboxMessagesAsRead(
        onSuccess: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        getInboxManager().markAllAsRead(onSuccess: onSuccess, onError: onError)
    }

    /// Get unread inbox count (from cache)
    public func getInboxUnreadCount() -> Int {
        return inboxManager?.getUnreadCount() ?? 0
    }

    /// Fetch unread inbox count from server
    public func fetchInboxUnreadCount(
        onSuccess: @escaping (Int) -> Void,
        onError: ((String) -> Void)? = nil
    ) {
        getInboxManager().fetchUnreadCount(onSuccess: onSuccess, onError: onError)
    }

    /// Get cached inbox messages without network call
    public func getCachedInboxMessages() -> [InboxMessage] {
        return inboxManager?.getCachedMessages() ?? []
    }

    /// Clear inbox cache
    public func clearInboxCache() {
        inboxManager?.clearCache()
    }

    // MARK: - A/B Testing

    /// Get the A/B testing manager instance
    public func getABTestingManager() -> ABTestingManager {
        if abTestingManager == nil {
            guard let apiClient = apiClient,
                  let deviceId = deviceId else {
                fatalError("RiviumPush not initialized")
            }
            ABTestingManager.shared.configure(apiClient: apiClient, deviceId: deviceId)
            abTestingManager = ABTestingManager.shared
        }
        return abTestingManager!
    }

    /// Set delegate for A/B testing events
    public func setABTestingDelegate(_ delegate: ABTestingDelegate?) {
        getABTestingManager().delegate = delegate
    }

    /// Get active A/B tests for the app
    public func getActiveABTests(
        completion: @escaping (Result<[ABTestSummary], Error>) -> Void
    ) {
        getABTestingManager().getActiveTests(completion: completion)
    }

    /// Get variant assignment for a specific A/B test
    public func getABTestVariant(
        testId: String,
        forceRefresh: Bool = false,
        completion: @escaping (Result<ABTestVariant, Error>) -> Void
    ) {
        getABTestingManager().getVariant(testId: testId, forceRefresh: forceRefresh, completion: completion)
    }

    /// Get cached variant for an A/B test (synchronous, no network)
    public func getCachedABTestVariant(testId: String) -> ABTestVariant? {
        return getABTestingManager().getCachedVariant(testId: testId)
    }

    /// Track A/B test impression
    public func trackABTestImpression(
        testId: String,
        variantId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        getABTestingManager().trackImpression(testId: testId, variantId: variantId, completion: completion)
    }

    /// Track A/B test opened
    public func trackABTestOpened(
        testId: String,
        variantId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        getABTestingManager().trackOpened(testId: testId, variantId: variantId, completion: completion)
    }

    /// Track A/B test clicked
    public func trackABTestClicked(
        testId: String,
        variantId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        getABTestingManager().trackClicked(testId: testId, variantId: variantId, completion: completion)
    }

    /// Track display of an A/B test variant (impression + opened)
    public func trackABTestDisplay(
        variant: ABTestVariant,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        getABTestingManager().trackDisplay(variant: variant, completion: completion)
    }

    /// Clear A/B test cache
    public func clearABTestCache() {
        getABTestingManager().clearCache()
    }

    // MARK: - Notification Response Handling

    /// Process notification response when user taps on a notification
    /// This automatically tracks A/B test clicks if the notification is from an A/B test
    ///
    /// Call this from your UNUserNotificationCenterDelegate's
    /// userNotificationCenter(_:didReceive:withCompletionHandler:) method
    ///
    /// - Parameters:
    ///   - userInfo: The notification's userInfo dictionary
    ///   - actionIdentifier: The action identifier (e.g., UNNotificationDefaultActionIdentifier)
    /// - Returns: The RiviumPushMessage if it was a RiviumPush notification, nil otherwise
    @discardableResult
    public func handleNotificationResponse(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String? = nil
    ) -> RiviumPushMessage? {
        // Try to extract RiviumPushMessage from userInfo
        var message: RiviumPushMessage?

        // Check for embedded rivium_push_message
        if let messageDict = userInfo["rivium_push_message"] as? [String: Any] {
            // Convert [String: Any] to [AnyHashable: Any] for the from(payload:) method
            let payloadDict: [AnyHashable: Any] = Dictionary(uniqueKeysWithValues: messageDict.map { ($0.key, $0.value) })
            message = RiviumPushMessage.from(payload: payloadDict)
        } else {
            // Try to parse userInfo directly
            message = RiviumPushMessage.from(payload: userInfo)
        }

        guard let riviumPushMessage = message else {
            Log.d(RiviumPush.TAG, "Not a RiviumPush notification")
            return nil
        }

        Log.d(RiviumPush.TAG, "Processing notification response: messageId=\(riviumPushMessage.messageId ?? "nil")")

        // Check for A/B test data and track click automatically
        if let data = riviumPushMessage.data,
           let abTestId = data["abTestId"]?.value as? String,
           let variantId = data["variantId"]?.value as? String,
           !abTestId.isEmpty,
           !variantId.isEmpty {

            Log.d(RiviumPush.TAG, "A/B test notification clicked: testId=\(abTestId), variantId=\(variantId)")

            // Track click automatically
            trackABTestClicked(testId: abTestId, variantId: variantId) { result in
                switch result {
                case .success:
                    Log.d(RiviumPush.TAG, "A/B test click tracked successfully")
                case .failure(let error):
                    Log.e(RiviumPush.TAG, "Failed to track A/B test click", error: error)
                }
            }
        }

        // Store clicked action if action button was pressed
        if let actionId = actionIdentifier,
           actionId != "com.apple.UNNotificationDefaultActionIdentifier",
           let actions = riviumPushMessage.actions,
           let action = actions.first(where: { $0.id == actionId }) {
            NotificationManager.shared.setClickedAction(action, message: riviumPushMessage)
        }

        // Handle initial message storage and delegate notification
        if let del = delegate {
            // App is running with delegate set - notify via callback, DON'T store
            // (so it won't show again on restart)
            Log.d(RiviumPush.TAG, "App is running - notifying via delegate, not storing initial message")
            del.riviumPush(self, didReceiveMessage: riviumPushMessage)
            del.riviumPush(self, didTapNotification: riviumPushMessage)
        } else {
            // App is NOT running - store for getInitialMessage()
            Log.d(RiviumPush.TAG, "App not running - storing initial message for getInitialMessage()")
            NotificationManager.shared.setInitialMessage(riviumPushMessage)
        }

        return riviumPushMessage
    }

    // MARK: - Private Methods

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        Log.d(RiviumPush.TAG, "App entered background")
        delegate?.riviumPush(self, didChangeAppState: AppState(isInForeground: false))

        if config?.autoConnect == true {
            disconnect()
        }
    }

    @objc private func appWillEnterForeground() {
        Log.d(RiviumPush.TAG, "App will enter foreground")
        delegate?.riviumPush(self, didChangeAppState: AppState(isInForeground: true))

        if config?.autoConnect == true && isInitialized {
            connect()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications when app is in foreground (APNs-delivered)
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if config?.showNotificationInForeground == true {
            if #available(iOS 14.0, *) {
                completionHandler([.banner, .sound, .badge])
            } else {
                completionHandler([.alert, .sound, .badge])
            }
        } else {
            completionHandler([])
        }
    }

    /// Handle notification tap
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        handleNotificationResponse(userInfo: userInfo, actionIdentifier: response.actionIdentifier)
        completionHandler()
    }

    private func registerForAPNs(userId: String?, metadata: [String: String]?) {
        // Store registration params for when token arrives
        RiviumPushDispatch.io {
            UserDefaults.standard.set(userId, forKey: "\(RiviumPush.PREFS_NAME).pendingUserId")
            if let metadata = metadata {
                UserDefaults.standard.set(metadata, forKey: "\(RiviumPush.PREFS_NAME).pendingMetadata")
            }
        }

        // Request APNs token from iOS
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }

        // Fallback: If APNs token doesn't arrive in 5 seconds (simulator or no push entitlement),
        // proceed with registration without a push token to enable MQTT-only mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.apnsToken == nil {
                Log.w(RiviumPush.TAG, "APNs token not received after 5s, proceeding without push token (MQTT-only mode)")
                self.registerDevice(userId: userId, metadata: metadata, pushToken: nil, apnsToken: nil)
            }
        }
    }

    private func registerForVoIP(userId: String?, metadata: [String: String]?) {
        voipManager = VoIPManager()
        voipManager?.delegate = self
        voipManager?.register()

        // Store registration params for when token arrives (on background queue)
        RiviumPushDispatch.io {
            UserDefaults.standard.set(userId, forKey: "\(RiviumPush.PREFS_NAME).pendingUserId")
            if let metadata = metadata {
                UserDefaults.standard.set(metadata, forKey: "\(RiviumPush.PREFS_NAME).pendingMetadata")
            }
        }

        // Fallback: If VoIP token doesn't arrive in 3 seconds (simulator or no push entitlement),
        // proceed with registration without a push token to enable MQTT-only mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            // Only proceed if we haven't received a token yet (voipToken is still nil)
            if self.voipToken == nil {
                Log.w(RiviumPush.TAG, "VoIP token not received after 3s, proceeding without push token (MQTT-only mode)")
                self.registerDevice(userId: userId, metadata: metadata, pushToken: nil, apnsToken: nil)
            }
        }
    }

    private func registerDevice(userId: String?, metadata: [String: String]?, pushToken: String?, apnsToken: String? = nil) {
        guard let deviceId = deviceId else {
            let error = RiviumPushError.notInitialized
            delegate?.riviumPush(self, didFailWithError: error)
            delegate?.riviumPush(self, didFailWithDetailedError: error)
            return
        }

        // Pass bundle identifier as appIdentifier for per-app isolation
        let appIdentifier = Bundle.main.bundleIdentifier

        apiClient?.registerDevice(
            deviceId: deviceId,
            pushToken: pushToken,
            apnsToken: apnsToken,
            userId: userId,
            metadata: metadata,
            appIdentifier: appIdentifier
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                Log.d(RiviumPush.TAG, "Registered with server: \(response.deviceId), appId: \(response.appId ?? "nil")")

                // Update appId from server response if provided (projectId-based)
                if let serverAppId = response.appId, !serverAppId.isEmpty {
                    self.appId = serverAppId
                    Log.d(RiviumPush.TAG, "Using server-provided appId for PN Protocol: \(serverAppId)")
                    // Save appId for future sessions
                    self.saveAppId(serverAppId)
                }

                // Capture subscriptionId — the per-install UUID — and persist it so
                // the socket can subscribe to `rivium_push/{appId}/sub/{subscriptionId}`
                // on the next launch even before a fresh register() lands.
                if let subId = response.subscriptionId, !subId.isEmpty {
                    self.subscriptionId = subId
                    UserDefaults.standard.set(subId, forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_SUBSCRIPTION_ID)")
                    Log.d(RiviumPush.TAG, "Stored subscriptionId: \(subId)")
                }

                // Update PN Protocol config from server response (host, port, secure, JWT token)
                if let mqtt = response.mqtt {
                    let secure = mqtt.secure ?? true  // Default to secure (TLS) if not specified
                    Log.d(RiviumPush.TAG, "Updating PN config: host=\(mqtt.host), port=\(mqtt.port), secure=\(secure), token=\(mqtt.token != nil ? "present" : "nil")")
                    // Must unwrap and reassign since RiviumPushConfig is a struct (value type)
                    // Optional chaining (config?.updatePNConfig) doesn't persist mutations
                    if var updatedConfig = self.config {
                        updatedConfig.updatePNConfig(
                            host: mqtt.host,
                            port: UInt16(mqtt.port),
                            secure: secure,
                            token: mqtt.token
                        )
                        self.config = updatedConfig
                        Log.d(RiviumPush.TAG, "PN config updated - secure=\(secure), pnToken is now: \(updatedConfig.pnToken != nil ? "present" : "nil")")
                    }
                }

                self.delegate?.riviumPush(self, didRegisterWithDeviceId: response.deviceId)

                // Start PN Protocol connection for foreground
                if self.config?.autoConnect == true {
                    self.connect()
                }

            case .failure(let error):
                Log.e(RiviumPush.TAG, "Registration failed", error: error)
                self.delegate?.riviumPush(self, didFailWithError: error)
                self.delegate?.riviumPush(self, didFailWithDetailedError: RiviumPushError(errorCode: .registrationFailed, cause: error))
            }
        }
    }

    private func handleInboxUpdate(_ json: [String: Any]) {
        let messageId = json["messageId"] as? String ?? UUID().uuidString
        let title = json["title"] as? String ?? ""
        let body = json["body"] as? String ?? ""

        Log.d(RiviumPush.TAG, "Inbox update received: messageId=\(messageId)")

        let inboxMessage = InboxMessage(
            id: messageId,
            userId: userId,
            deviceId: deviceId,
            content: InboxContent(title: title, body: body),
            status: .unread,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        getInboxManager().handleIncomingMessage(inboxMessage)
    }

    private func handlePushMessage(_ message: RiviumPushMessage) {
        // Check if silent
        if message.silent {
            Log.d(RiviumPush.TAG, "Silent message received")
            delegate?.riviumPush(self, didReceiveMessage: message)
            return
        }

        // Show local notification if enabled for foreground
        // Check app state and showNotificationInForeground setting
        let appInForeground = UIApplication.shared.applicationState == .active
        let shouldShowNotification = !appInForeground || (config?.showNotificationInForeground ?? true)

        if shouldShowNotification {
            NotificationManager.shared.showNotification(message: message)
        } else {
            Log.d(RiviumPush.TAG, "Skipping notification display (app in foreground, showNotificationInForeground=false)")
        }

        // Notify delegate
        delegate?.riviumPush(self, didReceiveMessage: message)
    }

    private func getOrCreateDeviceId() -> String {
        let key = "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_DEVICE_ID)"

        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }

        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    private func saveAppId(_ appId: String) {
        // Save server-provided appId for future sessions
        RiviumPushDispatch.io {
            UserDefaults.standard.set(appId, forKey: "\(RiviumPush.PREFS_NAME).appId")
        }
    }

    private func loadSavedAppId() -> String? {
        return UserDefaults.standard.string(forKey: "\(RiviumPush.PREFS_NAME).appId")
    }

    private func checkForAppUpdate() {
        let key = "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_APP_VERSION)"
        let savedVersion = UserDefaults.standard.string(forKey: key)
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        if let savedVersion = savedVersion, savedVersion != currentVersion {
            Log.d(RiviumPush.TAG, "App updated from \(savedVersion) to \(currentVersion)")
            delegate?.riviumPush(self, didDetectAppUpdate: AppUpdateInfo(
                previousVersion: savedVersion,
                currentVersion: currentVersion,
                needsReregistration: true
            ))
        }

        // Save version on background queue
        RiviumPushDispatch.io {
            UserDefaults.standard.set(currentVersion, forKey: key)
        }
    }
}

// MARK: - VoIPManagerDelegate
extension RiviumPush: VoIPManager.VoIPManagerDelegate {
    func voipManager(_ manager: VoIPManager, didReceiveToken token: String) {
        self.voipToken = token
        delegate?.riviumPush(self, didReceiveVoIPToken: token)

        // Complete registration with token
        let userId = UserDefaults.standard.string(forKey: "\(RiviumPush.PREFS_NAME).pendingUserId")
        let metadata = UserDefaults.standard.dictionary(forKey: "\(RiviumPush.PREFS_NAME).pendingMetadata") as? [String: String]

        registerDevice(userId: userId, metadata: metadata, pushToken: token, apnsToken: nil)

        // Clean up on background queue
        RiviumPushDispatch.io {
            UserDefaults.standard.removeObject(forKey: "\(RiviumPush.PREFS_NAME).pendingUserId")
            UserDefaults.standard.removeObject(forKey: "\(RiviumPush.PREFS_NAME).pendingMetadata")
        }
    }

    func voipManager(_ manager: VoIPManager, didReceivePayload payload: [AnyHashable: Any]) {
        Log.d(RiviumPush.TAG, "VoIP payload received")

        if let message = RiviumPushMessage.from(payload: payload) {
            handlePushMessage(message)
        }
    }

    func voipManager(_ manager: VoIPManager, didFailWithError error: Error) {
        delegate?.riviumPush(self, didFailWithError: error)
        delegate?.riviumPush(self, didFailWithDetailedError: RiviumPushError.fromException(error))
    }
}

// MARK: - PNSocketManagerDelegate
extension RiviumPush: PNSocketManager.PNSocketManagerDelegate {
    func pnSocketManager(_ manager: PNSocketManager, didConnect success: Bool) {
        delegate?.riviumPush(self, didChangeConnectionState: success)
    }

    func pnSocketManager(_ manager: PNSocketManager, didDisconnect error: Error?) {
        delegate?.riviumPush(self, didChangeConnectionState: false)

        if let error = error {
            delegate?.riviumPush(self, didFailWithDetailedError: RiviumPushError.fromException(error))
        }
    }

    func pnSocketManager(_ manager: PNSocketManager, didReceiveMessage message: String, channel: String) {
        // Check for inbox_update type first
        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String,
           type == "inbox_update" {
            handleInboxUpdate(json)
            return
        }

        if let riviumPushMessage = RiviumPushMessage.from(json: message) {
            handlePushMessage(riviumPushMessage)
        }
    }
}
