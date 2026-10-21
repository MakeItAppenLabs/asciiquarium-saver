import Foundation

// The random "special" creatures of asciiquarium 1.6, first half: ship, whale, monster, big fish,
// shark and fishhook. Exactly one special is on screen at a time. Each one's death starts the next
// (Perl `random_object`).

private let white = CellColor(color: .white, bright: false)
private let green = CellColor(color: .green, bright: false)
private let cyan = CellColor(color: .cyan, bright: false)
private let yellow = CellColor(color: .yellow, bright: false)

/// The specials that exist so far, in Perl `init_random_objects` order.
private let portedSpecials: [SpecialKind] = [.ship, .whale, .monster, .bigFish, .shark, .fishhook]

/// Adds one special of the given kind.
public func addSpecial(_ kind: SpecialKind, _ c: SpawnContext) {
    switch kind {
    case .ship: addShip(c)
    case .whale: addWhale(c)
    case .monster: addMonster(c)
    case .bigFish: addBigFish(c)
    case .shark: addShark(c)
    case .fishhook: addFishhook(c)
    case .swan, .ducks, .dolphins, .submarine, .swordfish, .jellyfish:
        unportedSpecial(kind)
    }
}

/// Perl `random_object`: starts a special chosen uniformly from the ones ported so far.
public func addRandomSpecial(_ c: SpawnContext) {
    addSpecial(portedSpecials[c.engine.rng.int(portedSpecials.count)], c)
}

/// TASK 6: replace this stub with the real `add...` calls, remove it, and make `addRandomSpecial`
/// pick among all twelve kinds (honoring `enabledSpecials`).
private func unportedSpecial(_ kind: SpecialKind) -> Never {
    fatalError("unported special: \(kind)")
}

// MARK: death

/// The `death_cb => \&random_object` of a special made of a single entity.
private func startsNextSpecial(_ settings: AquariumSettings) -> (Entity, Engine) -> Void {
    return { _, engine in
        addRandomSpecial(SpawnContext(engine: engine, settings: settings))
    }
}

/// Perl `group_death`: the member that carries the death callback takes the entities bound to it
/// along, then the next special starts. The other members have no callback, so only this one
/// death starts a special.
private func groupDeath(_ engine: Engine, settings: AquariumSettings, bound types: [String]) {
    for type in types {
        for member in engine.entities(ofType: type) {
            engine.kill(member)
        }
    }
    addRandomSpecial(SpawnContext(engine: engine, settings: settings))
}

// MARK: shark

/// Perl `add_shark`. The shark is only a picture; the separate `teeth` entity inside its mouth is
/// the physical part, and every fish it touches is eaten.
func addShark(_ c: SpawnContext) {
    let engine = c.engine
    let rng = engine.rng

    let dir = rng.int(2)
    var x = -53.0
    let y = rng.int(engine.rows - (10 + 9)) + 9
    var teethX = -9.0
    let teethY = y + 7
    var speed = 2.0
    if dir == 1 {
        speed *= -1
        x = Double(engine.cols - 2)
        teethX = x + 9
    }

    engine.add(Entity(
        type: "teeth",
        sprite: Sprite(shapes: ["*"], autoTransparent: false),
        x: teethX,
        y: Double(teethY),
        z: Depth.shark + 1,
        dx: speed,
        depth: Depth.fishEnd - Depth.fishStart,
        isPhysical: true
    ))

    let shark = Entity(
        type: "shark",
        sprite: Sprite(shapes: [SharkArt.shapes[dir]], masks: [SharkArt.masks[dir]], autoTransparent: true),
        x: x,
        y: Double(y),
        z: Depth.shark,
        dx: speed,
        defaultColor: cyan,
        dieOffscreen: true
    )
    let settings = c.settings
    shark.onDeath = { _, engine in
        // Perl `group_death(@_, 'teeth')`
        groupDeath(engine, settings: settings, bound: ["teeth"])
    }
    engine.add(shark)
}

// MARK: fishhook

/// Perl `retract`: pull the fishhook, line and whatever got caught back to the surface.
func retract(_ entity: Entity) {
    entity.isPhysical = false
    if entity.type == "fish" {
        entity.z = Depth.waterGap2
    }
    // Perl sets `callback_args` to 'hooked' (or a fish already has some), which `fishhook_cb` reads
    // as "reel in".
    entity.onTick = reelIn
}

