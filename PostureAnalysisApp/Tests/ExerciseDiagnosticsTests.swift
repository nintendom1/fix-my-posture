import XCTest
@testable import PostureAnalysisApp

/// Every exercise, in every camera view, records the tuning it ran with and can be rebuilt from a recorded tuning.
final class ExerciseDiagnosticsTests: XCTestCase {
    func testEveryCatalogExerciseRecordsItsConfiguration() throws {
        for exercise in ExerciseCatalog.everyView {
            let name = label(exercise)
            let diagnostics = try XCTUnwrap(exercise.diagnostics, "\(name) has no diagnostics")
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(diagnostics.configurationJSON.utf8)) as? [String: Any],
                "\(name) configuration isn't a JSON object")
            XCTAssertFalse(object.isEmpty, name)
            XCTAssertNotNil(object["confirmationSamples"], name)
            XCTAssertNotNil(object["maximumSampleGap"], name)
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

    func testEveryViewRebuildsFromItsRecordedJSONToTheSameViewAndConfiguration() throws {
        for exercise in ExerciseCatalog.everyView {
            let name = label(exercise)
            let diagnostics = try XCTUnwrap(exercise.diagnostics, "\(name) has no diagnostics")
            let rebuilt = try diagnostics.rebuild(Data(diagnostics.configurationJSON.utf8))
            XCTAssertEqual(rebuilt.diagnostics?.configurationJSON, diagnostics.configurationJSON, name)
            XCTAssertEqual(rebuilt.id, exercise.id, name)
            XCTAssertEqual(rebuilt.cameraView, exercise.cameraView, name)
        }
    }

    func testSharedConfigurationsEncodeWithSortedKeys() {
        let json = ExerciseDiagnostics.json(FramingConfiguration())
        XCTAssertTrue(json.hasPrefix(#"{"centerTolerance""#), json)
    }

    /// "hammer_curl (side)", so a failure names the view.
    private func label(_ exercise: ExerciseDefinition) -> String {
        "\(exercise.id.rawValue) (\(exercise.cameraView.rawValue))"
    }
}
