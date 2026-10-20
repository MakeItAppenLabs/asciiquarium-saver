import Testing
@testable import AquariumKit

@Suite struct EngineTests {
    private func engine(cols: Int = 20, rows: Int = 10) -> Engine {
        Engine(cols: cols, rows: rows, rng: RandomSource(seed: 1))
    }

    private func entity(
        _ art: String = "X", type: String = "t", x: Double = 0, y: Double = 0, z: Int = 0
    ) -> Entity {
        Entity(type: type, sprite: Sprite(shapes: [art]), x: x, y: y, z: z)
    }

    // MARK: movement (Entity.pm move_entity)

    @Test func defaultMove() {
        let e = engine()
        let ent = e.add(Entity(type: "t", sprite: Sprite(shapes: ["a", "b", "c"]), dx: 1.5, dy: 0.5, frameSpeed: 1.5))
        e.step()
        #expect(ent.x == 1.5)
        #expect(ent.y == 0.5)
        #expect(ent.frame == 1.5)
        e.step()
        #expect(ent.x == 3.0)
        #expect(ent.y == 1.0)
        // 1.5 + 1.5 = 3.0 -> fractional part 0, integer part 3 mod 3 frames = 0
        #expect(ent.frame == 0.0)
        e.step()
        #expect(ent.frame == 1.5)
    }

    @Test func zeroFrameSpeedLeavesFrameAlone() {
        let e = engine()
        let ent = e.add(Entity(type: "t", sprite: Sprite(shapes: ["a", "b"]), frame: 1))
        e.step()
        #expect(ent.frame == 1)
    }

    @Test func pathMoveCyclesAndSetsFrameAbsolutely() {
        let e = engine()
        let ent = entity()
        ent.path = [PathStep(dx: 1, dy: -0.5, frame: 0.5), PathStep(dx: 2, dy: 0, frame: nil)]
        ent.pathIndex = 1
        e.add(ent)
        e.step() // step index 1: dx 2, frame untouched
        #expect(ent.x == 2)
        #expect(ent.frame == 0)
        e.step() // wraps to index 0
        #expect(ent.x == 3)
        #expect(ent.y == -0.5)
        #expect(ent.frame == 0.5)
        e.step() // back to index 1; frame keeps the previous absolute value
        #expect(ent.x == 5)
        #expect(ent.frame == 0.5)
    }

    @Test func onTickReplacesDefaultMove() {
        let e = engine()
        let ent = entity()
        ent.dx = 5
        var ticks = 0
        ent.onTick = { entity, _ in
            ticks += 1
            entity.y += 1
        }
        e.add(ent)
        e.step()
        #expect(ticks == 1)
        #expect(ent.x == 0)
        #expect(ent.y == 1)
    }

    @Test func onTickCanCallDefaultMove() {
        let e = engine()
        let ent = entity()
        ent.dx = 2
        ent.onTick = { entity, _ in entity.defaultMove() }
        e.add(ent)
        e.step()
        #expect(ent.x == 2)
    }

    // MARK: lifetimes (Animation.pm _do_callbacks)

    @Test func dieOffscreenRunsDeathOnce() {
        let e = engine(cols: 10, rows: 5)
        let ent = entity("ab", x: 7)
        ent.dx = 1
        ent.dieOffscreen = true
        var deaths = 0
        ent.onDeath = { _, _ in deaths += 1 }
        e.add(ent)
        var steps = 0
        while e.entityCount > 0 && steps < 50 { e.step(); steps += 1 }
        #expect(e.entityCount == 0)
        #expect(deaths == 1)
        // x = 7 + n. The check runs at the start of a step, so the entity must already be at
        // x >= cols (10) when a step begins: it reaches 10 after step 3 and is removed in step 4.
        #expect(steps == 4)
        for _ in 0..<5 { e.step() }
        #expect(deaths == 1)
    }

    @Test func offscreenRuleMatchesTermAnimation() {
        // Perl: X >= WIDTH or Y >= HEIGHT or X < -width or Y < -height. Exactly -width is still alive.
        let e = engine(cols: 10, rows: 5)
        let atEdge = e.add(entity("abc", x: -3))
        atEdge.dieOffscreen = true
        let past = e.add(entity("abc", x: -3.5))
        past.dieOffscreen = true
        let below = e.add(entity("abc", x: 0, y: 5))
        below.dieOffscreen = true
        let inside = e.add(entity("abc", x: 9, y: 4))
        inside.dieOffscreen = true
        e.step()
        #expect(e.entityCount == 2)
        #expect(!past.isAlive)
        #expect(!below.isAlive)
        #expect(atEdge.isAlive)
        #expect(inside.isAlive)
    }

