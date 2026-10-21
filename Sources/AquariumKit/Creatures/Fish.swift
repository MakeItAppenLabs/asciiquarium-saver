// Asciiquarium for macOS — Swift port Copyright (C) 2026 Aaron Mashburn.
// Modified from asciiquarium 1.6, Copyright (C) 2013 Kirk Baucom.
// Licensed under the GNU GPL version 3 or (at your option) any later version; see LICENSE.

import Foundation

/// One fish species: a right-facing and a left-facing picture, each with its color mask.
/// Mask digits: 1 body, 2 dorsal fin, 3 flippers, 4 eye, 5 mouth, 6 tailfin, 7 gills.
public struct FishDesign: Sendable, Equatable {
    public let rightShape: String
    public let rightMask: String
    public let leftShape: String
    public let leftMask: String

    public init(rightShape: String, rightMask: String, leftShape: String, leftMask: String) {
        self.rightShape = rightShape
        self.rightMask = rightMask
        self.leftShape = leftShape
        self.leftMask = leftMask
    }
}

private let cyanBright = CellColor(color: .cyan, bright: true)
private let redBright = CellColor(color: .red, bright: true)

/// Perl `add_all_fish` with the fish amount setting applied: one fish per 350 cells of water, at
/// least one.
public func fishCount(cols: Int, rows: Int, fishAmount: Double) -> Int {
    // the stuff above the water does not count
    let screenSize = (rows - 9) * cols
    let count = (Double(screenSize) * fishAmount / 350).rounded(.down)
    return max(1, Int(count))
}

public func addAllFish(_ c: SpawnContext) {
    let count = fishCount(cols: c.engine.cols, rows: c.engine.rows, fishAmount: c.settings.fishAmount)
    for _ in 0..<count {
        addFish(c)
    }
}

/// Perl `add_fish`: one in four fish is a new design, unless the classic set is chosen.
public func addFish(_ c: SpawnContext) {
    addFishEntity(c, designs: fishDesigns(c))
}

/// The set `add_fish` draws from: `int(rand(12)) > 8` picks the new designs. The classic set
/// never rolls.
func fishDesigns(_ c: SpawnContext) -> [FishDesign] {
    if !c.classic, c.engine.rng.int(12) > 8 {
        return FishArt.new
    }
    return FishArt.old
}

/// Perl `add_fish_entity`.
///
/// Perl keeps shape and mask in one flat list and picks `int(rand($#list / 2))`, an even index
/// being right-facing and an odd one left-facing. That range is half a slot short, so the last
/// left-facing picture comes up half as often as the others. Kept.
private func addFishEntity(_ c: SpawnContext, designs: [FishDesign]) {
    let rng = c.engine.rng
    let pictures = designs.count * 2
    let fishNum = Int(rng.double() * (Double(pictures) - 0.5))
    let design = designs[fishNum / 2]
    let facesLeft = fishNum % 2 == 1

    var speed = rng.double() * 2 + 0.25
    let z = rng.int(Depth.fishEnd - Depth.fishStart) + Depth.fishStart
    let mask = randomizeFishMask(
        facesLeft ? design.leftMask : design.rightMask, rng: rng, whitenEyes: true)
    if facesLeft { speed = -speed }

    let fish = Entity(
        type: "fish",
        sprite: Sprite(
            shapes: [facesLeft ? design.leftShape : design.rightShape],
            masks: [mask],
            autoTransparent: true),
        z: z,
        dx: speed,
        isPhysical: true,
        dieOffscreen: true
    )

    let maxHeight = 9
    let minHeight = c.engine.rows - fish.height
    fish.y = Double(rng.int(minHeight - maxHeight) + maxHeight)
    fish.x = facesLeft ? Double(c.engine.cols - 2) : Double(1 - fish.width)

    let settings = c.settings
    fish.onTick = { fish, engine in
        // Perl `fish_callback`
        if engine.rng.int(100) > 97 {
            addBubble(SpawnContext(engine: engine, settings: settings), from: fish)
        }
        fish.defaultMove()
    }
    fish.onCollision = { fish, colliders, engine in
        fishCollision(SpawnContext(engine: engine, settings: settings), fish: fish, colliders: colliders)
    }
    fish.onDeath = { _, engine in
        addFish(SpawnContext(engine: engine, settings: settings))
    }
    c.engine.add(fish)
}

