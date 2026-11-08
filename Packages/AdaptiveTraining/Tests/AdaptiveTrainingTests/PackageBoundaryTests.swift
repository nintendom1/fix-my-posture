import XCTest

/// The package must stay Foundation-only, so the policy can never reach SwiftUI, SwiftData, UIKit, or the camera.
/// The `adaptive-replay` tool may also import the library itself, and nothing else.
final class PackageBoundaryTests: XCTestCase {
    func testEverySourceFileImportsOnlyFoundation() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let targets = [("AdaptiveTraining", Set(["import Foundation"])),
                       ("adaptive-replay", Set(["import Foundation", "import AdaptiveTraining"]))]
        for (target, allowed) in targets {
            let directory = sources.appendingPathComponent(target)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(files.isEmpty, "no sources found under \(directory.path)")
            for file in files {
                let imports = try String(contentsOf: file, encoding: .utf8)
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("import ") || $0.contains(" import ") && $0.hasPrefix("@") }
                for line in imports {
                    XCTAssertTrue(allowed.contains(line), "\(target)/\(file.lastPathComponent): \(line)")
                }
            }
        }
        let others = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { !$0.hasPrefix(".") && !targets.map(\.0).contains($0) }
        XCTAssertEqual(others, [], "a new target needs its own import rule here")
    }
}
