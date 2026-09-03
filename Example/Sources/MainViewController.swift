import UIKit
import MetrikeAds

// MARK: - Delegate proxies

/// One small forwarding shim per `MetrikeBannerView` load, rather than
/// `MainViewController` itself conforming to `MetrikeBannerViewDelegate` --
/// mirrors Android's testapp creating a fresh anonymous `MetrikeAdListener`
/// object per `load()` call (`MainActivity.kt`'s `loadBanner`). The reason
/// this matters here, not just there: `MetrikeBannerViewDelegate` and
/// `MetrikeInterstitialDelegate` both declare an IDENTICAL
/// `onError(_ code: Int, _ message: String)` requirement, so if
/// `MainViewController` conformed to both directly, ONE shared method body
/// would have to serve both formats with no way to tell, from inside it,
/// which ad actually failed -- a dedicated proxy per format sidesteps that
/// entirely, same as giving each format its own tagged log line below does.
final class BannerDelegateProxy: NSObject, MetrikeBannerViewDelegate {
    func onLoad() { EventLog.append("banner.onLoad") }
    func onNoFill() { EventLog.append("banner.onNoFill") }
    func onClick() { EventLog.append("banner.onClick") }
    func onClosed() { EventLog.append("banner.onClosed") }
    func onError(_ code: Int, _ message: String) {
        EventLog.append("banner.onError code=\(code) message=\(message)")
    }
    func onViewable(_ timeToViewableMs: Int64) {
        EventLog.append("banner.onViewable timeToViewableMs=\(timeToViewableMs)")
    }
}

/// See `BannerDelegateProxy`'s doc for why this is a dedicated proxy rather
/// than `MainViewController` conformance. `onReady` calls back into
/// `onReadyAction` to `show(from:)` the now-ready interstitial -- mirrors
/// Android's `MetrikeInterstitial.Listener.onReady` calling `ad.show(this)`
/// inline.
final class InterstitialDelegateProxy: NSObject, MetrikeInterstitialDelegate {
    private let onReadyAction: () -> Void

    init(onReady: @escaping () -> Void) {
        self.onReadyAction = onReady
    }

    func onReady() {
        EventLog.append("interstitial.onReady -> show()")
        onReadyAction()
    }
    func onNoFill() { EventLog.append("interstitial.onNoFill") }
    func onShown() { EventLog.append("interstitial.onShown") }
    func onClick() { EventLog.append("interstitial.onClick") }
    func onClosed() { EventLog.append("interstitial.onClosed") }
    func onError(_ code: Int, _ message: String) {
        EventLog.append("interstitial.onError code=\(code) message=\(message)")
    }
}

/// `MetrikeVideoDelegate` is ONE shared `@objc` protocol across
/// `MetrikeVastVideo`, `MetrikeVideoAdView`, and `MetrikeAdsLoader` (task-11
/// brief, pinned surface) -- this screen shows both a VAST-fullscreen
/// instance AND an outstream instance at once, so a single conformance
/// couldn't tag which one fired. `tag` (`"vastFullscreen"`/`"outstream"`)
/// gives every log line the same per-format prefix Android's testapp's own
/// separate anonymous `VastListener` objects produce
/// (`MainActivity.kt`'s `loadVastFullscreen`/`loadOutstream`).
final class TaggedVideoDelegate: NSObject, MetrikeVideoDelegate {
    private let tag: String
    private let readySuffix: String
    private let onReadyAction: (() -> Void)?

    init(tag: String, readySuffix: String = "", onReady: (() -> Void)? = nil) {
        self.tag = tag
        self.readySuffix = readySuffix
        self.onReadyAction = onReady
    }

    func onReady() {
        EventLog.append("\(tag).onReady\(readySuffix)")
        onReadyAction?()
    }
    func onStart() { EventLog.append("\(tag).onStart") }
    func onQuartile(_ name: String) { EventLog.append("\(tag).onQuartile(\(name))") }
    func onComplete() { EventLog.append("\(tag).onComplete") }
    func onSkip() { EventLog.append("\(tag).onSkip") }
    func onClick() { EventLog.append("\(tag).onClick") }
    func onClose() { EventLog.append("\(tag).onClose") }
    func onError(_ code: Int, _ message: String) {
        EventLog.append("\(tag).onError code=\(code) message=\(message)")
    }
}

