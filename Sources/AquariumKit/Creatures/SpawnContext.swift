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
