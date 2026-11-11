import UIKit

/// The Apple TV app. tvOS has no third-party screen savers, so the tank is an app you open; it runs
/// full screen until you press Back.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }
}

/// One black, dark-mode window holding the tank, so nothing ever flashes white.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        #if DEBUG
        ArtExport.runIfRequested()
        #endif
        let window = ActivityWindow(windowScene: scene)
        window.backgroundColor = .black
        window.overrideUserInterfaceStyle = .dark
        let tank = TankViewController()
        window.onActivity = { [weak tank] in tank?.remoteActivity() }
        window.rootViewController = tank
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// A window that reports every remote press and touch as it begins, before any view handles it. The
/// Options panel's list consumes its presses, so the tank never sees them.
final class ActivityWindow: UIWindow {
    var onActivity: (() -> Void)?

    override func sendEvent(_ event: UIEvent) {
        if Self.begins(event) { onActivity?() }
        super.sendEvent(event)
    }

    private static func begins(_ event: UIEvent) -> Bool {
        if let presses = event as? UIPressesEvent {
            return presses.allPresses.contains { $0.phase == .began }
        }
        return event.allTouches?.contains { $0.phase == .began } ?? false
    }
}
