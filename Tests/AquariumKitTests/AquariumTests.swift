import Foundation
import Testing

@testable import AquariumKit

@Suite struct AquariumTests {
    @Test(arguments: [(1, 1), (10, 5), (40, 15), (300, 120)])
    func tinyGrids(size: (Int, Int)) {
        let aquarium = Aquarium(cols: size.0, rows: size.1, settings: .defaults, seed: 7)
        for _ in 0..<100 { aquarium.step() }
        let grid = aquarium.render()
        #expect(grid.cols == size.0)
        #expect(grid.rows == size.1)
    }

    @Test func boundedOverLongRun() {
        let aquarium = Aquarium(cols: 162, rows: 52, settings: .defaults, seed: 1)
        let afterSetup = aquarium.entityCount
        var peak = afterSetup
        for _ in 0..<36_000 {
            aquarium.step()
            peak = max(peak, aquarium.entityCount)
        }
        #expect(peak <= 4 * afterSetup, "peak \(peak) vs setup \(afterSetup)")
        _ = aquarium.render()
    }

    @Test func deterministic() {
        func run() -> String {
            let aquarium = Aquarium(cols: 100, rows: 30, settings: .defaults, seed: 99)
            for _ in 0..<200 { aquarium.step() }
            return aquarium.render().text()
        }
        #expect(run() == run())
    }

    @Test func differentSeedsDiffer() {
        func run(_ seed: UInt64) -> String {
            let aquarium = Aquarium(cols: 100, rows: 30, settings: .defaults, seed: seed)
            for _ in 0..<50 { aquarium.step() }
            return aquarium.render().text()
        }
        #expect(run(1) != run(2))
    }

    @Test func exposesSizeAndSettings() {
        let settings = AquariumSettings(fishAmount: 2.0, creatureSet: .classic)
        let aquarium = Aquarium(cols: 80, rows: 24, settings: settings, seed: 3)
        #expect(aquarium.cols == 80)
        #expect(aquarium.rows == 24)
        #expect(aquarium.settings == settings)
    }

    @Test func setupEndsWithASpecial() {
        // Setup is environment, castle, seaweed, fish, then one special, so the count must
        // exceed what the first four produce alone.
        let engine = Engine(cols: 120, rows: 40, rng: RandomSource(seed: 5))
        let context = SpawnContext(engine: engine, settings: .defaults)
        addEnvironment(context)
        addCastle(context)
        addAllSeaweed(context)
        addAllFish(context)
        let withoutSpecial = engine.entityCount
        let aquarium = Aquarium(cols: 120, rows: 40, settings: .defaults, seed: 5)
        #expect(aquarium.entityCount > withoutSpecial)
    }

    private static let goldenURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Golden/seed42-120x40-f50.txt")

    @Test func goldenFrame() throws {
        let aquarium = Aquarium(cols: 120, rows: 40, settings: .defaults, seed: 42)
        for _ in 0..<50 { aquarium.step() }
        let actual = aquarium.render().text() + "\n"

        if ProcessInfo.processInfo.environment["GOLDEN_RECORD"] == "1" {
            try FileManager.default.createDirectory(
                at: Self.goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try actual.write(to: Self.goldenURL, atomically: true, encoding: .utf8)
            Issue.record("Recorded golden frame at \(Self.goldenURL.path). Re-run without GOLDEN_RECORD.")
            return
        }

        let expected = try String(contentsOf: Self.goldenURL, encoding: .utf8)
        #expect(actual == expected)
    }
}
