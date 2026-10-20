import Testing
@testable import AquariumKit

@Suite struct FishTests {
    private func context(
        cols: Int = 80, rows: Int = 24, seed: UInt64 = 1, settings: AquariumSettings = AquariumSettings()
    ) -> SpawnContext {
        SpawnContext(engine: Engine(cols: cols, rows: rows, rng: RandomSource(seed: seed)), settings: settings)
    }

    private func characters(_ sprite: Sprite) -> [[Character?]] {
        sprite.frames[0].cells.map { $0.map { $0?.char } }
    }

    /// The characters a fish is drawn with, for every design and side of a set.
    private func pictures(_ designs: [FishDesign]) -> [[[Character?]]] {
        designs.flatMap { [characters(Sprite(shapes: [$0.rightShape])), characters(Sprite(shapes: [$0.leftShape]))] }
    }

    // MARK: count

    @Test func fishCountFormula() {
        #expect(fishCount(cols: 162, rows: 52, fishAmount: 1.0) == 19)
        #expect(fishCount(cols: 80, rows: 24, fishAmount: 1.0) == 3)
        #expect(fishCount(cols: 20, rows: 5, fishAmount: 1.0) == 1)
        #expect(fishCount(cols: 162, rows: 52, fishAmount: 3.0) == 59)
    }

    @Test func addAllFishAddsTheCount() {
        let c = context(cols: 162, rows: 52)
        addAllFish(c)
        #expect(c.engine.entities(ofType: "fish").count == 19)
    }

    // MARK: which designs

    @Test func classicOnlyOldFish() {
        let c = context(settings: AquariumSettings(creatureSet: .classic))
        for _ in 0..<500 {
            #expect(fishDesigns(c) == FishArt.old)
        }
        // And the fish that addFish builds are drawn from the old set. Old fish 5 and new fish 0 look
        // alike, so only the pictures that exist in the new set alone are ruled out.
        for _ in 0..<500 { addFish(c) }
        let fish = c.engine.entities(ofType: "fish")
        #expect(fish.count == 500)
        let old = pictures(FishArt.old)
        let newOnly = pictures(FishArt.new).filter { !old.contains($0) }
        #expect(newOnly.count == 6)
        for f in fish {
            let drawn = characters(f.sprite)
            #expect(old.contains(drawn))
            #expect(!newOnly.contains(drawn))
        }
    }

    @Test func fullUsesNewFishAtPerlOdds() {
        let c = context(settings: AquariumSettings(creatureSet: .full))
        var newOnes = 0
        for _ in 0..<3000 where fishDesigns(c) == FishArt.new { newOnes += 1 }
        // int(rand(12)) > 8 is 3 in 12.
        let share = Double(newOnes) / 3000
        #expect(abs(share - 0.25) < 0.03, "share was \(share)")

        // End to end: fish made with addFish include pictures from the new set only.
        for _ in 0..<3000 { addFish(c) }
        let old = pictures(FishArt.old)
        let newOnly = pictures(FishArt.new).filter { !old.contains($0) }
        let drawn = c.engine.entities(ofType: "fish").map { characters($0.sprite) }
        #expect(drawn.allSatisfy { old.contains($0) || newOnly.contains($0) })
        let newShare = Double(drawn.filter { newOnly.contains($0) }.count) / 3000
        #expect(newShare > 0.15 && newShare < 0.25, "newShare was \(newShare)")
    }

    @Test func everyPictureAppears() {
        let c = context()
        for _ in 0..<3000 { addFish(c) }
        let drawn = Set(c.engine.entities(ofType: "fish").map { "\(characters($0.sprite))" })
        let expected = Set((pictures(FishArt.old) + pictures(FishArt.new)).map { "\($0)" })
        #expect(drawn == expected)
        #expect(expected.count == 22) // 24 pictures; old 5 and new 0 are the same design, both sides
    }

    // MARK: a new fish

