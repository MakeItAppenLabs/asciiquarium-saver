// Asciiquarium for macOS — Swift port Copyright (C) 2026 Make It Appen LLC.
// Modified from asciiquarium 1.6, Copyright (C) 2013 Kirk Baucom.
// Licensed under the GNU GPL version 3 or (at your option) any later version; see LICENSE.

/// What the `add...` functions need to put something into the aquarium.
public struct SpawnContext {
    public let engine: Engine
    public let settings: AquariumSettings

    /// Perl's `-c --classic`: only the species of Asciiquarium 1.0.
    public var classic: Bool { settings.creatureSet == .classic }

    public init(engine: Engine, settings: AquariumSettings) {
        self.engine = engine
        self.settings = settings
    }
}
