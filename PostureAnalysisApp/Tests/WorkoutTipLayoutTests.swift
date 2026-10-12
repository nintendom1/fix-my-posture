import XCTest
@testable import PostureAnalysisApp

final class WorkoutTipLayoutTests: XCTestCase {
    /// iPhone 15 Pro inside the safe area, with HUD regions like the workout screen's.
    private let container = CGRect(x: 0, y: 0, width: 393, height: 759)
    private let topHUD = CGRect(x: 0, y: 0, width: 393, height: 80)
    private let bottomHUD = CGRect(x: 8, y: 600, width: 377, height: 151)
    private let wide = CGSize(width: 300, height: 48)
    private let narrow = CGSize(width: 120, height: 84)

    func testFirstChoiceIsCenteredBelowTopHUD() {
        let frame = WorkoutTipLayout.placement(size: wide, container: container, protected: [],
                                               reserved: [topHUD, bottomHUD], previous: nil)
        XCTAssertEqual(frame, CGRect(x: 46.5, y: 92, width: 300, height: 48))
    }

    func testPressTipsAvoidBodyEnvelopeAndHUD() throws {
        let motion = ShoulderPressExercise.definition().guide.motion
        // At 3.75× the user stands close: the overhead envelope reaches the top HUD, so the narrow tip
        // moves beside the hips. At 4× the body fills the frame head to ankle and the cue is only spoken.
        for scale: CGFloat in [3, 3.75, 4] {
            for angles in [motion.startAngles, motion.topAngles] {
                let (overlay, metrics) = pressOverlay(angles: angles, scale: scale)
                let envelope = try XCTUnwrap(WorkoutTipLayout.envelopeRect(
                    ShoulderPressExercise.definition().motionEnvelope, overlay: overlay, metrics: metrics, containerSize: container.size))
                let protected = WorkoutTipLayout.protectedRects(pose: overlay.pose, envelope: envelope, containerSize: container.size)
                let frame = WorkoutTipLayout.placement(sizes: [wide, narrow], container: container, protected: protected,
                                                       reserved: [topHUD, bottomHUD], previous: nil)
                switch scale {
                case 3: XCTAssertEqual(frame?.size, wide, "Typical distance: one line below the top HUD.")
                case 3.75: XCTAssertEqual(frame?.size, narrow)
                default: XCTAssertNil(frame)
                }
                guard let frame else { continue }
                XCTAssertTrue(container.insetBy(dx: 8, dy: 8).contains(frame))
                for blocked in protected + [topHUD, bottomHUD] {
                    XCTAssertFalse(blocked.intersects(frame), "scale \(scale): \(frame) overlaps \(blocked)")
                }
                // Every point along both arms stays clear, including the hands overhead.
                for side in BodySide.allCases {
                    let points = side.armJoints.compactMap { overlay.pose[$0] }.map {
                        CoordinateConverter.normalizedToContainer(normalized: $0.normalizedLocation, imageSize: overlay.imageSize,
                                                                  containerSize: container.size)
                    }
                    for (a, b) in zip(points, points.dropFirst()) {
                        for step in 0...20 {
                            let t = CGFloat(step) / 20
                            let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                            XCTAssertFalse(frame.insetBy(dx: -8, dy: -8).contains(point))
                        }
                    }
                }
            }
        }
    }

    func testKeepsPreviousSlotWhileValid() {
        let gutter = CGRect(x: 8, y: 316, width: 120, height: 84)
        let kept = WorkoutTipLayout.placement(sizes: [wide, narrow], container: container, protected: [],
                                              reserved: [topHUD, bottomHUD], previous: gutter)
        XCTAssertEqual(kept, gutter, "Stays put even though a preferred slot is free.")

        let moved = WorkoutTipLayout.placement(sizes: [wide, narrow], container: container, protected: [gutter],
                                               reserved: [topHUD, bottomHUD], previous: gutter)
        XCTAssertEqual(moved?.size, wide, "Once blocked, it moves to the best slot again.")
    }

    func testNoRoomMeansSpeakOnly() {
        XCTAssertNil(WorkoutTipLayout.placement(sizes: [wide, narrow], container: container, protected: [container],
                                                reserved: [topHUD, bottomHUD], previous: nil))
    }

    /// The guide's demo figure, scaled up inside a 1080×1920 frame, mirrored like the live overlay.
    private func pressOverlay(angles: ArmAngles, scale: CGFloat) -> (WorkoutOverlayState, GuideMetrics) {
        let imageSize = CGSize(width: 1080, height: 1920)
        let figure = ExerciseDemoFigureView.pose(for: angles).jointLocations
        let origin = CGPoint(x: imageSize.width / 2 - 150 * scale, y: imageSize.height - 480 * scale)
        var landmarks: [LandmarkType: Landmark] = [:]
        var joints: [LandmarkType: OverlayJoint] = [:]
        for (type, point) in figure {
            let pixel = CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
            let normalized = CGPoint(x: 1 - pixel.x / imageSize.width, y: 1 - pixel.y / imageSize.height)
            landmarks[type] = Landmark(type: type, normalizedLocation: normalized,
                                       imageLocation: CGPoint(x: imageSize.width - pixel.x, y: pixel.y), confidence: 0.9)
            joints[type] = OverlayJoint(location: normalized, isStale: false)
        }
        let overlay = WorkoutOverlayState(imageSize: imageSize, joints: joints, segments: [], endPositionSides: [],
                                          pose: BodyPose(landmarks: landmarks, imageWidth: imageSize.width, imageHeight: imageSize.height))
        let metrics = GuideMetrics(upperArm: ExerciseDemoFigureView.upperArm * scale, forearm: ExerciseDemoFigureView.forearm * scale)
        return (overlay, metrics)
    }
}