    @Test func fishStartAtTheEdgeAndSwimAcross() {
        let c = context()
        for _ in 0..<500 { addFish(c) }
        for f in c.engine.entities(ofType: "fish") {
            if f.dx < 0 {
                #expect(f.x == Double(c.engine.cols - 2))
                #expect(f.dx <= -0.25 && f.dx > -2.25)
            } else {
                #expect(f.x == Double(1 - f.width))
                #expect(f.dx >= 0.25 && f.dx < 2.25)
            }
            #expect(f.z >= Depth.fishStart && f.z < Depth.fishEnd)
            #expect(f.y >= 9 && Int(f.y) < c.engine.rows - f.height + 1)
            #expect(f.isPhysical && f.dieOffscreen && f.dy == 0 && f.frameSpeed == 0)
        }
    }

    @Test func eyesAreBrightWhite() {
        // add_fish turns digit 4 into W before coloring; rand_color never picks white.
        let c = context()
        for _ in 0..<200 { addFish(c) }
        for f in c.engine.entities(ofType: "fish") {
            let white = CellColor(color: .white, bright: true)
            let eyes = f.sprite.frames[0].cells.joined().compactMap { $0 }.filter { $0.color == white }
            #expect(eyes.count == 1)
        }
    }

    // MARK: respawn

    @Test func fishRespawnOnDeath() {
        let c = context()
        addAllFish(c)
        let expected = c.engine.entities(ofType: "fish").count
        var seen = Set(c.engine.entities(ofType: "fish").map(\.id))
        for _ in 0..<2000 {
            c.engine.step()
            let fish = c.engine.entities(ofType: "fish")
            #expect(fish.count == expected)
            seen.formUnion(fish.map(\.id))
        }
        // The fish really did swim away and get replaced.
        #expect(seen.count > expected * 3)
    }

    // MARK: bubbles

    @Test func bubblesDie() {
        let c = context(cols: 162, rows: 52)
        addEnvironment(c)
        addAllFish(c)
        let fishCount = c.engine.entities(ofType: "fish").count
        var mostBubbles = 0
        var totalBubbles = 0
        for _ in 0..<2000 {
            c.engine.step()
            let bubbles = c.engine.entities(ofType: "bubble").count
            mostBubbles = max(mostBubbles, bubbles)
            totalBubbles += bubbles
        }
        #expect(totalBubbles > 0, "fish should have blown some bubbles")
        #expect(c.engine.entities(ofType: "bubble").count <= 3 * fishCount)
        #expect(mostBubbles <= 3 * fishCount)
    }

    private func bubbleSource(facingRight: Bool) -> Entity {
        Entity(
            type: "fish", sprite: Sprite(shapes: ["abcd\nabcd\nabcd"]),
            x: 10, y: 15, z: 10, dx: facingRight ? 1 : -1)
    }

    @Test func bubbleStartsAtTheMouth() {
        let c = context()
        addBubble(c, from: bubbleSource(facingRight: true))
        addBubble(c, from: bubbleSource(facingRight: false))
        let bubbles = c.engine.entities(ofType: "bubble")
        #expect(bubbles.count == 2)
        // Moving right: past the nose. Moving left: at the left edge. Always mid-height, one z closer.
        #expect(bubbles[0].x == 14)
        #expect(bubbles[1].x == 10)
        for b in bubbles {
            #expect(b.y == 16)
            #expect(b.z == 9)
            #expect(b.dy == -1)
            #expect(b.isPhysical && b.dieOffscreen)
        }
    }

    @Test func bubblePopsAtTheWaterline() {
        let c = context()
        addEnvironment(c)
        addBubble(c, from: bubbleSource(facingRight: true))
        let bubble = c.engine.entities(ofType: "bubble")[0]
        var steps = 0
        while bubble.isAlive && steps < 40 {
            c.engine.step()
            steps += 1
        }
        // From y 16 it rises one row a step and meets the lowest water line row at y 8.
        #expect(!bubble.isAlive)
        #expect(bubble.y == 8)
        #expect(steps == 8)
    }

