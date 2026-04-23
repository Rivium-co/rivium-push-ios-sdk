import UIKit
import UserNotifications
import RiviumPush

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    static let apiKeyKey = "RiviumPushSavedApiKey"
    static let userIdKey = "RiviumPushSavedUserId"

    static var savedApiKey: String? {
        get { UserDefaults.standard.string(forKey: apiKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }

    static var savedUserId: String? {
        get { UserDefaults.standard.string(forKey: userIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: userIdKey) }
    }

    static var isConfigured: Bool {
        guard let key = savedApiKey else { return false }
        return !key.isEmpty
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        #if DEBUG
        RiviumPush.shared.setLogLevel(.debug)
        #else
        RiviumPush.shared.setLogLevel(.error)
        #endif

        UNUserNotificationCenter.current().delegate = self

        // If already configured, initialize SDK
        if AppDelegate.isConfigured {
            AppDelegate.initializeSDK()
        }

        return true
    }

    static var isVoipEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "voip_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "voip_enabled") }
    }

    static func initializeSDK() {
        guard let apiKey = savedApiKey, !apiKey.isEmpty else { return }

        let config = RiviumPushConfig.builder(apiKey: apiKey)
            .usePushKit(isVoipEnabled)
            .showNotificationInForeground(true)
            .autoConnect(true)
            .build()

        RiviumPush.shared.initialize(config: config)
        RiviumPush.shared.delegate = UIApplication.shared.delegate as? RiviumPushDelegate

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        RiviumPush.shared.register(userId: savedUserId)
        print("[RiviumPush] SDK initialized with key: \(String(apiKey.prefix(12)))...")
    }

    // MARK: - Scene
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    // MARK: - APNs
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[RiviumPush] APNs token: \(token)")
        RiviumPush.shared.setAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[RiviumPush] APNs failed: \(error.localizedDescription)")
    }
}

// MARK: - RiviumPushDelegate
extension AppDelegate: RiviumPushDelegate {

    func riviumPush(_ riviumPush: RiviumPush, didRegisterWithDeviceId deviceId: String) {
        NotificationCenter.default.post(name: .riviumPushRegistered, object: nil, userInfo: ["deviceId": deviceId])
    }

    func riviumPush(_ riviumPush: RiviumPush, didReceiveMessage message: RiviumPushMessage) {
        NotificationCenter.default.post(name: .riviumPushMessageReceived, object: nil, userInfo: ["message": message])
    }

    func riviumPush(_ riviumPush: RiviumPush, didTapNotification message: RiviumPushMessage) {
        NotificationCenter.default.post(name: .riviumPushNotificationTapped, object: nil, userInfo: ["message": message])
    }

    func riviumPush(_ riviumPush: RiviumPush, didChangeConnectionState connected: Bool) {
        NotificationCenter.default.post(name: .riviumPushConnectionChanged, object: nil, userInfo: ["connected": connected])
    }

    func riviumPush(_ riviumPush: RiviumPush, didChangeAppState state: AppState) {}
    func riviumPush(_ riviumPush: RiviumPush, didFailWithError error: Error) {}
    func riviumPush(_ riviumPush: RiviumPush, didFailWithDetailedError error: RiviumPushError) {}
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let message = RiviumPushMessage.from(payload: userInfo) {
            RiviumPush.shared.delegate?.riviumPush(RiviumPush.shared, didTapNotification: message)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
