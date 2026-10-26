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
            closeOptions()
        default:
            // Includes Back with Options closed, which leaves the app.
            super.pressesBegan(presses, with: event)
        }
    }

    // MARK: Options

    func openOptions() {}

    func closeOptions() {}

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
