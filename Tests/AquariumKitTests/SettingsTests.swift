import Foundation
import Testing
@testable import AquariumKit

@Suite struct SettingsTests {
    @Test func settingsDefaultsRoundTrip() {
        let d = AquariumSettings.defaults
        #expect(AquariumSettings.decode(d.encoded()) == d)
        #expect(d.fishAmount == 1.0)
        #expect(d.creatureSet == .full)
        #expect(d.enabledSpecials == Set(SpecialKind.allCases))
        #expect(d.background == .solid(.black))
        #expect(d.textSize == .medium)
    }

    @Test func settingsCustomRoundTrip() {
        var s = AquariumSettings.defaults
        s.fishAmount = 2.5
        s.creatureSet = .classic
        s.enabledSpecials = [.shark, .swan]
        s.background = AquariumSettings.defaultGradient
        s.textSize = .large
        #expect(AquariumSettings.decode(s.encoded()) == s)
    }

    @Test func settingsCorruptData() {
        #expect(AquariumSettings.decode(Data("garbage".utf8)) == .defaults)
        #expect(AquariumSettings.decode(nil) == .defaults)
    }

    @Test func settingsPartialData() {
        let json = #"{"creatureSet":"classic","textSize":"huge"}"#
        let s = AquariumSettings.decode(Data(json.utf8))
        #expect(s.creatureSet == .classic)
        #expect(s.textSize == .medium)
        #expect(s.fishAmount == 1.0)
        #expect(s.enabledSpecials == Set(SpecialKind.allCases))
        #expect(s.background == .solid(.black))
    }

    @Test func settingsUnknownSpecialsDropped() {
        let json = #"{"enabledSpecials":["shark","kraken"]}"#
        let s = AquariumSettings.decode(Data(json.utf8))
        #expect(s.enabledSpecials == [.shark])
    }

    @Test func fishAmountClampAndSlider() {
        let high = AquariumSettings.decode(Data(#"{"fishAmount":10}"#.utf8))
        #expect(high.fishAmount == 3.0)
        let low = AquariumSettings.decode(Data(#"{"fishAmount":0}"#.utf8))
        #expect(low.fishAmount == 0.25)

        #expect(AquariumSettings.fishAmount(sliderPosition: 0) == 0.25)
        #expect(abs(AquariumSettings.fishAmount(sliderPosition: 0.5) - 1.0) < 1e-9)
        #expect(abs(AquariumSettings.fishAmount(sliderPosition: 1) - 3.0) < 1e-9)

        for i in 0...100 {
            let p = Double(i) / 100
            let back = AquariumSettings.sliderPosition(fishAmount: AquariumSettings.fishAmount(sliderPosition: p))
            #expect(abs(back - p) < 1e-9)
        }
    }

    @Test func specialKindOrderAndTextSize() {
        #expect(SpecialKind.allCases.map(\.rawValue) == [
            "ship", "whale", "monster", "bigFish", "shark", "fishhook",
            "swan", "ducks", "dolphins", "submarine", "swordfish", "jellyfish",
        ])
        #expect(TextSize.small.pointSize == 11.5)
        #expect(TextSize.medium.pointSize == 15.5)
        #expect(TextSize.large.pointSize == 23.0)
    }
}
