import Foundation

/// Example-app-only glue: persists the demo's zone id / vast token /
/// environment choice across launches. Mirrors Android's `object TestConfig`
/// (`sdk/android/testapp/.../TestConfig.kt`) 1:1 in shape, including the
/// reasoning behind it -- see `activeEnv`'s doc below for the one piece of
/// that reasoning worth restating on this side too.
///
/// Not part of the SDK's public surface at all -- `import MetrikeAds` is not
/// even needed in this file. Every actual SDK call this config feeds lives in
/// `AppDelegate`/`MainViewController`/`InstreamDemoViewController`.
enum TestConfig {

    enum Env: String {
        case prod
        case local

        /// Aponta o app de exemplo para o ambiente escolhido. A zona e o
        /// vast token NÃO são fixados aqui -- veja a nota em `zoneId`.
        var baseUrl: String {
            switch self {
            case .prod:
                return "https://track.metrike.com.br"
            case .local:
                // docker-compose.dev.yml's published host port for the
                // `ingestion` service. Unlike Android's emulator (which
                // reaches the host machine's loopback through the special
                // 10.0.2.2 alias -- see the Android testapp's
                // network_security_config.xml comment), the iOS Simulator
                // shares the Mac's own network stack directly, so
                // 127.0.0.1 here really is the Mac itself. A physical
                // device on the same Wi-Fi network cannot reach 127.0.0.1
                // at all (that is the DEVICE's own loopback) -- it needs
                // the Mac's LAN IP instead; see README.md.
                return "http://127.0.0.1:8005"
            }
        }

        var displayName: String {
            switch self {
            case .prod: return "Prod"
            case .local: return "Local"
            }
        }
    }

    // MARK: - Persistence

    private static let defaults = UserDefaults.standard
    private static let keyZoneId = "mk_example_zone_id"
    private static let keyVastToken = "mk_example_vast_token"
    private static let keyPendingEnv = "mk_example_pending_env"

    /// Empty by default, ON PURPOSE -- the tester types their own zone in.
    /// Mirrors Android's `TestConfig.zoneId`
    /// (`prefs.getString(KEY_ZONE_ID, "")`), and for the same reason: this
    /// app's source is published in the PUBLIC `metrike-ads-ios` repo, so a
    /// zone id or vast token hardcoded here would be permanently public in
    /// git history. Nothing loads until both fields are filled.
    static var zoneId: String {
        get { defaults.string(forKey: keyZoneId) ?? "" }
        set { defaults.set(newValue, forKey: keyZoneId) }
    }

    /// Same empty-by-default contract as `zoneId` -- see its doc.
    static var vastToken: String {
        get { defaults.string(forKey: keyVastToken) ?? "" }
        set { defaults.set(newValue, forKey: keyVastToken) }
    }

    static var pendingEnv: Env {
        get { Env(rawValue: defaults.string(forKey: keyPendingEnv) ?? Env.prod.rawValue) ?? .prod }
        set { defaults.set(newValue.rawValue, forKey: keyPendingEnv) }
    }

    /// The `Env` actually passed to `Metrike.initialize(config:)` for THIS
    /// process -- snapshotted once by `AppDelegate` at launch.
    ///
    /// `Metrike.initialize(config:)` is idempotent for the life of the
    /// process (`Metrike.swift`: `if initialized { return }`, no unlock/
    /// re-init path at all) -- there is no public API to re-point an
    /// already-initialized SDK at a different `baseUrl`. So flipping the
    /// env switch in `MainViewController` only WRITES the chosen `Env` to
    /// `pendingEnv`; it takes effect on the NEXT app launch, when
    /// `AppDelegate` reads it back and calls `initialize` fresh in the new
    /// process. This is the same honest "relaunch to apply" contract the
    /// Android testapp documents on its own `TestConfig.activeEnv` -- not a
    /// workaround, a direct, pinned consequence of the public API having no
    /// re-init hook. `MainViewController` compares `pendingEnv` against
    /// `activeEnv` to tell the user when a toggle they just flipped has not
    /// taken effect yet.
    private(set) static var activeEnv: Env = .prod

    static func activateForThisProcess(_ env: Env) {
        activeEnv = env
    }
}