/// Perl `fishhook_cb` for something that has been hooked: one row up per step.
private func reelIn(_ entity: Entity, _ engine: Engine) {
    entity.y -= 1
}

/// Perl `fishhook_cb` for the hook, line and point before anything is caught: lower until the
/// bottom of the entity is three quarters of the way down.
private func lowerHook(_ entity: Entity, _ engine: Engine) {
    if entity.y + Double(entity.height) < Double(engine.rows) * 0.75 {
        entity.y += 1
    }
}

/// Perl `add_fishhook`: a line, the hook and its point, which are lowered together.
func addFishhook(_ c: SpawnContext) {
    let engine = c.engine

    // "|\n" x 50 . " \n" x 6
    let lineImage = String(repeating: "|\n", count: 50) + String(repeating: " \n", count: 6)

    let x = 10 + engine.rng.int(engine.cols - 20)
    let y = -4
    let pointX = x + 1
    let pointY = y + 2

    let line = Entity(
        type: "fishline",
        sprite: Sprite(shapes: [lineImage], autoTransparent: true),
        x: Double(x + 7),
        y: Double(y - 50),
        z: Depth.waterLine1,
        defaultColor: white
    )
    line.onTick = lowerHook
    engine.add(line)

    let hook = Entity(
        type: "fishhook",
        sprite: Sprite(shapes: [FishhookArt.hook], autoTransparent: true),
        x: Double(x),
        y: Double(y),
        z: Depth.waterLine1,
        defaultColor: green,
        dieOffscreen: true
    )
    hook.onTick = lowerHook
    let settings = c.settings
    hook.onDeath = { _, engine in
        // Perl `group_death(@_, 'hook_point', 'fishline')`
        groupDeath(engine, settings: settings, bound: ["hook_point", "fishline"])
    }
    engine.add(hook)

    let point = Entity(
        type: "hook_point",
        sprite: Sprite(shapes: [FishhookArt.point], autoTransparent: false),
        x: Double(pointX),
        y: Double(pointY),
        z: Depth.shark + 1,
        defaultColor: green,
        depth: Depth.fishEnd - Depth.fishStart,
        isPhysical: true,
        dieOffscreen: true
    )
    point.onTick = lowerHook
    engine.add(point)
}

// MARK: ship

/// Perl `add_ship`.
func addShip(_ c: SpawnContext) {
    let engine = c.engine
    let dir = engine.rng.int(2)
    var x = -24.0
    var speed = 1.0
    if dir == 1 {
        speed *= -1
        x = Double(engine.cols - 2)
    }

    let ship = Entity(
        type: "ship",
        sprite: Sprite(shapes: [ShipArt.shapes[dir]], masks: [ShipArt.masks[dir]], autoTransparent: true),
        x: x,
        y: 0,
        z: Depth.waterGap1,
        dx: speed,
        defaultColor: white,
        dieOffscreen: true
    )
    ship.onDeath = startsNextSpecial(c.settings)
    engine.add(ship)
}

// MARK: whale

/// Perl `split("\n", $s)`: trailing empty fields are dropped, leading ones are kept.
private func perlSplitLines(_ s: String) -> [String] {
    var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    while lines.last == "" { lines.removeLast() }
    return lines
}

/// Perl `add_whale`: five frames without a spout, then seven with the spout growing and falling.
func addWhale(_ c: SpawnContext) {
    let engine = c.engine
    let dir = engine.rng.int(2)
    let x: Double
    var speed = 1.0
    let spoutAlign: Int
    if dir == 1 {
        spoutAlign = 1
        speed *= -1
        x = Double(engine.cols - 2)
    } else {
        spoutAlign = 11
        x = -18
    }

    let image = WhaleArt.shapes[dir]
    let mask = WhaleArt.masks[dir]
    var frames: [String] = []
    var masks: [String] = []

    // no water spout
    for _ in 1...5 {
        frames.append("\n\n\n" + image)
        masks.append(mask)
    }
    // animate water spout
    for spout in WhaleArt.spouts {
        let alignedSpout = perlSplitLines(spout)
            .joined(separator: "\n" + String(repeating: " ", count: spoutAlign))
        frames.append(alignedSpout + image)
        masks.append(mask)
    }

    let whale = Entity(
        type: "whale",
        sprite: Sprite(shapes: frames, masks: masks, autoTransparent: true),
        x: x,
        y: 0,
        z: Depth.waterGap2,
        dx: speed,
        frameSpeed: 1,
        defaultColor: white,
        dieOffscreen: true
    )
    whale.onDeath = startsNextSpecial(c.settings)
    engine.add(whale)
}

