import Testing
@testable import AquariumKit

@Suite struct SpecialsTests {
    /// The entity that stands for each special: the one whose death starts the next special.
    private static let headType: [SpecialKind: String] = [
        .ship: "ship", .whale: "whale", .monster: "monster", .bigFish: "bigfish",
        .shark: "shark", .fishhook: "fishhook", .swan: "swan", .ducks: "ducks",
        .dolphins: "dolphin", .submarine: "submarine", .swordfish: "swordfish",
        .jellyfish: "jellyfish",
    ]
    private static let headTypes = Set(headType.values)

    private func context(
        cols: Int = 80, rows: Int = 24, seed: UInt64 = 1, settings: AquariumSettings = AquariumSettings()
    ) -> SpawnContext {
        SpawnContext(engine: Engine(cols: cols, rows: rows, rng: RandomSource(seed: seed)), settings: settings)
    }

    /// The entity that stands for a special: the ship, whale, shark, ... itself, never a helper part.
    private func heads(_ engine: Engine) -> [Entity] {
        Self.headTypes.flatMap { engine.entities(ofType: $0) }
    }

    private func allEntities(_ engine: Engine) -> [Entity] {
        (Self.headTypes.union(["teeth", "fishline", "hook_point", "dolphin_mate"])).flatMap {
            engine.entities(ofType: $0)
        }
    }

    /// Steps until `entity` is gone. Fails the test when it takes longer than `limit` steps.
    @discardableResult
    private func step(_ engine: Engine, until entity: Entity, limit: Int = 1500) -> Int {
        var steps = 0
        while entity.isAlive && steps < limit {
            engine.step()
            steps += 1
        }
        #expect(!entity.isAlive, "still alive after \(limit) steps")
        return steps
    }

    private func characters(_ sprite: Sprite, frame: Int = 0) -> [[Character?]] {
        sprite.frames[frame].cells.map { $0.map { $0?.char } }
    }

    // MARK: shark

    @Test func sharkEatsFish() {
        let c = context()
        addShark(c)
        let shark = c.engine.entities(ofType: "shark")[0]
        let teeth = c.engine.entities(ofType: "teeth")[0]
        #expect(teeth.isPhysical)
        #expect(teeth.depth == 17)
        // Let it swim into the middle of the screen, away from the edges fish are killed at.
        for _ in 0..<25 { c.engine.step() }
        #expect(teeth.x > 20 && teeth.x < 60)

        // A small fish where the teeth will be after the next step.
        addFish(c)
        let fish = c.engine.entities(ofType: "fish")[0]
        fish.dx = 0
        fish.x = teeth.x + teeth.dx
        fish.y = teeth.y
        fish.z = 5
        #expect(c.engine.entities(ofType: "self").isEmpty)

        c.engine.step()
        #expect(!fish.isAlive)
        // The dead fish is replaced, and what is left of it is a splat where the teeth are.
        let splats = c.engine.entities(ofType: "self")
        #expect(splats.count == 1)
        #expect(splats[0].x == (teeth.x - 4).rounded(.down))

        // No teeth outlives the shark, and its death starts exactly one special.
        step(c.engine, until: shark)
        #expect(!teeth.isAlive)
        #expect(heads(c.engine).count == 1)
        #expect(heads(c.engine)[0] !== shark)
    }

    @Test func sharkIgnoresFishOutOfReach() {
        // Negative control for sharkEatsFish: the same fish on a row the teeth do not cross.
        let c = context()
        addShark(c)
        let teeth = c.engine.entities(ofType: "teeth")[0]
        for _ in 0..<25 { c.engine.step() }
        addFish(c)
        let fish = c.engine.entities(ofType: "fish")[0]
        fish.dx = 0
        fish.x = teeth.x + teeth.dx
        fish.y = teeth.y - 8
        fish.z = 5
        c.engine.step()
        #expect(fish.isAlive)
        #expect(c.engine.entities(ofType: "self").isEmpty)
    }

    @Test func sharkSpawnGeometry() {
        for seed in 1...40 as ClosedRange<UInt64> {
            let c = context(cols: 100, rows: 40, seed: seed)
            addShark(c)
            let shark = c.engine.entities(ofType: "shark")[0]
            let teeth = c.engine.entities(ofType: "teeth")[0]
            #expect(shark.z == Depth.shark)
            #expect(teeth.z == Depth.shark + 1)
            #expect(teeth.y == shark.y + 7)
            #expect(shark.y >= 9 && shark.y < 9 + 40 - 19)
            if shark.dx > 0 {
                #expect(shark.x == -53 && teeth.x == -9 && shark.dx == 2 && teeth.dx == 2)
            } else {
                #expect(shark.x == 98 && teeth.x == 107 && shark.dx == -2 && teeth.dx == -2)
            }
        }
    }

    // MARK: fishhook

    /// Lowers a fresh hook to its resting place, then puts a stationary fish on its point.
    private func hookWithFishOnPoint(_ c: SpawnContext) -> (fish: Entity, hook: Entity, line: Entity, point: Entity) {
        addFishhook(c)
        let hook = c.engine.entities(ofType: "fishhook")[0]
        let line = c.engine.entities(ofType: "fishline")[0]
        let point = c.engine.entities(ofType: "hook_point")[0]
        for _ in 0..<100 { c.engine.step() }
        addFish(c)
        let fish = c.engine.entities(ofType: "fish")[0]
        fish.dx = 0
        fish.x = point.x
        fish.y = point.y
        fish.z = 5
        return (fish, hook, line, point)
    }

    @Test func hookLowersAndWaits() {
        // Negative control for hookCatchesAndRetracts: without a fish the hook just hangs there.
        let c = context()
        addFishhook(c)
        let hook = c.engine.entities(ofType: "fishhook")[0]
        let line = c.engine.entities(ofType: "fishline")[0]
        let point = c.engine.entities(ofType: "hook_point")[0]
        #expect(hook.y == -4 && point.y == -2 && line.y == -54)
        #expect(hook.x >= 10 && hook.x < 10 + 60)
        #expect(point.x == hook.x + 1 && line.x == hook.x + 7)
        #expect(point.isPhysical && point.depth == 17)

        for _ in 0..<100 { c.engine.step() }
        // It stops when its bottom edge reaches three quarters of the height: 12 + 6 == 18.
        #expect(hook.y == 12)
        #expect(point.y == 14 && line.y == -38)
        for _ in 0..<200 { c.engine.step() }
        #expect(hook.isAlive && line.isAlive && point.isAlive)
        #expect(hook.y == 12)
    }

