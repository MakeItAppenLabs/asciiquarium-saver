import UIKit
import AquariumKit

/// The app's only screen: the tank, stepped every tenth of a second while the app is in front.
final class TankViewController: UIViewController {
    let store = SettingsStore(defaults: .standard)
    private(set) lazy var tankView = TankView(settings: store.load())
    private var timer: Timer?

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
    }

    @objc private func didBecomeActive() { start() }
    @objc private func willResignActive() { stop() }

    /// Starts the frame timer, and keeps the TV from dimming or starting its screen saver.
    func start() {
        UIApplication.shared.isIdleTimerDisabled = true
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tankView.step() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
