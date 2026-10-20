import Testing
@testable import AquariumKit

@Suite struct ArtInvariantTests {
    private static let allDesigns: [(name: String, designs: [FishDesign])] = [
        ("old", FishArt.old), ("new", FishArt.new),
    ]

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

    @Test func designCounts() {
        #expect(FishArt.old.count == 8)
        #expect(FishArt.new.count == 4)
    }

    @Test func masksMatchTheirShapes() {
        for (name, designs) in Self.allDesigns {
            for (index, design) in designs.enumerated() {
                for (shape, mask, side) in [
                    (design.rightShape, design.rightMask, "right"),
                    (design.leftShape, design.leftMask, "left"),
                ] {
                    let shapeRows = lines(shape)
                    let maskRows = lines(mask)
                    #expect(shapeRows.count == maskRows.count, "\(name) \(index) \(side): line count")
                    for (s, m) in zip(shapeRows, maskRows) {
                        #expect(m.count <= s.count, "\(name) \(index) \(side): mask line longer than shape line")
                    }
                }
            }
        }
    }

    @Test func leftAndRightShapesAreTheSameSize() {
        for (name, designs) in Self.allDesigns {
            for (index, design) in designs.enumerated() {
                let right = size(design.rightShape)
                let left = size(design.leftShape)
                #expect(right.width == left.width, "\(name) \(index): width")
                #expect(right.height == left.height, "\(name) \(index): height")
            }
        }
    }

    @Test func everyFishHasAnEye() {
        // Digit 4 is the eye, and add_fish turns it white; a design without one would never show it.
        for (name, designs) in Self.allDesigns {
            for (index, design) in designs.enumerated() {
                #expect(design.rightMask.contains("4"), "\(name) \(index) right")
                #expect(design.leftMask.contains("4"), "\(name) \(index) left")
            }
        }
    }

    /// Perl's `q{}` turns `\\` into one backslash and `\{`, `\}` into braces. These rows are the
    /// ones a mangled escape would change.
    @Test func backslashesSurvive() {
        // Old fish 0: lone backslashes at the end of a row.
        #expect(lines(FishArt.old[0].rightShape)[2] == #"\??/'       \"#)
        // Old fish 2: perl's five backslashes in `\\\\\,,` are three.
        #expect(lines(FishArt.old[2].rightShape)[1] == #"\;,???,;\\\,,"#)
        #expect(lines(FishArt.old[2].rightShape)[2] == #"  \\\;;:::::::o"#)
        #expect(lines(FishArt.old[2].leftShape)[3] == #">::::::::;;\\\"#)
        // New fish 0: `\\_/` is `\_/`, and `\\` alone is one backslash.
        #expect(lines(FishArt.old[5].rightShape)[3] == #"  \_/"#)
        #expect(lines(FishArt.new[0].rightShape)[0] == #"   \"#)
        #expect(lines(FishArt.new[0].rightShape)[3] == #"  \_/"#)
        // New fish 1: `\}\\` is `}\`, and `\}\}<` is `}}<`.
        #expect(lines(FishArt.new[1].rightShape)[1] == #"     }\"#)
        #expect(lines(FishArt.new[1].rightShape)[2] == #"\??.'  `\"#)
        #expect(lines(FishArt.new[1].rightShape)[3] == "}}<   ( 6>")
        #expect(lines(FishArt.new[1].leftShape)[1] == #"   /{"#)
        #expect(lines(FishArt.new[1].leftShape)[3] == "<6 )   >{{")
    }
}
