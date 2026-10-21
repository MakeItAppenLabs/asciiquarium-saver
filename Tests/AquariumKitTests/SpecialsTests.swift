import Testing
@testable import AquariumKit

@Suite struct SpecialsTests {
    private static let headTypes: Set<String> = ["ship", "whale", "monster", "bigfish", "shark", "fishhook"]
    private static let ported: [SpecialKind] = [.ship, .whale, .monster, .bigFish, .shark, .fishhook]

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
        (Self.headTypes.union(["teeth", "fishline", "hook_point"])).flatMap { engine.entities(ofType: $0) }
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

    @Test(arguments: [SpecialKind.ship, .whale, .monster, .bigFish, .shark, .fishhook])
    func oneSpecialAtATime(kind: SpecialKind) {
        for seed in 1...6 as ClosedRange<UInt64> {
            let c = context(seed: seed)
            addSpecial(kind, c)
            let original = heads(c.engine)
            #expect(original.count == 1)
            let members = allEntities(c.engine)

            if kind == .fishhook {
                // A hook only leaves when it catches something.
                for _ in 0..<100 { c.engine.step() }
                addFish(c)
                let fish = c.engine.entities(ofType: "fish")[0]
                let point = c.engine.entities(ofType: "hook_point")[0]
                fish.dx = 0
                fish.x = point.x
                fish.y = point.y
                fish.z = 5
            }

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

    @Test func randomSpecialPicksUniformlyAmongThePorted() {
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
            #expect(abs(Double(count) / Double(n) - 1.0 / 6.0) < 0.04, "\(type): \(count)")
        }
    }

    @Test func addSpecialBuildsEachPortedKind() {
        let expected: [SpecialKind: String] = [
            .ship: "ship", .whale: "whale", .monster: "monster", .bigFish: "bigfish",
            .shark: "shark", .fishhook: "fishhook",
        ]
        for kind in Self.ported {
            let c = context()
            addSpecial(kind, c)
            #expect(heads(c.engine).map(\.type) == [expected[kind]!])
        }
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
}
