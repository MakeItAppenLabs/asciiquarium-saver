import Foundation
import Testing

@testable import AquariumKit

/// The Apple TV remote's fishhook: a click drops a hook, or reels in one still lowering. It never puts
/// a second hook in the water, and a hook it dropped doesn't start the next special when it leaves.
@Suite struct RemoteHookTests {
    /// The entity type that stands for each special, one per kind.
    private static let headTypes: [SpecialKind: String] = [
        .ship: "ship", .whale: "whale", .monster: "monster", .bigFish: "bigfish",
        .shark: "shark", .fishhook: "fishhook", .swan: "swan", .ducks: "ducks",
        .dolphins: "dolphin", .submarine: "submarine", .swordfish: "swordfish",
        .jellyfish: "jellyfish",
    ]

    /// A tank set up like `Aquarium`, but without the first special, so any special that turns up
    /// was started by something the test did.
    private static func tank(seed: UInt64, settings: AquariumSettings) -> SpawnContext {
        let engine = Engine(cols: 200, rows: 56, rng: RandomSource(seed: seed))
        let c = SpawnContext(engine: engine, settings: settings)
        addEnvironment(c)
        addCastle(c)
        addAllSeaweed(c)
        addAllFish(c)
        return c
    }

    private static func liveSpecials(_ engine: Engine) -> Int {
        headTypes.values.reduce(0) { $0 + engine.entities(ofType: $1).count }
    }

    private static func stepUntilNoHook(_ c: SpawnContext, limit: Int = 2000) {
        for _ in 0..<limit {
            if c.engine.entities(ofType: "fishhook").isEmpty { return }
            c.engine.step()
        }
        Issue.record("the hook was still in the water after \(limit) steps")
    }

    @Test func pressWithNoHookDropsOneEvenWithFishhookDisabled() {
        let c = Self.tank(seed: 1, settings: AquariumSettings(enabledSpecials: []))
        #expect(pressHook(c) == .dropped)
        #expect(c.engine.entities(ofType: "fishhook").count == 1)
        #expect(c.engine.entities(ofType: "fishline").count == 1)
        #expect(c.engine.entities(ofType: "hook_point").count == 1)
    }

    @Test func secondPressReelsUpEmptyAndThirdIsIgnoredWhileRising() {
        let c = Self.tank(seed: 2, settings: .defaults)
        pressHook(c)
        for _ in 0..<5 { c.engine.step() }
        #expect(pressHook(c) == .reeledIn)
        #expect(c.engine.entities(ofType: "hook_point")[0].isPhysical == false)
        c.engine.step()
        #expect(pressHook(c) == .ignored)
        #expect(c.engine.entities(ofType: "fishhook").count == 1)
        Self.stepUntilNoHook(c)
        #expect(c.engine.entities(ofType: "hook_point").isEmpty)
        #expect(c.engine.entities(ofType: "fishline").isEmpty)
    }

    @Test func remoteHookLeavingStartsNoSpecial() {
        let c = Self.tank(seed: 3, settings: .defaults)
        pressHook(c)
        c.engine.step()
        pressHook(c)
        Self.stepUntilNoHook(c)
        c.engine.step()
        #expect(Self.liveSpecials(c.engine) == 0)
    }

    @Test func cycleHookReeledByRemoteStillStartsNextSpecial() {
        let c = Self.tank(seed: 4, settings: .defaults)
        addFishhook(c)  // the cycle's hook
        c.engine.step()
        #expect(pressHook(c) == .reeledIn)
        Self.stepUntilNoHook(c)
        c.engine.step()
        #expect(Self.liveSpecials(c.engine) == 1)
    }

    @Test func cyclePickingFishhookAdoptsTheRemoteHook() {
        let c = Self.tank(seed: 5, settings: .defaults)
        pressHook(c)
        addFishhook(c)  // the cycle picks the fishhook while the remote's hook is down
        #expect(c.engine.entities(ofType: "fishhook").count == 1)
        #expect(c.engine.entities(ofType: "hook_point").count == 1)
        #expect(c.engine.entities(ofType: "fishline").count == 1)
        pressHook(c)
        Self.stepUntilNoHook(c)
        c.engine.step()
        #expect(Self.liveSpecials(c.engine) == 1)
    }

