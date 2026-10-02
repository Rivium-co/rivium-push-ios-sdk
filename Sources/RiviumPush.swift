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
    private static let KEY_HAS_REGISTERED = "hasRegistered"
    private static let KEY_LAST_REGISTERED_AT = "lastRegisteredAt"
    private static let KEY_REGISTRATION_FINGERPRINT = "registrationFingerprint"

    /// Version of this SDK, as reported to the Rivium Push backend.
    public static let sdkVersion: String = RiviumPushSDKInfo.version

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
    private var receiptStore: DeliveryReceiptStore?

    /// Signed user token, kept next to the SDK's other saved state. Lives
    /// outside `config` so a provider can be set before or after initialize().
    private let userTokens = UserTokenManager(defaults: .standard)

    /// Called when the server refuses the signed user token (`token_invalid`,
    /// `token_required`, `token_expired` after a failed refresh,
    /// `token_mismatch`) or the token provider fails (`token_provider_failed`).
    /// Informational: requests report their own errors as before. Called on
    /// the main queue, together with the delegate's `didFailWithAuthError`.
    public var onAuthError: ((RiviumPushAuthErrorEvent) -> Void)?

    /// An explicit register() is in progress; auto refresh stays out of its way.
    private var explicitRegisterInFlight = false
    /// Auto refresh asked iOS for a push token and is waiting to decide.
    private var autoRefreshPending = false

    /// The socket should be up: connect() ran and disconnect() has not.
    /// Network and foreground triggers only act while this is true.
    private var wantsConnection = false
    private let connectivity = ConnectivityMonitor()
    private let endpointMemory = MqttEndpointMemory()
    private var fastReconnectWork: DispatchWorkItem?
    private var fastReconnectForce = false
    /// Triggers that arrive together (path updates, foreground + active)
    /// collapse into one reconnect.
    private static let fastReconnectDebounce: TimeInterval = 1.0

    private override init() {
        super.init()
        setupAppLifecycleObservers()
    }

    // MARK: - Initialization

    /// Initialize the SDK
    public func initialize(config: RiviumPushConfig) {
        self.config = config
        if let tokenProvider = config.tokenProvider {
            userTokens.setProvider(tokenProvider)
        }
        let apiClient = ApiClient(config: config, userTokens: userTokens)
        apiClient.onAuthError = { [weak self] event in
            guard let self = self else { return }
            self.onAuthError?(event)
            self.delegate?.riviumPush(self, didFailWithAuthError: event)
        }
        self.apiClient = apiClient
        self.deviceId = getOrCreateDeviceId()
        // Restore previously-issued subscriptionId so the socket can subscribe to
        // the new topic immediately on launch — register() will refresh it.
        self.subscriptionId = UserDefaults.standard.string(forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_SUBSCRIPTION_ID)")
        // Use saved appId from server if available, otherwise fallback to apiKey prefix
        self.appId = loadSavedAppId() ?? String(config.apiKey.prefix(16))
        self.userId = UserDefaults.standard.string(forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_USER_ID)")
        // A saved token of another user is never sent for this one.
        if let userId = self.userId { userTokens.prepare(forUserId: userId) }
        self.receiptStore = DeliveryReceiptStore(appGroup: config.appGroup)
        self.isInitialized = true

        // Reconnect at once when the network comes back or changes.
        connectivity.onChange = { [weak self] kind, interfaceChanged in
            Log.d(RiviumPush.TAG, "Network path changed (\(kind.rawValue), interfaceChanged: \(interfaceChanged))")
            // The old socket went through an outage or sits on a dead interface.
            self?.scheduleFastReconnect(force: true)
        }
        connectivity.start()

        // Mirror the device id into the shared App Group so a Notification
        // Service Extension can confirm delivery. The extension runs in its
        // own process and cannot read this app's UserDefaults.
        shareDeviceIdWithExtension()

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

        // Keep the server's device record fresh without the app calling register().
        startAutoRefreshIfNeeded()
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
    public func register(userId: String? = nil, metadata: [String: Any]? = nil) {
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
            userTokens.prepare(forUserId: userId)
            // Save to UserDefaults on background queue to avoid blocking main thread
            RiviumPushDispatch.io {
                UserDefaults.standard.set(userId, forKey: "\(RiviumPush.PREFS_NAME).\(RiviumPush.KEY_USER_ID)")
            }
        }
        let effectiveUserId = self.userId

        // Explicit register() always registers; cancel any pending auto refresh.
        explicitRegisterInFlight = true
        autoRefreshPending = false

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
        stopWantingConnection()
        socketManager?.disconnect()
        socketManager = nil
        voipManager = nil

        // Detach the user server-side too: clearing only local state would
        // leave this device receiving the logged-out user's pushes.
        if userId != nil, let apiClient = apiClient, let deviceId = deviceId {
            apiClient.clearUserId(deviceId: deviceId) { [weak self] result in
                if case .success = result { self?.forgetUserInFingerprint() }
                if case .failure(let error) = result {
                    // The next registration retries the detach.
                    Log.e(RiviumPush.TAG, "Failed to detach user on unregister", error: error)
                }
            }
        } else {
            userTokens.clear()
        }

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
        wantsConnection = true

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
        socketManager = PNSocketManager(
            config: config,
            appId: appId,
            deviceId: deviceId,
            appIdentifier: appIdentifier,
            subscriptionId: subscriptionId,
            endpointMemory: endpointMemory,
            networkKind: { [weak self] in self?.connectivity.currentKind ?? .other }
        )
        socketManager?.delegate = self

        Log.d(RiviumPush.TAG, "Calling socketManager.connect()")
        socketManager?.connect()
    }

    /// Stop PN Protocol connection (call when app enters background)
    public func disconnect() {
        stopWantingConnection()
        socketManager?.disconnect()
    }

    private func stopWantingConnection() {
        wantsConnection = false
        fastReconnectWork?.cancel()
        fastReconnectWork = nil
        fastReconnectForce = false
    }

    /// Reconnect soon (debounced) with the backoff reset. `force` also drops a
    /// connection that looks alive. Does nothing unless the socket is wanted.
    private func scheduleFastReconnect(force: Bool) {
        guard wantsConnection, socketManager != nil else { return }
        fastReconnectForce = fastReconnectForce || force
        fastReconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let force = self.fastReconnectForce
            self.fastReconnectForce = false
            self.fastReconnectWork = nil
            guard self.wantsConnection, let manager = self.socketManager else { return }
            manager.reconnectNow(force: force)
        }
        fastReconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + RiviumPush.fastReconnectDebounce, execute: work)
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

    /// Publish the device id into the App Group shared with a Notification
    /// Service Extension, so `RiviumPushServiceExtension` can confirm delivery.
    /// No-op unless `appGroup` was set in the config.
    private func shareDeviceIdWithExtension() {
        guard
            let appGroup = config?.appGroup,
            let deviceId = deviceId,
            let shared = UserDefaults(suiteName: appGroup)
        else { return }

        shared.set(deviceId, forKey: RiviumPushServiceExtension.sharedDeviceIdKey)
        if let config = config {
            shared.set(config.sdkHeaderValue, forKey: RiviumPushSDKInfo.sharedIdentityKey)
        }
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

        // Token requested by auto refresh (not by register()): register only
        // if something changed.
        if autoRefreshPending && !explicitRegisterInFlight {
            completeAutoRefresh(apnsToken: token, voipToken: nil)
            return
        }

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
        // A cached token of another user is dropped; the provider is asked
        // again before the request.
        userTokens.prepare(forUserId: userId)
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
                self.forgetUserInFingerprint()
                self.inAppMessageManager?.setUserId(nil)
                self.inboxManager?.setUserId(nil)
            case .failure(let error):
                Log.e(RiviumPush.TAG, "Failed to clear user ID", error: error)
                self.delegate?.riviumPush(self, didFailWithError: error)
            }
        }
    }

    // MARK: - Signed User Tokens

    /// Set, replace or remove (nil) the signed user token provider.
    ///
    /// Works before or after `initialize(config:)`. The provider is called off
    /// the main thread and may switch to the main queue. If it throws or does
    /// not answer within 10 seconds, the request is sent without a token and
    /// an auth error (`token_provider_failed`) is reported.
    public func setTokenProvider(_ provider: RiviumPushTokenProvider?) {
        userTokens.setProvider(provider)
    }

    /// Completion-handler form of `setTokenProvider(_:)`. Call `completion`
    /// once, from any thread, with the token or nil when no user is signed in.
    public func setTokenProvider(callback provider: RiviumPushTokenCallbackProvider?) {
        userTokens.setCallbackProvider(provider)
    }

    /// Hand the SDK a signed user token you fetched yourself (nil forgets it).
    ///
    /// Without a provider the SDK cannot renew it: call this again with a new
    /// token before it expires, or when `token_expired` is reported.
    public func setUserToken(_ token: String?) {
        userTokens.set(token)
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

    // MARK: - Delivery Confirmation

    /// Report delivery of a remote (APNs) notification the app received.
    ///
    /// The SDK does this automatically when it is the
    /// `UNUserNotificationCenter` delegate and for messages received over its
    /// own connection. Call it yourself from
    /// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
    /// or from your own `userNotificationCenter(_:willPresent:…)`.
    ///
    /// Without a Notification Service Extension, iOS only hands the app a
    /// notification while it is running, so background deliveries go
    /// unconfirmed; see `RiviumPushServiceExtension`. Each message is reported
    /// once, even if both the extension and the app see it.
    public func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        reportDeliveryIfNeeded(messageId: RiviumPushServiceExtension.messageId(from: userInfo))
    }

    private func reportDeliveryIfNeeded(messageId: String?) {
        guard
            let messageId = messageId, !messageId.isEmpty,
            let apiClient = apiClient,
            let deviceId = deviceId,
            let store = receiptStore
        else { return }

        guard store.claim(messageId) else {
            Log.d(RiviumPush.TAG, "Delivery already reported: \(messageId)")
            return
        }

        apiClient.reportDelivered(messageId: messageId, deviceId: deviceId) { success in
            if success {
                Log.d(RiviumPush.TAG, "Delivery reported: \(messageId)")
            } else {
                // Let a later sighting of the message try again.
                store.release(messageId)
                Log.w(RiviumPush.TAG, "Failed to report delivery: \(messageId)")
            }
        }
    }

    // MARK: - Automatic Registration Refresh

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional:
            return true
        default:
            if #available(iOS 14.0, *), status == .ephemeral { return true }
            return false
        }
    }

    /// On launch, re-send the registration in the background if the install
    /// registered before and the record may be stale. Never prompts for
    /// permission and never blocks initialize().
    private func startAutoRefreshIfNeeded() {
        guard let config = config, config.autoRefresh else { return }
        guard UserDefaults.standard.bool(forKey: prefsKey(RiviumPush.KEY_HAS_REGISTERED)) else {
            Log.d(RiviumPush.TAG, "Auto refresh skipped - install has not registered yet")
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            guard RiviumPush.isAuthorized(settings.authorizationStatus) else {
                Log.d(RiviumPush.TAG, "Auto refresh skipped - notification permission not granted")
                return
            }

            DispatchQueue.main.async {
                guard !self.explicitRegisterInFlight, !self.autoRefreshPending else { return }
                self.autoRefreshPending = true

                let waitsForToken = config.usePushKit || config.useAPNs
                if config.usePushKit {
                    if self.voipManager == nil {
                        self.voipManager = VoIPManager()
                        self.voipManager?.delegate = self
                    }
                    self.voipManager?.register()
                } else if config.useAPNs {
                    // Apple recommends calling this on every launch; the token
                    // arrives through setAPNsToken(_:).
                    UIApplication.shared.registerForRemoteNotifications()
                }

                // No token (simulator, missing entitlement, the app does not
                // forward it): decide with what we know.
                let delay: TimeInterval = waitsForToken ? 10 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, self.autoRefreshPending else { return }
                    self.completeAutoRefresh(apnsToken: nil, voipToken: nil)
                }
            }
        }
    }

    private func completeAutoRefresh(apnsToken: String?, voipToken: String?) {
        autoRefreshPending = false

        let current = currentFingerprint(apnsToken: apnsToken, voipToken: voipToken)
        let reason = RegistrationRefresh.reason(
            hasRegistered: UserDefaults.standard.bool(forKey: prefsKey(RiviumPush.KEY_HAS_REGISTERED)),
            lastSuccess: loadLastRegisteredAt(),
            now: Date(),
            stored: loadFingerprint(),
            current: current
        )

        guard let reason = reason else {
            Log.d(RiviumPush.TAG, "Auto refresh skipped - registration is up to date")
            return
        }

        Log.d(RiviumPush.TAG, "Auto refreshing registration (\(reason.rawValue))")
        registerDevice(userId: userId, metadata: nil, pushToken: voipToken, apnsToken: apnsToken)
    }

    private func currentFingerprint(apnsToken: String?, voipToken: String?) -> RegistrationFingerprint {
        let info = Bundle.main.infoDictionary
        return RegistrationFingerprint(
            appVersion: info?["CFBundleShortVersionString"] as? String,
            appBuild: info?["CFBundleVersion"] as? String,
            sdkIdentity: config?.sdkHeaderValue
                ?? RiviumPushSDKInfo.headerValue(name: RiviumPushSDKInfo.name, version: RiviumPushSDKInfo.version),
            apnsToken: apnsToken,
            voipToken: voipToken,
            userId: userId
        )
    }

    /// Persist what was registered. Called only after the server accepted it.
    private func recordSuccessfulRegistration(apnsToken: String?, voipToken: String?, keepPreviousUser: Bool = false) {
        let previous = loadFingerprint()
        var fingerprint = currentFingerprint(
            apnsToken: apnsToken ?? previous?.apnsToken,
            voipToken: (config?.usePushKit ?? false) ? (voipToken ?? previous?.voipToken) : nil
        )
        if fingerprint.apnsToken == nil { fingerprint.apnsToken = self.apnsToken }
        if keepPreviousUser { fingerprint.userId = previous?.userId }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: prefsKey(RiviumPush.KEY_HAS_REGISTERED))
        defaults.set(Date().timeIntervalSince1970, forKey: prefsKey(RiviumPush.KEY_LAST_REGISTERED_AT))
        if let data = try? JSONEncoder().encode(fingerprint) {
            defaults.set(data, forKey: prefsKey(RiviumPush.KEY_REGISTRATION_FINGERPRINT))
        }
    }

    /// The server no longer has a user on this device; record that so the
    /// next registration does not detach it again.
    private func forgetUserInFingerprint() {
        guard var fingerprint = loadFingerprint(), fingerprint.userId != nil else { return }
        fingerprint.userId = nil
        if let data = try? JSONEncoder().encode(fingerprint) {
            UserDefaults.standard.set(data, forKey: prefsKey(RiviumPush.KEY_REGISTRATION_FINGERPRINT))
        }
    }

    private func loadFingerprint() -> RegistrationFingerprint? {
        guard let data = UserDefaults.standard.data(forKey: prefsKey(RiviumPush.KEY_REGISTRATION_FINGERPRINT)) else { return nil }
        return try? JSONDecoder().decode(RegistrationFingerprint.self, from: data)
    }

    private func loadLastRegisteredAt() -> Date? {
        let value = UserDefaults.standard.double(forKey: prefsKey(RiviumPush.KEY_LAST_REGISTERED_AT))
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    private func prefsKey(_ key: String) -> String {
        return "\(RiviumPush.PREFS_NAME).\(key)"
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

        // A tap proves delivery; covers apps without a Service Extension.
        reportDeliveryIfNeeded(messageId: RiviumPushServiceExtension.messageId(from: userInfo) ?? riviumPushMessage.messageId)

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

        // The system default-action identifier means a tap on the
        // notification body, not on an action button.
        let isActionButtonTap: Bool = {
            guard let id = actionIdentifier else { return false }
            return id != "com.apple.UNNotificationDefaultActionIdentifier"
        }()

        if isActionButtonTap,
           let actionId = actionIdentifier,
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
            if isActionButtonTap,
               let actionId = actionIdentifier,
               let action = riviumPushMessage.actions?.first(where: { $0.id == actionId }) {
                del.riviumPush(self, didReceiveNotificationAction: action, forMessage: riviumPushMessage)
            } else {
                del.riviumPush(self, didTapNotification: riviumPushMessage)
            }
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        // Back from Control Center, a call, an alert or the background: make
        // sure the socket is up (or probe it) without waiting for the backoff.
        scheduleFastReconnect(force: false)
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
        // Confirm delivery of a push that arrived while the app is in the
        // foreground (skipped if the Service Extension already reported it).
        // Local notifications the SDK posts for socket messages carry the same
        // id and are deduplicated.
        handleRemoteNotification(userInfo: notification.request.content.userInfo)

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

    private func registerForAPNs(userId: String?, metadata: [String: Any]?) {
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

    private func registerForVoIP(userId: String?, metadata: [String: Any]?) {
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

    private func registerDevice(userId: String?, metadata: [String: Any]?, pushToken: String?, apnsToken: String? = nil) {
        guard let deviceId = deviceId else {
            let error = RiviumPushError.notInitialized
            delegate?.riviumPush(self, didFailWithError: error)
            delegate?.riviumPush(self, didFailWithDetailedError: error)
            return
        }

        // The server treats a missing userId as "keep the existing one", so a
        // registration can never detach a user. If a user was attached at the
        // last successful registration and is gone now (clearUserId() whose
        // request failed, or unregister()), detach it explicitly first so the
        // device stops receiving that user's pushes.
        // Checks self.userId too: some paths pass nil only because no pending
        // userId was stored, while the SDK still has a signed-in user.
        if userId == nil, self.userId == nil, loadFingerprint()?.userId != nil, let apiClient = apiClient {
            apiClient.clearUserId(deviceId: deviceId) { [weak self] result in
                guard let self = self else { return }
                var keepUserInFingerprint = false
                if case .failure(let error) = result {
                    // Keep the old user in the fingerprint so the next launch retries.
                    Log.e(RiviumPush.TAG, "Failed to detach user from device", error: error)
                    keepUserInFingerprint = true
                }
                self.sendRegistration(deviceId: deviceId, userId: nil, metadata: metadata, pushToken: pushToken,
                                      apnsToken: apnsToken, keepPreviousUser: keepUserInFingerprint)
            }
            return
        }

        sendRegistration(deviceId: deviceId, userId: userId, metadata: metadata, pushToken: pushToken,
                         apnsToken: apnsToken, keepPreviousUser: false)
    }

    private func sendRegistration(
        deviceId: String,
        userId: String?,
        metadata: [String: Any]?,
        pushToken: String?,
        apnsToken: String?,
        keepPreviousUser: Bool
    ) {

        // Pass bundle identifier as appIdentifier for per-app isolation
        let appIdentifier = Bundle.main.bundleIdentifier

        // With PushKit disabled a VoIP token must never linger on the device
        // row. "" tells the server to clear it; nil would mean "keep what you
        // have", which left stale tokens behind on the registration paths that
        // don't carry one (APNs timeout, MQTT-only fallback). A stale VoIP
        // token is not harmless: iOS terminates an app that receives a VoIP
        // push without reporting a CallKit call, and can revoke the
        // entitlement.
        let effectivePushToken: String? =
            (config?.usePushKit ?? false) ? pushToken : ""

        // Auto-captured device attributes — sent as top-level fields so the
        // dashboard's segment builder can filter on them as preset fields.
        let attributes = Self.captureDeviceAttributes()

        apiClient?.registerDevice(
            deviceId: deviceId,
            pushToken: effectivePushToken,
            apnsToken: apnsToken,
            userId: userId,
            metadata: metadata,
            appIdentifier: appIdentifier,
            appVersion: attributes.appVersion,
            appBuild: attributes.appBuild,
            osVersion: attributes.osVersion,
            deviceModel: attributes.deviceModel,
            language: attributes.language,
            country: attributes.country,
            timezone: attributes.timezone,
            installId: InstallId.current
        ) { [weak self] result in
            guard let self = self else { return }

            self.explicitRegisterInFlight = false

            switch result {
            case .success(let response):
                self.recordSuccessfulRegistration(apnsToken: apnsToken, voipToken: pushToken, keepPreviousUser: keepPreviousUser)
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
                            token: mqtt.token,
                            endpoints: response.mqttEndpoints?.endpoints ?? []
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
        // Received over the socket or PushKit: the message is on the device.
        reportDeliveryIfNeeded(messageId: message.messageId)

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

    // MARK: - Device Attributes

    struct DeviceAttributes {
        let appVersion: String?
        let appBuild: Int?
        let osVersion: String?
        let deviceModel: String?
        let language: String?
        let country: String?
        let timezone: String?
    }

    /// Read platform-native device attributes. Sent on every register() so
    /// the dashboard can segment by app version, OS, locale, timezone, etc.
    /// without the customer app having to populate metadata manually.
    private static func captureDeviceAttributes() -> DeviceAttributes {
        // App version — CFBundleShortVersionString is the user-facing "2.0.0".
        // CFBundleVersion is the build number ("18"); coerced to Int, dropped
        // if it's a dotted form ("1.2.3") that can't be represented as one.
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let appBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) }

        let osVersion = UIDevice.current.systemVersion

        // utsname.machine returns the hardware identifier ("iPhone14,2"),
        // not a marketing name — deliberate, so the dashboard operator can
        // filter by exact model without name-mangling.
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let deviceModel = machineMirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }

        let locale = Locale.current
        let language = locale.languageCode
        let country = locale.regionCode
        let timezone = TimeZone.current.identifier

        return DeviceAttributes(
            appVersion: appVersion,
            appBuild: appBuild,
            osVersion: osVersion,
            deviceModel: deviceModel.isEmpty ? nil : deviceModel,
            language: language,
            country: country,
            timezone: timezone
        )
    }
}

// MARK: - VoIPManagerDelegate
extension RiviumPush: VoIPManager.VoIPManagerDelegate {
    func voipManager(_ manager: VoIPManager, didReceiveToken token: String) {
        self.voipToken = token
        delegate?.riviumPush(self, didReceiveVoIPToken: token)

        if autoRefreshPending && !explicitRegisterInFlight {
            completeAutoRefresh(apnsToken: nil, voipToken: token)
            return
        }

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
