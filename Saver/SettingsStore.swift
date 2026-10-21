import Foundation
import AquariumKit

/// Reads and writes the settings as one JSON blob under `settings.v1`.
///
/// The saver passes `ScreenSaverDefaults(forModuleWithName:)`, which the sandboxed host and the Options
/// sheet share; the Preview app passes `.standard`.
final class SettingsStore {
    static let key = "settings.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> AquariumSettings {
        // ScreenSaverDefaults caches; pick up a change saved by another process (the Options sheet).
        defaults.synchronize()
        return AquariumSettings.decode(defaults.data(forKey: Self.key))
    }

    func save(_ s: AquariumSettings) {
        defaults.set(s.encoded(), forKey: Self.key)
        // ScreenSaverDefaults only writes to disk on synchronize.
        defaults.synchronize()
    }
}
