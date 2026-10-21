import Foundation

// The random "special" creatures of asciiquarium 1.6: ship, whale, monster, big fish, shark, fishhook,
// swan, ducks, dolphins, submarine, swordfish and jellyfish. Exactly one special is on screen at a
// time. Each one's death starts the next (Perl `random_object`), chosen among the enabled ones.

// Perl's lower case color names are normal, upper case ones bold (bright).
private let white = CellColor(color: .white, bright: false)
private let green = CellColor(color: .green, bright: false)
private let cyan = CellColor(color: .cyan, bright: false)
private let yellow = CellColor(color: .yellow, bright: false)
private let blue = CellColor(color: .blue, bright: false)
private let whiteBright = CellColor(color: .white, bright: true)
private let yellowBright = CellColor(color: .yellow, bright: true)
private let blueBright = CellColor(color: .blue, bright: true)
private let cyanBright = CellColor(color: .cyan, bright: true)
private let magentaBright = CellColor(color: .magenta, bright: true)

/// Adds one special of the given kind.
public func addSpecial(_ kind: SpecialKind, _ c: SpawnContext) {
    switch kind {
    case .ship: addShip(c)
    case .whale: addWhale(c)
    case .monster: addMonster(c)
    case .bigFish: addBigFish(c)
    case .shark: addShark(c)
    case .fishhook: addFishhook(c)
    case .swan: addSwan(c)
    case .ducks: addDucks(c)
    case .dolphins: addDolphins(c)
    case .submarine: addSubmarine(c)
    case .swordfish: addSwordfish(c)
    case .jellyfish: addJellyfish(c)
    }
}

