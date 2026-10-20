import Foundation

/// The animation engine: a port of Term::Animation 2.6 as asciiquarium 1.6 uses it.
///
/// One `step()` is one Perl `animate()` minus the drawing: per entity the death checks and then the
/// tick, then collisions, then the removal of killed entities. `render()` draws the current state.
///
/// Callbacks may add and kill entities freely. During a step those changes are queued and applied at
/// the end of the phase, so an entity added in a callback does not tick until the next step but is
/// visible to `entities(ofType:)` straight away. Outside a step they apply immediately.
///
/// Entities are always visited in the order they were added. Perl iterates a hash in random order, so
/// nothing may depend on that order.
public final class Engine {
    public let cols: Int
    public let rows: Int
    public let rng: RandomSource
    /// Steps completed so far.
    public private(set) var frameCount = 0

    private enum Phase { case idle, tick, collision, removal }
    private var phase = Phase.idle

    private var entities: [Entity] = []
    private var pendingAdds: [Entity] = []
    private var killQueue: [Entity] = []

    public init(cols: Int, rows: Int, rng: RandomSource) {
        self.cols = cols
        self.rows = rows
        self.rng = rng
    }

    // MARK: membership

    /// Adds an entity. Adding one that is already in an engine does nothing.
    @discardableResult
    public func add(_ e: Entity) -> Entity {
        guard e.lifecycle == .detached else { return e }
        e.lifecycle = .active
        e.age = 0
        if phase == .idle {
            entities.append(e)
        } else {
            pendingAdds.append(e)
        }
        return e
    }

    /// Kills an entity: `onDeath` runs once, then the entity leaves. During a step this is queued for
    /// the removal phase (Perl `del_entity`); outside a step it happens now. Killing an entity that is
    /// already dying or gone does nothing.
    public func kill(_ e: Entity) {
        guard e.lifecycle == .active else { return }
        e.lifecycle = .dying
        killQueue.append(e)
        if phase == .idle { processKills() }
    }

    /// Removes an entity without running `onDeath`. During a step it leaves in the removal phase. If a
    /// kill is already queued for the entity, that kill still runs `onDeath`.
    public func remove(_ e: Entity) {
        switch (e.lifecycle, phase) {
        case (.detached, _), (.dying, _):
            return
        case (.active, .idle):
            detach(e)
        case (.active, _):
            e.lifecycle = .dying
            killQueue.append(e)
            silentKills.insert(e.id)
        }
    }

    /// Removes everything without running any `onDeath` (Perl `remove_all_entities`).
    public func removeAll() {
        for e in entities + pendingAdds { e.lifecycle = .detached }
        entities.removeAll()
        pendingAdds.removeAll()
        killQueue.removeAll()
        silentKills.removeAll()
    }

    /// Entities of a type, including ones with a queued kill (Perl keeps those until the removal phase).
    public func entities(ofType type: String) -> [Entity] {
        (entities + pendingAdds).filter { $0.type == type }
    }

    public var entityCount: Int { entities.count + pendingAdds.count }

    // MARK: step

    /// One animation step.
    ///
    /// 1. For each entity, in order: `dieAfterFrames`, then `dieAfterCycles`, then `dieOffscreen` are
    ///    checked, and a dying entity does not tick. Otherwise `onTick` runs, or `defaultMove()`.
    ///    The offscreen rule is Perl's: `x >= cols || y >= rows || x < -width || y < -height`, using the
    ///    position left by the previous step.
    /// 2. Physical entities that overlap are found, then each one's `onCollision` runs.
    /// 3. Queued kills run `onDeath` and leave, including kills queued by `onDeath` itself.
    public func step() {
        phase = .tick
        for e in entities {
            if let n = e.dieAfterFrames {
                e.age += 1
                if e.age >= n {
                    kill(e)
                    continue
                }
            }
            if let c = e.dieAfterCycles {
                e.dieAfterCycles = c - 1
                if c <= 0 {
                    kill(e)
                    continue
                }
            }
            if e.dieOffscreen && isOffscreen(e) {
                kill(e)
                continue
            }
            if let tick = e.onTick {
                tick(e, self)
            } else {
                e.defaultMove()
            }
        }
        applyPendingAdds()

        phase = .collision
        runCollisions()
        applyPendingAdds()

        phase = .removal
        processKills()

        phase = .idle
        frameCount += 1
    }

