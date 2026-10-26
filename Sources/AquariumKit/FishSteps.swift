/// The fish amount as five steps, for a remote that has no slider. Each step sits at a position of
/// the Mac's Fish amount slider, so Few and Many are its ends and Normal its middle.
public enum FishStep: Int, CaseIterable, Sendable {
    case few, fewer, normal, more, many

    public var label: String {
        switch self {
        case .few: "Few"
        case .fewer: "Fewer"
        case .normal: "Normal"
        case .more: "More"
        case .many: "Many"
        }
    }

    public var sliderPosition: Double { Double(rawValue) / 4 }

    public var fishAmount: Double { AquariumSettings.fishAmount(sliderPosition: sliderPosition) }

    /// The step closest to a stored amount on the slider's scale; a tie goes to the lower step.
    public static func nearest(toFishAmount amount: Double) -> FishStep {
        let position = AquariumSettings.sliderPosition(fishAmount: amount)
        var best = FishStep.few
        for step in allCases where abs(step.sliderPosition - position) < abs(best.sliderPosition - position) {
            best = step
        }
        return best
    }
}
