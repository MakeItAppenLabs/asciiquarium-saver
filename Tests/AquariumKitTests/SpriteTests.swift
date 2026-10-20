import Testing
@testable import AquariumKit

@Suite struct SpriteTests {
    private func cell(_ sprite: Sprite, frame: Int = 0, row: Int = 0, col: Int) -> SpriteCell? {
        sprite.frames[frame].cells[row][col]
    }

    // MARK: shape rules (Term::Animation 2.6 auto_trans / _build_shape)

    @Test func leadingSpacesTransparent() {
        let sprite = Sprite(shapes: ["\n  ><>\n"])
        #expect(sprite.frames[0].width == 5)
        #expect(sprite.frames[0].height == 1)
        #expect(cell(sprite, col: 0) == nil)
        #expect(cell(sprite, col: 1) == nil)
        #expect(cell(sprite, col: 2) == SpriteCell(char: ">", color: nil))
    }

    @Test func questionMarkTransparent() {
        let sprite = Sprite(shapes: ["a?b"])
        #expect(cell(sprite, col: 0) == SpriteCell(char: "a", color: nil))
        #expect(cell(sprite, col: 1) == nil)
        #expect(cell(sprite, col: 2) == SpriteCell(char: "b", color: nil))
    }

    @Test func innerSpaceOpaque() {
        let sprite = Sprite(shapes: ["a b"])
        #expect(cell(sprite, col: 1) == SpriteCell(char: " ", color: nil))
    }

    @Test func questionMarkTransparentWithoutAutoTransparent() {
        let sprite = Sprite(shapes: ["?a"], autoTransparent: false)
        #expect(cell(sprite, col: 0) == nil)
    }

    @Test func leadingSpacesOpaqueWithoutAutoTransparent() {
        let sprite = Sprite(shapes: [" a"], autoTransparent: false)
        #expect(cell(sprite, col: 0) == SpriteCell(char: " ", color: nil))
    }

    @Test func onlyOneLeadingNewlineDropped() {
        let sprite = Sprite(shapes: ["\n\nab"])
        #expect(sprite.frames[0].height == 2)
        #expect(sprite.frames[0].cells[0].count == 2)
        #expect(sprite.frames[0].cells[0].allSatisfy { $0 == nil })
        #expect(sprite.frames[0].cells[1][0] == SpriteCell(char: "a", color: nil))
    }

    @Test func trailingBlankLinesDropped() {
        let sprite = Sprite(shapes: ["ab\n\n\n"])
        #expect(sprite.frames[0].height == 1)
    }

    @Test func whitespaceOnlyLineBecomesTransparent() {
        let sprite = Sprite(shapes: ["ab\n   \ncd"])
        #expect(sprite.frames[0].height == 3)
        #expect(sprite.frames[0].cells[1].allSatisfy { $0 == nil })
    }

    @Test func widthIsLongestLineAndShortLinesPadTransparent() {
        let sprite = Sprite(shapes: ["abcd\nx"])
        let frame = sprite.frames[0]
        #expect(frame.width == 4)
        #expect(frame.height == 2)
        #expect(frame.cells.allSatisfy { $0.count == 4 })
        #expect(frame.cells[1][0] == SpriteCell(char: "x", color: nil))
        #expect(frame.cells[1][1] == nil)
        #expect(frame.cells[1][3] == nil)
    }

    @Test func spriteSizeIsLargestFrame() {
        let sprite = Sprite(shapes: ["ab\ncd", "xyz"])
        #expect(sprite.width == 3)
        #expect(sprite.height == 2)
    }