// MARK: - MainViewController

/// Living integration example for the SDK's entire public surface -- every
/// call in this file is exactly what the doc snippets show. `Metrike
/// .initialize` itself already happened once, in `AppDelegate`, before this
/// screen (or any ad call) exists. Single-scroll layout with the event log
/// pinned outside the scroll (task-14 brief's "round 1 lesson", carried over
/// from the Android testapp's own `activity_main.xml` fix comment: a fixed
/// controls section + a weighted `ScrollView` can resolve to 0pt on a short
/// screen -- one scroll for everything else, log pinned separately, avoids
/// that entirely).
final class MainViewController: UIViewController {

    // MARK: Ad instances (retained -- every SDK delegate property is `weak`)

    private var bannerView: MetrikeBannerView?
    private var bannerDelegate: BannerDelegateProxy?

    private var interstitial: MetrikeInterstitial?
    private var interstitialDelegate: InterstitialDelegateProxy?

    private var vastVideo: MetrikeVastVideo?
    private var vastVideoDelegate: TaggedVideoDelegate?

    private var outstreamAd: MetrikeVideoAdView?
    private var outstreamDelegate: TaggedVideoDelegate?

    // MARK: Layout

    private let eventLogView = EventLogView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let zoneIdField = UITextField()
    private let vastTokenField = UITextField()
    private let envControl = UISegmentedControl(items: ["Prod", "Local"])
    private let envNoticeLabel = UILabel()

    private let bannerContainer = UIView()
    private let outstreamContainer = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Metrike Example"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        buildLayout()
        loadPersistedConfigIntoFields()
        refreshEnvNotice()

