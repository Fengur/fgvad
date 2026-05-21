import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        _ = DemoLogger.shared
        DemoLogger.shared.i("App", "fgvad ios demo launched")
        let window = UIWindow(frame: UIScreen.main.bounds)
        let nav = UINavigationController(rootViewController: ViewController())
        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
