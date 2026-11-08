import Foundation
import XCTest

final class PackageBoundaryTests: XCTestCase {
    func testEveryNarrativeSourceImportsOnlyFoundation() throws {
        let packageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = packageDirectory.appendingPathComponent("Sources")
        let targets = try FileManager.default.contentsOfDirectory(atPath: sourcesRoot.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        XCTAssertEqual(targets, ["Narrative"], "A new source target needs an explicit Foundation import rule here.")

        let sources = sourcesRoot.appendingPathComponent("Narrative")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "No sources found under \(sources.path)")
        for file in files {
            let imports = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") || ($0.hasPrefix("@") && $0.contains(" import ")) }
                .compactMap { $0.components(separatedBy: "import ").last?.trimmingCharacters(in: .whitespaces) }
            for module in imports {
                XCTAssertEqual(module, "Foundation", "\(file.lastPathComponent): import \(module)")
            }
        }
    }

    func testAppProjectDoesNotReferenceNarrativePackage() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = repositoryRoot.appendingPathComponent("PostureAnalysisApp.xcodeproj/project.pbxproj")
        let contents = try String(contentsOf: project, encoding: .utf8)
        XCTAssertFalse(contents.contains("Packages/Narrative"))
        XCTAssertFalse(contents.contains("Narrative"), "The app project must not link the dormant package.")
    }
}