        EventLog.append("MainViewController: pronto -- API pública apenas (MetrikeAds import), zoneId=\(TestConfig.zoneId), vastToken=\(TestConfig.vastToken)")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Only torn down if this screen itself is being popped/dismissed --
        // a pushed InstreamDemoViewController on top does NOT trigger this
        // (viewWillDisappear fires for the view leaving the WINDOW, which a
        // push does technically call -- so guard on isMovingFromParent /
        // being removed from the nav stack, not just visibility, to avoid
        // destroying the banner/outstream every time the user goes look at
        // the instream demo and comes back).
        guard isMovingFromParent || isBeingDismissed else { return }
        bannerView?.destroy()
        outstreamAd?.destroy()
    }

    // MARK: - Layout construction

    private func buildLayout() {
        eventLogView.translatesAutoresizingMaskIntoConstraints = false
        eventLogView.layer.borderColor = UIColor.separator.cgColor
        eventLogView.layer.borderWidth = 1

        let eventLogHeader = UILabel()
        eventLogHeader.text = "Event log"
        eventLogHeader.font = .boldSystemFont(ofSize: 13)
        eventLogHeader.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(eventLogHeader)
        view.addSubview(eventLogView)

        // Task-14 brief / Android round-1 lesson: the event log is pinned
        // OUTSIDE the scroll, at a fixed ~35% of the screen, so it is always
        // visible while scrolling through the demo content above it.
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.65),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            eventLogHeader.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            eventLogHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            eventLogView.topAnchor.constraint(equalTo: eventLogHeader.bottomAnchor, constant: 2),
            eventLogView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            eventLogView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            eventLogView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        contentStack.addArrangedSubview(buildIntroSection())
        contentStack.addArrangedSubview(buildConfigSection())
        contentStack.addArrangedSubview(buildBannerSection())
        contentStack.addArrangedSubview(buildFillerLabel(
            "Role a tela para ver o banner acima entrar e sair da área visível -- o beacon "
                + "\"viewable\" só deve disparar quando o banner estiver de fato visível por tempo "
                + "suficiente (MRC: 50% da área, 1s contínuo). Acompanhe os eventos correspondentes "
                + "no log abaixo (request, impression, onLoad, onViewable)."
        ))
        contentStack.addArrangedSubview(buildInterstitialSection())
        contentStack.addArrangedSubview(buildVastFullscreenSection())
        contentStack.addArrangedSubview(buildOutstreamSection())
        contentStack.addArrangedSubview(buildInstreamSection())
        contentStack.addArrangedSubview(buildConversionSection())
        contentStack.addArrangedSubview(buildDeepLinkSection())
        contentStack.addArrangedSubview(buildFillerLabel(
            "Metrike Ads SDK -- iOS. Este app de exemplo consome exclusivamente a API pública do "
                + "módulo MetrikeAds: Metrike.initialize, MetrikeBannerView, MetrikeInterstitial, "
                + "MetrikeVastVideo, MetrikeVideoAdView, MetrikeAdsLoader, Metrike.handleDeepLink e "
                + "Metrike.trackConversion. Nenhum tipo interno é usado aqui -- o que você vê nesta "
                + "tela é exatamente o que a documentação de integração descreve."
        ))
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 15)
        return label
    }

    private func button(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func buildFillerLabel(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }

    private func stack(_ views: [UIView], spacing: CGFloat = 8) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        return stack
    }

    private func buildIntroSection() -> UIView {
        buildFillerLabel(
            "Galeria dos 6 formatos do Metrike Ads SDK (iOS): banner, interstitial, VAST "
                + "fullscreen, outstream, instream e MRAID (via banner). Zonas de teste do org de "
                + "teste id 2 -- NUNCA uma zona real."
        )
    }

    private func buildConfigSection() -> UIView {
        zoneIdField.borderStyle = .roundedRect
        zoneIdField.keyboardType = .numberPad
        zoneIdField.placeholder = "id numérico da sua zona de display"
        zoneIdField.addTarget(self, action: #selector(zoneIdChanged), for: .editingChanged)

        vastTokenField.borderStyle = .roundedRect
        vastTokenField.placeholder = "vast token da sua zona de vídeo"
        vastTokenField.autocapitalizationType = .none
        vastTokenField.autocorrectionType = .no
        vastTokenField.addTarget(self, action: #selector(vastTokenChanged), for: .editingChanged)

        envControl.selectedSegmentIndex = TestConfig.pendingEnv == .local ? 1 : 0
        envControl.addTarget(self, action: #selector(envChanged), for: .valueChanged)

        envNoticeLabel.font = .systemFont(ofSize: 12)
        envNoticeLabel.textColor = .systemOrange
        envNoticeLabel.numberOfLines = 0

        return stack([
            sectionLabel("Configuração"),
            UILabel.caption("Zone ID (banner + interstitial)"),
            zoneIdField,
            UILabel.caption("VAST token (fullscreen + outstream + instream)"),
            vastTokenField,
            UILabel.caption("Ambiente"),
            envControl,
            envNoticeLabel,
        ], spacing: 6)
    }

    private func buildBannerSection() -> UIView {
        bannerContainer.backgroundColor = UIColor.systemGray5
        bannerContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bannerContainer.heightAnchor.constraint(equalToConstant: 60),
        ])

        let mraidNote = buildFillerLabel(
            "Nota MRAID: esta mesma zona (banner) serve o que estiver configurado no servidor para "
                + "ela. Se a zona informada acima tiver uma criativo MRAID (expand/resize) "
                + "configurado, o SDK "
                + "renderiza e faz o host do bridge mraid.js automaticamente dentro do WebView "
                + "interno -- não há nenhuma API pública adicional a chamar aqui além de "
                + "MetrikeBannerView.load(). Configure a criativo de teste MRAID no painel do org de "
                + "teste id 2 para exercitar expand/resize."
        )

        return stack([
            sectionLabel("Banner 320x50"),
            button("Carregar banner", action: #selector(loadBannerTapped)),
            bannerContainer,
            mraidNote,
        ])
    }

    private func buildInterstitialSection() -> UIView {
        stack([
            sectionLabel("Interstitial"),
            button("Interstitial (preload → show)", action: #selector(loadInterstitialTapped)),
        ])
    }

    private func buildVastFullscreenSection() -> UIView {
        stack([
            sectionLabel("VAST fullscreen"),
            button("VAST fullscreen (preload → display)", action: #selector(loadVastFullscreenTapped)),
        ])
    }

    private func buildOutstreamSection() -> UIView {
        outstreamContainer.backgroundColor = .black
        outstreamContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            outstreamContainer.heightAnchor.constraint(equalToConstant: 200),
        ])
        return stack([
            sectionLabel("Outstream"),
            button("Outstream (MetrikeVideoAdView no feed)", action: #selector(loadOutstreamTapped)),
            outstreamContainer,
        ])
    }

    private func buildInstreamSection() -> UIView {
        stack([
            sectionLabel("Instream (IMA-style)"),
            buildFillerLabel(
                "Abre uma tela dedicada com um AVPlayer real reproduzindo conteúdo de demonstração "
                    + "com pre/mid/post-roll inseridos via MetrikeAdsLoader."
            ),
            button("Abrir demo instream", action: #selector(openInstreamTapped)),
        ])
    }

    private func buildConversionSection() -> UIView {
        stack([
            sectionLabel("Conversão"),
            button("Comprar (trackConversion)", action: #selector(buyTapped)),
        ])
    }

    private func buildDeepLinkSection() -> UIView {
        stack([
            sectionLabel("Deep link"),
            buildFillerLabel(
                "Simula um deep link mk_cid=... chegando via o esquema metriketest:// -- "
                    + "AppDelegate.application(_:open:) roteia para Metrike.handleDeepLink(_:), o "
                    + "mesmo caminho que um clique real em um app publicitário externo dispara."
            ),
            button("Deep link fake", action: #selector(fakeDeepLinkTapped)),
        ])
    }

    private func loadPersistedConfigIntoFields() {
        zoneIdField.text = TestConfig.zoneId
        vastTokenField.text = TestConfig.vastToken
    }

    private func refreshEnvNotice() {
        if TestConfig.pendingEnv != TestConfig.activeEnv {
            envNoticeLabel.text = "Ambiente muda no próximo início do app (feche e reabra para aplicar). "
                + "Ativo agora: \(TestConfig.activeEnv.displayName)."
        } else {
            envNoticeLabel.text = "Ambiente ativo: \(TestConfig.activeEnv.displayName)."
        }
    }

    // MARK: - Current field values

    /// `nil` when the field is empty or not a number. There is deliberately
    /// no fallback zone to substitute (see `TestConfig.zoneId`'s doc), so a
    /// caller with `nil` here must not call the SDK at all -- it would fire a
    /// request for zone 0 and get a confusing server-side error instead of
    /// the obvious "you did not fill the field in" this reports.
    private func currentZoneId() -> Int64? {
        guard let text = zoneIdField.text, let zoneId = Int64(text), zoneId > 0 else { return nil }
        return zoneId
    }

    /// `nil` when the field is empty -- same contract as `currentZoneId()`.
    private func currentVastToken() -> String? {
        guard let text = vastTokenField.text, !text.isEmpty else { return nil }
        return text
    }

    /// One place to report "the demo cannot run without this field", so every
    /// format button behaves identically when the tester has not filled the
    /// config in yet.
    private func requireZoneId() -> Int64? {
        guard let zoneId = currentZoneId() else {
            EventLog.append("configuração: informe o Zone ID antes de carregar um anúncio de display")
            return nil
        }
        return zoneId
    }

    private func requireVastToken() -> String? {
        guard let token = currentVastToken() else {
            EventLog.append("configuração: informe o VAST token antes de carregar um anúncio de vídeo")
            return nil
        }
        return token
    }

    // MARK: - Actions: config

    @objc private func zoneIdChanged() {
        TestConfig.zoneId = zoneIdField.text ?? ""
    }

    @objc private func vastTokenChanged() {
        TestConfig.vastToken = vastTokenField.text ?? ""
    }

    @objc private func envChanged() {
        let chosen: TestConfig.Env = envControl.selectedSegmentIndex == 1 ? .local : .prod
        TestConfig.pendingEnv = chosen
        refreshEnvNotice()
        EventLog.append("TestConfig.pendingEnv = \(chosen.displayName) (reabra o app para aplicar)")
    }

    // MARK: - Actions: banner

    @objc private func loadBannerTapped() {
        guard let zoneId = requireZoneId() else { return }
        bannerView?.destroy()
        bannerView?.removeFromSuperview()

        let banner = MetrikeBannerView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.zoneId = zoneId
        let proxy = BannerDelegateProxy()
        banner.delegate = proxy

        bannerContainer.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: bannerContainer.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: bannerContainer.centerYAnchor),
            banner.widthAnchor.constraint(equalToConstant: 320),
            banner.heightAnchor.constraint(equalToConstant: 50),
        ])

        bannerView = banner
        bannerDelegate = proxy
        EventLog.append("banner.load() zoneId=\(banner.zoneId)")
        banner.load()
    }

    // MARK: - Actions: interstitial

    @objc private func loadInterstitialTapped() {
        guard let zoneId = requireZoneId() else { return }
        let ad = MetrikeInterstitial(zoneId: zoneId)
        ad.closeDelaySeconds = 5
        let proxy = InterstitialDelegateProxy { [weak self, weak ad] in
            guard let self, let ad else { return }
            ad.show(from: self)
        }
        ad.delegate = proxy

        interstitial = ad
        interstitialDelegate = proxy
        EventLog.append("interstitial.preload() zoneId=\(zoneId)")
        ad.preload()
    }

    // MARK: - Actions: VAST fullscreen

    @objc private func loadVastFullscreenTapped() {
        guard let token = requireVastToken() else { return }
        let vast = MetrikeVastVideo(vastToken: token)
        let proxy = TaggedVideoDelegate(tag: "vastFullscreen", readySuffix: " -> display()") { [weak self, weak vast] in
            guard let self, let vast else { return }
            vast.display(from: self)
        }
        vast.delegate = proxy

        vastVideo = vast
        vastVideoDelegate = proxy
        EventLog.append("vastFullscreen.preload() vastToken=\(token)")
        vast.preload()
    }

    // MARK: - Actions: outstream

    @objc private func loadOutstreamTapped() {
        outstreamAd?.destroy()
        outstreamAd?.removeFromSuperview()

        guard let token = requireVastToken() else { return }
        let view = MetrikeVideoAdView(frame: outstreamContainer.bounds)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.vastToken = token
        let proxy = TaggedVideoDelegate(tag: "outstream")
        view.delegate = proxy

        outstreamContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: outstreamContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: outstreamContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: outstreamContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: outstreamContainer.trailingAnchor),
        ])

        outstreamAd = view
        outstreamDelegate = proxy
        EventLog.append("outstream.load() vastToken=\(token)")
        view.load()
    }

    // MARK: - Actions: instream

    @objc private func openInstreamTapped() {
        guard let token = requireVastToken() else { return }
        EventLog.append("instream: abrindo InstreamDemoViewController vastToken=\(token)")
        let controller = InstreamDemoViewController(vastToken: token)
        navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: - Actions: conversion + deep link

    @objc private func buyTapped() {
        let orderId = "order-\(Int(Date().timeIntervalSince1970 * 1000))"
        EventLog.append("trackConversion(goal=demo-goal, valueCents=4990, orderId=\(orderId))")
        Metrike.trackConversion("demo-goal", valueCents: 4990, orderId: orderId)
    }

    @objc private func fakeDeepLinkTapped() {
        let fakeCid = "test-\(Int(Date().timeIntervalSince1970 * 1000))"
        guard let url = URL(string: "metriketest://open?mk_cid=\(fakeCid)") else { return }
        // Calls the public entry point directly (in-process) -- exercising
        // the actual `application(_:open:)` round trip would require
        // Springboard/UIApplication.shared.open, which cannot be driven
        // reliably from inside the app's own UI. AppDelegate.application(_:open:)
        // is still wired for a REAL external open (e.g. tapping a
        // metriketest:// link from Safari/Notes) and calls this exact same
        // Metrike.handleDeepLink(_:).
        let handled = Metrike.handleDeepLink(url)
        EventLog.append("handleDeepLink(mk_cid=\(fakeCid)) -> \(handled)")
    }
}

private extension UILabel {
    static func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }
}