    @Test func hookCatchesAndRetracts() {
        let c = context()
        let (fish, hook, line, point) = hookWithFishOnPoint(c)
        let before = hook.y
        let lineY = line.y

        c.engine.step()
        // Caught: the fish and every part of the hook stop being physical, and the fish goes behind
        // the waterline's gap.
        #expect(!fish.isPhysical && !point.isPhysical)
        #expect(fish.z == Depth.waterGap2)
        #expect(hook.y == before)

        // And all of them are reeled in together, one row a step.
        let fishY = fish.y
        for n in 1...5 {
            c.engine.step()
            #expect(hook.y == before - Double(n))
            #expect(line.y == lineY - Double(n))
            #expect(point.y == before + 2 - Double(n))
            #expect(fish.y == fishY - Double(n))
        }

        let members = [hook, line, point]
        var steps = 0
        while members.contains(where: \.isAlive) && steps < 600 {
            c.engine.step()
            steps += 1
        }
        #expect(members.allSatisfy { !$0.isAlive }, "hook parts still there after \(steps) steps")
        // Exactly one special took over.
        #expect(heads(c.engine).count == 1)
        #expect(heads(c.engine)[0] !== hook)
    }

    // MARK: fish_collision: first matching collider wins

    private func collisionPieces(_ c: SpawnContext) -> (fish: Entity, point: Entity, teeth: Entity) {
        addFishhook(c)
        addFish(c)
        let fish = c.engine.entities(ofType: "fish")[0]
        let point = c.engine.entities(ofType: "hook_point")[0]
        let teeth = Entity(type: "teeth", sprite: Sprite(shapes: ["*"], autoTransparent: false), isPhysical: true)
        return (fish, point, teeth)
    }

    @Test func hookWinsWhenListedBeforeTeeth() {
        let c = context()
        let (fish, point, teeth) = collisionPieces(c)
        fishCollision(c, fish: fish, colliders: [point, teeth])

        #expect(fish.isAlive)
        #expect(!fish.isPhysical)
        #expect(fish.z == Depth.waterGap2)
        #expect(!point.isPhysical)
        // No splat: the teeth were never looked at.
        #expect(c.engine.entities(ofType: "self").isEmpty)
        // The hook and line are pulled up as well.
        let hook = c.engine.entities(ofType: "fishhook")[0]
        let line = c.engine.entities(ofType: "fishline")[0]
        let (hookY, lineY, fishY) = (hook.y, line.y, fish.y)
        c.engine.step()
        #expect(hook.y == hookY - 1 && line.y == lineY - 1 && fish.y == fishY - 1)
    }

    @Test func teethWinWhenListedBeforeHook() {
        let c = context()
        let (fish, point, teeth) = collisionPieces(c)
        fish.x = 10
        fish.y = 10
        fishCollision(c, fish: fish, colliders: [teeth, point])

        #expect(!fish.isAlive)
        #expect(c.engine.entities(ofType: "self").count == 1)
        // The hook was left alone.
        #expect(point.isPhysical)
    }

    @Test func fishCollisionSkipsOtherTypesToFindTheHook() {
        let c = context()
        let (fish, point, _) = collisionPieces(c)
        let bubble = Entity(type: "bubble", sprite: Sprite(shapes: ["o"]), isPhysical: true)
        fishCollision(c, fish: fish, colliders: [bubble, point])
        #expect(!point.isPhysical)
        #expect(fish.z == Depth.waterGap2)
    }

    // MARK: ship, whale

    @Test func shipSpawnGeometry() {
        var seen = Set<Double>()
        for seed in 1...20 as ClosedRange<UInt64> {
            let c = context(seed: seed)
            addShip(c)
            let ship = c.engine.entities(ofType: "ship")[0]
            seen.insert(ship.dx)
            #expect(ship.y == 0 && ship.z == Depth.waterGap1)
            #expect(ship.x == (ship.dx > 0 ? -24 : 78))
            #expect(abs(ship.dx) == 1)
        }
        #expect(seen == [1, -1])
    }

    @Test func shipSailsAcrossAndLeaves() {
        let c = context()
        addShip(c)
        let ship = c.engine.entities(ofType: "ship")[0]
        let steps = step(c.engine, until: ship)
        // 24 + 80 columns at one a step, plus the step that notices it is gone.
        #expect(steps > 90 && steps < 130, "took \(steps) steps")
        #expect(heads(c.engine).count == 1)
    }

    @Test func whaleBlowsItsSpout() {
        var dirs = Set<Double>()
        for seed in 1...20 as ClosedRange<UInt64> {
            let c = context(seed: seed)
            addWhale(c)
            let whale = c.engine.entities(ofType: "whale")[0]
            dirs.insert(whale.dx)
            #expect(whale.sprite.frames.count == 12)
            #expect(whale.frameSpeed == 1)
            #expect(whale.z == Depth.waterGap2 && whale.y == 0)
            #expect(whale.x == (whale.dx > 0 ? -18 : 78))

            let rightFacing = whale.dx > 0
            // The whale's body is on the same rows in every frame, whether or not it spouts.
            let bodyRows = (0..<12).map { f in
                characters(whale.sprite, frame: f).firstIndex { $0.contains("(") && $0.contains("o") }
            }
            #expect(Set(bodyRows).count == 1, "body moved between frames: \(bodyRows)")

            // The spout stands over the blowhole: the ":" that ends the whale's top row.
            let blowhole = rightFacing ? 14 : 4
            // Frame 0 has no spout above the whale; frame 5 (first spout frame) has one ":" at the blowhole.
            #expect(characters(whale.sprite, frame: 0)[2].allSatisfy { $0 == nil })
            #expect(characters(whale.sprite, frame: 5)[2][blowhole] == ":")
            // The color mask lines up with the body in every frame, spout or not: the eye is bright white.
            let eyeColumn = rightFacing ? 14 : 4
            for f in 0..<12 {
                let row = bodyRows[f]!
                #expect(characters(whale.sprite, frame: f)[row][eyeColumn] == "o")
                #expect(whale.sprite.frames[f].cells[row][eyeColumn]?.color == CellColor(color: .white, bright: true))
            }
        }
        #expect(dirs == [1, -1])
    }

    // MARK: monster

    @Test func monsterArtByMode() {
        for (set, frames) in [(CreatureSet.classic, 4), (CreatureSet.full, 2)] {
            let c = context(settings: AquariumSettings(creatureSet: set))
            var dirs = Set<Double>()
            for _ in 0..<200 { addMonster(c) }
            for monster in c.engine.entities(ofType: "monster") {
                #expect(monster.sprite.frames.count == frames, "\(set)")
                dirs.insert(monster.dx)
                #expect(monster.y == 2 && monster.z == Depth.waterGap2)
                #expect(monster.frameSpeed == 0.25)
                #expect(abs(monster.dx) == 2)
                let start = set == .classic ? -64.0 : -54.0
                #expect(monster.x == (monster.dx > 0 ? start : 78))
            }
            #expect(dirs == [2, -2])
        }
        // The two sets really are different pictures.
        let old = context(settings: AquariumSettings(creatureSet: .classic))
        let new = context(settings: AquariumSettings(creatureSet: .full))
        addOldMonster(old)
        addNewMonster(new)
        #expect(old.engine.entities(ofType: "monster")[0].sprite.width != new.engine.entities(ofType: "monster")[0].sprite.width)
    }

    @Test func monsterSwimsThroughAndLeaves() {
        for set in [CreatureSet.classic, .full] {
            let c = context(settings: AquariumSettings(creatureSet: set))
            addMonster(c)
            let monster = c.engine.entities(ofType: "monster")[0]
            step(c.engine, until: monster)
            #expect(heads(c.engine).count == 1)
        }
    }

