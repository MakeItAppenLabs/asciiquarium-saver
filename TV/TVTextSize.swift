import CoreGraphics
import AquariumKit

extension TextSize {
    /// Point sizes for a TV seen from across the room. The Mac's `pointSize` is for a desk.
    var tvPointSize: CGFloat {
        switch self {
        case .small: 13
        case .medium: 17
        case .large: 22
        }
    }
}