// MARK: monster

/// Perl `add_monster`: the classic set has the old monster, the full set the new one.
func addMonster(_ c: SpawnContext) {
    if c.classic {
        addOldMonster(c)
    } else {
        addNewMonster(c)
    }
}

private func addMonsterEntity(
    _ c: SpawnContext, shapes: [String], mask: String, startX: Double, dir: Int
) {
    let engine = c.engine
    var x = startX
    var speed = 2.0
    if dir == 1 {
        speed *= -1
        x = Double(engine.cols - 2)
    }

    let monster = Entity(
        type: "monster",
        sprite: Sprite(
            shapes: shapes,
            masks: Array(repeating: mask, count: shapes.count),
            autoTransparent: true),
        x: x,
        y: 2,
        z: Depth.waterGap2,
        dx: speed,
        frameSpeed: 0.25,
        defaultColor: green,
        dieOffscreen: true
    )
    monster.onDeath = startsNextSpecial(c.settings)
    engine.add(monster)
}

/// Perl `add_new_monster`: two frames.
func addNewMonster(_ c: SpawnContext) {
    let dir = c.engine.rng.int(2)
    addMonsterEntity(c, shapes: MonsterArt.newShapes[dir], mask: MonsterArt.newMasks[dir], startX: -54, dir: dir)
}

/// Perl `add_old_monster`: four frames.
func addOldMonster(_ c: SpawnContext) {
    let dir = c.engine.rng.int(2)
    addMonsterEntity(c, shapes: MonsterArt.oldShapes[dir], mask: MonsterArt.oldMasks[dir], startX: -64, dir: dir)
}

// MARK: big fish

/// Which big fish `add_big_fish` builds: the full set picks the second with `int(rand(3)) > 1`,
/// the classic set always the first.
func bigFishVariant(_ c: SpawnContext) -> Int {
    if !c.classic, c.engine.rng.int(3) > 1 {
        return 2
    }
    return 1
}

/// Perl `add_big_fish`.
func addBigFish(_ c: SpawnContext) {
    if bigFishVariant(c) == 2 {
        addBigFish2(c)
    } else {
        addBigFish1(c)
    }
}

/// Perl `add_big_fish_1`.
func addBigFish1(_ c: SpawnContext) {
    addBigFishEntity(
        c, shapes: BigFishArt.oneShapes, masks: BigFishArt.oneMasks,
        speed: 3, startX: -34, heightMargin: 15)
}

/// Perl `add_big_fish_2`.
func addBigFish2(_ c: SpawnContext) {
    addBigFishEntity(
        c, shapes: BigFishArt.twoShapes, masks: BigFishArt.twoMasks,
        speed: 2.5, startX: -33, heightMargin: 14)
}

private func addBigFishEntity(
    _ c: SpawnContext, shapes: [String], masks: [String], speed: Double, startX: Double,
    heightMargin: Int
) {
    let engine = c.engine
    let rng = engine.rng
    let dir = rng.int(2)
    var x = startX
    var dx = speed
    if dir == 1 {
        x = Double(engine.cols - 1)
        dx *= -1
    }
    let maxHeight = 9
    let minHeight = engine.rows - heightMargin
    let y = rng.int(minHeight - maxHeight) + maxHeight
    // Perl calls `rand_color` straight on the mask, so the eye (digit 4, if any) is not whitened.
    let colorMask = randomizeFishMask(masks[dir], rng: rng)

    let fish = Entity(
        type: "bigfish",
        sprite: Sprite(shapes: [shapes[dir]], masks: [colorMask], autoTransparent: true),
        x: x,
        y: Double(y),
        z: Depth.shark,
        dx: dx,
        defaultColor: yellow,
        dieOffscreen: true
    )
    fish.onDeath = startsNextSpecial(c.settings)
    engine.add(fish)
}
