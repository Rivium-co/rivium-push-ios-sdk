import Foundation

/// Reconnection state information
public struct ReconnectionState {
    public let attempt: Int
    public let nextRetryMs: Int64

    public init(attempt: Int, nextRetryMs: Int64) {
        self.attempt = attempt
        self.nextRetryMs = nextRetryMs
    }

    public func toDictionary() -> [String: Any] {
        return [
            "attempt": attempt,
            "nextRetryMs": nextRetryMs
        ]
    }
}

/// Network state information
public struct NetworkState {
    public let isAvailable: Bool
    public let networkType: String

    public init(isAvailable: Bool, networkType: String) {
        self.isAvailable = isAvailable
        self.networkType = networkType
    }

    public func toDictionary() -> [String: Any] {
        return [
            "isAvailable": isAvailable,
            "networkType": networkType
        ]
    }
}

/// App state information
public struct AppState {
    public let isInForeground: Bool

    public init(isInForeground: Bool) {
        self.isInForeground = isInForeground
    }

    public func toDictionary() -> [String: Any] {
        return ["isInForeground": isInForeground]
    }
}

/// App update information
public struct AppUpdateInfo {
    public let previousVersion: String
    public let currentVersion: String
    public let needsReregistration: Bool

    public init(previousVersion: String, currentVersion: String, needsReregistration: Bool) {
        self.previousVersion = previousVersion
        self.currentVersion = currentVersion
        self.needsReregistration = needsReregistration
    }

    public func toDictionary() -> [String: Any] {
        return [
            "previousVersion": previousVersion,
            "currentVersion": currentVersion,
            "needsReregistration": needsReregistration
        ]
    }
}

/// Delegate protocol for RiviumPush events
public protocol RiviumPushDelegate: AnyObject {
    /// Called when a push message is received
    func riviumPush(_ riviumPush: RiviumPush, didReceiveMessage message: RiviumPushMessage)

    /// Called when connection state changes (MQTT)
    func riviumPush(_ riviumPush: RiviumPush, didChangeConnectionState connected: Bool)

    /// Called when device is registered successfully
    func riviumPush(_ riviumPush: RiviumPush, didRegisterWithDeviceId deviceId: String)

    /// Called when VoIP token is received
    func riviumPush(_ riviumPush: RiviumPush, didReceiveVoIPToken token: String)

    /// Called when APNs device token is received
    func riviumPush(_ riviumPush: RiviumPush, didReceiveAPNsToken token: String)

    /// Called when an error occurs (simple string message)
    func riviumPush(_ riviumPush: RiviumPush, didFailWithError error: Error)

    /// Called when a detailed error occurs with error codes
    func riviumPush(_ riviumPush: RiviumPush, didFailWithDetailedError error: RiviumPushError)

    /// Called when the SDK is automatically retrying connection with exponential backoff
    func riviumPush(_ riviumPush: RiviumPush, didStartReconnecting state: ReconnectionState)

    /// Called when network connectivity changes
    func riviumPush(_ riviumPush: RiviumPush, didChangeNetworkState state: NetworkState)

    /// Called when the app transitions between foreground and background
    func riviumPush(_ riviumPush: RiviumPush, didChangeAppState state: AppState)

    /// Called when the SDK detects the app was updated
    func riviumPush(_ riviumPush: RiviumPush, didDetectAppUpdate info: AppUpdateInfo)

    /// Called when a notification action button is clicked
    func riviumPush(_ riviumPush: RiviumPush, didReceiveNotificationAction action: NotificationAction, forMessage message: RiviumPushMessage)

    /// Called when a notification is tapped (for real-time handling when app is in foreground)
    func riviumPush(_ riviumPush: RiviumPush, didTapNotification message: RiviumPushMessage)
}

/// Default implementations (all optional)
public extension RiviumPushDelegate {
    func riviumPush(_ riviumPush: RiviumPush, didReceiveMessage message: RiviumPushMessage) {}
    func riviumPush(_ riviumPush: RiviumPush, didChangeConnectionState connected: Bool) {}
    func riviumPush(_ riviumPush: RiviumPush, didRegisterWithDeviceId deviceId: String) {}
    func riviumPush(_ riviumPush: RiviumPush, didReceiveVoIPToken token: String) {}
    func riviumPush(_ riviumPush: RiviumPush, didReceiveAPNsToken token: String) {}
    func riviumPush(_ riviumPush: RiviumPush, didFailWithError error: Error) {}
    func riviumPush(_ riviumPush: RiviumPush, didFailWithDetailedError error: RiviumPushError) {
        // Default: delegate to simple error handler
        self.riviumPush(riviumPush, didFailWithError: error)
    }
    func riviumPush(_ riviumPush: RiviumPush, didStartReconnecting state: ReconnectionState) {}
    func riviumPush(_ riviumPush: RiviumPush, didChangeNetworkState state: NetworkState) {}
    func riviumPush(_ riviumPush: RiviumPush, didChangeAppState state: AppState) {}
    func riviumPush(_ riviumPush: RiviumPush, didDetectAppUpdate info: AppUpdateInfo) {}
    func riviumPush(_ riviumPush: RiviumPush, didReceiveNotificationAction action: NotificationAction, forMessage message: RiviumPushMessage) {}
    func riviumPush(_ riviumPush: RiviumPush, didTapNotification message: RiviumPushMessage) {}
}
