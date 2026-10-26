import AquariumKit

/// The background colors the remote can pick from, since tvOS has no color picker. Black and the
/// default gradient's top color are among them, so the Mac defaults are always reachable.
enum Swatches {
    static let all: [(name: String, rgb: RGB)] = [
        ("Black", RGB(r: 0, g: 0, b: 0)),
        ("Deep Sea", RGB(r: 0.02, g: 0.06, b: 0.16)),
        ("Navy", RGB(r: 0.00, g: 0.10, b: 0.25)),
        ("Teal", RGB(r: 0.00, g: 0.18, b: 0.18)),
        ("Kelp", RGB(r: 0.03, g: 0.15, b: 0.08)),
        ("Violet", RGB(r: 0.12, g: 0.04, b: 0.20)),
        ("Slate", RGB(r: 0.10, g: 0.10, b: 0.10)),
        ("Maroon", RGB(r: 0.18, g: 0.03, b: 0.05)),
    ]
}
