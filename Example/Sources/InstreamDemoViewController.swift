import UIKit
import AVFoundation
import MetrikeAds

/// "Instream (IMA-style)" demo -- a real `AVPlayer` playing demo content with
/// pre/mid/post-roll ads inserted via `MetrikeAdsLoader`, the iOS
/// counterpart of Android's `InstreamDemoActivity`
/// (`sdk/android/testapp/.../InstreamDemoActivity.kt`). Wired exactly the
/// way `MetrikeAdsLoader`'s own kdoc prescribes:
///
/// ```swift
/// let loader = MetrikeAdsLoader(vmapToken: token)
/// loader.delegate = self
/// loader.attach(to: contentPlayer, overlayContainer: overlayContainerView, from: self)
/// ```
///
/// Only the public `MetrikeAds` surface is touched (`MetrikeAdsLoader`) --
/// `AVPlayer`/`AVPlayerLayer` are the *host's own* AVFoundation dependencies,
/// same as any real publisher integrating this SDK's instream format would
/// need (there is no Media3/ExoPlayer equivalent on iOS; see
/// `MetrikeAdsLoader`'s own class kdoc for the full platform-difference
/// rationale).
///
/// Content URL diverges from the Android testapp's
/// `InstreamDemoActivity.CONTENT_URL` (the gtv-videos-bucket Big Buck Bunny
/// sample) for one reason only: Google closed public read on that bucket, so
/// it now answers 403 to everyone. The failed item produced a black screen
/// with no ad at all on the first Simulator run -- and no ad is the point:
/// `MetrikeAdsLoader` triggers a pre-roll from the CONTENT player's own
/// periodic time observer (`handleContentTick`), which never ticks for an
/// item that failed to load, so a dead content URL silently takes the whole
/// instream demo with it. Replaced with Apple's own HLS sample stream, which
/// their documentation points at and their CDN keeps alive.
/// (Android's testapp carries the same dead URL and needs the same fix.)
final class InstreamDemoViewController: UIViewController {

