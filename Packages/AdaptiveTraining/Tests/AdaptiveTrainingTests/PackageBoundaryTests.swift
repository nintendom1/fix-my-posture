import XCTest

/// The package must stay Foundation-only, so the policy can never reach SwiftUI, SwiftData, UIKit, or the camera.
final class PackageBoundaryTests: XCTestCase {
    func testEverySourceFileImportsOnlyFoundation() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no sources found under \(sources.path)")
        for file in files {
            let imports = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") || $0.contains(" import ") && $0.hasPrefix("@") }
            for line in imports {
                XCTAssertEqual(line, "import Foundation", "\(file.lastPathComponent) imports more than Foundation")
            }
        }
    }
}
