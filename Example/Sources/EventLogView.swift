import UIKit

/// Process-wide, in-memory log of every line the SDK's `MetrikeDebugListener`
/// reports (the "beacon:" lines), plus a few app-added lines (button taps,
/// deep-link fakes, delegate callbacks) -- mirrors Android's
/// `object EventLog` (`sdk/android/testapp/.../EventLogView.kt`) 1:1,
/// including the reason it is a singleton rather than something
/// `MainViewController` owns: `AppDelegate` wires `MetrikeConfig
/// .debugListener` -- and the SDK can start emitting lines -- before any
/// view controller exists to display them.
///
/// `addListener` replays the full history to a newly-attached subscriber so
/// an `EventLogView` created after launch (or a pushed
/// `InstreamDemoViewController`'s own log, if it had one) still shows
/// everything that happened before it existed.
///
/// Not `@objc`/does not itself conform to `MetrikeDebugListener` --
/// `AppDelegate` is the one class that conforms (see its own doc for why:
/// `MetrikeConfig.debugListener` is a `weak var`, so the listener object
/// needs a lifetime at least as long as the process; `AppDelegate` already
/// has exactly that, `EventLog` doesn't need to be a delegate to get it).
final class EventLog {
    static let shared = EventLog()
    private init() {}

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var lines: [String] = []
    /// Keyed by a token (rather than the closure itself -- Swift closures
    /// aren't `Equatable`/removable-by-value the way Kotlin's
    /// `MutableList<(String) -> Unit>.remove(listener)` is) so
    /// `EventLogView` can precisely un-subscribe its own listener and no
    /// other's.
    private var listeners: [UUID: (String) -> Void] = [:]
    private let lock = NSLock()

    /// Appends one line, timestamped, and notifies every current listener --
    /// always on the main thread (matches `MetrikeDebugListener`'s own
    /// "always delivered on the main thread" contract, and lets every
    /// app-added call site below use this from anywhere without its own
    /// thread-hopping).
    static func append(_ line: String) {
        shared.appendLine(line)
    }

    private func appendLine(_ line: String) {
        let stamped = "[\(Self.timestampFormatter.string(from: Date()))] \(line)"
        lock.lock()
        lines.append(stamped)
        let currentListeners = Array(listeners.values)
        lock.unlock()
        if Thread.isMainThread {
            currentListeners.forEach { $0(stamped) }
        } else {
            DispatchQueue.main.async {
                currentListeners.forEach { $0(stamped) }
            }
        }
    }

    @discardableResult
    func addListener(_ listener: @escaping (String) -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        listeners[token] = listener
        let history = lines
        lock.unlock()
        history.forEach(listener)
        return token
    }

    func removeListener(_ token: UUID) {
        lock.lock()
        listeners.removeValue(forKey: token)
        lock.unlock()
    }
}

/// Scrollable, append-only log view fed by `EventLog` -- the demo's window
/// into `MetrikeDebugListener` plus every ad-format delegate callback.
/// Example-app-only widget, not part of the SDK.
///
/// Self-contained, same contract as Android's `EventLogView`: subscribes to
/// `EventLog` when added to a window and unsubscribes when removed, so
/// dropping one into `MainViewController`'s layout is all a caller needs to
/// do -- no wiring required from the view controller.
final class EventLogView: UIView {

    private let textView: UITextView = {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.alwaysBounceVertical = true
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.backgroundColor = UIColor(white: 0.95, alpha: 1)
        view.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var listenerToken: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            guard listenerToken == nil else { return }
            listenerToken = EventLog.shared.addListener { [weak self] line in
                self?.appendLine(line)
            }
        } else if let token = listenerToken {
            EventLog.shared.removeListener(token)
            listenerToken = nil
        }
    }

    private func appendLine(_ line: String) {
        let existing = textView.text ?? ""
        textView.text = existing.isEmpty ? line : existing + "\n" + line
        let bottom = NSRange(location: (textView.text as NSString).length, length: 0)
        textView.scrollRangeToVisible(bottom)
    }
}