    private static let contentUrl = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
    )!

    /// How long to wait, after the CONTENT player's own end-of-item
    /// notification fires, before concluding no post-roll is coming and
    /// popping this screen. `MetrikeAdsLoader.attach`'s own content-end
    /// observer and this screen's `contentDidEnd` observer both fire off the
    /// SAME `AVPlayerItemDidPlayToEndTime` notification, but the loader's
    /// own post-roll ad-tag/VAST resolution is asynchronous network work --
    /// this grace window gives that a chance to actually start
    /// (`adBreakActive` flips true via `onStart`) before this screen decides
    /// there is nothing left to wait for. Documented departure from
    /// Android's `InstreamDemoActivity`, which gets an exact "is an ad
    /// playing" signal for free from `ExoPlayer.isPlayingAd` because Media3
    /// inserts ads directly into the content player's own timeline;
    /// `MetrikeAdsLoader` instead pauses the content player and shows each
    /// break in a completely separate, SDK-owned `AVPlayer` (see that
    /// class's kdoc's "Escape hatches" section), so there is no single
    /// player-level flag this screen can read the same way.
    private static let postRollGraceSeconds: TimeInterval = 1.5

    private let vastToken: String

    private let contentPlayer = AVPlayer()
    private var contentPlayerLayer: AVPlayerLayer?
    private let contentContainerView = UIView()
    /// Handed to `MetrikeAdsLoader.attach(overlayContainer:)` -- every ad
    /// break's own chrome/`AVPlayer` is embedded here for the duration of
    /// that break only. `isUserInteractionEnabled` starts `false` (so taps
    /// pass straight through to `contentContainerView`'s own tap-to-pause
    /// gesture beneath it while idle) and is toggled `true` only while a
    /// break is actually showing (`onStart` .. `onComplete`/`onSkip`/
    /// `onError`) so the ad's own skip/click chrome can receive taps.
    private let overlayContainerView = UIView()
    private let playStateHintLabel = UILabel()

    private var adsLoader: MetrikeAdsLoader?
    private var contentEndObserver: NSObjectProtocol?

    /// Set/cleared only by `togglePlayPause` -- a deliberate pause the
    /// viewer chose themselves must not be overridden by
    /// `appDidBecomeActive`'s auto-resume, same rule Android's
    /// `InstreamDemoActivity.userPaused` documents on its own `onResume`.
    private var userPaused = false

    /// `true` from the content item's own end-of-playback notification
    /// through to this screen actually popping -- see `postRollGraceSeconds`.
    private var contentDidEnd = false
    /// `true` for the span between an ad break's `onStart` and its
    /// `onComplete`/`onSkip`/`onError` -- also gates
    /// `overlayContainerView.isUserInteractionEnabled` (see that
    /// property's doc).
    private var adBreakActive = false
    /// Guards `finishDemo` so a repeat trigger (grace timer racing a
    /// just-started break, or multiple ad-lifecycle callbacks) never pops
    /// this screen twice.
    private var finished = false

    init(vastToken: String) {
        self.vastToken = vastToken
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InstreamDemoViewController does not support storyboard/XIB instantiation")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Instream (IMA-style)"
        view.backgroundColor = .black

        buildLayout()
        startPlayback()

        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentPlayerLayer?.frame = contentContainerView.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent || isBeingDismissed else { return }
        teardown()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func buildLayout() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.backgroundColor = .black
        contentContainerView.isUserInteractionEnabled = true
        contentContainerView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(togglePlayPause))
        )
        view.addSubview(contentContainerView)

        overlayContainerView.translatesAutoresizingMaskIntoConstraints = false
        overlayContainerView.isUserInteractionEnabled = false // see property doc
        view.addSubview(overlayContainerView)

        playStateHintLabel.translatesAutoresizingMaskIntoConstraints = false
        playStateHintLabel.textColor = .white
        playStateHintLabel.font = .systemFont(ofSize: 13)
        playStateHintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        playStateHintLabel.text = Self.playingHint
        view.addSubview(playStateHintLabel)

        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            overlayContainerView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            overlayContainerView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            overlayContainerView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            overlayContainerView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),

            playStateHintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            playStateHintLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
        ])
    }

    // MARK: - Playback + MetrikeAdsLoader wiring

    private func startPlayback() {
        let item = AVPlayerItem(url: Self.contentUrl)
        contentPlayer.replaceCurrentItem(with: item)

        let layer = AVPlayerLayer(player: contentPlayer)
        layer.videoGravity = .resizeAspect
        contentContainerView.layer.addSublayer(layer)
        contentPlayerLayer = layer

        // This screen's OWN signal for "content finished" -- separate from,
        // but registered on the same notification as, the one
        // `MetrikeAdsLoader.attach` installs internally to trigger the
        // post-roll (see that method's doc). Both observers fire; only this
        // one decides whether to pop the screen (see `postRollGraceSeconds`).
        contentEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.handleContentEnded()
        }

        EventLog.append("instream: contentUrl=\(Self.contentUrl.absoluteString) vastToken=\(vastToken)")

        let loader = MetrikeAdsLoader(vmapToken: vastToken)
        loader.delegate = self
        adsLoader = loader
        loader.attach(to: contentPlayer, overlayContainer: overlayContainerView, from: self)

        contentPlayer.play()
    }

    private func handleContentEnded() {
        guard !contentDidEnd else { return }
        contentDidEnd = true
        EventLog.append("instream: content playback ended")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.postRollGraceSeconds) { [weak self] in
            self?.finishIfNothingLeftToWaitFor()
        }
    }

    private func finishIfNothingLeftToWaitFor() {
        guard contentDidEnd, !adBreakActive else { return }
        finishDemo()
    }

    private func finishDemo() {
        guard !finished else { return }
        finished = true
        EventLog.append("instream: demo finished -- popping")
        navigationController?.popViewController(animated: true)
    }

    private func teardown() {
        adsLoader?.detach()
        adsLoader = nil
        if let contentEndObserver {
            NotificationCenter.default.removeObserver(contentEndObserver)
            self.contentEndObserver = nil
        }
        contentPlayer.pause()
        contentPlayerLayer?.removeFromSuperlayer()
        contentPlayerLayer = nil
    }

    // MARK: - Tap-to-pause/resume

    /// `contentContainerView`'s own tap gesture only ever fires when
    /// `overlayContainerView` is NOT intercepting (i.e. no ad break is
    /// showing) -- a plain `UIView` with `isUserInteractionEnabled == false`
    /// is skipped entirely during hit-testing, so taps pass straight through
    /// to this view underneath while idle, and are captured by the overlay's
    /// own chrome (skip/click) the instant a break makes it interactive.
    @objc private func togglePlayPause() {
        if contentPlayer.timeControlStatus == .playing {
            userPaused = true
            contentPlayer.pause()
            playStateHintLabel.text = Self.pausedHint
        } else {
            userPaused = false
            contentPlayer.play()
            playStateHintLabel.text = Self.playingHint
        }
    }

    // MARK: - App lifecycle (never leave audio playing behind the app)

    @objc private func appWillResignActive() {
        contentPlayer.pause()
    }

    @objc private func appDidBecomeActive() {
        // I3 fix-review: without `!adBreakActive`, backgrounding/foregrounding
        // WHILE an ad break is showing (`AdBreakOverlayView` already has its
        // own app-lifecycle pair that correctly pauses/resumes the AD
        // player) also resumed this screen's OWN content player underneath
        // it -- two players racing to play at once, content audibly/visibly
        // playing under a still-active ad. `adBreakActive` (flipped by
        // `onStart`/`onComplete`/`onSkip`/`onError` below) is this screen's
        // own signal for "a break is currently showing"; mirrors
        // `finishIfNothingLeftToWaitFor`'s existing `!adBreakActive` guard
        // above.
        guard !userPaused, !finished, !adBreakActive else { return }
        contentPlayer.play()
    }

    private static let playingHint = "▶ tocando (toque para pausar)"
    private static let pausedHint = "⏸ pausado (toque para retomar)"
}

