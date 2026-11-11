// Asciiquarium for macOS — Swift port Copyright (C) 2026 Make It Appen LLC.
// Modified from asciiquarium 1.6, Copyright (C) 2013 Kirk Baucom.
// Licensed under the GNU GPL version 3 or (at your option) any later version; see LICENSE.

/// The one public entry point the screen saver drives: a populated, running aquarium.
///
/// Setup follows the top of Perl's main loop: environment, castle, seaweed, fish, then one random
/// special. After that each special's death starts the next, so nothing else is needed per frame
/// except `step()`. (Perl's `init_colors` is the palette's job, and its keyboard and food handling are
/// out of scope.)
///
/// Settings are captured by value by every spawn chain, so they are fixed for the lifetime of an
/// aquarium. When the settings or the size change, build a new `Aquarium`, as Perl does when it
/// recreates all objects on a resize.
public final class Aquarium {
    public let cols: Int
    public let rows: Int
    public let settings: AquariumSettings

    private let engine: Engine

    public init(cols: Int, rows: Int, settings: AquariumSettings, seed: UInt64) {
        self.cols = cols
        self.rows = rows
        self.settings = settings
        engine = Engine(cols: cols, rows: rows, rng: RandomSource(seed: seed))

        let context = SpawnContext(engine: engine, settings: settings)
        addEnvironment(context)
        addCastle(context)
        addAllSeaweed(context)
        addAllFish(context)
        addRandomSpecial(context)
    }

    /// Advances the animation by one frame (about a tenth of a second).
    public func step() {
        engine.step()
    }

    /// The Apple TV remote's click: drops the fishhook, or reels in one that is still lowering.
    @discardableResult
    public func pressHook() -> HookPress {
        AquariumKit.pressHook(SpawnContext(engine: engine, settings: settings))
    }

    /// Draws the current state.
    public func render() -> Grid {
        engine.render()
    }

    /// The number of live entities, for tests and diagnostics.
    public var entityCount: Int { engine.entityCount }
}