    // MARK: big fish

    @Test func bigFishOdds() {
        let full = context(settings: AquariumSettings(creatureSet: .full))
        var second = 0
        for _ in 0..<3000 where bigFishVariant(full) == 2 { second += 1 }
        let share = Double(second) / 3000
        #expect(abs(share - 1.0 / 3.0) < 0.03, "share was \(share)")

        let classic = context(settings: AquariumSettings(creatureSet: .classic))
        for _ in 0..<3000 { #expect(bigFishVariant(classic) == 1) }

        // End to end: the two pictures have different heights, so count the ones addBigFish drew.
        let one = Sprite(shapes: [BigFishArt.oneShapes[0]]).height
        let two = Sprite(shapes: [BigFishArt.twoShapes[0]]).height
        #expect(one != two)
        for _ in 0..<3000 { addBigFish(full) }
        let tall = full.engine.entities(ofType: "bigfish").filter { $0.height == two }.count
        #expect(abs(Double(tall) / 3000 - 1.0 / 3.0) < 0.03, "drawn share was \(Double(tall) / 3000)")
        for _ in 0..<500 { addBigFish(classic) }
        #expect(classic.engine.entities(ofType: "bigfish").allSatisfy { $0.height == one })
    }

    @Test func bigFishSpawnGeometry() {
        for (variant, speed, startX, margin) in [(1, 3.0, -34.0, 15), (2, 2.5, -33.0, 14)] {
            var dirs = Set<Double>()
            for seed in 1...30 as ClosedRange<UInt64> {
                let c = context(cols: 100, rows: 40, seed: seed)
                if variant == 1 { addBigFish1(c) } else { addBigFish2(c) }
                let fish = c.engine.entities(ofType: "bigfish")[0]
                dirs.insert(fish.dx)
                #expect(abs(fish.dx) == speed)
                #expect(fish.x == (fish.dx > 0 ? startX : 99))
                #expect(fish.z == Depth.shark)
                #expect(fish.y >= 9 && fish.y < Double(40 - margin))
            }
            #expect(dirs == [speed, -speed])
        }
    }

    @Test func bigFishColorsAreRandomized() {
        let c = context()
        addBigFish1(c)
        // Digits in the mask are replaced by color letters; none is left in the sprite's colors, and
        // the body ("1") is colored.
        let fish = c.engine.entities(ofType: "bigfish")[0]
        let colored = fish.sprite.frames[0].cells.joined().compactMap { $0 }.filter { $0.color != nil }
        #expect(colored.count > 100)
    }

    // MARK: one special at a time

    @Test(arguments: SpecialKind.allCases)
    func oneSpecialAtATime(kind: SpecialKind) {
        for seed in 1...6 as ClosedRange<UInt64> {
            let c = context(seed: seed)
            addSpecial(kind, c)
            let original = heads(c.engine)
            #expect(original.count == 1)
            let members = allEntities(c.engine)

            if kind == .fishhook { feedHook(c) }

            step(c.engine, until: original[0])
            let now = heads(c.engine)
            #expect(now.count == 1, "seed \(seed): \(now.map(\.type))")
            #expect(now[0] !== original[0])
            #expect(members.allSatisfy { !$0.isAlive }, "seed \(seed): a member outlived the special")
            // Helper parts belong to the new special only.
            #expect(c.engine.entities(ofType: "teeth").count == (now[0].type == "shark" ? 1 : 0))
            #expect(c.engine.entities(ofType: "hook_point").count == (now[0].type == "fishhook" ? 1 : 0))
            #expect(c.engine.entities(ofType: "fishline").count == (now[0].type == "fishhook" ? 1 : 0))

            // And nothing starts a second one afterwards.
            for _ in 0..<10 { c.engine.step() }
            #expect(heads(c.engine).count == 1)
        }
    }

    @Test func randomSpecialPicksUniformlyAmongAllTwelve() {
        var counts: [String: Int] = [:]
        let n = 1800
        for seed in 0..<n {
            let c = context(seed: UInt64(seed))
            addRandomSpecial(c)
            let found = heads(c.engine)
            #expect(found.count == 1)
            counts[found[0].type, default: 0] += 1
        }
        #expect(Set(counts.keys) == Self.headTypes)
        for (type, count) in counts {
            #expect(abs(Double(count) / Double(n) - 1.0 / 12.0) < 0.03, "\(type): \(count)")
        }
    }

    @Test func addSpecialBuildsEachKind() {
        #expect(Self.headType.count == SpecialKind.allCases.count)
        for kind in SpecialKind.allCases {
            let c = context()
            addSpecial(kind, c)
            #expect(heads(c.engine).map(\.type) == [Self.headType[kind]!], "\(kind)")
        }
    }

    /// A hook only leaves when it catches something: lowers it, then puts a stationary fish on its point.
    private func feedHook(_ c: SpawnContext) {
        for _ in 0..<100 { c.engine.step() }
        addFish(c)
        let fish = c.engine.entities(ofType: "fish")[0]
        let point = c.engine.entities(ofType: "hook_point")[0]
        fish.dx = 0
        fish.x = point.x
        fish.y = point.y
        fish.z = 5
    }

    // MARK: default colors

    /// Term::Animation reads an upper-case `default_color` ('WHITE') as bright and a lower-case one
    /// ('white') as normal; an entity with none is normal white. Every value here is Perl's.
    @Test func defaultColorsFollowPerlCase() {
        func color(_ c: ANSIColor, bright: Bool) -> CellColor { CellColor(color: c, bright: bright) }
        func only(_ type: String, _ engine: Engine) -> Entity { engine.entities(ofType: type)[0] }
        let normalWhite = color(.white, bright: false)

        // Upper case, one per Perl creature.
        let expectedSpecial: [SpecialKind: CellColor] = [
            .ship: color(.white, bright: true), .whale: color(.white, bright: true),
            .monster: color(.green, bright: true), .bigFish: color(.yellow, bright: true),
            .shark: color(.cyan, bright: true), .fishhook: color(.green, bright: true),
            .swan: color(.white, bright: true), .ducks: color(.white, bright: true),
            .dolphins: color(.blue, bright: false), .submarine: color(.yellow, bright: true),
            .swordfish: color(.yellow, bright: true), .jellyfish: color(.magenta, bright: true),
        ]
        for kind in SpecialKind.allCases {
            let c = context(seed: 3)
            addSpecial(kind, c)
            #expect(heads(c.engine)[0].defaultColor == expectedSpecial[kind], "\(kind)")
        }
        // Both monsters and both big fish.
        let mc = context(seed: 3, settings: AquariumSettings(creatureSet: .classic))
        addOldMonster(mc)
        addBigFish1(mc)
        addNewMonster(mc)
        addBigFish2(mc)
        #expect(mc.engine.entities(ofType: "monster").map(\.defaultColor) == Array(repeating: color(.green, bright: true), count: 2))
        #expect(mc.engine.entities(ofType: "bigfish").map(\.defaultColor) == Array(repeating: color(.yellow, bright: true), count: 2))

        // The helper parts: hook and point 'GREEN'; the line and the teeth have no color of their own.
        let h = context(seed: 3)
        addFishhook(h)
        #expect(only("fishhook", h.engine).defaultColor == color(.green, bright: true))
        #expect(only("hook_point", h.engine).defaultColor == color(.green, bright: true))
        #expect(only("fishline", h.engine).defaultColor == normalWhite)
        let s = context(seed: 3)
        addShark(s)
        #expect(only("teeth", s.engine).defaultColor == normalWhite)
        // The dolphins: 'blue' is normal, 'BLUE' and 'CYAN' are bright.
        let d = context(seed: 3)
        addDolphins(d)
        #expect(only("dolphin", d.engine).defaultColor == color(.blue, bright: false))

        // The scenery: lower-case 'cyan', 'white', 'green' are normal; bubble 'CYAN' and splat 'RED' are bright.
        let e = context(seed: 3)
        addEnvironment(e)
        addCastle(e)
        addSeaweed(e)
        #expect(e.engine.entities(ofType: "waterline").count == 4)
        #expect(e.engine.entities(ofType: "waterline").allSatisfy { $0.defaultColor == color(.cyan, bright: false) })
        let selfTyped = e.engine.entities(ofType: "self")
        #expect(selfTyped.count == 2)
        #expect(selfTyped.map(\.defaultColor).sorted { "\($0.color)" < "\($1.color)" }
            == [color(.green, bright: false), normalWhite])
        let f = context(seed: 3)
        addFish(f)
        let fish = only("fish", f.engine)
        #expect(fish.defaultColor == normalWhite)
        addBubble(f, from: fish)
        #expect(only("bubble", f.engine).defaultColor == color(.cyan, bright: true))
        addSplat(f, x: 10, y: 10, z: 5)
        #expect(only("self", f.engine).defaultColor == color(.red, bright: true))
    }