    @Test func bubbleWithoutWaterRisesOffscreen() {
        // Negative control for bubblePopsAtTheWaterline: the waterline is what pops it.
        let c = context()
        addBubble(c, from: bubbleSource(facingRight: true))
        let bubble = c.engine.entities(ofType: "bubble")[0]
        for _ in 0..<8 { c.engine.step() }
        #expect(bubble.isAlive)
        #expect(bubble.y == 8)
        var steps = 8
        while bubble.isAlive && steps < 60 { c.engine.step(); steps += 1 }
        #expect(!bubble.isAlive)
        #expect(bubble.y < 0)
    }

    // MARK: eaten

    private func fishAndTeeth(_ c: SpawnContext, teethType: String) -> (fish: Entity, teeth: Entity) {
        addFish(c)
        let fish = c.engine.entities(ofType: "fish")[0]
        fish.x = 30
        fish.y = 12
        fish.z = 5
        let teeth = Entity(
            type: teethType, sprite: Sprite(shapes: [String(repeating: "V", count: 20)]),
            x: 20, y: 13, z: 5, isPhysical: true)
        c.engine.add(teeth)
        return (fish, teeth)
    }

    @Test func fishIsEatenByTeeth() {
        let c = context()
        let (fish, teeth) = fishAndTeeth(c, teethType: "teeth")
        c.engine.step()

        #expect(!fish.isAlive)
        // The dead fish is replaced, as for any other death.
        let fishNow = c.engine.entities(ofType: "fish")
        #expect(fishNow.count == 1)
        #expect(fishNow[0] !== fish)
        // And leaves a splat, offset from the teeth.
        let splats = c.engine.entities(ofType: "self")
        #expect(splats.count == 1)
        #expect(splats[0].x == teeth.x - 4)
        #expect(splats[0].y == teeth.y - 2)
        #expect(splats[0].z == teeth.z - 2)
    }

    @Test func fishIgnoresOtherEntities() {
        // Negative control: the same overlap with something that is not teeth.
        let c = context()
        let (fish, _) = fishAndTeeth(c, teethType: "shark")
        c.engine.step()
        #expect(fish.isAlive)
        #expect(c.engine.entities(ofType: "self").isEmpty)
    }

    @Test func splatFadesAfterFifteenCycles() {
        let c = context()
        addSplat(c, x: 20, y: 10, z: 5)
        let splat = c.engine.entities(ofType: "self")[0]
        #expect(splat.x == 16 && splat.y == 8 && splat.z == 3)
        #expect(splat.sprite.frames.count == 4)
        for _ in 0..<15 { c.engine.step() }
        #expect(splat.isAlive)
        c.engine.step()
        #expect(!splat.isAlive)
    }

    @Test func splatSpacesAreTransparent() {
        let c = context()
        addSplat(c, x: 20, y: 10, z: 5)
        let splat = c.engine.entities(ofType: "self")[0]
        // Frame 0 is "   .", "  ***", "   '" under two blank lines (one stripped, one kept).
        let cells = splat.sprite.frames[0].cells
        #expect(cells.joined().allSatisfy { $0 == nil || $0!.char != " " })
        #expect(splat.sprite.frames[0].cells.joined().compactMap { $0 }.count == 5)
    }
}

@Suite struct SceneryTests {
    private func context(cols: Int = 80, rows: Int = 24, seed: UInt64 = 1) -> SpawnContext {
        SpawnContext(
            engine: Engine(cols: cols, rows: rows, rng: RandomSource(seed: seed)), settings: AquariumSettings())
    }

