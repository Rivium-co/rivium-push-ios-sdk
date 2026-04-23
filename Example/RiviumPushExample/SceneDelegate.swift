import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)

        if AppDelegate.isConfigured {
            showMainApp()
        } else {
            showOnboarding()
        }

        window?.makeKeyAndVisible()
    }

    func showOnboarding() {
        window?.rootViewController = OnboardingViewController()
    }

    func showMainApp() {
        let tabBarController = UITabBarController()
        tabBarController.tabBar.tintColor = UIColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 1)

        let tabs: [(UIViewController, String, String)] = [
            (MainViewController(), "Home", "house.fill"),
            (InboxViewController(), "Inbox", "tray.fill"),
            (InAppMessagesViewController(), "In-App", "bubble.left.fill"),
            (ABTestingViewController(), "A/B Tests", "flask.fill"),
            (VoIPViewController(), "VoIP", "phone.fill"),
            (SettingsViewController(), "Settings", "gearshape.fill"),
        ]

        tabBarController.viewControllers = tabs.enumerated().map { (i, item) in
            item.0.tabBarItem = UITabBarItem(title: item.1, image: UIImage(systemName: item.2), tag: i)
            let nav = UINavigationController(rootViewController: item.0)
            nav.navigationBar.prefersLargeTitles = false
            return nav
        }

        window?.rootViewController = tabBarController
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