/// Perl `fish_collision`: the colliders are checked in order and the first `teeth` or `hook_point`
/// decides. A fish that meets teeth is eaten and leaves a splat; one that meets a hook point is
/// caught and reeled in with the hook.
func fishCollision(_ c: SpawnContext, fish: Entity, colliders: [Entity]) {
    for other in colliders {
        switch other.type {
        case "teeth":
            addSplat(
                c,
                x: Int(other.x.rounded(.down)),
                y: Int(other.y.rounded(.down)),
                z: other.z)
            c.engine.kill(fish)
            return
        case "hook_point":
            retract(other)
            retract(fish)
            // get the hook and line
            if let hook = c.engine.entities(ofType: "fishhook").first { retract(hook) }
            if let line = c.engine.entities(ofType: "fishline").first { retract(line) }
            return
        default:
            continue
        }
    }
}

/// Perl `add_bubble`: an air bubble rises from a fish's mouth and pops at the water line.
public func addBubble(_ c: SpawnContext, from fish: Entity) {
    var x = fish.x
    // moving right
    if fish.dx > 0 {
        x += Double(fish.width)
    }
    let y = fish.y + Double(fish.height / 2)
    // bubble always goes on top of the fish
    let z = fish.z - 1

    let bubble = Entity(
        type: "bubble",
        sprite: Sprite(shapes: [".", "o", "O", "O", "O"], autoTransparent: false),
        x: x,
        y: y,
        z: z,
        dy: -1,
        frameSpeed: 0.1,
        defaultColor: cyanBright,
        isPhysical: true,
        dieOffscreen: true
    )
    bubble.onCollision = { bubble, colliders, engine in
        // Perl `bubble_collision`
        if colliders.contains(where: { $0.type == "waterline" }) {
            engine.kill(bubble)
        }
    }
    c.engine.add(bubble)
}

/// Perl `add_splat`: what is left of an eaten fish, centered on the `teeth` that ate it.
public func addSplat(_ c: SpawnContext, x: Int, y: Int, z: Int) {
    c.engine.add(Entity(
        sprite: Sprite(shapes: SplatArt.shapes, autoTransparent: false, transparent: " "),
        x: Double(x - 4),
        y: Double(y - 2),
        z: z - 2,
        frameSpeed: 0.25,
        defaultColor: redBright,
        dieAfterCycles: 15
    ))
}

