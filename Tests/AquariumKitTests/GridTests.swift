import Testing
@testable import AquariumKit

@Suite struct GridTests {
    private let x = Cell(char: "X", color: CellColor(color: .white, bright: false))

    @Test func gridPutAndClip() {
        var grid = Grid(cols: 3, rows: 2)
        grid.put(x, x: 0, y: 0)
        grid.put(x, x: 2, y: 1)
        #expect(grid[0, 0] == x)
        #expect(grid[2, 1] == x)
        #expect(grid[1, 0] == nil)

        var clipped = Grid(cols: 3, rows: 2)
        clipped.put(x, x: -1, y: 0)
        clipped.put(x, x: 3, y: 0)
        clipped.put(x, x: 0, y: -1)
        clipped.put(x, x: 0, y: 2)
        #expect(clipped.text() == "   \n   ")
        #expect(clipped[-1, 0] == nil)
        #expect(clipped[3, 0] == nil)

        var one = Grid(cols: 3, rows: 2)
        one.put(x, x: 1, y: 1)
        #expect(one.text() == "   \n X ")

        one.put(nil, x: 1, y: 1)
        #expect(one.text() == "   \n   ")
    }

    @Test func randomDeterministic() {
        let a = RandomSource(seed: 42)
        let b = RandomSource(seed: 42)
        let seqA = (0..<100).map { _ in a.int(12) }
        let seqB = (0..<100).map { _ in b.int(12) }
        #expect(seqA == seqB)
        #expect(seqA.allSatisfy { (0..<12).contains($0) })
        #expect(Set(seqA).count > 6)
        #expect(a.int(0) == 0)
        #expect(a.int(-5) == 0)
    }

    @Test func randomDoubleRange() {
        let r = RandomSource(seed: 7)
        for _ in 0..<1000 {
            let d = r.double()
            #expect(d >= 0 && d < 1)
        }
    }

    @Test func splitMix64KnownVector() {
        // Reference SplitMix64 output for seed 0.
        let r = RandomSource(seed: 0)
        #expect(r.next() == 0xE220A8397B1DCDAF)
        #expect(r.next() == 0x6E789E6AA1B965F4)
    }
}
