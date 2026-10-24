import CoreGraphics
import XCTest
@testable import PostureAnalysisApp

/// What the ghost can draw from the overlay alone, and what needs the pipeline's guide metrics.
@MainActor
final class WorkoutGhostGeometryTests: XCTestCase {
    private let containerSize = CGSize(width: 393, height: 852)

    func testAirSquatLegGhostDoesNotNeedArmMetrics() throws {
        let exercise = AirSquatExercise.definition()
        let keyframe = try XCTUnwrap(exercise.guide.motion.keyframes.first { $0.legs != .standing })
        let overlay = makeOverlay([
            .leftHip: CGPoint(x: 0.62, y: 0.64),
            .leftKnee: CGPoint(x: 0.66, y: 0.42),
            .leftAnkle: CGPoint(x: 0.68, y: 0.18),
            .rightHip: CGPoint(x: 0.38, y: 0.64),
            .rightKnee: CGPoint(x: 0.34, y: 0.42),
            .rightAnkle: CGPoint(x: 0.32, y: 0.18)
        ])

        let geometry = WorkoutGhostGeometry.make(overlay: overlay, metrics: nil, motion: exercise.guide.motion,
                                                 cameraView: .front, containerSize: containerSize,
                                                 angles: keyframe.angles, legs: keyframe.legs)

        XCTAssertEqual(geometry.limbs.count, 2)
        XCTAssertEqual(geometry.connector?.points.count, 2)
    }

    func testFrontArmGhostNeedsMetrics() {
        let exercise = ShoulderPressExercise.definition()
        let overlay = makeOverlay([
            .leftShoulder: CGPoint(x: 0.62, y: 0.7),
            .rightShoulder: CGPoint(x: 0.38, y: 0.7)
        ])

        let geometry = WorkoutGhostGeometry.make(overlay: overlay, metrics: nil, motion: exercise.guide.motion,
                                                 cameraView: .front, containerSize: containerSize,
                                                 angles: exercise.guide.motion.startAngles,
                                                 legs: exercise.guide.motion.startLegs)

        XCTAssertTrue(geometry.isEmpty)
    }

    func testSideArmGhostNeedsMetrics() {
        let exercise = TricepsExtensionExercise.definition()
        let overlay = makeOverlay([.leftShoulder: CGPoint(x: 0.58, y: 0.7)])

        let geometry = WorkoutGhostGeometry.make(overlay: overlay, metrics: nil, motion: exercise.guide.motion,
                                                 cameraView: .side, containerSize: containerSize,
                                                 angles: exercise.guide.motion.startAngles,
                                                 legs: exercise.guide.motion.startLegs)

        XCTAssertTrue(geometry.isEmpty)
    }

    func testFloorGhostNeedsMetrics() {
        let exercise = PushUpExercise.definition()
        let overlay = makeOverlay([
            .leftWrist: CGPoint(x: 0.65, y: 0.18),
            .rightWrist: CGPoint(x: 0.35, y: 0.18)
        ])

        let geometry = WorkoutGhostGeometry.make(overlay: overlay, metrics: nil, motion: exercise.guide.motion,
                                                 cameraView: .floor, containerSize: containerSize,
                                                 angles: exercise.guide.motion.startAngles,
                                                 legs: exercise.guide.motion.startLegs)

        XCTAssertTrue(geometry.isEmpty)
    }

    func testSideArmGhostWithMetricsAnchorsAtNearShoulder() {
        let exercise = TricepsExtensionExercise.definition()
        let nearShoulder = CGPoint(x: 0.62, y: 0.68)
        let overlay = makeOverlay([
            .leftShoulder: nearShoulder,
            .leftElbow: CGPoint(x: 0.66, y: 0.54),
            .rightShoulder: CGPoint(x: 0.3, y: 0.67)
        ])

        let geometry = WorkoutGhostGeometry.make(overlay: overlay,
                                                 metrics: GuideMetrics(upperArm: 72, forearm: 64),
                                                 motion: exercise.guide.motion, cameraView: .side,
                                                 containerSize: containerSize,
                                                 angles: exercise.guide.motion.startAngles,
                                                 legs: exercise.guide.motion.startLegs)
        let expectedShoulder = CoordinateConverter.normalizedToContainer(normalized: nearShoulder,
                                                                         imageSize: overlay.imageSize,
                                                                         containerSize: containerSize)

        XCTAssertEqual(geometry.limbs.count, 1)
        XCTAssertEqual(geometry.limbs[0].points.first, expectedShoulder)
    }

    private func makeOverlay(_ joints: [LandmarkType: CGPoint]) -> WorkoutOverlayState {
        let imageSize = CGSize(width: 1080, height: 1920)
        return WorkoutOverlayState(imageSize: imageSize,
                                  joints: joints.mapValues { OverlayJoint(location: $0, isStale: false) },
                                  segments: [],
                                  endPositionSides: [],
                                  pose: BodyPose(landmarks: [:], imageWidth: imageSize.width,
                                                 imageHeight: imageSize.height))
    }
}
