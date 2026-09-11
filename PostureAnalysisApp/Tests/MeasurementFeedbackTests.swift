import XCTest
@testable import PostureAnalysisApp

final class MeasurementFeedbackTests: XCTestCase {
    private let evaluator = MeasurementFeedbackEvaluator()
    private let profile = DefaultPostureReferenceProvider().currentProfile

    func testSeverityUsesDistanceFromReferenceTolerance() {
        XCTAssertEqual(feedback(value: 0.5).severity, .aligned)
        XCTAssertEqual(feedback(value: 1.0).severity, .moderate)
        XCTAssertEqual(feedback(value: 1.1).severity, .high)
    }

    func testNonzeroReferenceTargetIsHandled() {
        let measurement = makeMeasurement(id: .kneeJointAngle, value: 179)
        let result = evaluator.feedback(for: measurement, view: .leftSide, profile: profile)
        XCTAssertEqual(result.severity, .aligned)
        XCTAssertEqual(result.normalizedDeviation, 1)
    }

    func testLowConfidenceOverridesPresentationLabel() {
        let measurement = makeMeasurement(id: .shoulderLineAngle, value: 0, confidence: 0.49)
        let result = evaluator.feedback(for: measurement, view: .front, profile: profile)
        XCTAssertEqual(result.severity, .aligned)
        XCTAssertTrue(result.isLowConfidence)
        XCTAssertEqual(result.label, "Low confidence")
    }

    func testMissingRuleHasNoSeverityJudgment() {
        let measurement = makeMeasurement(id: .shoulderHeightAsymmetry, value: 3)
        let result = evaluator.feedback(for: measurement, view: .front, profile: profile)
        XCTAssertEqual(result.severity, .unavailable)
        XCTAssertNil(result.normalizedDeviation)
    }

    private func feedback(value: Double) -> MeasurementFeedback {
        evaluator.feedback(
            for: makeMeasurement(id: .shoulderLineAngle, value: value),
            view: .front,
            profile: profile
        )
    }

    private func makeMeasurement(
        id: MeasurementID,
        value: Double,
        confidence: Double = 0.9
    ) -> PostureMeasurement {
        PostureMeasurement(
            id: id,
            name: id.defaultDisplayName,
            value: value,
            unit: "°",
            landmarksUsed: [],
            confidence: confidence,
            explanation: "Test measurement"
        )
    }
}
