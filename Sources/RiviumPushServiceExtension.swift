import Foundation
import UserNotifications

/// Delivery confirmation from a Notification Service Extension.
///
/// APNs, FCM and Web Push all report only that the push service *accepted* a
/// notification — none of them confirm it reached the device. On iOS the only
/// way to know a notification actually arrived is a Notification Service
/// Extension, which the system runs before the notification is displayed, even
/// when the app is not running.
///
/// ## Setup
///
/// 1. Add a Notification Service Extension target to your app, and give it the
///    extension-safe subspec — the full SDK cannot be linked into an extension:
///
/// ```ruby
/// target 'Notification Service Extension' do
///   pod 'RiviumPushSDKExtension'
/// end
/// ```
///
/// 2. Enable the **same App Group** on both the app and the extension.
/// 3. Pass that group to the SDK in your app:
///
/// ```swift
/// RiviumPush.shared.initialize(
///     config: RiviumPushConfig(
///         apiKey: "rv_live_…",
///         appGroup: "group.com.example.app"
///     )
/// )
/// ```
///
/// 4. Call this from your extension:
///
/// ```swift
/// class NotificationService: UNNotificationServiceExtension {
///     override func didReceive(
///         _ request: UNNotificationRequest,
///         withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
///     ) {
///         RiviumPushServiceExtension.didReceive(
///             request,
///             apiKey: "rv_live_…",
///             appGroup: "group.com.example.app"
///         )
///         contentHandler(request.content)
///     }
/// }
/// ```
///
/// The extension has a short execution budget, so the report is fire-and-forget
/// and never delays `contentHandler`. A missed report costs a delivery
/// statistic, never a notification.
public enum RiviumPushServiceExtension {

    /// Key the SDK mirrors the device id under, inside the shared App Group.
    internal static let sharedDeviceIdKey = "co.rivium.push.sharedDeviceId"

    /// Report that a notification arrived on this device.
    ///
    /// - Parameters:
    ///   - request: The request handed to `didReceive(_:withContentHandler:)`.
    ///   - apiKey: Your Rivium Push API key (`rv_live_…`).
    ///   - appGroup: App Group shared by the app and this extension. Must match
    ///     the `appGroup` passed to `RiviumPushConfig`.
    ///   - serverUrl: Override only if you run a self-hosted Rivium Push.
    public static func didReceive(
        _ request: UNNotificationRequest,
        apiKey: String,
        appGroup: String,
        serverUrl: String = "https://push-api.rivium.co"
    ) {
        let userInfo = request.content.userInfo

        guard let messageId = messageId(from: userInfo) else {
            // Not a Rivium notification, or sent before delivery tracking —
            // nothing to report.
            return
        }

        guard
            let defaults = UserDefaults(suiteName: appGroup),
            let deviceId = defaults.string(forKey: sharedDeviceIdKey)
        else {
            // The app has not registered yet, or the App Group is not enabled
            // on both targets.
            return
        }

        // Skip if this message was already reported (dedupe set shared with
        // the app through the App Group).
        let store = DeliveryReceiptStore(defaults: defaults)
        guard store.claim(messageId) else { return }

        let identity = defaults.string(forKey: RiviumPushSDKInfo.sharedIdentityKey)
            ?? RiviumPushSDKInfo.headerValue(name: RiviumPushSDKInfo.name, version: RiviumPushSDKInfo.version)

        reportDelivered(
            messageId: messageId,
            deviceId: deviceId,
            apiKey: apiKey,
            serverUrl: serverUrl,
            sdkHeader: identity,
            store: store
        )
    }

    /// Pull the message id out of the APNs payload.
    ///
    /// The backend sends the structured message under `rivium_push_message`;
    /// fall back to a top-level `messageId` for payloads sent by older
    /// backends or composed by hand.
    internal static func messageId(from userInfo: [AnyHashable: Any]) -> String? {
        if let message = userInfo["rivium_push_message"] as? [String: Any],
           let id = message["messageId"] as? String,
           !id.isEmpty {
            return id
        }
        if let id = userInfo["messageId"] as? String, !id.isEmpty {
            return id
        }
        return nil
    }

    private static func reportDelivered(
        messageId: String,
        deviceId: String,
        apiKey: String,
        serverUrl: String,
        sdkHeader: String,
        store: DeliveryReceiptStore
    ) {
        // Keep the extension alive just long enough for the request to leave,
        // without blocking the notification being shown. A single attempt:
        // extensions are killed quickly, and if it fails the claim is released
        // so the app can report the delivery when it next sees the message.
        let semaphore = DispatchSemaphore(value: 0)
        DeliveryReceiptSender.send(
            messageId: messageId,
            deviceId: deviceId,
            apiKey: apiKey,
            serverUrl: serverUrl,
            sdkHeader: sdkHeader,
            maxAttempts: 1,
            timeout: 5
        ) { success in
            if !success { store.release(messageId) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
    }
}
