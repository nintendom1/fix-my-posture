import XCTest
@testable import PostureAnalysisApp

/// Every exercise records the tuning it ran with and can be rebuilt from a recorded tuning.
final class ExerciseDiagnosticsTests: XCTestCase {
    func testEveryCatalogExerciseRecordsItsConfiguration() throws {
        for exercise in ExerciseCatalog.all {
            let diagnostics = try XCTUnwrap(exercise.diagnostics, "\(exercise.id.rawValue) has no diagnostics")
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(diagnostics.configurationJSON.utf8)) as? [String: Any],
                "\(exercise.id.rawValue) configuration isn't a JSON object")
            XCTAssertFalse(object.isEmpty, exercise.id.rawValue)
            XCTAssertNotNil(object["confirmationSamples"], exercise.id.rawValue)
            XCTAssertNotNil(object["maximumSampleGap"], exercise.id.rawValue)
        }
    }

    func testRebuildLaysRecordedValuesOverTheDefaultsAndIgnoresUnknownKeys() throws {
        let diagnostics = try XCTUnwrap(ShoulderPressExercise.definition().diagnostics)
        let rebuilt = try diagnostics.rebuild(Data(#"{"topMinHeight":0.75,"retiredSetting":3}"#.utf8))

        XCTAssertEqual(rebuilt.id, .shoulderPress)
        XCTAssertEqual(rebuilt.cameraView, .front)
        let configuration = try XCTUnwrap(rebuilt.diagnostics.flatMap {
            try JSONSerialization.jsonObject(with: Data($0.configurationJSON.utf8)) as? [String: Any]
        })
        XCTAssertEqual(configuration["topMinHeight"] as? Double, 0.75)
        XCTAssertEqual(configuration["bottomMaxHeight"] as? Double, 0.6)
        XCTAssertNil(configuration["retiredSetting"])
    }

    func testRebuildingFromTheRecordedJSONGivesTheSameConfiguration() throws {
        for exercise in ExerciseCatalog.all {
            let diagnostics = try XCTUnwrap(exercise.diagnostics)
            let rebuilt = try diagnostics.rebuild(Data(diagnostics.configurationJSON.utf8))
            XCTAssertEqual(rebuilt.diagnostics?.configurationJSON, diagnostics.configurationJSON, exercise.id.rawValue)
            XCTAssertEqual(rebuilt.id, exercise.id)
        }
    }

    func testSharedConfigurationsEncodeWithSortedKeys() {
        let json = ExerciseDiagnostics.json(FramingConfiguration())
        XCTAssertTrue(json.hasPrefix(#"{"centerTolerance""#), json)
    }
}