    @Test func waterLine() {
        let c = context()
        addEnvironment(c)
        let lines = c.engine.entities(ofType: "waterline")
        #expect(lines.count == 4)
        #expect(lines.map(\.y) == [5, 6, 7, 8])
        #expect(lines.map(\.z) == [8, 6, 4, 2])
        for line in lines {
            #expect(line.depth == 22)
            #expect(line.isPhysical)
            #expect(line.width >= 80)
            #expect(line.width % 33 == 0)
        }
        let text = c.engine.render().text().split(separator: "\n", omittingEmptySubsequences: false)
        #expect(text[5].hasPrefix("~~~~~~~~"))
        #expect(text[6].hasPrefix("^^^^ ^^^  ^^^   ^^^    ^^^^      ^^^^ ^^^"))
        #expect(text[5].count == 80)
    }

    @Test func castle() {
        let c = context()
        addCastle(c)
        let castle = c.engine.entities(ofType: "self")[0]
        #expect(castle.x == 48)
        #expect(castle.y == 11)
        #expect(castle.z == Depth.castle)
        #expect(castle.sprite.frames.count == 6)
        #expect(castle.frameSpeed == 0.1)
        #expect(castle.height == 13)
        #expect(castle.width == 31) // the widest row; Perl places it at width - 32
        let rows = c.engine.render().text().split(separator: "\n", omittingEmptySubsequences: false)
        #expect(rows[13].contains(#"/^\"#))
        // The row with `\[` in it: a backslash directly before a bracket.
        #expect(rows[16].dropFirst(48).hasPrefix(#"[ ]_[ ]_[ ]/ _   _ \[ ]_[ ]_[ ]"#))
        // Colors: the flag on top of the tower is bright green, the roof red.
        let grid = c.engine.render()
        #expect(grid[48 + 16, 11]?.color == CellColor(color: .green, bright: true))
        #expect(grid[48 + 15, 13]?.color == CellColor(color: .red, bright: false))
        #expect(grid[48 + 3, 17]?.color == CellColor(color: .white, bright: false))
    }

    @Test func castleDoorAnimates() {
        let c = context()
        addCastle(c)
        let castle = c.engine.entities(ofType: "self")[0]
        var frames = Set<Int>()
        for _ in 0..<60 {
            c.engine.step()
            frames.insert(Int(castle.frame))
        }
        #expect(frames == [0, 1, 2, 3, 4, 5])
    }

    private func seaweed(_ c: SpawnContext) -> [Entity] {
        c.engine.entities(ofType: "self").filter { $0.z == Depth.seaweed }
    }

    @Test func seaweedCountFollowsWidth() {
        let c = context(cols: 162)
        addAllSeaweed(c)
        #expect(seaweed(c).count == 10)
    }

    @Test func seaweedShape() {
        let c = context()
        for _ in 0..<200 { addSeaweed(c) }
        for weed in seaweed(c) {
            #expect((3...6).contains(weed.height))
            #expect(weed.y == Double(24 - weed.height))
            #expect(weed.x >= 1 && weed.x <= 78)
            #expect(weed.sprite.frames.count == 2)
            #expect(weed.frameSpeed >= 0.25 && weed.frameSpeed < 0.30)
            // Frame 1 starts with "(", frame 0 with " )": the stem swaps sides.
            #expect(weed.sprite.frames[1].cells[0].map { $0?.char } == ["(", nil])
            #expect(weed.sprite.frames[0].cells[0].map { $0?.char } == [" ", ")"])
            #expect(weed.defaultColor == CellColor(color: .green, bright: false))
            // 8 to 12 minutes at ten steps a second.
            let life = weed.dieAfterFrames ?? 0
            #expect(life >= 4800 && life < 7200)
        }
    }

    @Test func seaweedIsReplacedWhenItDies() {
        let c = context()
        addAllSeaweed(c)
        let before = seaweed(c)
        #expect(before.count == 5)
        before[0].dieAfterFrames = 3
        for _ in 0..<2 { c.engine.step() }
        #expect(before[0].isAlive)
        c.engine.step()
        #expect(!before[0].isAlive)
        let after = seaweed(c)
        #expect(after.count == 5)
        #expect(!after.contains { $0 === before[0] })
    }
}
