/// The water line, castle and seaweed: the fixed scenery of the aquarium.

private let cyan = CellColor(color: .cyan, bright: false)
private let green = CellColor(color: .green, bright: false)
private let white = CellColor(color: .white, bright: false)

/// Perl `add_environment`: four water line segments tiled across the screen.
public func addEnvironment(_ c: SpawnContext) {
    let segments = SceneryArt.waterLineSegments
    // tile the segments so they stretch across the screen
    let segmentSize = segments[0].count
    let segmentRepeat = c.engine.cols / segmentSize + 1

    for (i, segment) in segments.enumerated() {
        c.engine.add(Entity(
            type: "waterline",
            sprite: Sprite(
                shapes: [String(repeating: segment, count: segmentRepeat)],
                autoTransparent: false),
            x: 0,
            y: Double(i + 5),
            z: Depth.waterLine(i),
            defaultColor: cyan,
            depth: 22,
            isPhysical: true
        ))
    }
}

/// Perl `add_castle`.
public func addCastle(_ c: SpawnContext) {
    c.engine.add(Entity(
        sprite: Sprite(shapes: SceneryArt.castleShapes, masks: SceneryArt.castleMasks, autoTransparent: true),
        x: Double(c.engine.cols - 32),
        y: Double(c.engine.rows - 13),
        z: Depth.castle,
        frameSpeed: 0.1,
        defaultColor: white
    ))
}

/// Perl `add_all_seaweed`: one plant per 15 columns.
public func addAllSeaweed(_ c: SpawnContext) {
    for _ in 0..<(c.engine.cols / 15) {
        addSeaweed(c)
    }
}

/// Perl `add_seaweed`. The plant lives 8 to 12 minutes and then plants a replacement.
func addSeaweed(_ c: SpawnContext) {
    let rng = c.engine.rng
    // Two frames, each holding every other stroke of the stem.
    var frames = ["", ""]
    let height = rng.int(4) + 3
    for i in 1...height {
        let leftSide = i % 2
        let rightSide = 1 - leftSide
        frames[leftSide] += "(\n"
        frames[rightSide] += " )\n"
    }
    let x = rng.int(c.engine.cols - 2) + 1
    let y = c.engine.rows - height
    let animSpeed = rng.double() * 0.05 + 0.25
    let lifetimeSeconds = rng.int(4 * 60) + 8 * 60
    let settings = c.settings

    let weed = Entity(
        sprite: Sprite(shapes: frames, autoTransparent: false),
        x: Double(x),
        y: Double(y),
        z: Depth.seaweed,
        frameSpeed: animSpeed,
        defaultColor: green,
        dieAfterFrames: lifetimeSeconds * 10
    )
    weed.onDeath = { _, engine in
        addSeaweed(SpawnContext(engine: engine, settings: settings))
    }
    c.engine.add(weed)
}