// MARK: - MetrikeVideoDelegate (MetrikeAdsLoader)

extension InstreamDemoViewController: MetrikeVideoDelegate {
    /// Never actually invoked by `MetrikeAdsLoader` (its own `notify(_:)`
    /// only ever maps "start"/quartiles/"complete"/"skip"/"click" -- see
    /// that file) -- implemented anyway for documentation completeness
    /// against the shared `MetrikeVideoDelegate` protocol.
    func onReady() {
        EventLog.append("instream.onReady")
    }

    func onStart() {
        adBreakActive = true
        overlayContainerView.isUserInteractionEnabled = true
        // Hide THIS screen's own chrome for the duration of the break. The
        // hint sits above `overlayContainerView` in the hierarchy, so during
        // a break it printed straight over the ad's own "Anúncio · 0:0X"
        // countdown -- and its instruction ("toque para pausar") is a lie
        // while the overlay is swallowing taps anyway. A host app owns this
        // decision, which is exactly why the example demonstrates it.
        playStateHintLabel.isHidden = true
        EventLog.append("instream.onStart")
    }

    func onQuartile(_ name: String) {
        EventLog.append("instream.onQuartile(\(name))")
    }

    func onClick() {
        EventLog.append("instream.onClick")
    }

    /// Not invoked by `MetrikeAdsLoader` either (its ad-break overlay has no
    /// close button -- see that class's kdoc, "Deliberately has NO close (X)
    /// button"), kept for the same documentation-completeness reason as
    /// `onReady` above.
    func onClose() {
        EventLog.append("instream.onClose")
    }

    func onComplete() {
        adBreakEnded("onComplete")
    }

    func onSkip() {
        adBreakEnded("onSkip")
    }

    func onError(_ code: Int, _ message: String) {
        EventLog.append("instream.onError code=\(code) message=\(message)")
        adBreakEnded("onError(handled above)", logged: false)
    }

    private func adBreakEnded(_ label: String, logged: Bool = true) {
        adBreakActive = false
        overlayContainerView.isUserInteractionEnabled = false
        playStateHintLabel.isHidden = false // see onStart
        if logged { EventLog.append("instream.\(label)") }
        if contentDidEnd { finishDemo() }
    }
}
