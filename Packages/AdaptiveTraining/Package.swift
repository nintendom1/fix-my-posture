// swift-tools-version: 5.10
import PackageDescription

// Adaptive training: progression ladders, evidence, and the recommendation policy. Foundation only, so the
// policy runs and is tested on the Mac with `swift test` and can never reach SwiftUI, SwiftData, or the camera.
let package = Package(
    name: "AdaptiveTraining",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AdaptiveTraining", targets: ["AdaptiveTraining"])
    ],
    targets: [
        .target(name: "AdaptiveTraining"),
        .testTarget(name: "AdaptiveTrainingTests", dependencies: ["AdaptiveTraining"])
    ]
)
