import CoreGraphics

/// How a character grid sits inside a view: grid size, where it starts, and the size of one cell.
public struct GridLayout: Equatable, Sendable {
    public var cols: Int
    public var rows: Int
    public var origin: CGPoint
    public var cellSize: CGSize

    public init(cols: Int, rows: Int, origin: CGPoint, cellSize: CGSize) {
        self.cols = cols
        self.rows = rows
        self.origin = origin
        self.cellSize = cellSize
    }

    /// As many whole cells as fit in the view (at least 1 each way), centered.
    public static func fit(viewSize: CGSize, cellSize: CGSize) -> GridLayout {
        let cols = cellSize.width > 0 ? max(1, Int((viewSize.width / cellSize.width).rounded(.down))) : 1
        let rows = cellSize.height > 0 ? max(1, Int((viewSize.height / cellSize.height).rounded(.down))) : 1
        return GridLayout(
            cols: cols,
            rows: rows,
            origin: CGPoint(
                x: (viewSize.width - CGFloat(cols) * cellSize.width) / 2,
                y: (viewSize.height - CGFloat(rows) * cellSize.height) / 2
            ),
            cellSize: cellSize
        )
    }

    /// Keeps the reference grid and shrinks the cells until it fits the view, centered.
    ///
    /// `cellAspect` is cell height divided by cell width. `pointScale` is the new cell width measured
    /// against a reference cell one point wide (and `cellAspect` points tall). A caller whose font has
    /// a cell `w` points wide at point size `s` draws at `s * pointScale / w`.
    public static func preview(
        viewSize: CGSize,
        referenceCols: Int,
        referenceRows: Int,
        cellAspect: CGFloat
    ) -> (layout: GridLayout, pointScale: CGFloat) {
        let cols = max(1, referenceCols)
        let rows = max(1, referenceRows)
        let aspect = cellAspect > 0 ? cellAspect : 1
        let width = max(0, min(viewSize.width / CGFloat(cols), viewSize.height / (CGFloat(rows) * aspect)))
        let cell = CGSize(width: width, height: width * aspect)
        let layout = GridLayout(
            cols: cols,
            rows: rows,
            origin: CGPoint(
                x: (viewSize.width - CGFloat(cols) * cell.width) / 2,
                y: (viewSize.height - CGFloat(rows) * cell.height) / 2
            ),
            cellSize: cell
        )
        return (layout, width)
    }
}