    @Test func dieAfterFrames() {
        // die_time converted to steps: removed during step N (the check precedes the tick).
        let e = engine()
        let ent = entity()
        ent.dieAfterFrames = 3
        var ticks = 0
        ent.onTick = { _, _ in ticks += 1 }
        var deaths = 0
        ent.onDeath = { _, _ in deaths += 1 }
        e.add(ent)
        e.step()
        e.step()
        #expect(e.entityCount == 1)
        e.step()
        #expect(e.entityCount == 0)
        #expect(ticks == 2)
        #expect(deaths == 1)
    }

    @Test func dieAfterCycles() {
        // die_frame: the entity is displayed for N frames and is gone after step N + 1.
        let e = engine()
        let ent = entity()
        ent.dieAfterCycles = 3
        var ticks = 0
        ent.onTick = { _, _ in ticks += 1 }
        var deaths = 0
        ent.onDeath = { _, _ in deaths += 1 }
        e.add(ent)
        for _ in 0..<3 {
            e.step()
            #expect(e.entityCount == 1)
        }
        e.step()
        #expect(e.entityCount == 0)
        #expect(ticks == 3)
        #expect(deaths == 1)
    }

    @Test func killRunsDeathOnceAndRemoveDoesNot() {
        let e = engine()
        var deaths = 0
        let a = entity()
        a.onDeath = { _, _ in deaths += 1 }
        let b = entity()
        b.onDeath = { _, _ in deaths += 1 }
        e.add(a)
        e.add(b)
        e.kill(a)
        e.kill(a)
        #expect(deaths == 1)
        #expect(e.entityCount == 1)
        e.remove(b)
        #expect(deaths == 1)
        #expect(e.entityCount == 0)
        e.kill(b) // already gone
        #expect(deaths == 1)
    }

    @Test func removeInsideStepSkipsDeathButNotAfterKill() {
        let e = engine()
        var deaths = 0
        let silent = entity(type: "silent")
        silent.onDeath = { _, _ in deaths += 1 }
        let killed = entity(type: "killed")
        killed.onDeath = { _, _ in deaths += 1 }
        let driver = entity(type: "driver")
        driver.onTick = { _, engine in
            engine.remove(silent)
            engine.kill(killed)
            engine.remove(killed) // a queued kill still runs onDeath
        }
        e.add(silent)
        e.add(killed)
        e.add(driver)
        e.step()
        #expect(deaths == 1)
        #expect(e.entityCount == 1)
    }

    @Test func killInsideStepIsDeferredToRemovalPhase() {
        let e = engine()
        let victim = entity()
        var victimDeaths = 0
        victim.onDeath = { _, _ in victimDeaths += 1 }
        let killer = entity()
        var sawAliveAfterKill = false
        killer.onTick = { _, engine in
            engine.kill(victim)
            sawAliveAfterKill = engine.entityCount == 2 && victimDeaths == 0
        }
        e.add(victim)
        e.add(killer)
        e.step()
        #expect(sawAliveAfterKill)
        #expect(victimDeaths == 1)
        #expect(e.entityCount == 1)
    }

    @Test func deathCallbackCanAddAndKill() {
        let e = engine()
        let child = entity(type: "child")
        let linked = entity(type: "linked")
        let parent = entity(type: "parent")
        parent.dieAfterFrames = 1
        parent.onDeath = { _, engine in
            engine.add(child)
            for other in engine.entities(ofType: "linked") { engine.kill(other) }
        }
        e.add(parent)
        e.add(linked)
        e.step()
        #expect(e.entities(ofType: "parent").isEmpty)
        #expect(e.entities(ofType: "linked").isEmpty)
        #expect(e.entities(ofType: "child").count == 1)
    }

