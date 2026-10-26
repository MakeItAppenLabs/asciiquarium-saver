import UIKit
import os

private let log = Logger(subsystem: "com.makeitappenlabs.asciiquarium", category: "idle")

/// Keeps the TV from dimming or starting its screen saver while the tank runs, but only until no
/// button has been pressed for `limit`. Then the TV's own idle behavior takes over again, so a tank
/// left on all night can't burn the castle into an OLED panel.
@MainActor
final class IdleGuard {
    /// Four hours without a press.
    static let defaultLimit: TimeInterval = 14_400

    /// `defaultLimit`, or in Debug builds the `-idleGuardSeconds N` launch argument, for testing.
    static var configuredLimit: TimeInterval {
        #if DEBUG
        let seconds = UserDefaults.standard.double(forKey: "idleGuardSeconds")
        if seconds > 0 { return seconds }
        #endif
        return defaultLimit
    }

    private let limit: TimeInterval
    private var timer: Timer?

    init(limit: TimeInterval) {
        self.limit = limit
    }

    /// A button press, or the app coming to the front: keep the TV awake and restart the clock.
    func activity() {
        setIdleTimerDisabled(true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.setIdleTimerDisabled(false) }
        }
    }

    /// The app is leaving the front: stop the clock. The system manages idle while it's away.
    func suspend() {
        timer?.invalidate()
        timer = nil
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
        log.debug("isIdleTimerDisabled=\(disabled)")
    }
}
