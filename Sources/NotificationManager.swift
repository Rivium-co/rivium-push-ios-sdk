import Foundation
import UserNotifications
import UIKit

/// Manages local notifications with rich notification support
internal class NotificationManager: NSObject {
    static let shared = NotificationManager()
    private static let TAG = "Notification"

    private static let KEY_INITIAL_MESSAGE = "rivium_push_initial_message"
    private static let KEY_CLICKED_ACTION = "rivium_push_clicked_action"

    private var initialMessage: RiviumPushMessage?
    private var clickedAction: NotificationAction?
    private var clickedMessage: RiviumPushMessage?

    private override init() {
        super.init()
    }

    // MARK: - Permissions

    /// Request notification permission
    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    Log.e(NotificationManager.TAG, "Permission error", error: error)
                }
                completion(granted)
            }
        }
    }

    /// Check if notifications are enabled
    func checkPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }

    // MARK: - Show Notifications

    /// Show local notification from push message with rich notification support
    func showNotification(message: RiviumPushMessage, completion: ((Error?) -> Void)? = nil) {
        let content = UNMutableNotificationContent()

        // Use localized content if available
        content.title = message.getLocalizedTitle()
        content.body = message.getLocalizedBody()

        // Sound
        if let soundName = message.sound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
        } else {
            content.sound = .default
        }

        // Thread ID for grouping
        if let threadId = message.threadId {
            content.threadIdentifier = threadId
        }

        // Category for action buttons
        if let category = message.category {
            content.categoryIdentifier = category
        } else if let actions = message.actions, !actions.isEmpty {
            // Register dynamic category for actions
            registerActionsCategory(actions: actions, message: message)
            content.categoryIdentifier = "rivium_push_dynamic_\(message.messageId ?? UUID().uuidString)"
        }

        // Badge
        if let badge = message.badge {
            switch message.badgeAction {
            case "set":
                content.badge = NSNumber(value: badge)
            case "increment":
                let current = UIApplication.shared.applicationIconBadgeNumber
                content.badge = NSNumber(value: current + badge)
            case "decrement":
                let current = UIApplication.shared.applicationIconBadgeNumber
                content.badge = NSNumber(value: max(0, current - badge))
            case "clear":
                content.badge = 0
            default:
                content.badge = NSNumber(value: badge)
            }
        }

        // User info
        var userInfo: [String: Any] = ["rivium_push_message": message.toDictionary()]
        if let data = message.data {
            for (key, value) in data {
                userInfo[key] = value.value
            }
        }
        if let messageId = message.messageId {
            userInfo["messageId"] = messageId
        }
        if let campaignId = message.campaignId {
            userInfo["campaignId"] = campaignId
        }
        if let deepLink = message.deepLink {
            userInfo["deepLink"] = deepLink
        }
        content.userInfo = userInfo

        // Handle image attachment
        if let imageUrl = message.imageUrl, let url = URL(string: imageUrl) {
            downloadImage(from: url) { [weak self] localUrl in
                if let localUrl = localUrl {
                    do {
                        let attachment = try UNNotificationAttachment(identifier: "image", url: localUrl, options: nil)
                        content.attachments = [attachment]
                    } catch {
                        Log.e(NotificationManager.TAG, "Failed to attach image", error: error)
                    }
                }
                self?.scheduleNotification(content: content, message: message, completion: completion)
            }
        } else {
            scheduleNotification(content: content, message: message, completion: completion)
        }
    }

    private func scheduleNotification(content: UNMutableNotificationContent, message: RiviumPushMessage, completion: ((Error?) -> Void)?) {
        let identifier = message.messageId ?? UUID().uuidString

        // Use collapse key to replace existing notification
        let request: UNNotificationRequest
        if let collapseKey = message.collapseKey {
            request = UNNotificationRequest(identifier: collapseKey, content: content, trigger: nil)
        } else {
            request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        }

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.e(NotificationManager.TAG, "Failed to show notification", error: error)
            } else {
                Log.d(NotificationManager.TAG, "Notification shown: \(identifier)")
            }
            DispatchQueue.main.async {
                completion?(error)
            }
        }
    }

    // MARK: - Action Buttons

    private func registerActionsCategory(actions: [NotificationAction], message: RiviumPushMessage) {
        var notificationActions: [UNNotificationAction] = []

        for action in actions.prefix(4) { // iOS supports max 4 actions
            var options: UNNotificationActionOptions = []

            if action.destructive {
                options.insert(.destructive)
            }
            if action.authRequired {
                options.insert(.authenticationRequired)
            }
            // All actions should bring app to foreground
            options.insert(.foreground)

            let notificationAction = UNNotificationAction(
                identifier: action.id,
                title: action.title,
                options: options
            )
            notificationActions.append(notificationAction)
        }

        let categoryId = "rivium_push_dynamic_\(message.messageId ?? UUID().uuidString)"
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: notificationActions,
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().getNotificationCategories { categories in
            var updatedCategories = categories
            updatedCategories.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(updatedCategories)
        }
    }

    // MARK: - Image Download

    private func downloadImage(from url: URL, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { localUrl, response, error in
            guard let localUrl = localUrl, error == nil else {
                Log.e(NotificationManager.TAG, "Image download failed", error: error)
                completion(nil)
                return
            }

            // Move to a location that won't be cleaned up
            let tempDir = FileManager.default.temporaryDirectory
            let destinationUrl = tempDir.appendingPathComponent(UUID().uuidString + ".jpg")

            do {
                try FileManager.default.moveItem(at: localUrl, to: destinationUrl)
                completion(destinationUrl)
            } catch {
                Log.e(NotificationManager.TAG, "Failed to move image", error: error)
                completion(nil)
            }
        }
        task.resume()
    }

    // MARK: - Initial Message & Action Handling

    /// Store the message that launched the app
    func setInitialMessage(_ message: RiviumPushMessage) {
        initialMessage = message

        // Also persist to UserDefaults for cold start
        if let json = message.toJson() {
            UserDefaults.standard.set(json, forKey: NotificationManager.KEY_INITIAL_MESSAGE)
        }
    }

    /// Get the message that launched the app
    func getInitialMessage() -> RiviumPushMessage? {
        if let message = initialMessage {
            return message
        }

        // Try to load from UserDefaults
        if let json = UserDefaults.standard.string(forKey: NotificationManager.KEY_INITIAL_MESSAGE) {
            return RiviumPushMessage.from(json: json)
        }

        return nil
    }

    /// Clear the initial message
    func clearInitialMessage() {
        initialMessage = nil
        UserDefaults.standard.removeObject(forKey: NotificationManager.KEY_INITIAL_MESSAGE)
    }

    /// Store clicked action
    func setClickedAction(_ action: NotificationAction, message: RiviumPushMessage) {
        clickedAction = action
        clickedMessage = message
    }

    /// Get clicked action
    func getClickedAction() -> (action: NotificationAction, message: RiviumPushMessage)? {
        if let action = clickedAction, let message = clickedMessage {
            return (action, message)
        }
        return nil
    }

    /// Clear clicked action
    func clearClickedAction() {
        clickedAction = nil
        clickedMessage = nil
    }

    // MARK: - Badge Management

    /// Set app badge number
    func setBadge(_ count: Int) {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }

    /// Increment app badge number
    func incrementBadge(by count: Int = 1) {
        DispatchQueue.main.async {
            let current = UIApplication.shared.applicationIconBadgeNumber
            UIApplication.shared.applicationIconBadgeNumber = current + count
        }
    }

    /// Clear app badge
    func clearBadge() {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    /// Get current badge number
    func getBadgeCount() -> Int {
        return UIApplication.shared.applicationIconBadgeNumber
    }
}