    @Test func addInsideTickWaitsForNextStep() {
        let e = engine()
        let spawn = entity()
        let newborn = entity(type: "new")
        var newbornTicks = 0
        newborn.onTick = { _, _ in newbornTicks += 1 }
        spawn.onTick = { entity, engine in
            if engine.frameCount == 0 { engine.add(newborn) }
        }
        e.add(spawn)
        e.step()
        #expect(newbornTicks == 0)
        #expect(e.entities(ofType: "new").count == 1)
        e.step()
        #expect(newbornTicks == 1)
    }

    @Test func entitiesOfTypeAndCount() {
        let e = engine()
        e.add(entity(type: "fish"))
        e.add(entity(type: "fish"))
        e.add(entity(type: "shark"))
        #expect(e.entityCount == 3)
        #expect(e.entities(ofType: "fish").count == 2)
        #expect(e.entities(ofType: "shark").count == 1)
        #expect(e.entities(ofType: "none").isEmpty)
        e.removeAll()
        #expect(e.entityCount == 0)
    }

    @Test func frameCountCountsSteps() {
        let e = engine()
        #expect(e.frameCount == 0)
        e.step()
        e.step()
        #expect(e.frameCount == 2)
    }

    // MARK: collisions (Animation.pm _find_collisions)

    @Test func collisionReported() {
        let e = engine()
        let a = entity("aaa", type: "a", x: 0)
        let b = entity("bbb", type: "b", x: 2)
        a.isPhysical = true
        b.isPhysical = true
        var aSaw: [Entity] = []
        var bSaw: [Entity] = []
        a.onCollision = { _, others, _ in aSaw = others }
        b.onCollision = { _, others, _ in bSaw = others }
        e.add(a)
        e.add(b)
        e.step()
        #expect(aSaw.map(\.id) == [b.id])
        #expect(bSaw.map(\.id) == [a.id])
    }

    @Test func nonPhysicalOverlapReportsNothing() {
        let e = engine()
        let a = entity("aaa", x: 0)
        let b = entity("bbb", x: 2)
        b.isPhysical = true // only one side is physical
        var calls = 0
        a.onCollision = { _, _, _ in calls += 1 }
        b.onCollision = { _, _, _ in calls += 1 }
        e.add(a)
        e.add(b)
        e.step()
        #expect(calls == 0)
    }

    @Test func touchingEdgesDoNotCollide() {
        let e = engine()
        let a = entity("aa", x: 0)
        let b = entity("bb", x: 2)
        a.isPhysical = true
        b.isPhysical = true
        var calls = 0
        a.onCollision = { _, _, _ in calls += 1 }
        e.add(a)
        e.add(b)
        e.step()
        #expect(calls == 0)
    }

    @Test func collisionNeedsZOverlap() {
        let e = engine()
        let a = entity("aa", x: 0, z: 1)
        let b = entity("aa", x: 0, z: 2) // depth 1: z ranges [1,2) and [2,3) do not meet
        a.isPhysical = true
        b.isPhysical = true
        var calls = 0
        a.onCollision = { _, _, _ in calls += 1 }
        b.depth = 3 // [2,5)
        e.add(a)
        e.add(b)
        e.step()
        #expect(calls == 0)
        a.depth = 2 // [1,3) now reaches z 2
        e.step()
        #expect(calls == 1)
    }

    @Test func collisionUsesFractionalPositionAndEntityWideSize() {
        let e = engine()
        // Second frame is wider; the entity-wide width (3) is what counts.
        let wide = Entity(type: "w", sprite: Sprite(shapes: ["a", "aaa"]))
        wide.isPhysical = true
        let other = entity("b", x: 2.5)
        other.isPhysical = true
        var calls = 0
        wide.onCollision = { _, _, _ in calls += 1 }
        e.add(wide)
        e.add(other)
        e.step()
        #expect(calls == 1)
    }

    @Test func collisionsRunAfterMovement() {
        let e = engine()
        let a = entity("aa", x: 0)
        let b = entity("bb", x: 5)
        b.dx = -4
        a.isPhysical = true
        b.isPhysical = true
        var calls = 0
        a.onCollision = { _, _, _ in calls += 1 }
        e.add(a)
        e.add(b)
        e.step()
        #expect(calls == 1)
    }

