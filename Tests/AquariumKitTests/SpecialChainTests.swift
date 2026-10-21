import Foundation
import Testing

@testable import AquariumKit

/// The random-object chain across many specials: each special's death starts the next, chosen
/// uniformly (Perl `random_object`), so over a long run every one of the twelve turns up about
/// equally often and there is never more than one at a time.
@Suite struct SpecialChainTests {
    /// The entity type that stands for each special, one per kind.
    private static let headTypes: [SpecialKind: String] = [
        .ship: "ship", .whale: "whale", .monster: "monster", .bigFish: "bigfish",
        .shark: "shark", .fishhook: "fishhook", .swan: "swan", .ducks: "ducks",
        .dolphins: "dolphin", .submarine: "submarine", .swordfish: "swordfish",
        .jellyfish: "jellyfish",
    ]

    /// Runs an aquarium set up like `Aquarium`, calling `observe` after every step.
    private static func run(
        seed: UInt64, settings: AquariumSettings, steps: Int, observe: (Engine) -> Void
    ) {
        let engine = Engine(cols: 200, rows: 56, rng: RandomSource(seed: seed))
        let context = SpawnContext(engine: engine, settings: settings)
        addEnvironment(context)
        addCastle(context)
        addAllSeaweed(context)
        addAllFish(context)
        addRandomSpecial(context)
        observe(engine)
        for _ in 0..<steps {
            engine.step()
            observe(engine)
        }
    }

    /// How many specials of each kind started, counting each live head entity once.
    private static func tally(
        seed: UInt64, settings: AquariumSettings, steps: Int
    ) -> (starts: [SpecialKind: Int], maxAtOnce: Int) {
        var seen = Set<Int>()
        var starts: [SpecialKind: Int] = [:]
        var maxAtOnce = 0
        run(seed: seed, settings: settings, steps: steps) { engine in
            var live = 0
            for (kind, type) in headTypes {
                let heads = engine.entities(ofType: type)
                live += heads.count
                for head in heads where seen.insert(head.id).inserted {
                    starts[kind, default: 0] += 1
                }
            }
            maxAtOnce = max(maxAtOnce, live)
        }
        return (starts, maxAtOnce)
    }

    /// The bounds are wide because two seeds give only about 28 starts per kind (a Poisson spread of
    /// 5). A chain that skips a kind, or favors one, still fails; 40 seeds of 100 minutes in Release
    /// gave 0.95 to 1.05 of the mean for every kind (chi-squared 11 on 11 degrees of freedom).
    @Test func everySpecialAppearsAboutEquallyOftenInFull() {
        var total: [SpecialKind: Int] = [:]
        for seed in [UInt64(11), 12] {
            let result = Self.tally(seed: seed, settings: .defaults, steps: 30_000)
            for (kind, n) in result.starts { total[kind, default: 0] += n }
            #expect(result.maxAtOnce <= 1, "seed \(seed): \(result.maxAtOnce) specials at once")
        }
        let sum = total.values.reduce(0, +)
        #expect(sum > 200, "only \(sum) specials in 2 x 50 minutes: \(total)")
        let expected = Double(sum) / Double(SpecialKind.allCases.count)
        for kind in SpecialKind.allCases {
            let n = Double(total[kind, default: 0])
            #expect(
                n > expected * 0.4 && n < expected * 2.0,
                "\(kind): \(Int(n)) of \(sum) (expected about \(Int(expected))): \(total)")
        }
    }

    /// The characters a sprite's first frame is drawn with.
    private static func characters(_ sprite: Sprite) -> [[Character?]] {
        sprite.frames[0].cells.map { $0.map { $0?.char } }
    }

    /// Classic mode end to end: the chain and the respawning fish carry the setting through every
    /// death, so over a long run only the eight old fish, the old monster and big fish 1 are ever
    /// on screen, while all twelve specials still appear.
    @Test func classicModeStaysClassicThroughTheChain() {
        let settings = AquariumSettings(creatureSet: .classic)
        let old = FishArt.old.flatMap {
            [Self.characters(Sprite(shapes: [$0.rightShape])), Self.characters(Sprite(shapes: [$0.leftShape]))]
        }
        let newOnly = FishArt.new.flatMap {
            [Self.characters(Sprite(shapes: [$0.rightShape])), Self.characters(Sprite(shapes: [$0.leftShape]))]
        }.filter { !old.contains($0) }
        #expect(newOnly.count == 6)
        let oneHeight = Sprite(shapes: [BigFishArt.oneShapes[0]]).height
        let twoHeight = Sprite(shapes: [BigFishArt.twoShapes[0]]).height
        #expect(oneHeight != twoHeight)

        var seen = Set<Int>()
        var starts: [SpecialKind: Int] = [:]
        var fishChecked = 0
        Self.run(seed: 21, settings: settings, steps: 30_000) { engine in
            for fish in engine.entities(ofType: "fish") where seen.insert(fish.id).inserted {
                fishChecked += 1
                let drawn = Self.characters(fish.sprite)
                #expect(old.contains(drawn))
                #expect(!newOnly.contains(drawn))
            }
            for (kind, type) in Self.headTypes {
                for head in engine.entities(ofType: type) where seen.insert(head.id).inserted {
                    starts[kind, default: 0] += 1
                    if kind == .monster { #expect(head.sprite.frames.count == 4) }
                    if kind == .bigFish { #expect(head.height == oneHeight) }
                }
            }
        }
        #expect(fishChecked > 500, "only \(fishChecked) fish seen")
        for kind in SpecialKind.allCases {
            #expect(starts[kind, default: 0] > 0, "\(kind) never appeared in classic: \(starts)")
        }
    }

    @Test func onlyEnabledSpecialsAppear() {
        let settings = AquariumSettings(enabledSpecials: [.shark, .swan])
        let result = Self.tally(seed: 31, settings: settings, steps: 20_000)
        #expect(Set(result.starts.keys) == [.shark, .swan], "\(result.starts)")
    }
}
