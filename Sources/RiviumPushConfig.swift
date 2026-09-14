import Foundation

/// Configuration for Rivium Push SDK
///
/// Only `apiKey` is required. PN Protocol gateway configuration (host, port, credentials) is automatically
/// fetched from the server during registration.
public struct RiviumPushConfig {
    /// Your Rivium Push API key (required)
    public let apiKey: String

    /// Rivium Push backend server URL (not user-configurable)
    /// For development, add `RiviumPushServerURL` key to your app's Info.plist
    internal let serverUrl: String

    /// PN Protocol gateway host (fetched from server at registration)
    public internal(set) var pnHost: String

    /// PN Protocol gateway port (fetched from server at registration)
    public internal(set) var pnPort: UInt16

    /// Enable TLS/SSL for secure PN Protocol connection (fetched from server at registration)
    public internal(set) var pnSecure: Bool

    /// JWT token for PN Protocol authentication (per-device, fetched at registration)
    public internal(set) var pnToken: String?

    /// Enable PushKit VoIP for background delivery (default: false).
    /// Only enable for apps whose primary purpose is voice/video calling (e.g. telehealth, messaging).
    /// Using VoIP push in non-calling apps will cause App Store rejection.
    public let usePushKit: Bool

    /// Enable standard APNs for background push delivery (default: true).
    /// Works for all app types and is the recommended approach for most apps.
    public let useAPNs: Bool

    /// Show notification when app is in foreground (default: false)
    public let showNotificationInForeground: Bool

    /// Auto-connect PN Protocol when app enters foreground (default: true)
    public let autoConnect: Bool

    /// Enable auto-reconnect with exponential backoff (default: true)
    public let autoReconnect: Bool

    /// Maximum reconnection attempts (0 = unlimited)
    public let maxReconnectAttempts: Int

    /// Initial reconnect delay in milliseconds
    public let initialReconnectDelayMs: Int

    /// Maximum reconnect delay in milliseconds
    public let maxReconnectDelayMs: Int

    /// App Group identifier shared with a Notification Service Extension.
    ///
    /// An extension runs in its own process and cannot read the app's
    /// UserDefaults, so delivery confirmation needs a shared container. Set
    /// this to the App Group enabled on both targets (e.g.
    /// "group.com.example.app") and the SDK mirrors the device identity there
    /// for `RiviumPushServiceExtension` to use.
    ///
    /// Leave nil if you are not confirming delivery from an extension.
    public let appGroup: String?

    /// Refresh the device registration automatically on launch (default: true).
    ///
    /// When this install has registered before, `initialize(config:)` re-sends
    /// the registration in the background if 24 hours have passed since the
    /// last successful one, or if the app version/build, SDK version, push
    /// token or user id changed. It never prompts for notification permission:
    /// it only runs when permission was already granted. An explicit
    /// `register()` always registers regardless of this setting.
    public let autoRefresh: Bool

    /// Name of the official wrapper SDK embedding this one (e.g. "flutter",
    /// "react-native"). Intended for Rivium's official Flutter and React Native
    /// wrappers only; apps should leave this nil. When both `wrapperSdkName`
    /// and `wrapperSdkVersion` are set they replace the reported SDK identity.
    public let wrapperSdkName: String?

    /// Version of the official wrapper SDK. See `wrapperSdkName`.
    public let wrapperSdkVersion: String?

    public init(
        apiKey: String,
        pnHost: String = "",
        pnPort: UInt16 = 8883,
        pnSecure: Bool = true,
        pnToken: String? = nil,
        usePushKit: Bool = false,
        useAPNs: Bool = true,
        showNotificationInForeground: Bool = false,
        autoConnect: Bool = true,
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 0,
        initialReconnectDelayMs: Int = 1000,
        maxReconnectDelayMs: Int = 60000,
        appGroup: String? = nil,
        autoRefresh: Bool = true,
        wrapperSdkName: String? = nil,
        wrapperSdkVersion: String? = nil
    ) {
        self.apiKey = apiKey
        self.appGroup = appGroup
        self.autoRefresh = autoRefresh
        self.wrapperSdkName = wrapperSdkName
        self.wrapperSdkVersion = wrapperSdkVersion
        // Dev server override via Info.plist key "RiviumPushServerURL" (not committed to git)
        if let devUrl = Bundle.main.object(forInfoDictionaryKey: "RiviumPushServerURL") as? String, !devUrl.isEmpty {
            self.serverUrl = devUrl
        } else {
            self.serverUrl = SdkCredentials.apiUrl
        }
        self.pnHost = pnHost.isEmpty ? SdkCredentials.pnHost : pnHost
        self.pnPort = pnPort == 8883 ? SdkCredentials.pnPort : pnPort
        self.pnSecure = pnSecure
        self.pnToken = pnToken
        self.usePushKit = usePushKit
        self.useAPNs = useAPNs
        self.showNotificationInForeground = showNotificationInForeground
        self.autoConnect = autoConnect
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.initialReconnectDelayMs = initialReconnectDelayMs
        self.maxReconnectDelayMs = maxReconnectDelayMs
    }

    /// SDK name reported to the backend: the wrapper's if set, else "ios".
    internal var reportedSdkName: String {
        return RiviumPushSDKInfo.identity(wrapperName: wrapperSdkName, wrapperVersion: wrapperSdkVersion).name
    }

