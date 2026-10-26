import CoreGraphics
import AquariumKit

extension TextSize {
    /// Point sizes for a TV seen from across the room. The Mac's `pointSize` is for a desk.
    var tvPointSize: CGFloat {
        switch self {
        case .small: 22
        case .medium: 28
        case .large: 38
        }
    }
}