    /// Clicks at every awkward moment (while lowering, rising, carrying a fish, during the cycle's own
    /// hook, several in a row) never put two hooks in the water or two of the cycle's specials on screen.
    @Test func manyPressesNeverDoubleUp() {
        let c = Self.tank(seed: 6, settings: .defaults)
        addRandomSpecial(c)
        var worst = (hooks: 0, points: 0, lines: 0, others: 0)
        for step in 1...20_000 {
            if step % 37 == 0 || step % 500 < 3 { pressHook(c) }
            c.engine.step()
            let others = Self.headTypes.filter { $0.key != .fishhook }.values
                .reduce(0) { $0 + c.engine.entities(ofType: $1).count }
            worst.hooks = max(worst.hooks, c.engine.entities(ofType: "fishhook").count)
            worst.points = max(worst.points, c.engine.entities(ofType: "hook_point").count)
            worst.lines = max(worst.lines, c.engine.entities(ofType: "fishline").count)
            worst.others = max(worst.others, others)
        }
        #expect(worst.hooks == 1)
        #expect(worst.points == 1)
        #expect(worst.lines == 1)
        #expect(worst.others == 1)
    }

    /// A remote hook leaving in the same step as the cycle's special, when the cycle then picks the
    /// fishhook: the new hook keeps its own point and line, so it can still catch, be reeled in and
    /// leave, and the cycle carries on.
    @Test func newCycleHookSurvivesARemoteHookLeavingInTheSameStep() {
        let c = Self.tank(seed: 7, settings: AquariumSettings(enabledSpecials: [.fishhook]))
        addShip(c)
        pressHook(c)
        let ship = c.engine.entities(ofType: "ship")[0]
        let remoteHook = c.engine.entities(ofType: "fishhook")[0]
        ship.dieAfterFrames = 1
        remoteHook.dieAfterFrames = 1
        c.engine.step()
        let alive = { (type: String) in c.engine.entities(ofType: type).filter(\.isAlive).count }
        #expect(alive("fishhook") == 1)
        #expect(alive("hook_point") == 1)
        #expect(alive("fishline") == 1)
        let cycleHook = c.engine.entities(ofType: "fishhook").first(where: \.isAlive)!
        #expect(pressHook(c) == .reeledIn)
        for _ in 0..<200 where cycleHook.isAlive { c.engine.step() }
        #expect(!cycleHook.isAlive)
        c.engine.step()
        // Only the fishhook is enabled, so the cycle carries on with a fresh one.
        #expect(c.engine.entities(ofType: "fishhook").filter(\.isAlive).count == 1)
        #expect(alive("hook_point") == 1)
    }

    /// In a TV-sized tank with frequent clicks, a hook in the water always has its point and line, and
    /// the cycle keeps starting specials.
    @Test func everyHookKeepsItsPointAndLineAndTheCycleNeverStalls() {
        for seed in UInt64(1)...6 {
            let aquarium = Aquarium(cols: 114, rows: 31, settings: .defaults, seed: seed)
            let engine = Mirror(reflecting: aquarium).children.first { $0.label == "engine" }!.value as! Engine
            var specialsSeen = Set<Int>()
            var broken = 0
            for step in 1...10_000 {
                if step % 23 == 0 { aquarium.pressHook() }
                aquarium.step()
                let alive = { (type: String) in engine.entities(ofType: type).filter(\.isAlive).count }
                if alive("fishhook") != alive("hook_point") || alive("fishhook") != alive("fishline") { broken += 1 }
                for type in Self.headTypes.values where type != "fishhook" {
                    for e in engine.entities(ofType: type) { specialsSeen.insert(e.id) }
                }
            }
            #expect(broken == 0, "seed \(seed): \(broken) steps with a hook missing its point or line")
            #expect(specialsSeen.count > 10, "seed \(seed): only \(specialsSeen.count) specials in 10,000 steps")
        }
    }

    /// Only printable ASCII ever reaches the screen, so no glyph can come from a fallback font.
    @Test func everyDrawnCharacterIsPrintableASCII() {
        for set in [CreatureSet.full, .classic] {
            for seed in UInt64(1)...2 {
                let aquarium = Aquarium(
                    cols: 160, rows: 50, settings: AquariumSettings(creatureSet: set), seed: seed)
                var bad = Set<Character>()
                for step in 1...2_000 {
                    if step % 200 == 0 { aquarium.pressHook() }
                    aquarium.step()
                    let grid = aquarium.render()
                    for y in 0..<grid.rows {
                        for x in 0..<grid.cols {
                            guard let ch = grid[x, y]?.char else { continue }
                            if !(ch.asciiValue.map { (0x20...0x7E).contains($0) } ?? false) { bad.insert(ch) }
                        }
                    }
                }
                #expect(bad.isEmpty, "\(set) seed \(seed): \(bad)")
            }
        }
    }
}
