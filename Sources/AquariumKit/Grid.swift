/// The eight ANSI terminal colors Perl's `Curses` / Term::Animation color masks use.
public enum ANSIColor: UInt8, CaseIterable, Sendable {
    case black, red, green, yellow, blue, magenta, cyan, white
}

/// A foreground color: one of the eight ANSI colors, normal or bright (bold).
public struct CellColor: Hashable, Sendable {
    public var color: ANSIColor
    public var bright: Bool

    public init(color: ANSIColor, bright: Bool) {
        self.color = color
        self.bright = bright
    }
}

/// One drawn character cell. A background cell is represented by `nil` in the grid, not by a `Cell`.
public struct Cell: Hashable, Sendable {
    public var char: Character
    public var color: CellColor

    public init(char: Character, color: CellColor) {
        self.char = char
        self.color = color
    }
}

/// A fixed-size character grid. `nil` means background.
public struct Grid: Sendable {
    public let cols: Int
    public let rows: Int
    private var cells: [Cell?]

    public init(cols: Int, rows: Int) {
        let cols = max(0, cols)
        let rows = max(0, rows)
        self.cols = cols
        self.rows = rows
        self.cells = Array(repeating: nil, count: cols * rows)
    }

    /// The cell at (x, y), or `nil` for background and for any out-of-range position.
    public subscript(x: Int, y: Int) -> Cell? {
        guard x >= 0, x < cols, y >= 0, y < rows else { return nil }
        return cells[y * cols + x]
    }

    /// Writes `cell` at (x, y). Positions outside the grid are silently ignored.
    public mutating func put(_ cell: Cell?, x: Int, y: Int) {
        guard x >= 0, x < cols, y >= 0, y < rows else { return }
        cells[y * cols + x] = cell
    }

    /// Rows joined by `\n`, with background drawn as a space.
    public func text() -> String {
        var lines: [String] = []
        lines.reserveCapacity(rows)
        for y in 0..<rows {
            var line = ""
            line.reserveCapacity(cols)
            for x in 0..<cols {
                line.append(cells[y * cols + x]?.char ?? " ")
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