    @Test func backslashesSurvive() {
        let sprite = Sprite(shapes: [#"\\_/"#])
        #expect(sprite.frames[0].width == 4)
        #expect(cell(sprite, col: 0) == SpriteCell(char: "\\", color: nil))
        #expect(cell(sprite, col: 1) == SpriteCell(char: "\\", color: nil))
    }

    // MARK: color masks

    @Test func maskApplied() {
        let sprite = Sprite(shapes: ["ab"], masks: ["rB"])
        #expect(cell(sprite, col: 0)?.color == CellColor(color: .red, bright: false))
        #expect(cell(sprite, col: 1)?.color == CellColor(color: .blue, bright: true))
    }

    @Test func singleMaskAllFrames() {
        let sprite = Sprite(shapes: ["ab", "cd"], masks: ["gY"])
        for frame in 0..<2 {
            #expect(cell(sprite, frame: frame, col: 0)?.color == CellColor(color: .green, bright: false))
            #expect(cell(sprite, frame: frame, col: 1)?.color == CellColor(color: .yellow, bright: true))
        }
    }

    @Test func fewerMasksThanFramesRepeatLikePerl() {
        let sprite = Sprite(shapes: ["a", "a", "a", "a"], masks: ["r", "g"])
        let colors = (0..<4).map { cell(sprite, frame: $0, col: 0)?.color?.color }
        #expect(colors == [.red, .green, .red, .green])
    }

    @Test func perFrameMasks() {
        let sprite = Sprite(shapes: ["a", "a"], masks: ["r", "c"])
        #expect(cell(sprite, frame: 0, col: 0)?.color?.color == .red)
        #expect(cell(sprite, frame: 1, col: 0)?.color?.color == .cyan)
    }

    @Test func maskUsesSamePositionsAsShapeIncludingLeadingNewline() {
        let sprite = Sprite(shapes: ["\n  ab\n"], masks: ["\n  rg\n"])
        #expect(cell(sprite, col: 2)?.color == CellColor(color: .red, bright: false))
        #expect(cell(sprite, col: 3)?.color == CellColor(color: .green, bright: false))
    }

    @Test func maskSpaceMissingAndInvalidMeanDefaultColor() {
        let sprite = Sprite(shapes: ["abc"], masks: [" 1"])
        #expect(cell(sprite, col: 0)?.color == nil)
        #expect(cell(sprite, col: 1)?.color == nil)
        #expect(cell(sprite, col: 2)?.color == nil)
    }

    @Test func noMaskMeansDefaultColor() {
        let sprite = Sprite(shapes: ["ab"])
        #expect(cell(sprite, col: 0)?.color == nil)
    }

    @Test func maskColorLetters() {
        let expected: [(Character, ANSIColor)] = [
            ("r", .red), ("g", .green), ("y", .yellow), ("b", .blue),
            ("m", .magenta), ("c", .cyan), ("w", .white), ("k", .black),
        ]
        for (letter, color) in expected {
            #expect(maskColor(letter) == CellColor(color: color, bright: false))
            let upper = Character(letter.uppercased())
            #expect(maskColor(upper) == CellColor(color: color, bright: true))
        }
        for other in ["1", " ", "?", "z", "x"] as [Character] {
            #expect(maskColor(other) == nil)
        }
    }

    // MARK: rand_color port

    private let perlColors: Set<Character> = ["c", "C", "r", "R", "y", "Y", "b", "B", "g", "G", "m", "M"]

    @Test func randomizeFishMaskReplacesDigitsWithPerlColors() {
        let mask = "123456789 x\n99"
        let out = randomizeFishMask(mask, rng: RandomSource(seed: 7))
        #expect(out.count == mask.count)
        #expect(Array(out)[9...11] == [" ", "x", "\n"])
        for ch in out where ch != " " && ch != "\n" && ch != "x" {
            #expect(perlColors.contains(ch))
        }
        // The same digit gets the same replacement everywhere.
        let tail = Array(out.suffix(2))
        #expect(tail[0] == tail[1])
        #expect(tail[0] == Array(out)[8])
    }

    @Test func randomizeFishMaskLeavesLettersAndLayoutAlone() {
        let out = randomizeFishMask("W r\n1 K", rng: RandomSource(seed: 3))
        let chars = Array(out)
        #expect(chars[0] == "W")
        #expect(chars[1] == " ")
        #expect(chars[2] == "r")
        #expect(chars[3] == "\n")
        #expect(chars[5] == " ")
        #expect(chars[6] == "K")
    }

    @Test func randomizeFishMaskEyeWhite() {
        // add_fish does s/4/W/ before rand_color; rand_color itself does not.
        let out = randomizeFishMask("1234", rng: RandomSource(seed: 11), whitenEyes: true)
        let chars = Array(out)
        #expect(chars.count == 4)
        #expect(chars[3] == "W")
        for ch in chars.prefix(3) { #expect(perlColors.contains(ch)) }
    }

    @Test func randomizeFishMaskTreatsFourAsAnyOtherDigitByDefault() {
        // Perl's swordfish mask goes straight to rand_color, so its 4s are random colors.
        for seed in 0..<50 as Range<UInt64> {
            let out = randomizeFishMask("4", rng: RandomSource(seed: seed))
            #expect(perlColors.contains(Array(out)[0]))
        }
    }

    @Test func randomizeFishMaskNeverPicksLastListEntry() {
        // Perl indexes with int(rand($#colors)), so 'M' (index 11) is unreachable.
        var seen: Set<Character> = []
        let rng = RandomSource(seed: 1)
        for _ in 0..<400 {
            seen.formUnion(randomizeFishMask("123456789", rng: rng))
        }
        #expect(!seen.contains("M"))
        #expect(seen == perlColors.subtracting(["M"]))
    }

    @Test func randomizeFishMaskDrawsOncePerDigitInOrder() {
        // Perl draws for digits 1...9 whether or not the digit appears.
        let rng = RandomSource(seed: 99)
        let reference = RandomSource(seed: 99)
        let order = ["c", "C", "r", "R", "y", "Y", "b", "B", "g", "G", "m"] as [Character]
        let draws = (0..<9).map { _ in order[reference.int(11)] }
        let out = randomizeFishMask("5 2", rng: rng)
        #expect(Array(out) == [draws[4], " ", draws[1]])
        #expect(rng.int(1000) == reference.int(1000))
    }
}
