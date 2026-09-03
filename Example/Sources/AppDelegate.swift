import UIKit
import MetrikeAds

/// Wires the SDK exactly once per process, before any view controller has a
/// chance to load an ad -- mirrors Android's `TestApplication.onCreate`
/// (`sdk/android/testapp/.../TestConfig.kt`). `EventLogView` must be able to
/// show every debug line, including ones fired during this very call, which
/// is why `EventLog` replays its history to late subscribers instead of
/// requiring them to already be attached (see that class's doc).
///
/// No storyboard/XIB, no `SceneDelegate` -- `Info.plist` declares no
/// `UIApplicationSceneManifest`, so `application(_:didFinishLaunchingWithOptions:)`
/// is where the window is built, per the task-14 brief ("programmatic
/// window, no storyboard").
@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate, MetrikeDebugListener {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let env = TestConfig.pendingEnv
        TestConfig.activateForThisProcess(env)

        // MetrikeConfig has no named-argument initializer (an `NSObject`
        // with plain mutable `@objc` properties, not a Kotlin data class
        // with `@JvmOverloads` defaults -- see that file's own doc) --
        // configure it property-by-property before the one
        // `Metrike.initialize(config:)` call for this process.
        let config = MetrikeConfig()
        config.appName = "Metrike SDK Example (iOS)"
        config.baseUrl = env.baseUrl
        config.collectLocation = false
        // `MetrikeConfig.debugListener` is a WEAK var (see MetrikeConfig.swift)
        // -- `self` (AppDelegate) is what keeps this listener alive for the
        // whole process, since AppDelegate itself already has exactly that
        // lifetime. A transient object (e.g. a plain closure box created
        // and dropped here) would be deallocated the instant this method
        // returns, silently going dark.
        config.debugListener = self
        Metrike.initialize(config: config)
        EventLog.append("Metrike.initialize(config:) baseUrl=\(env.baseUrl) appName=\(config.appName ?? "") env=\(env.displayName)")

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: MainViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    // MARK: - MetrikeDebugListener

    /// Every "beacon:"/internal debug line the SDK reports -- forwarded
    /// as-is into the same on-screen log every delegate callback also feeds,
    /// so `EventLogView` is a single, complete window into what the SDK is
    /// doing (task-14 brief: "the log IS the demo").
    func onDebugLine(_ line: String) {
        EventLog.append(line)
    }

    // MARK: - Deep links (conversion attribution demo)

    /// Custom URL scheme (`metriketest://open?mk_cid=...`, declared in
    /// Info.plist's `CFBundleURLTypes`) -- routed straight to
    /// `Metrike.handleDeepLink(_:)`, the same public entry point Android's
    /// testapp calls from its own fake-deep-link Intent.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let handled = Metrike.handleDeepLink(url)
        EventLog.append("handleDeepLink(url=\(url.absoluteString)) -> \(handled)")
        return handled
    }

    /// Universal links (`https://track.metrike.com.br/...?mk_cid=...`)
    /// arrive as an `NSUserActivity` of type
    /// `NSUserActivityTypeBrowsingWeb`, not as a plain `open url:` call --
    /// this is the other half of "route ... + universal links to
    /// Metrike.handleDeepLink" from the task brief. A real host would
    /// additionally need Associated Domains (`applinks:`) entitlements and
    /// an `apple-app-site-association` file served from the target domain
    /// for iOS to ever deliver this callback at all; wiring that up is a
    /// deploy-time host concern outside what this example can demonstrate
    /// in-process (see task-14-report.md).
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }
        let handled = Metrike.handleDeepLink(url)
        EventLog.append("handleDeepLink(universalLink=\(url.absoluteString)) -> \(handled)")
        return handled
    }
}
