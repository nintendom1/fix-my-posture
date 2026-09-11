import XCTest
@testable import PostureAnalysisApp

final class MeasurementPresentationTests: XCTestCase {
    private func fixture(_ points: [LandmarkType: CGPoint]) -> BodyPose {
        BodyPose(landmarks: Dictionary(uniqueKeysWithValues: points.map { key, point in
            (key, Landmark(type: key, normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: point,
                imageWidth: 1000, imageHeight: 2000), imageLocation: point, confidence: 0.95))
        }), imageWidth: 1000, imageHeight: 2000)
    }
    private func measurement(_ id: MeasurementID, _ value: Double, _ joints: [LandmarkType]) -> PostureMeasurement {
        PostureMeasurement(id: id, name: id.defaultDisplayName, value: value, unit: "°", landmarksUsed: joints, confidence: 0.95, explanation: "")
    }

    func testLevelCrossesZeroAndSavedPoseRetainsDirection() throws {
        for (dy, value, expected) in [(20.0, 3.2, "+3.2"), (-20, 3.2, "−3.2"), (-0.01, 0.01, "0.0")] {
            let original = fixture([.leftShoulder: CGPoint(x: 600, y: 500), .rightShoulder: CGPoint(x: 400, y: 500 + dy)])
            let m = measurement(.shoulderLineAngle, value, [.leftShoulder, .rightShoulder])
            let saved = try JSONDecoder().decode(BodyPose.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(MeasurementPresentation.reading(m, pose: saved, view: .front), expected)
            XCTAssertEqual(MeasurementPresentation.reading(m, pose: RealtimePoseProcessing.displayPose(original, mirrored: true), view: .front), expected)
            XCTAssertEqual(m.value, value)
        }
    }

    func testBodyRelativeRightIsIndependentOfImageHandedness() {
        let original = fixture([.leftShoulder: CGPoint(x: 600, y: 500), .rightShoulder: CGPoint(x: 400, y: 500),
            .neck: CGPoint(x: 480, y: 450), .leftHip: CGPoint(x: 550, y: 1000), .rightHip: CGPoint(x: 450, y: 1000)])
        let m = measurement(.torsoLateralDeviation, 2, [.neck, .leftHip, .rightHip])
        for mirrored in [false, true] {
            XCTAssertEqual(MeasurementPresentation.reading(m, pose: RealtimePoseProcessing.displayPose(original, mirrored: mirrored), view: .front), "+2.0")
        }
    }

    func testBothSidesUseFaceGeometryAndUnknownDirectionIsUnsigned() {
        for view in [PostureView.leftSide, .rightSide] {
            let ear: LandmarkType = view == .leftSide ? .leftEar : .rightEar
            let shoulder: LandmarkType = view == .leftSide ? .leftShoulder : .rightShoulder
            for forward in [-1.0, 1.0] {
                var pose = fixture([ear: CGPoint(x: 500 + forward * 20, y: 400), shoulder: CGPoint(x: 500, y: 600),
                    .nose: CGPoint(x: 500 + forward * 60, y: 400)])
                let m = measurement(.forwardHeadAngle, 3, [ear, shoulder])
                XCTAssertEqual(MeasurementPresentation.reading(m, pose: pose, view: view), "+3.0")
                pose[.nose]?.imageLocation.x = 500 - forward * 60
                XCTAssertEqual(MeasurementPresentation.reading(m, pose: pose, view: view), "−3.0")
                pose[.nose]?.confidence = 0.2
                XCTAssertEqual(MeasurementPresentation.reading(m, pose: pose, view: view), "3.0")
            }
        }
    }

    func testOriginalNonzeroTargetsAndMissingHistoryStayUnsigned() {
        XCTAssertEqual(MeasurementPresentation.reading(measurement(.kneeJointAngle, 179, []), pose: nil, view: .leftSide), "179.0")
        XCTAssertEqual(MeasurementPresentation.reading(measurement(.kneeAnkleStanceRatio, 1.23, []), pose: nil, view: .front), "1.23")
        XCTAssertEqual(MeasurementPresentation.reading(measurement(.headTiltAngle, 2, []), pose: nil, view: .front), "2.0")
    }

    func testJointSeverityPrecedenceAndConfidenceExclusionWithoutCallouts() {
        var pose = fixture([.leftShoulder: CGPoint(x: 600, y: 500), .rightShoulder: CGPoint(x: 400, y: 500)])
        let profile = DefaultPostureReferenceProvider().currentProfile
        let measurements = [measurement(.shoulderLineAngle, 0, [.leftShoulder, .rightShoulder]),
                            measurement(.headTiltAngle, 8, [.leftShoulder, .rightShoulder])]
        let result = MeasurementPresentation.jointFeedback(measurements: measurements, pose: pose, view: .front, profile: profile)
        XCTAssertEqual(result[.leftShoulder]?.severity, .high)
        pose[.rightShoulder]?.confidence = 0.2
        XCTAssertTrue(MeasurementPresentation.jointFeedback(measurements: measurements, pose: pose, view: .front, profile: profile).isEmpty)
        XCTAssertEqual(MeasurementFeedbackEvaluator().feedback(for: measurement(.shoulderLineAngle, -8, []), view: .front, profile: profile).severity, .high)
    }
}
