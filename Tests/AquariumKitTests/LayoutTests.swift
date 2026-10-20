import CoreGraphics
import Testing
@testable import AquariumKit

@Suite struct LayoutTests {
    @Test func layoutFit() {
        let l = GridLayout.fit(viewSize: CGSize(width: 1512, height: 982), cellSize: CGSize(width: 9.33, height: 18.6))
        #expect(l.cols == 162)
        #expect(l.rows == 52)
        // Centered: leftover space split evenly.
        let usedW = CGFloat(l.cols) * l.cellSize.width
        let usedH = CGFloat(l.rows) * l.cellSize.height
        #expect(abs(l.origin.x - (1512 - usedW) / 2) < 1e-9)
        #expect(abs(l.origin.y - (982 - usedH) / 2) < 1e-9)

        let tiny = GridLayout.fit(viewSize: CGSize(width: 5, height: 5), cellSize: CGSize(width: 9.33, height: 18.6))
        #expect(tiny.cols == 1)
        #expect(tiny.rows == 1)
    }

    @Test func layoutPreview() {
        let view = CGSize(width: 296, height: 184)
        let (l, scale) = GridLayout.preview(viewSize: view, referenceCols: 162, referenceRows: 52, cellAspect: 2.0)
        #expect(l.cols == 162)
        #expect(l.rows == 52)
        #expect(scale > 0)
        #expect(abs(scale - l.cellSize.width) < 1e-9)
        #expect(l.origin.x >= 0 && l.origin.y >= 0)
        #expect(CGFloat(l.cols) * l.cellSize.width + l.origin.x * 2 <= view.width + 1e-9)
        #expect(CGFloat(l.rows) * l.cellSize.height + l.origin.y * 2 <= view.height + 1e-9)
        #expect(abs(l.cellSize.height / l.cellSize.width - 2.0) < 1e-9)
    }
}