    private func isOffscreen(_ e: Entity) -> Bool {
        e.x >= Double(cols) || e.y >= Double(rows)
            || e.x < -Double(e.width) || e.y < -Double(e.height)
    }

    // MARK: collisions

    /// Term::Animation `_find_collisions`: per axis, the half-open ranges `[pos, pos + size)` overlap.
    /// All three axes must overlap, z included (`z ..< z + depth`). Positions are not rounded.
    private func overlaps(_ a: Entity, _ b: Entity) -> Bool {
        func axis(_ pa: Double, _ sa: Int, _ pb: Double, _ sb: Int) -> Bool {
            (pa <= pb && pb < pa + Double(sa)) || (pb <= pa && pa < pb + Double(sb))
        }
        return axis(a.x, a.width, b.x, b.width)
            && axis(a.y, a.height, b.y, b.height)
            && axis(Double(a.z), a.depth, Double(b.z), b.depth)
    }

    private func runCollisions() {
        let physical = entities.filter(\.isPhysical)
        guard physical.count > 1 else { return }

        // Find every pair first, so handlers that kill or add cannot change what other handlers see.
        var found: [Int: [Entity]] = [:]
        for (index, later) in physical.enumerated() {
            for earlier in physical[..<index] where overlaps(earlier, later) {
                found[later.id, default: []].append(earlier)
                found[earlier.id, default: []].append(later)
            }
        }
        guard !found.isEmpty else { return }

        // Entities with a queued kill still get their handler, as in Perl.
        for e in entities {
            if let others = found[e.id], let handler = e.onCollision {
                handler(e, others, self)
            }
        }
    }

    // MARK: removal

    private var silentKills: Set<Int> = []

    private func applyPendingAdds() {
        guard !pendingAdds.isEmpty else { return }
        entities.append(contentsOf: pendingAdds)
        pendingAdds.removeAll()
    }

    private func processKills() {
        let outer = phase
        phase = .removal
        applyPendingAdds()
        while !killQueue.isEmpty {
            let e = killQueue.removeFirst()
            guard e.lifecycle == .dying else { continue }
            if silentKills.remove(e.id) == nil {
                // Perl runs death_cb while the entity is still in the animation.
                e.onDeath?(e, self)
            }
            detach(e)
            applyPendingAdds()
        }
        phase = outer
    }

    private func detach(_ e: Entity) {
        e.lifecycle = .detached
        entities.removeAll { $0 === e }
        pendingAdds.removeAll { $0 === e }
    }

    // MARK: render

    /// Term::Animation `_build_screen`: draws from the highest z to the lowest, so the lowest z ends
    /// up in front. Entities with equal z draw in the order they were added, the later one on top.
    /// Each entity draws its frame `floor(frame)` at `floor(x)`, `floor(y)`; cells outside the grid are
    /// clipped. A transparent cell leaves what is underneath; an opaque blank clears it.
    public func render() -> Grid {
        var grid = Grid(cols: cols, rows: rows)
        let ordered = (entities + pendingAdds).enumerated().sorted { a, b in
            a.element.z != b.element.z ? a.element.z > b.element.z : a.offset < b.offset
        }
        for (_, e) in ordered {
            draw(e, into: &grid)
        }
        return grid
    }

    private func draw(_ e: Entity, into grid: inout Grid) {
        let index = Int(e.frame.rounded(.down))
        guard index >= 0, index < e.sprite.frames.count else { return }
        let frame = e.sprite.frames[index]
        let originX = Int(e.x.rounded(.down))
        let originY = Int(e.y.rounded(.down))
        for (row, cells) in frame.cells.enumerated() {
            for (col, cell) in cells.enumerated() {
                guard let cell else { continue }
                if cell.char == " " {
                    grid.put(nil, x: originX + col, y: originY + row)
                } else {
                    grid.put(
                        Cell(char: cell.char, color: cell.color ?? e.defaultColor),
                        x: originX + col, y: originY + row)
                }
            }
        }
    }
}
