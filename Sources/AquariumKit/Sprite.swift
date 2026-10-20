/// One drawn character of a sprite. A `nil` color means "use the entity's default color".
public struct SpriteCell: Hashable, Sendable {
    public var char: Character
    public var color: CellColor?

    public init(char: Character, color: CellColor?) {
        self.char = char
        self.color = color
    }
}

/// One animation frame. A `nil` cell is transparent; `" "` is an opaque blank.
/// Every row has exactly `width` entries (short lines are padded with transparent cells).
public struct Frame: Sendable {
    public let width: Int
    public let height: Int
    public let cells: [[SpriteCell?]]

    public init(width: Int, height: Int, cells: [[SpriteCell?]]) {
        self.width = width
        self.height = height
        self.cells = cells
    }
}

/// ASCII art parsed the way Term::Animation 2.6 does (`_auto_trans`, `_build_shape`, `_build_mask`).
public struct Sprite: Sendable {
    public let frames: [Frame]

    /// Entity-wide size: Perl's `width()` / `height()` are the maximum over all frames.
    public var width: Int { frames.map(\.width).max() ?? 0 }
    public var height: Int { frames.map(\.height).max() ?? 0 }

    /// - Parameters:
    ///   - shapes: one string per frame. One leading newline is dropped.
    ///   - masks: color masks laid out like the shapes. Fewer masks than frames repeat the way Perl does,
    ///     so a single mask colors every frame.
    ///   - autoTransparent: turn whitespace before the first non-whitespace character of each line
    ///     into transparent cells. `?` is always transparent.
    public init(shapes: [String], masks: [String] = [], autoTransparent: Bool = true) {
        let shapeRows = shapes.map { Sprite.rows(of: $0, autoTransparent: autoTransparent) }

        // Term::Animation::Entity::_build_mask: pad a short mask list by re-pushing mask[0], mask[1], ...
        var maskRows: [[[Character]]?] = masks.map { Sprite.rows(of: $0, autoTransparent: false) }
        if maskRows.count < shapeRows.count {
            let have = maskRows.count
            for k in 0..<(shapeRows.count - have) {
                maskRows.append(k < maskRows.count ? maskRows[k] : nil)
            }
        }

        frames = shapeRows.enumerated().map { index, rows in
            let width = rows.map(\.count).max() ?? 0
            let mask = maskRows[index]
            let cells: [[SpriteCell?]] = rows.enumerated().map { y, row in
                (0..<width).map { x -> SpriteCell? in
                    guard x < row.count, row[x] != Sprite.transparent else { return nil }
                    var color: CellColor?
                    if let mask, y < mask.count, x < mask[y].count {
                        color = maskColor(mask[y][x])
                    }
                    return SpriteCell(char: row[x], color: color)
                }
            }
            return Frame(width: width, height: rows.count, cells: cells)
        }
    }

    private static let transparent: Character = "?"

    /// Perl `\s`: space, \t, \n, \r, \f, \v.
    private static func isPerlSpace(_ ch: Character) -> Bool {
        ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\u{0C}" || ch == "\u{0B}"
    }

    /// `_trans_fill_string` + `_build_shape` for one string: rows of characters.
    /// Splitting works on unicode scalars so that "\r\n" is two characters, as in Perl.
    private static func rows(of text: String, autoTransparent: Bool) -> [[Character]] {
        var lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Array($0.map(Character.init)) }
        // Perl's split drops trailing empty fields (and yields nothing for an empty string).
        while let last = lines.last, last.isEmpty { lines.removeLast() }

        if autoTransparent {
            lines = lines.map { line in
                let lead = line.prefix(while: isPerlSpace).count
                return Array(repeating: transparent, count: lead) + line.dropFirst(lead)
            }
        }
        // "strip an empty line from the top, for convenience" (only one, and after auto_trans).
        if text.hasPrefix("\n"), !lines.isEmpty { lines.removeFirst() }
        return lines
    }
}

/// Term::Animation color mask letter: `r g y b m c w k` are normal, uppercase is bright (bold).
/// Anything else (digits, space, `?`, ...) has no color of its own and yields `nil`.
public func maskColor(_ ch: Character) -> CellColor? {
    let color: ANSIColor
    switch ch {
    case "k", "K": color = .black
    case "r", "R": color = .red
    case "g", "G": color = .green
    case "y", "Y": color = .yellow
    case "b", "B": color = .blue
    case "m", "M": color = .magenta
    case "c", "C": color = .cyan
    case "w", "W": color = .white
    default: return nil
    }
    return CellColor(color: color, bright: ch.isUppercase)
}

/// Port of Perl asciiquarium's `rand_color`: each digit 1...9 is replaced everywhere in the mask by one
/// random color letter, drawing once per digit in order whether or not it occurs.
///
/// Perl indexes the list with `int(rand($#colors))`, so the last entry (`M`) can never be chosen. That
/// is kept on purpose.
///
/// - Parameter whitenEyes: also apply `add_fish`'s `s/4/W/` first. Only the eight ordinary fish do this;
///   the big fish, swordfish and jellyfish pass their masks straight to `rand_color`, so their 4s are
///   random colors. Perl still draws a color for digit 4 either way.
public func randomizeFishMask(_ mask: String, rng: RandomSource, whitenEyes: Bool = false) -> String {
    let colors: [Character] = ["c", "C", "r", "R", "y", "Y", "b", "B", "g", "G", "m", "M"]
    var result = Array(mask)
    if whitenEyes { result = result.map { $0 == "4" ? "W" : $0 } }
    for digit in "123456789" {
        let color = colors[rng.int(colors.count - 1)]
        result = result.map { $0 == digit ? color : $0 }
    }
    return String(result)
}