    @Test func killDuringCollision() {
        let e = engine()
        var aDeaths = 0
        var bDeaths = 0
        let a = entity("aa", type: "a")
        let b = entity("bb", type: "b")
        a.isPhysical = true
        b.isPhysical = true
        a.onDeath = { _, _ in aDeaths += 1 }
        b.onDeath = { _, _ in bDeaths += 1 }
        a.onCollision = { _, others, engine in
            for other in others { engine.kill(other) }
        }
        b.onCollision = { _, others, engine in
            for other in others { engine.kill(other) }
        }
        e.add(a)
        e.add(b)
        e.step()
        #expect(aDeaths == 1)
        #expect(bDeaths == 1)
        #expect(e.entityCount == 0)
        e.step()
        #expect(aDeaths == 1)
        #expect(bDeaths == 1)
    }

    @Test func killSelfDuringCollisionFiresOnce() {
        let e = engine()
        var deaths = 0
        let a = entity("aa")
        let b = entity("bb")
        a.isPhysical = true
        b.isPhysical = true
        a.onDeath = { _, _ in deaths += 1 }
        a.onCollision = { me, _, engine in
            engine.kill(me)
            engine.kill(me)
        }
        e.add(a)
        e.add(b)
        e.step()
        #expect(deaths == 1)
        #expect(e.entityCount == 1)
    }

    // MARK: rendering (Animation.pm _build_screen / _draw_entity)

    @Test func zOrder() {
        let e = engine()
        e.add(entity("B", z: 5))
        e.add(entity("A", z: 1))
        #expect(e.render()[0, 0]?.char == "A")
        // Insertion order must not matter.
        let e2 = engine()
        e2.add(entity("A", z: 1))
        e2.add(entity("B", z: 5))
        #expect(e2.render()[0, 0]?.char == "A")
    }

    @Test func opaqueBlankAtLowerZClearsCell() {
        let e = engine()
        e.add(entity("B", z: 5))
        // " X": autoTransparent would drop the leading space, so build the blank explicitly.
        let blank = Entity(type: "t", sprite: Sprite(shapes: ["a b"], autoTransparent: false), z: 1)
        e.add(blank)
        let grid = e.render()
        #expect(grid[0, 0]?.char == "a")
        #expect(grid[1, 0] == nil)
        #expect(grid[2, 0]?.char == "b")

        let e2 = engine()
        e2.add(entity("B", z: 5))
        e2.add(Entity(type: "t", sprite: Sprite(shapes: [" "], autoTransparent: false), z: 1))
        #expect(e2.render()[0, 0] == nil)
    }

    @Test func transparentCellsLetLowerLayersShow() {
        let e = engine()
        e.add(entity("B", z: 5))
        e.add(Entity(type: "t", sprite: Sprite(shapes: ["?"]), z: 1))
        #expect(e.render()[0, 0]?.char == "B")
    }

    @Test func renderUsesFloorOfPosition() {
        let e = engine()
        e.add(entity("X", x: 2.9, y: 1.1))
        let grid = e.render()
        #expect(grid[2, 1]?.char == "X")
        #expect(grid[3, 1] == nil)
        // A fractional negative x floors towards the left; the second cell lands on column 0.
        let e2 = engine()
        e2.add(entity("ab", x: -0.5))
        let grid2 = e2.render()
        #expect(grid2[0, 0]?.char == "b")
    }

    @Test func renderClipsToGrid() {
        let e = engine(cols: 3, rows: 2)
        e.add(entity("abcd\nefgh", x: 1, y: 1))
        let grid = e.render()
        #expect(grid.text() == "   \n ab")
    }

    @Test func renderColorsUseMaskThenDefault() {
        let e = engine()
        let red = CellColor(color: .red, bright: true)
        let cyan = CellColor(color: .cyan, bright: false)
        let sprite = Sprite(shapes: ["ab"], masks: ["R "])
        e.add(Entity(type: "t", sprite: sprite, defaultColor: cyan))
        let grid = e.render()
        #expect(grid[0, 0]?.color == red)
        #expect(grid[1, 0]?.color == cyan)
    }

    @Test func renderPicksFrameByFlooringFractionalFrame() {
        let e = engine()
        let ent = e.add(Entity(type: "t", sprite: Sprite(shapes: ["a", "b"]), frame: 1.75))
        #expect(e.render()[0, 0]?.char == "b")
        ent.frame = 0.5
        #expect(e.render()[0, 0]?.char == "a")
        ent.frame = 7 // outside the sprite: nothing drawn, as in Perl
        #expect(e.render()[0, 0] == nil)
    }
}
