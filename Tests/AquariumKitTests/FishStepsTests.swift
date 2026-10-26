import Testing

@testable import AquariumKit

/// The Apple TV's five fish-amount steps stand in for the Mac slider: Few and Many are its ends and
/// Normal its middle.
@Suite struct FishStepsTests {
    @Test func normalIsTheMacDefault() {
        #expect(FishStep.normal.fishAmount == AquariumSettings.fishAmount(sliderPosition: 0.5))
        #expect(FishStep.nearest(toFishAmount: AquariumSettings.defaults.fishAmount) == .normal)
    }

    @Test func endsMatchTheSliderEnds() {
        #expect(FishStep.few.fishAmount == AquariumSettings.fishAmountRange.lowerBound)
        #expect(FishStep.many.fishAmount == AquariumSettings.fishAmountRange.upperBound)
    }

    @Test func everyStepRoundTrips() {
        for step in FishStep.allCases {
            #expect(FishStep.nearest(toFishAmount: step.fishAmount) == step)
        }
    }

    /// A stored amount between steps shows the nearest one.
    @Test func stepForStoredAmountIsNearest() {
        #expect(FishStep.nearest(toFishAmount: AquariumSettings.fishAmount(sliderPosition: 0.6)) == .normal)
        #expect(FishStep.nearest(toFishAmount: AquariumSettings.fishAmount(sliderPosition: 0.7)) == .more)
    }

    @Test func tiesGoToTheLowerStep() {
        #expect(FishStep.nearest(toFishAmount: AquariumSettings.fishAmount(sliderPosition: 0.125)) == .few)
    }

    @Test func labels() {
        #expect(FishStep.allCases.map(\.label) == ["Few", "Fewer", "Normal", "More", "Many"])
    }
}