    // MARK: swan, ducks

    @Test func swanAndDucksGeometry() {
        for (kind, type, startX, y, frames) in [
            (SpecialKind.swan, "swan", -10.0, 1.0, 1), (.ducks, "ducks", -30.0, 5.0, 3),
        ] {
            var dirs = Set<Double>()
            for seed in 1...20 as ClosedRange<UInt64> {
                let c = context(seed: seed)
                addSpecial(kind, c)
                let e = c.engine.entities(ofType: type)[0]
                dirs.insert(e.dx)
                #expect(abs(e.dx) == 1 && e.frameSpeed == 0.25)
                #expect(e.x == (e.dx > 0 ? startX : 78) && e.y == y)
                #expect(e.z == Depth.waterGap3 && e.dieOffscreen)
                #expect(e.sprite.frames.count == frames)
                #expect(e.defaultColor == CellColor(color: .white, bright: true))
            }
            #expect(dirs == [1, -1], "\(type)")
        }
    }

    @Test func ducksTakeTurnsLeading() {
        // Three frames, a quarter frame a step: each is shown for four steps, in order, and wraps.
        let c = context(seed: 3)
        addDucks(c)
        let ducks = c.engine.entities(ofType: "ducks")[0]
        var shown: [Int] = []
        for _ in 0..<24 {
            shown.append(Int(ducks.frame))
            c.engine.step()
        }
        let cycle = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2]
        #expect(shown == cycle + cycle)
    }

    // MARK: dolphins

    @Test func dolphinsGeometry() {
        var dirs = Set<Double>()
        for seed in 1...20 as ClosedRange<UInt64> {
            let c = context(seed: seed)
            addDolphins(c)
            let trailing = c.engine.entities(ofType: "dolphin")
            let mates = c.engine.entities(ofType: "dolphin_mate")
            #expect(trailing.count == 1 && mates.count == 2)
            let (d3, d2, d1) = (trailing[0], mates[0], mates[1])  // in the order Perl adds them
            let speed = d1.path[0].dx
            dirs.insert(speed)
            let lead = speed > 0 ? -13.0 : 78
            let gap = speed > 0 ? 15.0 : -15
            #expect(d1.x == lead && d2.x == lead - gap && d3.x == lead - 2 * gap)
            #expect([d3.y, d2.y, d1.y] == [8, 2, 5])
            #expect([d3.pathIndex, d2.pathIndex, d1.pathIndex] == [0, 12, 24])
            #expect([d3, d2, d1].allSatisfy { $0.z == Depth.waterGap3 && $0.path.count == 36 })
            #expect([d3, d2, d1].allSatisfy { $0.sprite.frames.count == 2 })
            // Only the lead dolphin may die off screen at first.
            #expect(!d3.dieOffscreen && !d2.dieOffscreen && d1.dieOffscreen)
            #expect(d3.defaultColor == CellColor(color: .blue, bright: false))
            #expect(d2.defaultColor == CellColor(color: .blue, bright: true))
            #expect(d1.defaultColor == CellColor(color: .cyan, bright: true))
        }
        #expect(dirs == [1, -1])
    }

    @Test func dolphinsLeapAndDive() {
        let c = context(seed: 1)
        addDolphins(c)
        let lead = c.engine.entities(ofType: "dolphin_mate")[1]
        let (x0, y0) = (lead.x, lead.y)
        let speed = lead.path[0].dx
        // The path is 14 up, 2 glide, 14 down, 6 glide, and the lead starts at index 24: six steps
        // into the dive.
        var ys: [Double] = []
        for _ in 0..<36 {
            c.engine.step()
            ys.append(lead.y)
        }
        #expect(lead.x == x0 + 36 * speed)
        #expect(ys[5] == y0 + 3)  // end of the dive
        #expect(ys[11] == y0 + 3)  // glided
        #expect(ys[11 + 14] == y0 + 3 - 7)  // top of the leap
        #expect(ys[11 + 16] == y0 + 3 - 7)  // glided
        #expect(ys[35] == y0)  // and back where it began
        // The path sets the frame outright: always the first picture, as in Perl.
        #expect(lead.frame == 0.5 && Int(lead.frame) == 0)
    }

    @Test func dolphinsLeaveInOrderAndStartOneSpecial() {
        for seed in 1...6 as ClosedRange<UInt64> {
            let c = context(seed: seed)
            addDolphins(c)
            let trailing = c.engine.entities(ofType: "dolphin")[0]
            let mates = c.engine.entities(ofType: "dolphin_mate")
            let lead = mates[1]
            var steps = 0
            var leadDied: Int?
            while trailing.isAlive && steps < 1500 {
                c.engine.step()
                steps += 1
                if leadDied == nil, !lead.isAlive { leadDied = steps }
                if trailing.isAlive {
                    // No special starts before the trailing dolphin is gone.
                    #expect(heads(c.engine).count == 1 && heads(c.engine)[0] === trailing)
                }
            }
            #expect(!trailing.isAlive, "seed \(seed)")
            let leadStep = try! #require(leadDied)
            #expect(leadStep < steps, "the lead dolphin leaves before the trailing one")
            #expect(mates.allSatisfy { !$0.isAlive })
            #expect(heads(c.engine).count == 1 && heads(c.engine)[0] !== trailing)
        }
    }

    @Test func dolphinsDoNotDieOffscreenBeforeTheLeadLeaves() {
        // Negative control: the two that start off screen are still there while the lead swims.
        let c = context(seed: 1)
        addDolphins(c)
        let lead = c.engine.entities(ofType: "dolphin_mate")[1]
        let others = c.engine.entities(ofType: "dolphin") + [c.engine.entities(ofType: "dolphin_mate")[0]]
        for _ in 0..<10 { c.engine.step() }
        #expect(lead.isAlive && others.allSatisfy(\.isAlive))
    }

    // MARK: submarine

    @Test func submarineGeometry() {
        var dirs = Set<Double>()
        for seed in 1...20 as ClosedRange<UInt64> {
            let c = context(seed: seed)
            addSubmarine(c)
            let sub = c.engine.entities(ofType: "submarine")[0]
            dirs.insert(sub.dx)
            #expect(abs(sub.dx) == 1 && sub.y == 6 && sub.z == Depth.waterGap3)
            #expect(sub.x == (sub.dx > 0 ? -40 : 78))
            #expect(sub.sprite.frames.count == 9 && sub.frame == 0)
            #expect(sub.defaultColor == CellColor(color: .yellow, bright: true))
        }
        #expect(dirs == [1, -1])
    }

    /// The submarine sits in the middle of the screen while the periscope comes up frame by frame. An
    /// odd width puts the middle between two columns, and the step that would skip over it pauses
    /// instead.
    @Test(arguments: [80, 81])
    func submarineStopsInTheMiddle(cols: Int) {
        for seed in 1...8 as ClosedRange<UInt64> {
            let c = context(cols: cols, seed: seed)
            addSubmarine(c)
            let sub = c.engine.entities(ofType: "submarine")[0]
            var xs: [Double] = []
            var frames: [Int] = []
            while sub.isAlive && xs.count < 600 {
                c.engine.step()
                xs.append(sub.x)
                frames.append(Int(sub.frame))
            }
            #expect(!sub.isAlive)
            // The longest stretch at one place is the pause: frames 0...7 last 52 steps in all, and the
            // step that completes frame 7 leaves the picture at frame 8.
            var best = (start: 0, length: 0)
            var start = 0
            for i in 1...xs.count {
                if i == xs.count || xs[i] != xs[start] {
                    if i - start > best.length { best = (start, i - start) }
                    start = i
                }
            }
            #expect(best.length == 53, "cols \(cols) seed \(seed): paused \(best.length) steps")
            let paused = Array(frames[best.start..<(best.start + best.length)])
            #expect(paused == paused.sorted() && paused.first == 0 && paused.last == 8)
            #expect(Set(paused) == Set(0...8))
            // It never goes back to an earlier frame afterwards.
            #expect(frames[(best.start + best.length)...].allSatisfy { $0 == 8 })
            #expect(abs(xs[best.start] - (Double(cols) / 2 - 20)) < 1)
        }
    }

    @Test func submarineWaitsLongestOnTheMiddleFrames() {
        let c = context(seed: 2)
        addSubmarine(c)
        let sub = c.engine.entities(ofType: "submarine")[0]
        var counts = [Int](repeating: 0, count: 9)
        var steps = 0
        while sub.isAlive && steps < 600 {
            c.engine.step()
            counts[Int(sub.frame)] += 1
            steps += 1
        }
        // Frames 0...7 are each shown for delay + 1 steps while it sits there. (Frame 0 is also shown
        // on the way in, and frame 8 on the way out.)
        let waits = (1...7).map { counts[$0] }
        #expect(waits == [5, 5, 10, 10, 10, 5, 5])
    }

    // MARK: swordfish

    @Test func swordfishGeometry() {
        var dirs = Set<Double>()
        for seed in 1...30 as ClosedRange<UInt64> {
            let c = context(cols: 100, rows: 40, seed: seed)
            addSwordfish(c)
            let fish = c.engine.entities(ofType: "swordfish")[0]
            dirs.insert(fish.dx)
            #expect(abs(fish.dx) == 3.5)
            #expect(fish.x == (fish.dx > 0 ? -33 : 99))
            #expect(fish.z == Depth.shark)
            #expect(fish.y >= 9 && fish.y < Double(40 - 14))
            #expect(fish.defaultColor == CellColor(color: .yellow, bright: true))
        }
        #expect(dirs == [3.5, -3.5])
    }

    @Test func swordfishColorsAreRandomIncludingTheEye() {
        for dir in 0..<2 {
            let mask = lines(SwordfishArt.masks[dir])
            var eyeColors = Set<CellColor>()
            for seed in 1...60 as ClosedRange<UInt64> {
                let c = context(seed: seed)
                addSwordfish(c)
                let fish = c.engine.entities(ofType: "swordfish")[0]
                guard (fish.dx > 0) == (dir == 0) else { continue }
                for (y, row) in mask.enumerated() {
                    for (x, ch) in row.enumerated() where ch.isNumber {
                        // A digit under a transparent cell of the picture is never drawn.
                        guard let cell = fish.sprite.frames[0].cells[y][x] else { continue }
                        #expect(cell.color != nil, "digit \(ch) was left uncolored")
                        // rand_color never picks white, so the 4s are not the white eye ordinary fish get.
                        #expect(cell.color?.color != .white)
                        if ch == "4", let color = cell.color { eyeColors.insert(color) }
                    }
                }
            }
            #expect(eyeColors.count > 1, "the eye is a random color, direction \(dir)")
        }
    }

    // MARK: jellyfish

    @Test func jellyfishGeometry() {
        var dirs = Set<Bool>()
        for seed in 1...80 as ClosedRange<UInt64> {
            let c = context(seed: seed)
            addJellyfish(c)
            let jelly = c.engine.entities(ofType: "jellyfish")[0]
            dirs.insert(jelly.dx > 0)
            #expect(abs(jelly.dx) >= 0.5 && abs(jelly.dx) < 1.5)
            #expect(jelly.x == (jelly.dx > 0 ? 0 : 78))
            #expect(jelly.y >= 9 && jelly.y < Double(24 - 10))
            #expect(jelly.z >= Depth.fishStart && jelly.z < Depth.fishStart + 10)
            #expect(abs(jelly.dy) == 0.2 && jelly.frameSpeed == 0.2)
            #expect(jelly.sprite.frames.count == 2 && jelly.height == 6)
            #expect(jelly.defaultColor == CellColor(color: .magenta, bright: true))
        }
        #expect(dirs == [true, false])
    }

    @Test func jellyfishTentaclesComeInPairs() {
        let c = context(seed: 11)
        var counts: [String: Int] = [:]
        let n = 1000
        for _ in 0..<n { addJellyfish(c) }
        for jelly in c.engine.entities(ofType: "jellyfish") {
            // Row 3 is the first row of tentacles: " l r l" in the first frame facing right and in the
            // second facing left.
            let cells = jelly.sprite.frames[jelly.dx > 0 ? 0 : 1].cells[3]
            #expect(cells[5]?.char == cells[1]?.char)
            counts["\(cells[1]!.char)\(cells[3]!.char)", default: 0] += 1
        }
        #expect(Set(counts.keys) == ["()", "[]", "/\\", "||"])
        // `(` and `)` are in Perl's list twice, so they come up twice as often.
        #expect(abs(Double(counts["()"]!) / Double(n) - 0.4) < 0.05)
        #expect(abs(Double(counts["[]"]!) / Double(n) - 0.2) < 0.05)
    }

    @Test func jellyfishTurnsBackFromTheWaterlineAndTheBottom() {
        let c = context(seed: 4)
        addJellyfish(c)
        let jelly = c.engine.entities(ofType: "jellyfish")[0]
        jelly.x = 30
        jelly.dx = 0

        // At the top it can only drift down.
        jelly.y = 7
        jelly.dy = -0.2
        c.engine.step()
        #expect(jelly.dy == 0.2)
        #expect(abs(jelly.y - 7.2) < 1e-9)

        // At the bottom it can only drift up.
        let bottom = Double(24 - 2 - jelly.height)
        jelly.y = bottom
        jelly.dy = 0.2
        c.engine.step()
        #expect(jelly.dy == -0.2)
        #expect(abs(jelly.y - (bottom - 0.2)) < 1e-9)

        // Control: in the middle of the water the drift is left alone while its timer runs.
        jelly.y = 14
        jelly.dy = 0.2
        c.engine.step()
        #expect(jelly.dy == 0.2)
    }

    @Test func jellyfishWandersButStaysInTheWater() {
        for seed in 1...12 as ClosedRange<UInt64> {
            let c = context(cols: 240, rows: 24, seed: seed)
            addJellyfish(c)
            let jelly = c.engine.entities(ofType: "jellyfish")[0]
            var drifts = Set<Double>()
            var steps = 0
            while jelly.isAlive && steps < 1000 {
                c.engine.step()
                steps += 1
                drifts.insert(jelly.dy)
                // The drift is at most 0.3 a step, so it never gets far past the turning points.
                #expect(jelly.y > 6 && jelly.y + Double(jelly.height) < 23.1, "seed \(seed) y \(jelly.y)")
            }
            #expect(!jelly.isAlive)
            #expect(drifts.count > 2, "seed \(seed): the drift never changed")
        }
    }

    // MARK: the enabled set

    @Test func allTwelveSpawn() {
        for kind in SpecialKind.allCases {
            for (cols, rows) in [(80, 24), (200, 60)] {
                let c = context(cols: cols, rows: rows, seed: 21)
                addSpecial(kind, c)
                #expect(c.engine.entityCount > 0, "\(kind)")
                let head = heads(c.engine)
                #expect(head.map(\.type) == [Self.headType[kind]!], "\(kind)")
                if kind == .fishhook { feedHook(c) }
                step(c.engine, until: head[0])
                // A new special follows, and it is a different entity.
                #expect(heads(c.engine).count == 1 && heads(c.engine)[0] !== head[0], "\(kind)")
            }
        }
    }

    @Test func respectsEnabledSet() {
        let c = context(seed: 5, settings: AquariumSettings(enabledSpecials: [.whale, .ship]))
        addRandomSpecial(c)
        var seen: [String] = []
        for _ in 0..<200 {
            let current = heads(c.engine)
            #expect(current.count == 1)
            guard let head = current.first else { break }
            seen.append(head.type)
            step(c.engine, until: head)
        }
        #expect(seen.count == 200)
        #expect(Set(seen) == ["ship", "whale"], "got \(Set(seen))")
    }

    @Test func oneEnabledSpecialRepeats() {
        for kind in [SpecialKind.swan, .jellyfish, .shark] {
            let c = context(seed: 8, settings: AquariumSettings(enabledSpecials: [kind]))
            addRandomSpecial(c)
            for _ in 0..<5 {
                let current = heads(c.engine)
                #expect(current.map(\.type) == [Self.headType[kind]!], "\(kind)")
                guard let head = current.first else { break }
                step(c.engine, until: head)
            }
        }
    }

    @Test func everyKindCanBeTheOnlyOneEnabled() {
        for kind in SpecialKind.allCases {
            for seed in 1...3 as ClosedRange<UInt64> {
                let c = context(seed: seed, settings: AquariumSettings(enabledSpecials: [kind]))
                addRandomSpecial(c)
                #expect(heads(c.engine).map(\.type) == [Self.headType[kind]!], "\(kind)")
            }
        }
        // And with two enabled, both come up.
        var seen = Set<String>()
        for seed in 0..<100 {
            let c = context(seed: UInt64(seed), settings: AquariumSettings(enabledSpecials: [.swordfish, .ducks]))
            addRandomSpecial(c)
            seen.formUnion(heads(c.engine).map(\.type))
        }
        #expect(seen == ["swordfish", "ducks"])
    }

    @Test func noSpecialsWhenNoneEnabled() {
        let settings = AquariumSettings(enabledSpecials: [])
        let c = context(cols: 120, rows: 40, seed: 9, settings: settings)
        addAllFish(c)
        let fishBefore = c.engine.entities(ofType: "fish").count
        #expect(fishBefore > 0)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            addRandomSpecial(c)
            for _ in 0..<1000 { c.engine.step() }
        }
        #expect(elapsed < .seconds(1), "took \(elapsed)")
        #expect(allEntities(c.engine).isEmpty)
        // The fish carry on: each one that leaves is replaced, so the count holds.
        #expect(c.engine.entities(ofType: "fish").count == fishBefore)

        // A special that is already out dies without a successor and without a crash.
        let d = context(seed: 9, settings: settings)
        addSpecial(.ship, d)
        let ship = d.engine.entities(ofType: "ship")[0]
        step(d.engine, until: ship)
        for _ in 0..<50 { d.engine.step() }
        #expect(allEntities(d.engine).isEmpty)
    }

    // MARK: art

    /// Perl's `_build_shape` view of a string: lines, minus one leading empty line and any trailing
    /// empty lines.
    private func lines(_ art: String) -> [String] {
        var rows = art.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if rows.first == "" { rows.removeFirst() }
        while rows.last == "" { rows.removeLast() }
        return rows
    }

    private func size(_ art: String) -> (width: Int, height: Int) {
        let rows = lines(art)
        return (rows.map(\.count).max() ?? 0, rows.count)
    }

    /// Every (shape, mask) pair of a left or right picture that Task 5 draws as a single string pair.
    private var pictures: [(name: String, shape: String, mask: String)] {
        var all: [(String, String, String)] = []
        for dir in 0..<2 {
            let side = dir == 0 ? "right" : "left"
            all.append(("shark \(side)", SharkArt.shapes[dir], SharkArt.masks[dir]))
            all.append(("ship \(side)", ShipArt.shapes[dir], ShipArt.masks[dir]))
            all.append(("big fish 1 \(side)", BigFishArt.oneShapes[dir], BigFishArt.oneMasks[dir]))
            all.append(("big fish 2 \(side)", BigFishArt.twoShapes[dir], BigFishArt.twoMasks[dir]))
            for (i, shape) in MonsterArt.newShapes[dir].enumerated() {
                all.append(("new monster \(side) \(i)", shape, MonsterArt.newMasks[dir]))
            }
            for (i, shape) in MonsterArt.oldShapes[dir].enumerated() {
                all.append(("old monster \(side) \(i)", shape, MonsterArt.oldMasks[dir]))
            }
        }
        return all.map { (name: $0.0, shape: $0.1, mask: $0.2) }
    }

    @Test func specialsArtInvariants() {
        for (name, shape, mask) in pictures {
            let shapeRows = lines(shape)
            let maskRows = lines(mask)
            // A mask never has more rows than its picture, and never a row longer than the picture's.
            #expect(maskRows.count <= shapeRows.count, "\(name): mask has more rows than the shape")
            for (s, m) in zip(shapeRows, maskRows) {
                #expect(m.count <= s.count, "\(name): mask row longer than the shape row")
            }
        }
    }

    @Test func shipAndBigFishMasksHaveEveryRow() {
        // The ship and big fish masks have exactly the picture's rows. (The shark's and monsters' stop
        // after the last row that has any color.)
        for (name, shape, mask) in pictures where name.contains("ship") || name.contains("big fish") {
            #expect(lines(shape).count == lines(mask).count, "\(name): row count")
        }
        // Whale: its mask is for the whole frame, three rows of room for the spout above the body.
        for dir in 0..<2 {
            #expect(lines(WhaleArt.masks[dir]).count == 7)
            #expect(lines(WhaleArt.shapes[dir]).count == 4)
        }
    }

    @Test func leftAndRightPicturesAreTheSameSize() {
        func same(_ name: String, _ right: String, _ left: String) {
            let r = size(right), l = size(left)
            #expect(r.width == l.width, "\(name): width \(r.width) vs \(l.width)")
            #expect(r.height == l.height, "\(name): height \(r.height) vs \(l.height)")
        }
        same("shark", SharkArt.shapes[0], SharkArt.shapes[1])
        same("ship", ShipArt.shapes[0], ShipArt.shapes[1])
        same("whale", WhaleArt.shapes[0], WhaleArt.shapes[1])
        same("big fish 1", BigFishArt.oneShapes[0], BigFishArt.oneShapes[1])
        same("big fish 2", BigFishArt.twoShapes[0], BigFishArt.twoShapes[1])
        // The monsters' frames differ by a column here and there in Perl, but each direction's widest
        // frame, which is the entity's size, is the same.
        for (name, shapes) in [("new monster", MonsterArt.newShapes), ("old monster", MonsterArt.oldShapes)] {
            let sizes = shapes.map { $0.map(size) }
            #expect(sizes[0].map(\.width).max() == sizes[1].map(\.width).max(), "\(name): width")
            #expect(sizes[0].map(\.height).max() == sizes[1].map(\.height).max(), "\(name): height")
        }
    }

    @Test func artCounts() {
        #expect(SharkArt.shapes.count == 2 && SharkArt.masks.count == 2)
        #expect(ShipArt.shapes.count == 2 && ShipArt.masks.count == 2)
        #expect(WhaleArt.shapes.count == 2 && WhaleArt.masks.count == 2 && WhaleArt.spouts.count == 7)
        #expect(MonsterArt.newShapes.map(\.count) == [2, 2] && MonsterArt.newMasks.count == 2)
        #expect(MonsterArt.oldShapes.map(\.count) == [4, 4] && MonsterArt.oldMasks.count == 2)
        #expect(BigFishArt.oneShapes.count == 2 && BigFishArt.oneMasks.count == 2)
        #expect(BigFishArt.twoShapes.count == 2 && BigFishArt.twoMasks.count == 2)
    }

    @Test func bigFishMasksOnlyUseRandomizableDigits() {
        for mask in BigFishArt.oneMasks + BigFishArt.twoMasks {
            // 1 is the body, 2 the fins; W is the fixed eye.
            #expect(Set(mask.filter { !$0.isWhitespace }).isSubset(of: ["1", "2", "W"]))
        }
    }

    /// Perl's `q{}`/`q##`/`"..."` turn `\\` into one backslash and `\{`, `\}` into braces. These rows
    /// are the ones a mangled escape would change.
    @Test func backslashesSurvive() {
        // Ship: `\\\` at the end of a row is two backslashes, `\\\\\__` is three.
        #expect(lines(ShipArt.shapes[0])[2] == #"   )___))___))___)\"#)
        #expect(lines(ShipArt.shapes[0])[3] == #"  )____)____)_____)\\"#)
        #expect(lines(ShipArt.shapes[0])[4] == #"_____|____|____|____\\\__"#)
        #expect(lines(ShipArt.shapes[0])[5] == #"\                   /"#)
        // Shark.
        #expect(lines(SharkArt.shapes[0])[1] == #"                             ( `\"#)
        // Whale.
        #expect(lines(WhaleArt.shapes[0])[2] == #",????/       (o) \"#)
        #expect(lines(WhaleArt.shapes[0])[3] == #"\`._/          ,__)"#)
        // Fishhook.
        #expect(lines(FishhookArt.hook)[3] == #"/ \???||"#)
        #expect(lines(FishhookArt.hook)[4] == #"  \__//"#)
        #expect(lines(FishhookArt.point)[2] == #"\"#)
        // New monster: the double-quoted strings write `\\` for one backslash.
        #expect(lines(MonsterArt.newShapes[0][0])[1] == #"       _{.`=`.}_??????_???_??????_{.`=`.}_????{/ ''\_"#)
        #expect(lines(MonsterArt.newShapes[0][0])[3] == #"{ \??{/  .'?'.  \}??{/ .-. \}??{/  .'?'.  \}?{/  |"#)
        // Old monster.
        #expect(lines(MonsterArt.oldShapes[0][0])[0] == #"                                                          ____"#)
        #expect(lines(MonsterArt.oldShapes[0][0])[1].hasSuffix(#"/   o  \"#))
        #expect(lines(MonsterArt.oldShapes[0][0])[2] == #"          /    \????????_?????????????????????_???????/     ____ >"#)
        // Big fish 2: `\\` is one backslash and `\{` is a brace.
        #expect(lines(BigFishArt.twoShapes[0])[1] == #"             .='\ \ \`"=,"#)
        #expect(lines(BigFishArt.twoShapes[0])[6] == #"  ;"= ._\=./_ -_ -_ {`"=_    @ \"#)
        #expect(lines(BigFishArt.twoShapes[1])[6] == #" / @    _="`} _- _- _\.=/_. =";"#)
    }

    // MARK: art, second half

    private var picturesB: [(name: String, shape: String, mask: String)] {
        var all: [(String, String, String)] = []
        for dir in 0..<2 {
            let side = dir == 0 ? "right" : "left"
            all.append(("swan \(side)", SwanArt.shapes[dir], SwanArt.masks[dir]))
            all.append(("swordfish \(side)", SwordfishArt.shapes[dir], SwordfishArt.masks[dir]))
            for (i, shape) in DuckArt.shapes[dir].enumerated() {
                all.append(("ducks \(side) \(i)", shape, DuckArt.masks[dir]))
            }
            for (i, shape) in DolphinArt.shapes[dir].enumerated() {
                all.append(("dolphin \(side) \(i)", shape, DolphinArt.masks[dir]))
            }
            // The submarine is checked on its own below: one mask serves all nine frames.
            for tentacle in 0..<JellyfishArt.leftTentacles.count {
                let shapes = JellyfishArt.shapes(
                    left: JellyfishArt.leftTentacles[tentacle], right: JellyfishArt.rightTentacles[tentacle])
                for (i, shape) in shapes[dir].enumerated() {
                    all.append(("jellyfish \(tentacle) \(side) \(i)", shape, JellyfishArt.masks[dir]))
                }
            }
        }
        return all.map { (name: $0.0, shape: $0.1, mask: $0.2) }
    }

    @Test func specialsArtInvariantsB() {
        for (name, shape, mask) in picturesB {
            let shapeRows = lines(shape)
            let maskRows = lines(mask)
            // A mask never has more rows than its picture, and never a row longer than the picture's.
            #expect(maskRows.count <= shapeRows.count, "\(name): mask has more rows than the shape")
            for (s, m) in zip(shapeRows, maskRows) {
                #expect(m.count <= s.count, "\(name): mask row longer than the shape row")
            }
        }
        // The submarine has one mask for nine frames, with the periscope at different heights, so it
        // cannot fit each frame row by row (Perl's own mask is a column wider than the periscope). It
        // fits inside the picture's bounding box, and so draws nowhere outside it.
        for dir in 0..<2 {
            let box = (width: SubmarineArt.shapes[dir].map { size($0).width }.max()!,
                       height: SubmarineArt.shapes[dir].map { size($0).height }.max()!)
            let mask = lines(SubmarineArt.masks[dir])
            #expect(mask.count <= box.height && (mask.map(\.count).max() ?? 0) <= box.width, "submarine \(dir)")
        }
        // The pictures that animate keep every frame the same height, so nothing jumps.
        for (name, frames) in [
            ("ducks", DuckArt.shapes), ("dolphins", DolphinArt.shapes), ("submarine", SubmarineArt.shapes),
        ] {
            for (dir, shapes) in frames.enumerated() {
                #expect(Set(shapes.map { size($0).height }).count == 1, "\(name) \(dir): frame heights differ")
            }
        }
    }

    @Test func artCountsB() {
        #expect(DuckArt.shapes.map(\.count) == [3, 3] && DuckArt.masks.count == 2)
        #expect(SwanArt.shapes.count == 2 && SwanArt.masks.count == 2)
        #expect(DolphinArt.shapes.map(\.count) == [2, 2] && DolphinArt.masks.count == 2)
        #expect(SubmarineArt.shapes.map(\.count) == [9, 9] && SubmarineArt.masks.count == 2)
        #expect(SwordfishArt.shapes.count == 2 && SwordfishArt.masks.count == 2)
        #expect(JellyfishArt.masks.count == 2)
        #expect(JellyfishArt.leftTentacles.count == 5 && JellyfishArt.rightTentacles.count == 5)
        for (l, r) in zip(JellyfishArt.leftTentacles, JellyfishArt.rightTentacles) {
            #expect(["()", "[]", "/\\", "||"].contains("\(l)\(r)"))
        }
    }

    @Test func leftAndRightPicturesAreTheSameSizeB() {
        func widest(_ shapes: [String]) -> (width: Int, height: Int) {
            (shapes.map { size($0).width }.max() ?? 0, shapes.map { size($0).height }.max() ?? 0)
        }
        // Perl's swordfish and submarine pictures differ by a column between the two directions (the
        // art is copied as is), so the width may differ by one; the height may not.
        func same(_ name: String, _ right: [String], _ left: [String], widthSlack: Int = 0) {
            let r = widest(right), l = widest(left)
            #expect(abs(r.width - l.width) <= widthSlack, "\(name): width \(r.width) vs \(l.width)")
            #expect(r.height == l.height, "\(name): height \(r.height) vs \(l.height)")
        }
        same("swan", [SwanArt.shapes[0]], [SwanArt.shapes[1]])
        same("swordfish", [SwordfishArt.shapes[0]], [SwordfishArt.shapes[1]], widthSlack: 1)
        same("ducks", DuckArt.shapes[0], DuckArt.shapes[1])
        same("dolphins", DolphinArt.shapes[0], DolphinArt.shapes[1])
        same("submarine", SubmarineArt.shapes[0], SubmarineArt.shapes[1], widthSlack: 1)
        let jelly = JellyfishArt.shapes(left: "(", right: ")")
        same("jellyfish", jelly[0], jelly[1])
    }

    @Test func swordfishMaskOnlyUsesRandomizableDigits() {
        for mask in SwordfishArt.masks {
            let used = Set(mask.filter { !$0.isWhitespace })
            #expect(used == ["1", "2", "3", "4", "5", "6", "7"])
        }
    }

    /// Perl's `q{}` turns `\\` into one backslash. These rows are the ones a mangled escape would change.
    @Test func backslashesSurviveB() {
        // Swan: `\\\` at the end of a row is two backslashes.
        #expect(lines(SwanArt.shapes[0])[1] == #",_    / _,\"#)
        #expect(lines(SwanArt.shapes[0])[3] == #"|  \_  \\"#)
        #expect(lines(SwanArt.shapes[1])[6] == #"\  ~=-   /"#)
        // Ducks: a single backslash stays one.
        #expect(lines(DuckArt.shapes[0][0])[2] == #" \~~= ')????\~~= ')????\~~= ')"#)
        // Dolphins.
        #expect(lines(DolphinArt.shapes[0][0])[1] == #"      __)\_"#)
        #expect(lines(DolphinArt.shapes[0][0])[2] == #"(\_.-'    a`-."#)
        // Submarine.
        #expect(lines(SubmarineArt.shapes[0][0])[9] == #"(_)?\_________________________________/"#)
        #expect(lines(SubmarineArt.shapes[1][0])[5] == #"              |   \"#)
        // Swordfish: `\\\\` is two backslashes and `\\\\\\\\` is four.
        #expect(lines(SwordfishArt.shapes[0])[1] == #"_???????????????????????????/\\\\"#)
        #expect(lines(SwordfishArt.shapes[0])[2] == #" ",????????????_____,,,,,--\\\\\\)"#)
        #expect(lines(SwordfishArt.shapes[0])[3] == #"  \\????????,,;_______\\\\\----""";_"#)
        #expect(lines(SwordfishArt.shapes[0])[4] == #"   )\_.-'`"""""......-------------,o";__________"#)
        #expect(lines(SwordfishArt.shapes[1])[6] == #"             "-.:______,...;---""/"???"????\("#)
        #expect(lines(SwordfishArt.shapes[1])[7] == #"                 '-._??????`-._("???????????\\"#)
        // Jellyfish: the right tentacle for index 3 is one backslash.
        let jelly = JellyfishArt.shapes(left: JellyfishArt.leftTentacles[3], right: JellyfishArt.rightTentacles[3])
        #expect(lines(jelly[0][0])[3] == #" / \ /"#)
        #expect(lines(jelly[0][0])[4] == #" \ / \"#)
        #expect(lines(jelly[1][0])[3] == #" \ / \"#)
    }
}
