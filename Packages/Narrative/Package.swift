// swift-tools-version: 5.10
import PackageDescription

// Narrative: a dormant, data-driven script model and runtime for future story scenes and companion callouts.
// Foundation only, tested on the Mac with `swift test`, and deliberately not linked into the app yet.
let package = Package(
    name: "Narrative",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Narrative", targets: ["Narrative"])
    ],
    targets: [
        .target(name: "Narrative"),
        .testTarget(name: "NarrativeTests", dependencies: ["Narrative"])
    ]
)