/// Perl `random_object`: starts a special chosen uniformly from the enabled ones. The choice is made
/// from `SpecialKind.allCases` order, so a seeded run is reproducible. With none enabled nothing
/// starts.
public func addRandomSpecial(_ c: SpawnContext) {
    let choices = SpecialKind.allCases.filter { c.settings.enabledSpecials.contains($0) }
    guard !choices.isEmpty else { return }
    addSpecial(choices[c.engine.rng.int(choices.count)], c)
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

// MARK: swan

/// Perl `add_swan`.
func addSwan(_ c: SpawnContext) {
    let engine = c.engine
    let dir = engine.rng.int(2)
    var x = -10.0
    var speed = 1.0
    if dir == 1 {
        speed *= -1
        x = Double(engine.cols - 2)
    }

    let swan = Entity(
        type: "swan",
        sprite: Sprite(shapes: [SwanArt.shapes[dir]], masks: [SwanArt.masks[dir]], autoTransparent: true),
        x: x,
        y: 1,
        z: Depth.waterGap3,
        dx: speed,
        frameSpeed: 0.25,
        defaultColor: whiteBright,
        dieOffscreen: true
    )
    swan.onDeath = startsNextSpecial(c.settings)
    engine.add(swan)
}

// MARK: ducks

/// Perl `add_ducks`: three ducks in a row, three frames in which a different one is the lead.
func addDucks(_ c: SpawnContext) {
    let engine = c.engine
    let dir = engine.rng.int(2)
    var x = -30.0
    var speed = 1.0
    if dir == 1 {
        speed *= -1
        x = Double(engine.cols - 2)
    }

    let shapes = DuckArt.shapes[dir]
    let ducks = Entity(
        type: "ducks",
        sprite: Sprite(shapes: shapes, masks: [DuckArt.masks[dir]], autoTransparent: true),
        x: x,
        y: 5,
        z: Depth.waterGap3,
        dx: speed,
        frameSpeed: 0.25,
        defaultColor: whiteBright,
        dieOffscreen: true
    )
    ducks.onDeath = startsNextSpecial(c.settings)
    engine.add(ducks)
}

// MARK: dolphins

/// Perl `add_dolphins`: three dolphins that leap out of the water and dive back in on one shared path.
///
/// The trailing dolphin (`dolphin`) is the one whose death starts the next special. The others
/// (`dolphin_mate`) start off screen, so they only die off screen after the lead dolphin has left and
/// switched that on for them.
func addDolphins(_ c: SpawnContext) {
    let engine = c.engine
    let dir = engine.rng.int(2)

    var x = -13.0
    var speed = 1.0
    var distance = 15.0  // how far apart the dolphins are
    if dir == 1 {
        speed *= -1
        distance *= -1
        x = Double(engine.cols - 2)
    }

    let up = PathStep(dx: speed, dy: -0.5, frame: 0.5)
    let down = PathStep(dx: speed, dy: 0.5, frame: 0.5)
    let glide = PathStep(dx: speed, dy: 0, frame: 0.5)
    let path =
        Array(repeating: up, count: 14) + Array(repeating: glide, count: 2)
        + Array(repeating: down, count: 14) + Array(repeating: glide, count: 6)

    func dolphin(type: String, x: Double, y: Double, startIndex: Int, color: CellColor, dieOffscreen: Bool) -> Entity {
        let entity = Entity(
            type: type,
            sprite: Sprite(
                shapes: DolphinArt.shapes[dir], masks: [DolphinArt.masks[dir]], autoTransparent: true),
            x: x,
            y: y,
            z: Depth.waterGap3,
            defaultColor: color,
            dieOffscreen: dieOffscreen
        )
        entity.path = path
        entity.pathIndex = startIndex
        return entity
    }

    let dolphin3 = dolphin(
        type: "dolphin", x: x - distance * 2, y: 8, startIndex: 0, color: blue, dieOffscreen: false)
    dolphin3.onDeath = startsNextSpecial(c.settings)
    engine.add(dolphin3)

    let dolphin2 = dolphin(
        type: "dolphin_mate", x: x - distance, y: 2, startIndex: 12, color: blueBright, dieOffscreen: false)
    engine.add(dolphin2)

    let dolphin1 = dolphin(
        type: "dolphin_mate", x: x, y: 5, startIndex: 24, color: cyanBright, dieOffscreen: true)
    // The lead dolphin tells the others to die off screen, since they start off screen.
    dolphin1.onDeath = { _, _ in
        dolphin2.dieOffscreen = true
        dolphin3.dieOffscreen = true
    }
    engine.add(dolphin1)
}

// MARK: submarine

/// How many steps the submarine waits on each of its nine periscope frames.
private let submarineFrameDelay = [1, 4, 4, 9, 9, 9, 4, 4, 1]

/// Perl `submarine_callback`: sail on, but stop in the middle of the screen (or at the step that
/// would skip over it) and raise the periscope frame by frame before sailing on.
private func submarineTick(_ entity: Entity, _ engine: Engine, delay: inout Int) {
    let centre = Double(engine.cols) / 2 - 20
    let x = entity.x
    let skipsOverCentre = (x < centre && x + entity.dx > centre) || (x > centre && x + entity.dx < centre)
    var frame = Int(entity.frame)

    if !skipsOverCentre && x != centre {
        entity.x += entity.dx
    } else if frame < submarineFrameDelay.count - 1 {
        if delay < submarineFrameDelay[frame] {
            delay += 1
        } else {
            delay = 0
            frame += 1
        }
    } else {
        entity.x += entity.dx
    }
    entity.frame = Double(frame)
}

/// Perl `add_submarine`.
func addSubmarine(_ c: SpawnContext) {
    let engine = c.engine
    let dir = engine.rng.int(2)
    var x = -40.0
    var speed = 1.0
    if dir == 1 {
        speed *= -1
        x = Double(engine.cols - 2)
    }

    let submarine = Entity(
        type: "submarine",
        sprite: Sprite(
            shapes: SubmarineArt.shapes[dir], masks: [SubmarineArt.masks[dir]], autoTransparent: true),
        x: x,
        y: 6,
        z: Depth.waterGap3,
        dx: speed,
        defaultColor: yellowBright,
        dieOffscreen: true
    )
    var delay = 0
    submarine.onTick = { entity, engine in
        submarineTick(entity, engine, delay: &delay)
    }
    submarine.onDeath = startsNextSpecial(c.settings)
    engine.add(submarine)
}

// MARK: swordfish

/// Perl `add_sword_fish`.
func addSwordfish(_ c: SpawnContext) {
    let engine = c.engine
    let rng = engine.rng
    let dir = rng.int(2)
    var x = -33.0
    var speed = 3.5
    if dir == 1 {
        x = Double(engine.cols - 1)
        speed *= -1
    }
    let maxHeight = 9
    let minHeight = engine.rows - 14
    let y = rng.int(minHeight - maxHeight) + maxHeight
    // Perl calls `rand_color` straight on the mask, so the 4s are random colors, not eyes.
    let colorMask = randomizeFishMask(SwordfishArt.masks[dir], rng: rng)

    let fish = Entity(
        type: "swordfish",
        sprite: Sprite(shapes: [SwordfishArt.shapes[dir]], masks: [colorMask], autoTransparent: true),
        x: x,
        y: Double(y),
        z: Depth.shark,
        dx: speed,
        defaultColor: yellowBright,
        dieOffscreen: true
    )
    fish.onDeath = startsNextSpecial(c.settings)
    engine.add(fish)
}

// MARK: jellyfish

/// Perl `jellyfish_callback`: every so often pick a new vertical drift, turn it around near the
/// waterline and the bottom, then move as usual.
private func jellyfishTick(_ jellyfish: Entity, _ engine: Engine, delay: inout Int) {
    let rng = engine.rng

    if delay <= 0 {
        jellyfish.dy = (rng.double() < 0.5 ? -1 : 1) * (rng.double() * 0.25 + 0.05)
        delay = rng.int(40) + 20
    } else {
        delay -= 1
    }

    // Keep jellyfish from drifting into the title/waterline or bottom area.
    if jellyfish.y <= 7 {
        jellyfish.dy = abs(jellyfish.dy)
        delay = rng.int(20) + 10
    } else if jellyfish.y + Double(jellyfish.height) >= Double(engine.rows - 2) {
        jellyfish.dy = -abs(jellyfish.dy)
        delay = rng.int(20) + 10
    }

    jellyfish.defaultMove()
}

/// Perl `add_jellyfish`.
func addJellyfish(_ c: SpawnContext) {
    let engine = c.engine
    let rng = engine.rng

    let tentacle = rng.int(JellyfishArt.leftTentacles.count)
    let images = JellyfishArt.shapes(
        left: JellyfishArt.leftTentacles[tentacle], right: JellyfishArt.rightTentacles[tentacle])

    let dir = rng.int(2)
    var x = 0.0
    var speed = rng.double() + 0.5
    if dir == 1 {
        speed *= -1
        x = Double(engine.cols - 2)
    }

    let maxHeight = 9
    let minHeight = engine.rows - 10
    let y = rng.int(minHeight - maxHeight) + maxHeight
    let z = rng.int(10) + Depth.fishStart

    let colorMask = randomizeFishMask(JellyfishArt.masks[dir], rng: rng)

    let verticalSpeed = rng.int(2) == 0 ? -0.2 : 0.2
    var delay = rng.int(40) + 20

    let jellyfish = Entity(
        type: "jellyfish",
        sprite: Sprite(shapes: images[dir], masks: [colorMask], autoTransparent: true),
        x: x,
        y: Double(y),
        z: z,
        dx: speed,
        dy: verticalSpeed,
        frameSpeed: 0.2,
        defaultColor: magentaBright,
        dieOffscreen: true
    )
    jellyfish.onTick = { entity, engine in
        jellyfishTick(entity, engine, delay: &delay)
    }
    jellyfish.onDeath = startsNextSpecial(c.settings)
    engine.add(jellyfish)
}
