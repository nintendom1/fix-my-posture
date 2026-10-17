import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AssessmentViewModelTests: XCTestCase {
    func testDeltaStringsAndBaselineLineUseStableMeasurementMatches() throws {
        let current = assessment(date: date(10), measurements: [measurement(value: 2.1)], pose: directionPose())
        let baseline = assessment(date: date(2), measurements: [measurement(value: 2.7)], pose: directionPose())
        let viewModel = AssessmentViewModel(assessment: current, baselineAssessment: baseline)

        let row = try XCTUnwrap(viewModel.state.measurements.first)
        XCTAssertEqual(row.name, "Head Tilt Angle")
        XCTAssertEqual(row.valueText, "2.1° left")
        XCTAssertEqual(row.deltaText, "−0.6° vs baseline")
        XCTAssertEqual(row.baselineText, "Baseline 2.7° left")
        XCTAssertEqual(viewModel.state.viewComparisonText, "Front view · compared with baseline from Oct 2")
    }

    func testRoundedZeroDeltaReadsNoChange() throws {
        let current = assessment(date: date(10), measurements: [measurement(value: 2.14)], pose: directionPose())
        let baseline = assessment(date: date(2), measurements: [measurement(value: 2.1)], pose: directionPose())
        let viewModel = AssessmentViewModel(assessment: current, baselineAssessment: baseline)

        XCTAssertEqual(try XCTUnwrap(viewModel.state.measurements.first).deltaText, "No change")
    }

    func testNoBaselineMeansNoDeltaOrBaselineLine() throws {
        let viewModel = AssessmentViewModel(
            assessment: assessment(date: date(10), measurements: [measurement(value: 2.1)], pose: directionPose()),
            baselineAssessment: nil
        )

        let row = try XCTUnwrap(viewModel.state.measurements.first)
        XCTAssertNil(row.deltaText)
        XCTAssertNil(row.baselineText)
        XCTAssertFalse(viewModel.state.viewComparisonText.contains("baseline"))
    }

    func testAssessmentCopyAvoidsDiagnosticAndMedicalClaims() {
        let state = AssessmentViewModel(
            assessment: assessment(date: date(10), measurements: [measurement(value: 2.1)], pose: directionPose()),
            baselineAssessment: nil
        ).state
        let copy = ([state.viewComparisonText, state.notice] + state.measurements.flatMap {
            [$0.name, $0.valueText, $0.deltaText ?? "", $0.baselineText ?? ""]
        }).joined(separator: " ").lowercased()

        ["diagnosis", "scoliosis", "treatment", "medical condition"].forEach { banned in
            XCTAssertFalse(copy.contains(banned), "Unexpected claim in assessment copy: \(banned)")
        }
    }

    private func date(_ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func assessment(date: Date, measurements: [PostureMeasurement], pose: BodyPose) -> PostureAssessment {
        PostureAssessment(date: date, imageRelativePath: "photo.jpg", view: .front, pose: pose, measurements: measurements)
    }

    private func measurement(value: Double) -> PostureMeasurement {
        PostureMeasurement(
            id: .headTiltAngle,
            name: "Head Tilt Angle",
            value: value,
            unit: "°",
            landmarksUsed: [.leftEye, .rightEye],
            confidence: 0.95,
            explanation: "Geometric line angle."
        )
    }

    private func directionPose() -> BodyPose {
        let landmarks: [LandmarkType: Landmark] = [
            .leftEye: landmark(.leftEye, x: 200, y: 124),
            .rightEye: landmark(.rightEye, x: 400, y: 120)
        ]
        return BodyPose(landmarks: landmarks, imageWidth: 600, imageHeight: 1200)
    }

    private func landmark(_ type: LandmarkType, x: CGFloat, y: CGFloat) -> Landmark {
        Landmark(type: type, normalizedLocation: CGPoint(x: x / 600, y: 1 - y / 1200), imageLocation: CGPoint(x: x, y: y), confidence: 0.95)
    }
}