enum SceneryArt {
    /// `@water_line_segment`.
    static let waterLineSegments: [String] = [
        #"""
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""#,
        #"""
^^^^ ^^^  ^^^   ^^^    ^^^^      
"""#,
        #"""
^^^^      ^^^^     ^^^    ^^     
"""#,
        #"""
^^      ^^^^      ^^^    ^^^^^^  
"""#,
    ]

    /// `@castle_image`: six frames, the door opening and closing.
    static let castleShapes: [String] = [
        #"""

               T~~
               |
              /^\
             /   \
 _   _   _  /     \  _   _   _
[ ]_[ ]_[ ]/ _   _ \[ ]_[ ]_[ ]
|_=__-_ =_|_[ ]_[ ]_|_=-___-__|
 | _- =  | =_ = _    |= _=   |
 |= -[]  |- = _ =    |_-=_[] |
 | =_    |= - ___    | =_ =  |
 |=  []- |-  /| |\   |=_ =[] |
 |- =_   | =| | | |  |- = -  |
 |_______|__|_|_|_|__|_______|

"""#,
        #"""

               T~~
               |
              /^\
             /   \
 _   _   _  /     \  _   _   _
[ ]_[ ]_[ ]/ _   _ \[ ]_[ ]_[ ]
|_=__-_ =_|_[ ]_[ ]_|_=-___-__|
 | _- =  | =_ = _    |= _=   |
 |= -[]  |- = _ =    |_-=_[] |
 | =_    |= - ___    | =_ =  |
 |=  []- |-  /| |\   |=_ =[] |
 |- =_   | =|_|_|_|  |- = -  |
 |_______|__|     |__|_______|

"""#,
        #"""

               T~~
               |
              /^\
             /   \
 _   _   _  /     \  _   _   _
[ ]_[ ]_[ ]/ _   _ \[ ]_[ ]_[ ]
|_=__-_ =_|_[ ]_[ ]_|_=-___-__|
 | _- =  | =_ = _    |= _=   |
 |= -[]  |- = _ =    |_-=_[] |
 | =_    |= - ___    | =_ =  |
 |=  []- |-  /|_|\   |=_ =[] |
 |- =_   | =|     |  |- = -  |
 |_______|__|     |__|_______|

"""#,
        #"""

               T~~
               |
              /^\
             /   \
 _   _   _  /     \  _   _   _
[ ]_[ ]_[ ]/ _   _ \[ ]_[ ]_[ ]
|_=__-_ =_|_[ ]_[ ]_|_=-___-__|
 | _- =  | =_ = _    |= _=   |
 |= -[]  |- = _ =    |_-=_[] |
 | =_    |= - ___    | =_ =  |
 |=  []- |-  /   \   |=_ =[] |
 |- =_   | =|     |  |- = -  |
 |_______|__|     |__|_______|

"""#,
        #"""

               T~~
               |
              /^\
             /   \
 _   _   _  /     \  _   _   _
[ ]_[ ]_[ ]/ _   _ \[ ]_[ ]_[ ]
|_=__-_ =_|_[ ]_[ ]_|_=-___-__|
 | _- =  | =_ = _    |= _=   |
 |= -[]  |- = _ =    |_-=_[] |
 | =_    |= - ___    | =_ =  |
 |=  []- |-  /|_|\   |=_ =[] |
 |- =_   | =|     |  |- = -  |
 |_______|__|     |__|_______|

"""#,
        #"""

               T~~
               |
              /^\
             /   \
 _   _   _  /     \  _   _   _
[ ]_[ ]_[ ]/ _   _ \[ ]_[ ]_[ ]
|_=__-_ =_|_[ ]_[ ]_|_=-___-__|
 | _- =  | =_ = _    |= _=   |
 |= -[]  |- = _ =    |_-=_[] |
 | =_    |= - ___    | =_ =  |
 |=  []- |-  /| |\   |=_ =[] |
 |- =_   | =|_|_|_|  |- = -  |
 |_______|__|     |__|_______|

"""#,
    ]

    /// `@castle_mask`, one per frame.
    static let castleMasks: [String] = [
        #"""

                GG

              rrr
             r   r
            r     r
           r       r



              yyy
             yy yy
            y y y y
            yyyyyyy

"""#,
        #"""

                GG

              rrr
             r   r
            r     r
           r       r



              yyy
             yy yy
            yyyyyyy
            y     y

"""#,
        #"""

                GG

              rrr
             r   r
            r     r
           r       r



              yyy
             yyyyy
            y     y
            y     y

"""#,
        #"""

                GG

              rrr
             r   r
            r     r
           r       r



              yyy
             y   y
            y     y
            y     y

"""#,
        #"""

                GG

              rrr
             r   r
            r     r
           r       r



              yyy
             yyyyy
            y     y
            y     y

"""#,
        #"""

                GG

              rrr
             r   r
            r     r
           r       r



              yyy
             yy yy
            yyyyyyy
            y     y

"""#,
    ]
}
