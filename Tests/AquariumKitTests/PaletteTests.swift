import Testing
@testable import AquariumKit

@Suite struct PaletteTests {
    @Test func paletteReadable() {
        let palette = Palette.terminal
        let top: RGB
        if case .gradient(let t, _) = AquariumSettings.defaultGradient { top = t } else { top = .black }
        for bright in [false, true] {
            let blue = palette.rgb(CellColor(color: .blue, bright: bright))
            #expect(contrastRatio(blue, .black) >= 3.0)
            #expect(contrastRatio(blue, top) >= 3.0)
        }
    }

    @Test func contrastRatioKnownValues() {
        let white = RGB(r: 1, g: 1, b: 1)
        #expect(abs(contrastRatio(white, .black) - 21.0) < 1e-9)
        #expect(abs(contrastRatio(white, white) - 1.0) < 1e-9)
    }

    @Test func paletteCoversAllColors() {
        let palette = Palette.terminal
        for c in ANSIColor.allCases {
            for bright in [false, true] {
                let rgb = palette.rgb(CellColor(color: c, bright: bright))
                #expect((0...1).contains(rgb.r) && (0...1).contains(rgb.g) && (0...1).contains(rgb.b))
            }
        }
    }
}
