// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AquariumKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AquariumKit", targets: ["AquariumKit"]),
    ],
    targets: [
        .target(name: "AquariumKit"),
        .testTarget(name: "AquariumKitTests", dependencies: ["AquariumKit"]),
    ]
)