    /// SDK version reported to the backend: the wrapper's if set, else `RiviumPush.sdkVersion`.
    internal var reportedSdkVersion: String {
        return RiviumPushSDKInfo.identity(wrapperName: wrapperSdkName, wrapperVersion: wrapperSdkVersion).version
    }

    /// Value of the `X-Rivium-SDK` header, `name/version`.
    internal var sdkHeaderValue: String {
        return RiviumPushSDKInfo.headerValue(name: reportedSdkName, version: reportedSdkVersion)
    }

    /// Check if PN Protocol config has been fetched from server
    internal func hasPNConfig() -> Bool {
        return !pnHost.isEmpty && pnToken != nil
    }

    /// Update PN Protocol config from server registration response
    internal mutating func updatePNConfig(host: String, port: UInt16, secure: Bool = true, token: String?) {
        self.pnHost = host
        self.pnPort = port
        self.pnSecure = secure
        self.pnToken = token
    }

    /// Update just the PN Protocol token (for token refresh)
    internal mutating func updatePNToken(_ token: String) {
        self.pnToken = token
    }

    /// Builder pattern for creating RiviumPushConfig
    ///
    /// Only `apiKey` is required. Server URL defaults to production.
    /// PN Protocol configuration is automatically fetched from server during registration.
    public class Builder {
        private let apiKey: String
        private var pnHost: String = ""
        private var pnPort: UInt16 = 8883
        private var pnSecure: Bool = true
        private var usePushKit: Bool = false
        private var useAPNs: Bool = true
        private var showNotificationInForeground: Bool = false
        private var autoConnect: Bool = true
        private var autoReconnect: Bool = true
        private var maxReconnectAttempts: Int = 0
        private var initialReconnectDelayMs: Int = 1000
        private var maxReconnectDelayMs: Int = 60000
        private var appGroup: String? = nil
        private var autoRefresh: Bool = true
        private var wrapperSdkName: String? = nil
        private var wrapperSdkVersion: String? = nil

        public init(apiKey: String) {
            self.apiKey = apiKey
        }

        /// Refresh the registration automatically on launch (default: true).
        /// See `RiviumPushConfig.autoRefresh`.
        @discardableResult
        public func autoRefresh(_ enabled: Bool) -> Builder {
            self.autoRefresh = enabled
            return self
        }

        /// For Rivium's official Flutter / React Native wrappers only: report
        /// the wrapper's SDK identity instead of the native iOS one.
        @discardableResult
        public func wrapperSdk(name: String, version: String) -> Builder {
            self.wrapperSdkName = name
            self.wrapperSdkVersion = version
            return self
        }

        /// App Group shared with a Notification Service Extension, enabling
        /// delivery confirmation (e.g. "group.com.example.app").
        ///
        /// An extension runs in its own process and cannot read the app's
        /// storage, so confirming delivery needs a shared container. Enable the
        /// same App Group on both targets and pass it here.
        @discardableResult
        public func appGroup(_ group: String) -> Builder {
            self.appGroup = group
            return self
        }

        /// Set custom PN Protocol gateway host for development/testing (normally fetched from server)
        @discardableResult
        public func pnHost(_ host: String) -> Builder {
            self.pnHost = host
            return self
        }

        /// Set custom PN Protocol gateway port for development/testing (normally fetched from server)
        @discardableResult
        public func pnPort(_ port: UInt16) -> Builder {
            self.pnPort = port
            return self
        }

        @discardableResult
        public func usePushKit(_ use: Bool) -> Builder {
            self.usePushKit = use
            return self
        }

        @discardableResult
        public func useAPNs(_ use: Bool) -> Builder {
            self.useAPNs = use
            return self
        }

        @discardableResult
        public func showNotificationInForeground(_ show: Bool) -> Builder {
            self.showNotificationInForeground = show
            return self
        }

        @discardableResult
        public func autoConnect(_ auto: Bool) -> Builder {
            self.autoConnect = auto
            return self
        }

        @discardableResult
        public func autoReconnect(_ auto: Bool) -> Builder {
            self.autoReconnect = auto
            return self
        }

        @discardableResult
        public func maxReconnectAttempts(_ attempts: Int) -> Builder {
            self.maxReconnectAttempts = attempts
            return self
        }

        @discardableResult
        public func initialReconnectDelayMs(_ delay: Int) -> Builder {
            self.initialReconnectDelayMs = delay
            return self
        }

        @discardableResult
        public func maxReconnectDelayMs(_ delay: Int) -> Builder {
            self.maxReconnectDelayMs = delay
            return self
        }

        public func build() -> RiviumPushConfig {
            precondition(!apiKey.isEmpty, "API key is required")

            return RiviumPushConfig(
                apiKey: apiKey,
                pnHost: pnHost,
                pnPort: pnPort,
                pnSecure: pnSecure,
                pnToken: nil,  // Will be fetched from server at registration
                usePushKit: usePushKit,
                useAPNs: useAPNs,
                showNotificationInForeground: showNotificationInForeground,
                autoConnect: autoConnect,
                autoReconnect: autoReconnect,
                maxReconnectAttempts: maxReconnectAttempts,
                initialReconnectDelayMs: initialReconnectDelayMs,
                maxReconnectDelayMs: maxReconnectDelayMs,
                appGroup: appGroup,
                autoRefresh: autoRefresh,
                wrapperSdkName: wrapperSdkName,
                wrapperSdkVersion: wrapperSdkVersion
            )
        }
    }

    public static func builder(apiKey: String) -> Builder {
        return Builder(apiKey: apiKey)
    }
}