enum SplatArt {
    /// `@splat_image`: four frames.
    static let shapes: [String] = [
        #"""


   .
  ***
   '


"""#,
        #"""


 ",*;`
 "*,**
 *"'~'


"""#,
        #"""

  , ,
 " ","'
 *" *'"
  " ; .


"""#,
        #"""

* ' , ' `
' ` * . '
 ' `' ",'
* ' " * .
" * ', '

"""#,
    ]
}

/// Fish art, copied from Perl asciiquarium 1.6 with its `q{}` escapes resolved: `\\` is one
/// backslash, `\{` and `\}` are braces. `?` marks a transparent cell.
public enum FishArt {
    /// The eight fish of Asciiquarium 1.0 (`add_old_fish`).
    public static let old: [FishDesign] = [
        FishDesign(
            rightShape: #"""

       \
     ...\..,
\??/'       \
 >=     (  ' >
/??\      / /
    `"'"'/''

"""#,
            rightMask: #"""

       2
     1112111
6  11       1
 66     7  4 5
6  1      3 1
    11111311

"""#,
            leftShape: #"""

      /
  ,../...
 /       '\??/
< '  )     =<
 \ \      /??\
  `'\'"'"'

"""#,
            leftMask: #"""

      2
  1112111
 1       11  6
5 4  7     66
 1 3      1  6
  11311111

"""#
        ),
        FishDesign(
            rightShape: #"""

    \
\?/--\
>=  (o>
/?\__/
    /

"""#,
            rightMask: #"""

    2
6 1111
66  745
6 1111
    3

"""#,
            leftShape: #"""

  /
 /--\?/
<o)  =<
 \__/?\
  \

"""#,
            leftMask: #"""

  2
 1111 6
547  66
 1111 6
  3

"""#
        ),
        FishDesign(
            rightShape: #"""

       \:.
\;,???,;\\\,,
  \\\;;:::::::o
  ///;;::::::::<
 /;`?``/////``

"""#,
            rightMask: #"""

       222
666   1122211
  6661111111114
  66611111111115
 666 113333311

"""#,
            leftShape: #"""

      .:/
   ,,///;,???,;/
 o:::::::;;///
>::::::::;;\\\
  ''\\\\\''?';\

"""#,
            leftMask: #"""

      222
   1122211   666
 4111111111666
51111111111666
  113333311 666

"""#
        ),
        FishDesign(
            rightShape: #"""

  __
><_'>
   '

"""#,
            rightMask: #"""

  11
61145
   3

"""#,
            leftShape: #"""

 __
<'_><
 `

"""#,
            leftMask: #"""

 11
54116
 3

"""#
        ),
        FishDesign(
            rightShape: #"""

   ..\,
>='   ('>
  '''/''

"""#,
            rightMask: #"""

   1121
661   745
  111311

"""#,
            leftShape: #"""

  ,/..
<')   `=<
 ``\```

"""#,
            leftMask: #"""

  1211
547   166
 113111

"""#
        ),
        FishDesign(
            rightShape: #"""

   \
  / \
>=_('>
  \_/
   /

"""#,
            rightMask: #"""

   2
  1 1
661745
  111
   3

"""#,
            leftShape: #"""

  /
 / \
<')_=<
 \_/
  \

"""#,
            leftMask: #"""

  2
 1 1
547166
 111
  3

"""#
        ),
        FishDesign(
            rightShape: #"""

  ,\
>=('>
  '/

"""#,
            rightMask: #"""

  12
66745
  13

"""#,
            leftShape: #"""

 /,
<')=<
 \`

"""#,
            leftMask: #"""

 21
54766
 31

"""#
        ),
        FishDesign(
            rightShape: #"""

  __
\/ o\
/\__/

"""#,
            rightMask: #"""

  11
61 41
61111

"""#,
            leftShape: #"""

 __
/o \/
\__/\

"""#,
            leftMask: #"""

 11
14 16
11116

"""#
        ),
    ]

    /// The four fish added in 1.2 (`add_new_fish`).
    public static let new: [FishDesign] = [
        FishDesign(
            rightShape: #"""

   \
  / \
>=_('>
  \_/
   /

"""#,
            rightMask: #"""

   1
  1 1
663745
  111
   3

"""#,
            leftShape: #"""

  /
 / \
<')_=<
 \_/
  \

"""#,
            leftMask: #"""

  2
 111
547366
 111
  3

"""#
        ),
        FishDesign(
            rightShape: #"""

     ,
     }\
\??.'  `\
}}<   ( 6>
/??`,  .'
     }/
     '

"""#,
            rightMask: #"""

     2
     22
6  11  11
661   7 45
6  11  11
     33
     3

"""#,
            leftShape: #"""

    ,
   /{
 /'  `.??/
<6 )   >{{
 `.  ,'??\
   \{
    `

"""#,
            leftMask: #"""

    2
   22
 11  11  6
54 7   166
 11  11  6
   33
    3

"""#
        ),
        FishDesign(
            rightShape: #"""

            \'`.
             )  \
(`.??????_.-`' ' '`-.
 \ `.??.`        (o) \_
  >  ><     (((       (
 / .`??`._      /_|  /'
(.`???????`-. _  _.-`
            /__/'


"""#,
            rightMask: #"""

            1111
             1  1
111      11111 1 1111
 1 11  11        141 11
  1  11     777       5
 1 11  111      333  11
111       111 1  1111
            11111


"""#,
            leftShape: #"""

       .'`/
      /  (
  .-'` ` `'-._??????.')
_/ (o)        '.??.' /
)       )))     ><  <
`\  |_\      _.'??'. \
  '-._  _ .-'???????'.)
      `\__\

"""#,
            leftMask: #"""

       1111
      1  1
  1111 1 11111      111
11 141        11  11 1
5       777     11  1
11  333      111  11 1
  1111  1 111       111
      11111

"""#
        ),
        FishDesign(
            rightShape: #"""

       ,--,_
__????_\.---'-.
\ '.-"     // o\
/_.'-._    \\  /
       `"--(/"`

"""#,
            rightMask: #"""

       22222
66    121111211
6 6111     77 41
6661111    77  1
       11113311

"""#,
            leftShape: #"""

    _,--,
 .-'---./_????__
/o \\     "-.' /
\  //    _.-'._\
 `"\)--"`

"""#,
            leftMask: #"""

    22222
 112111121    66
14 77     1116 6
1  77    1111666
 11331111

"""#
        ),
    ]
}
