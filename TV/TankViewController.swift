import SwiftUI
import UIKit
import AquariumKit

/// The app's only screen: the tank, stepped every tenth of a second while the app is in front.
///
/// The remote: a click drops the fishhook (or reels it in), Play/Pause opens Options, and Back closes
/// Options or, with Options closed, leaves the app.
final class TankViewController: UIViewController {
    let store = SettingsStore(defaults: .standard)
    private(set) lazy var tankView = TankView(settings: store.load())
    private var timer: Timer?
    private let idleGuard = IdleGuard(limit: IdleGuard.configuredLimit)
    private let hint = UILabel()

    private(set) var isOptionsOpen = false
    /// The open Options panel: a blur flush with the right edge, holding the SwiftUI panel.
    private var optionsPanel: (blur: UIVisualEffectView, host: UIHostingController<OptionsPanel>)?

    /// The share of the screen width the Options panel covers.
    private static let panelWidthFraction: CGFloat = 0.42

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .black
        tankView.frame = root.bounds
        tankView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(tankView)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addHint()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(
            self, selector: #selector(willResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        start()
        showHint()
    }

    @objc private func didBecomeActive() { start() }
    @objc private func willResignActive() { stop() }

    /// Starts the frame timer, and keeps the TV awake until the idle guard's limit.
    func start() {
        idleGuard.activity()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tankView.step() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        idleGuard.suspend()
    }

    // MARK: Remote

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        idleGuard.activity()
        guard let type = presses.first?.type else {
            super.pressesBegan(presses, with: event)
            return
        }
        switch (type, isOptionsOpen) {
        case (.select, false):
            tankView.aquarium?.pressHook()
        case (.playPause, false):
            openOptions()
        case (.menu, true):
            // The panel handles Back itself (close, or back one screen); never let it quit the app.
            break
        default:
            // Includes Back with Options closed, which leaves the app.
            super.pressesBegan(presses, with: event)
        }
    }

    // MARK: Options

    /// Slides the panel in from the right. The tank keeps swimming beside it.
    func openOptions() {
        guard !isOptionsOpen else { return }
        isOptionsOpen = true
        hint.layer.removeAllAnimations()
        hint.alpha = 0
        let panel = OptionsPanel(
            settings: tankView.settings,
            onChange: { [weak self] new in
                self?.store.save(new)
                self?.tankView.apply(new)
            },
            onClose: { [weak self] in self?.closeOptions() }
        )
        let host = UIHostingController(rootView: panel)
        host.view.backgroundColor = .clear
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))

        addChild(host)
        blur.contentView.addSubview(host.view)
        view.addSubview(blur)
        host.didMove(toParent: self)
        optionsPanel = (blur, host)

        let width = (view.bounds.width * Self.panelWidthFraction).rounded()
        let insets = view.safeAreaInsets
        blur.frame = CGRect(x: view.bounds.width, y: 0, width: width, height: view.bounds.height)
        // The blur reaches the screen edge; the controls stay inside the safe area.
        host.view.frame = CGRect(
            x: 40, y: insets.top,
            width: width - 40 - insets.right, height: view.bounds.height - insets.top - insets.bottom)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            blur.frame.origin.x = self.view.bounds.width - width
        }
        setNeedsFocusUpdate()
    }

    /// Slides the panel out and removes it.
    func closeOptions() {
        guard isOptionsOpen, let (blur, host) = optionsPanel else { return }
        isOptionsOpen = false
        optionsPanel = nil
        host.willMove(toParent: nil)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn]) {
            blur.frame.origin.x = self.view.bounds.width
        } completion: { _ in
            host.view.removeFromSuperview()
            host.removeFromParent()
            blur.removeFromSuperview()
        }
        setNeedsFocusUpdate()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let host = optionsPanel?.host { return [host] }
        return super.preferredFocusEnvironments
    }

    // MARK: Launch hint

    private func addHint() {
        hint.text = "Click to drop a hook · Play/Pause for options"
        hint.font = .preferredFont(forTextStyle: .callout)
        hint.textColor = UIColor(white: 1, alpha: 0.7)
        hint.alpha = 0
        // Keeps the line readable where it crosses seaweed.
        hint.layer.shadowColor = UIColor.black.cgColor
        hint.layer.shadowOpacity = 1
        hint.layer.shadowRadius = 6
        hint.layer.shadowOffset = .zero
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    /// Shows the hint for four seconds after launch, then fades it out over one.
    private func showHint() {
        hint.alpha = 1
        UIView.animate(withDuration: 1, delay: 4, options: [.curveEaseInOut]) {
            self.hint.alpha = 0
        }
    }
}
