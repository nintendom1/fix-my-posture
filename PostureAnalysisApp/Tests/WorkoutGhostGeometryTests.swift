import CoreGraphics
import XCTest
@testable import PostureAnalysisApp

/// What the ghost draws, how the complete figure is fitted, and how calibration agrees with the pipeline.
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
        XCTAssertEqual(geometry.limbs.map(\.joints), [
            [.leftAnkle, .leftKnee, .leftHip], [.rightAnkle, .rightKnee, .rightHip]
        ])
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
        XCTAssertEqual(geometry.limbs[0].joints, [.leftShoulder, .leftElbow, .leftWrist])
    }

    func testIdealFigureStaysInsideTheFitForEveryExerciseAndKeyframe() throws {
        let overlay = WorkoutCameraFixtures.overlay()
        for exercise in ExerciseCatalog.all {
            let imageSizes = [WorkoutGhostGeometry.defaultImageSize, overlay.imageSize]
            for imageSize in imageSizes {
                let currentOverlay = imageSize == overlay.imageSize ? overlay : nil
                let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
                for (index, keyframe) in exercise.guide.motion.keyframes.enumerated() {
                    let figure = WorkoutGhostGeometry.ideal(overlay: currentOverlay,
                                                            motion: exercise.guide.motion,
                                                            cameraView: exercise.cameraView,
                                                            containerSize: containerSize,
                                                            angles: keyframe.angles,
                                                            legs: keyframe.legs)
                    XCTAssertFalse(figure.isEmpty, "\(exercise.id) keyframe \(index) was empty")
                    for (joint, point) in figure.joints {
                        XCTAssertTrue(fit.contains(point),
                                      "\(exercise.id) keyframe \(index) \(joint) fell outside \(imageSize)")
                    }
                    if exercise.cameraView == .front {
                        XCTAssertLessThan(try XCTUnwrap(figure.joints[.leftShoulder]).x,
                                          try XCTUnwrap(figure.joints[.rightShoulder]).x,
                                          "\(exercise.id) keyframe \(index) did not mirror the guide's front view")
                    }
                }
            }
        }
    }

    func testEveryReadyVariantAgreesWithGhostCalibration() throws {
        for exercise in ExerciseCatalog.all {
            for variant in ReadyPoseFixtures.variants(for: exercise) {
                let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(),
                                                       initialExercise: exercise.id)
                harness.model.onAppear(isApplicationActive: true)
                harness.camera.emit(.running)
                var readyFrames = 0
                var firstReadyOverlay: WorkoutOverlayState?
                var firstReadyMetrics: GuideMetrics?

                for _ in 0..<20 {
                    harness.camera.emit(.frame(ReadyPoseFixtures.frame(variant, at: harness.clock.now)))
                    if harness.model.session.phase == .ready {
                        readyFrames += 1
                        let overlay = try XCTUnwrap(harness.model.ghostFitOverlay,
                                                    "\(exercise.id) \(variant.name): missing fit overlay")
                        firstReadyOverlay = firstReadyOverlay ?? overlay
                        firstReadyMetrics = firstReadyMetrics ?? harness.model.guideMetrics
                        let canFit = GhostCalibration.canFit(overlay: overlay,
                                                             metrics: harness.model.guideMetrics,
                                                             motion: exercise.guide.motion,
                                                             cameraView: exercise.cameraView)
                        let figure = WorkoutGhostGeometry.calibrated(
                            fitOverlay: overlay,
                            metrics: harness.model.guideMetrics,
                            motion: exercise.guide.motion,
                            cameraView: exercise.cameraView,
                            containerSize: containerSize,
                            angles: exercise.guide.motion.startAngles,
                            legs: exercise.guide.motion.startLegs
                        )
                        XCTAssertEqual(canFit, figure != nil,
                                       "\(exercise.id) \(variant.name): calibration disagrees with canFit")
                        if canFit {
                            XCTAssertFalse(try XCTUnwrap(figure).isEmpty,
                                           "\(exercise.id) \(variant.name): calibrated figure is empty")
                        }
                    }
                    harness.clock.advance(by: 0.1)
                }
                XCTAssertGreaterThan(readyFrames, 0, "\(exercise.id) \(variant.name) never reached Ready")

                if let overlay = firstReadyOverlay {
                    var missingOverlay = overlay
                    switch exercise.cameraView {
                    case .front where exercise.guide.motion.animatesLegs:
                        missingOverlay.joints[.leftAnkle] = nil
                        missingOverlay.joints[.rightAnkle] = nil
                    case .front:
                        missingOverlay.joints[.leftShoulder] = nil
                    case .side:
                        XCTAssertFalse(GhostCalibration.canFit(overlay: overlay, metrics: nil,
                                                               motion: exercise.guide.motion,
                                                               cameraView: exercise.cameraView))
                        XCTAssertNil(WorkoutGhostGeometry.calibrated(fitOverlay: overlay, metrics: nil,
                                                                     motion: exercise.guide.motion,
                                                                     cameraView: exercise.cameraView,
                                                                     containerSize: containerSize,
                                                                     angles: exercise.guide.motion.startAngles,
                                                                     legs: exercise.guide.motion.startLegs))
                        continue
                    case .floor:
                        missingOverlay.joints[.leftWrist] = nil
                    }
                    XCTAssertFalse(GhostCalibration.canFit(overlay: missingOverlay,
                                                           metrics: firstReadyMetrics,
                                                           motion: exercise.guide.motion,
                                                           cameraView: exercise.cameraView),
                                   "\(exercise.id) \(variant.name): negative fixture still fit")
                    XCTAssertNil(WorkoutGhostGeometry.calibrated(fitOverlay: missingOverlay,
                                                                  metrics: firstReadyMetrics,
                                                                  motion: exercise.guide.motion,
                                                                  cameraView: exercise.cameraView,
                                                                  containerSize: containerSize,
                                                                  angles: exercise.guide.motion.startAngles,
                                                                  legs: exercise.guide.motion.startLegs))
                }
            }
        }
    }

    func testCalibratedFrontAndSideLimbsAreExact() throws {
        let front = try readyContext(for: ShoulderPressExercise.definition())
        let frontExercise = ShoulderPressExercise.definition()
        let frontMetrics = try XCTUnwrap(front.harness.model.guideMetrics)
        let frontMotion = frontExercise.guide.motion
        let frontGeometry = WorkoutGhostGeometry.make(overlay: front.overlay, metrics: frontMetrics,
                                                      motion: frontMotion, cameraView: .front,
                                                      containerSize: containerSize,
                                                      angles: frontMotion.startAngles, legs: frontMotion.startLegs)
        let frontFigure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: front.overlay, metrics: frontMetrics, motion: frontMotion, cameraView: .front,
            containerSize: containerSize, angles: frontMotion.startAngles, legs: frontMotion.startLegs
        ))
        assertExactLimbs(frontGeometry, in: frontFigure, labels: nil)

        let sideExercise = TricepsExtensionExercise.definition()
        let side = try readyContext(for: sideExercise)
        let sideMetrics = try XCTUnwrap(side.harness.model.guideMetrics)
        let sideMotion = sideExercise.guide.motion
        let sideGeometry = WorkoutGhostGeometry.make(overlay: side.overlay, metrics: sideMetrics,
                                                     motion: sideMotion, cameraView: .side,
                                                     containerSize: containerSize,
                                                     angles: sideMotion.startAngles, legs: sideMotion.startLegs)
        let sideFigure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: side.overlay, metrics: sideMetrics, motion: sideMotion, cameraView: .side,
            containerSize: containerSize, angles: sideMotion.startAngles, legs: sideMotion.startLegs
        ))
        assertExactLimbs(sideGeometry, in: sideFigure,
                         labels: [.leftShoulder, .leftElbow, .leftWrist])
    }

    func testCalibratedFrontBodyCentersHipsUnderShoulders() throws {
        let exercise = ShoulderPressExercise.definition()
        let ready = try readyContext(for: exercise)
        let metrics = try XCTUnwrap(ready.harness.model.guideMetrics)
        let figure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: ready.overlay, metrics: metrics, motion: exercise.guide.motion, cameraView: .front,
            containerSize: containerSize, angles: exercise.guide.motion.startAngles,
            legs: exercise.guide.motion.startLegs
        ))
        let shoulderMidpoint = ArmGeometry.midpoint(
            try XCTUnwrap(containerPoint(.leftShoulder, in: ready.overlay)),
            try XCTUnwrap(containerPoint(.rightShoulder, in: ready.overlay))
        )
        let hipMidpoint = ArmGeometry.midpoint(try XCTUnwrap(figure.joints[.leftHip]),
                                               try XCTUnwrap(figure.joints[.rightHip]))

        XCTAssertEqual(hipMidpoint.x, shoulderMidpoint.x, accuracy: 1)
    }

    func testCalibratedSquatAnklesEqualTheUsersAnkles() throws {
        let exercise = AirSquatExercise.definition()
        let ready = try readyContext(for: exercise)
        let keyframe = try XCTUnwrap(exercise.guide.motion.keyframes.first { $0.legs != .standing })
        let figure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: ready.overlay, metrics: ready.harness.model.guideMetrics,
            motion: exercise.guide.motion, cameraView: exercise.cameraView,
            containerSize: containerSize, angles: keyframe.angles, legs: keyframe.legs
        ))
        for ankle in [LandmarkType.leftAnkle, .rightAnkle] {
            XCTAssertEqual(figure.joints[ankle], try XCTUnwrap(containerPoint(ankle, in: ready.overlay)))
        }
    }

    func testCalibratedSquatBodyKeepsItsSizeThroughTheSquat() throws {
        let exercise = AirSquatExercise.definition()
        let ready = try readyContext(for: exercise)
        let scales = try exercise.guide.motion.keyframes.map { keyframe in
            try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                fitOverlay: ready.overlay, metrics: ready.harness.model.guideMetrics,
                motion: exercise.guide.motion, cameraView: exercise.cameraView,
                containerSize: containerSize, angles: keyframe.angles, legs: keyframe.legs
            )).bodyScale
        }
        XCTAssertTrue(exercise.guide.motion.keyframes.contains { $0.legs != .standing })
        for scale in scales {
            XCTAssertEqual(scale, try XCTUnwrap(scales.first), accuracy: 0.0001)
        }
    }

    func testBlendedFiguresInterpolateJointsScaleAndForearm() {
        let from = WorkoutGhostGeometry.Figure(
            joints: [.leftShoulder: CGPoint(x: 0, y: 4), .leftElbow: CGPoint(x: 10, y: 14)],
            bodyScale: 2,
            dumbbells: [.init(elbow: CGPoint(x: 10, y: 14), wrist: CGPoint(x: 20, y: 24))],
            forearmLength: 6,
            isCalibrated: false
        )
        let to = WorkoutGhostGeometry.Figure(
            joints: [.leftShoulder: CGPoint(x: 20, y: 24), .leftElbow: CGPoint(x: 30, y: 34)],
            bodyScale: 4,
            dumbbells: [.init(elbow: CGPoint(x: 30, y: 34), wrist: CGPoint(x: 40, y: 44))],
            forearmLength: 10,
            isCalibrated: true
        )

        let start = WorkoutGhostGeometry.blended(from: from, to: to, progress: 0)
        XCTAssertEqual(start.joints, from.joints)
        XCTAssertEqual(start.bodyScale, from.bodyScale)
        XCTAssertEqual(start.forearmLength, from.forearmLength)
        XCTAssertEqual(start.dumbbells, from.dumbbells)
        let middle = WorkoutGhostGeometry.blended(from: from, to: to, progress: 0.5)
        XCTAssertEqual(middle.joints[.leftShoulder], CGPoint(x: 10, y: 14))
        XCTAssertEqual(middle.bodyScale, 3)
        XCTAssertEqual(middle.forearmLength, 8)
        XCTAssertEqual(middle.dumbbells[0].wrist, CGPoint(x: 30, y: 34))
        let end = WorkoutGhostGeometry.blended(from: from, to: to, progress: 1)
        XCTAssertEqual(end.joints, to.joints)
        XCTAssertEqual(end.bodyScale, to.bodyScale)
        XCTAssertEqual(end.forearmLength, to.forearmLength)
        XCTAssertEqual(end.dumbbells, to.dumbbells)
        XCTAssertTrue(end.isCalibrated)
    }

    func testGlideProgressUsesEasedDurationAndReduceMotionSkipsIt() {
        XCTAssertEqual(WorkoutGhostGeometry.glideProgress(since: nil, now: 1, reduceMotion: false), 1)
        XCTAssertEqual(WorkoutGhostGeometry.glideProgress(since: 1, now: 1.1, reduceMotion: true), 1)
        XCTAssertEqual(WorkoutGhostGeometry.glideProgress(since: 1, now: 1, reduceMotion: false), 0)
        XCTAssertEqual(WorkoutGhostGeometry.glideProgress(since: 1, now: 1.2, reduceMotion: false), 0.5,
                       accuracy: 0.0001)
        XCTAssertEqual(WorkoutGhostGeometry.glideProgress(since: 1, now: 1.4, reduceMotion: false), 1)
        XCTAssertEqual(WorkoutGhostGeometry.glideProgress(since: 1, now: 2, reduceMotion: false), 1)
    }

    private func readyContext(for exercise: ExerciseDefinition) throws
        -> (harness: WorkoutCoachHarness, overlay: WorkoutOverlayState) {
        let variant = try XCTUnwrap(ReadyPoseFixtures.variants(for: exercise).first { $0.name == "full" })
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), initialExercise: exercise.id)
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        for _ in 0..<20 {
            harness.camera.emit(.frame(ReadyPoseFixtures.frame(variant, at: harness.clock.now)))
            if harness.model.session.phase == .ready, let overlay = harness.model.ghostFitOverlay {
                return (harness, overlay)
            }
            harness.clock.advance(by: 0.1)
        }
        XCTFail("\(exercise.id) did not reach calibrated Ready")
        return (harness, try XCTUnwrap(harness.model.ghostFitOverlay))
    }

    private func assertExactLimbs(_ geometry: WorkoutGhostGeometry,
                                  in figure: WorkoutGhostGeometry.Figure,
                                  labels override: [LandmarkType]?) {
        XCTAssertFalse(geometry.limbs.isEmpty)
        for limb in geometry.limbs {
            let labels = override ?? limb.joints
            XCTAssertEqual(labels.count, limb.points.count)
            for (label, point) in zip(labels, limb.points) {
                XCTAssertEqual(figure.joints[label], point, "\(label) was not copied from the exact limb")
            }
        }
    }

    private func containerPoint(_ joint: LandmarkType, in overlay: WorkoutOverlayState) -> CGPoint? {
        guard let value = overlay.joints[joint], !value.isStale else { return nil }
        return CoordinateConverter.normalizedToContainer(normalized: value.location,
                                                         imageSize: overlay.imageSize,
                                                         containerSize: containerSize)
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
