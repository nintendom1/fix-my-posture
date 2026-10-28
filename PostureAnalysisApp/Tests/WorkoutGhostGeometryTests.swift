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
                                                 sample: exercise.guide.motion.sample(of: keyframe))

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
                                                 sample: exercise.guide.motion.startSample)

        XCTAssertTrue(geometry.isEmpty)
    }

    func testSideArmGhostNeedsMetrics() {
        let exercise = TricepsExtensionExercise.definition()
        let overlay = makeOverlay([.leftShoulder: CGPoint(x: 0.58, y: 0.7)])

        let geometry = WorkoutGhostGeometry.make(overlay: overlay, metrics: nil, motion: exercise.guide.motion,
                                                 cameraView: .side, containerSize: containerSize,
                                                 sample: exercise.guide.motion.startSample)

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
                                                 sample: exercise.guide.motion.startSample)

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
                                                 sample: exercise.guide.motion.startSample)
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
                                                            sample: exercise.guide.motion.sample(of: keyframe))
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

    func testCatalogFigureBoundsFitTheCanvasOrIncludeTheFullLateralRaiseSpan() {
        let canvas = CGRect(origin: .zero, size: ExerciseDemoFigureView.canvasSize)
        for exercise in ExerciseCatalog.all {
            let bounds = ExerciseDemoFigureView.bounds(for: exercise.guide.motion,
                                                       cameraView: exercise.cameraView)
            if exercise.id == .lateralRaise {
                XCTAssertLessThan(bounds.minX, canvas.minX)
                XCTAssertGreaterThan(bounds.maxX, canvas.maxX)
                XCTAssertEqual(bounds.minY, canvas.minY)
                XCTAssertEqual(bounds.maxY, canvas.maxY)
            } else if exercise.guide.motion.plantedLayout?.surface == .bench {
                // A bench figure is wider than the canvas and low on it, so its bounds hug the figure and bench.
                XCTAssertGreaterThan(bounds.maxX, canvas.maxX)
                XCTAssertLessThan(bounds.height, canvas.height)
                for sample in [exercise.guide.motion.startSample, exercise.guide.motion.topSample] {
                    let joints = ExerciseDemoFigureView.pose(for: sample, cameraView: exercise.cameraView).jointLocations
                    for (joint, point) in joints {
                        XCTAssertTrue(bounds.contains(point), "\(exercise.id) \(joint) falls outside \(bounds)")
                    }
                }
            } else {
                XCTAssertEqual(bounds, canvas,
                               "\(exercise.id) bounds expanded by \(bounds.width - canvas.width)×\(bounds.height - canvas.height)")
            }
        }
    }

    func testFigureShapeInterpolatesAndSelectsTopWhenOnlyBodyMoves() throws {
        let start = ArmKeyframe(angles: hangingArms, moveDuration: 0, holdDuration: 0.5, stepIndex: 0)
        let bottom = ArmKeyframe(angles: hangingArms, moveDuration: 1, holdDuration: 0.5, stepIndex: 1,
                                 shape: FigureShape(torsoPitch: 60, hipShift: 1, hipDrop: 0.2, stride: 1.1))
        let motion = ArmMotion(keyframes: [start, bottom])
        let middle = motion.sample(at: 1.0)

        XCTAssertEqual(try XCTUnwrap(middle.shape.torsoPitch), 30, accuracy: 0.0001)
        XCTAssertEqual(middle.shape.hipShift, 0.5, accuracy: 0.0001)
        XCTAssertEqual(middle.shape.hipDrop, 0.1, accuracy: 0.0001)
        XCTAssertEqual(middle.shape.stride, 0.55, accuracy: 0.0001)
        XCTAssertTrue(motion.movesSideBody)
        XCTAssertEqual(motion.topSample, motion.sample(of: bottom))

        let row = DumbbellRowExercise.definition().guide.motion
        XCTAssertFalse(row.movesSideBody, "The row's constant motion-level pitch is not a body transition")
        XCTAssertEqual(try XCTUnwrap(row.startSample.shape.torsoPitch), row.torsoPitch)
    }

    func testHingeAndSplitStanceSidePosesStayFiniteAndKeepLegLengths() throws {
        let hinge = sideMotion(shape: FigureShape(torsoPitch: 60, hipShift: 1, hipDrop: 0.2))
        let hingeSample = hinge.topSample
        let hingePose = ExerciseDemoFigureView.pose(for: hingeSample, forearmPlane: hinge.forearmPlane,
                                                    cameraView: .side).jointLocations
        assertFinite(hingePose)
        try assertSideLegLengths(hingePose, side: .left)
        let hingeWrist = try XCTUnwrap(hingePose[.leftWrist])
        let hingeKnee = try XCTUnwrap(hingePose[.leftKnee])
        let hingeAnkle = try XCTUnwrap(hingePose[.leftAnkle])
        XCTAssertLessThan(distance(hingeWrist, hingeKnee, hingeAnkle),
                          ArmGeometry.distance(ExerciseDemoFigureView.sideFigureJoints[.leftHip] ?? .zero,
                                               ExerciseDemoFigureView.sideFigureJoints[.leftKnee] ?? .zero) * 0.7)

        let split = sideMotion(shape: FigureShape(torsoPitch: 0, hipShift: 1, hipDrop: 0.5, stride: 1.1))
        let splitStartPose = ExerciseDemoFigureView.pose(for: split.startSample, cameraView: .side).jointLocations
        XCTAssertNil(splitStartPose[.rightHip])
        XCTAssertNil(splitStartPose[.rightKnee])
        XCTAssertNil(splitStartPose[.rightAnkle])
        let splitPose = ExerciseDemoFigureView.pose(for: split.topSample, cameraView: .side).jointLocations
        assertFinite(splitPose)
        for side in [BodySide.left, .right] {
            try assertSideLegLengths(splitPose, side: side)
            let hip = try XCTUnwrap(splitPose[side.hip])
            let knee = try XCTUnwrap(splitPose[side.knee])
            let ankle = try XCTUnwrap(splitPose[side.ankle])
            XCTAssertGreaterThan(knee.x, projectedX(of: knee, from: hip, to: ankle),
                                 "\(side) knee did not bend toward the figure's facing direction")
        }
    }

    func testSideBodyGhostCalibratesFromReadyJointsAtBothScalesAndFacings() throws {
        for scale in [CGFloat(0.5), 2] {
            for facing in [CGFloat(1), -1] {
                let motion = sideMotion(shape: FigureShape(torsoPitch: 60, hipShift: 1, hipDrop: 0.2))
                let (overlay, nearSide) = sideBodyOverlay(motion: motion, scale: scale, facing: facing)
                for sample in [motion.startSample, motion.topSample] {
                    let canFit = GhostCalibration.canFit(overlay: overlay, metrics: nil, motion: motion,
                                                         cameraView: .side, sample: sample)
                    let geometry = WorkoutGhostGeometry.make(overlay: overlay, metrics: nil, motion: motion,
                                                             cameraView: .side, containerSize: containerSize,
                                                             sample: sample)
                    let figure = WorkoutGhostGeometry.calibrated(fitOverlay: overlay, metrics: nil,
                                                                 motion: motion, cameraView: .side,
                                                                 containerSize: containerSize, sample: sample)
                    XCTAssertEqual(canFit, figure != nil)
                    XCTAssertEqual(canFit, !geometry.isEmpty)
                    XCTAssertTrue(canFit)
                }

                let startFigure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                    fitOverlay: overlay, metrics: nil, motion: motion, cameraView: .side,
                    containerSize: containerSize, sample: motion.startSample))
                let guideToTracked = [(BodySide.left.shoulder, nearSide.shoulder),
                                      (.leftHip, nearSide.hip), (.leftKnee, nearSide.knee),
                                      (.leftAnkle, nearSide.ankle)]
                for (guideJoint, trackedJoint) in guideToTracked {
                    XCTAssertEqual(startFigure.joints[guideJoint],
                                   try XCTUnwrap(containerPoint(trackedJoint, in: overlay)),
                                   "\(guideJoint) did not match at scale \(scale), facing \(facing)")
                }
                XCTAssertEqual(startFigure.dumbbells.count, 1)
                XCTAssertNotNil(startFigure.joints[BodySide.left.wrist],
                                 "The missing-wrist case did not build a fallback arm")

                var missingAnkle = overlay
                missingAnkle.joints[nearSide.ankle] = nil
                var missingHip = overlay
                missingHip.joints[nearSide.hip] = nil
                for missing in [missingAnkle, missingHip] {
                    XCTAssertFalse(GhostCalibration.canFit(overlay: missing, metrics: nil, motion: motion,
                                                           cameraView: .side, sample: motion.startSample))
                    XCTAssertTrue(WorkoutGhostGeometry.make(overlay: missing, metrics: nil, motion: motion,
                                                            cameraView: .side, containerSize: containerSize,
                                                            sample: motion.startSample).isEmpty)
                    XCTAssertNil(WorkoutGhostGeometry.calibrated(fitOverlay: missing, metrics: nil,
                                                                 motion: motion, cameraView: .side,
                                                                 containerSize: containerSize, sample: motion.startSample))
                }
            }
        }
    }

    func testRightSideReadyPosesBlendWithoutExtraIdealLimbs() throws {
        let exercises = [StiffLegDeadliftExercise.definition(), RearLungeExercise.definition(),
                         GluteBridgeExercise.definition(), WallPushUpExercise.definition(),
                         InclinePushUpExercise.definition()]
        for exercise in exercises {
            let variant = try XCTUnwrap(ReadyPoseFixtures.variants(for: exercise).first { $0.name == "minimal right" })
            let readyFrame = ReadyPoseFixtures.frame(variant, at: 0)
            let overlay = overlay(from: readyFrame)
            let samples = exercise.id == .rearLunge || exercise.id == .gluteBridge || exercise.id == .wallPushUp
                || exercise.id == .inclinePushUp
                ? [exercise.guide.motion.startSample, exercise.guide.motion.topSample]
                : [exercise.guide.motion.startSample]

            for sample in samples {
                let calibrated = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                    fitOverlay: overlay, metrics: nil, motion: exercise.guide.motion,
                    cameraView: exercise.cameraView, containerSize: containerSize, sample: sample
                ), "\(exercise.id) did not calibrate from the right-side Ready pose")
                let ideal = WorkoutGhostGeometry.ideal(overlay: nil, motion: exercise.guide.motion,
                                                       cameraView: exercise.cameraView, containerSize: containerSize,
                                                       sample: sample)
                let blended = WorkoutGhostGeometry.blended(from: ideal, to: calibrated, progress: 1)

                XCTAssertEqual(Set(blended.joints.keys), Set(calibrated.joints.keys),
                               "\(exercise.id) retained ideal joints after calibration")
                XCTAssertNotNil(blended.joints[.leftShoulder])
                XCTAssertNotNil(blended.joints[.leftHip])
                XCTAssertNotNil(blended.joints[.leftKnee])
                XCTAssertNotNil(blended.joints[.leftAnkle])
                XCTAssertNil(blended.joints[.rightShoulder])
                if sample.shape.stride > 0 {
                    XCTAssertNotNil(blended.joints[.rightKnee], "The split stance rear leg uses right labels")
                    XCTAssertNotNil(blended.joints[.rightAnkle], "The split stance rear foot uses right labels")
                } else {
                    XCTAssertNil(blended.joints[.rightKnee])
                    XCTAssertNil(blended.joints[.rightAnkle])
                }
                if exercise.id == .gluteBridge {
                    XCTAssertNotNil(blended.joints[.leftElbow])
                    XCTAssertNotNil(blended.joints[.leftWrist])
                    XCTAssertNil(blended.joints[.rightHip])
                }
            }
        }
    }

    func testLyingSidePoseUsesItsOwnFloorLayoutAndStraightTopLine() throws {
        let bridge = GluteBridgeExercise.definition()
        let down = ExerciseDemoFigureView.pose(for: bridge.guide.motion.startSample,
                                               cameraView: .lyingSide).jointLocations
        let top = ExerciseDemoFigureView.pose(for: bridge.guide.motion.topSample,
                                              cameraView: .lyingSide).jointLocations
        let shoulder = try XCTUnwrap(down[.leftShoulder])
        let downHip = try XCTUnwrap(down[.leftHip])
        let downAnkle = try XCTUnwrap(down[.leftAnkle])
        let upHip = try XCTUnwrap(top[.leftHip])
        let upKnee = try XCTUnwrap(top[.leftKnee])
        let upAnkle = try XCTUnwrap(top[.leftAnkle])

        XCTAssertEqual(downHip.y, ExerciseDemoFigureView.lyingSideFloorY - 20, accuracy: 0.001)
        XCTAssertEqual(shoulder.y, downAnkle.y)
        XCTAssertEqual(down[.leftElbow]?.y, shoulder.y)
        XCTAssertGreaterThan(try XCTUnwrap(down[.leftWrist]).x, try XCTUnwrap(down[.leftElbow]).x)
        XCTAssertLessThan(upHip.y, downHip.y)
        XCTAssertEqual(try XCTUnwrap(top[.leftShoulder]), shoulder)
        XCTAssertEqual(upAnkle, downAnkle)

        let hipAngle = GluteBridgeAnalyzer.hipAngle(shoulder: shoulder, hip: upHip, knee: upKnee, facing: 1)
        XCTAssertEqual(hipAngle, 180, accuracy: 0.01)
        let cross = (upHip.x - shoulder.x) * (upKnee.y - upHip.y)
            - (upHip.y - shoulder.y) * (upKnee.x - upHip.x)
        XCTAssertEqual(cross, 0, accuracy: 0.01)
        XCTAssertNotEqual(try XCTUnwrap(down[.nose]), try XCTUnwrap(down[.neck]))
    }

    func testLyingSideGhostAnchorsExactReadyJointsAndDoesNotNeedArmMetrics() throws {
        let bridge = GluteBridgeExercise.definition()
        let poses: [(joints: [LandmarkType: CGPoint], facing: CGFloat)] = [
            ([.rightShoulder: CGPoint(x: 0.72, y: 0.72),
              .rightHip: CGPoint(x: 0.59, y: 0.72),
              .rightKnee: CGPoint(x: 0.43, y: 0.68),
              .rightAnkle: CGPoint(x: 0.25, y: 0.72)], -1),
            ([.rightShoulder: CGPoint(x: 0.25, y: 0.72),
              .rightHip: CGPoint(x: 0.41, y: 0.72),
              .rightKnee: CGPoint(x: 0.57, y: 0.68),
              .rightAnkle: CGPoint(x: 0.75, y: 0.72)], 1)
        ]
        let sample = bridge.guide.motion.startSample
        for pose in poses {
            let overlay = makeOverlay(pose.joints)
            let canFit = GhostCalibration.canFit(overlay: overlay, metrics: nil,
                                                 motion: bridge.guide.motion, cameraView: .lyingSide,
                                                 sample: sample)
            let figure = WorkoutGhostGeometry.calibrated(fitOverlay: overlay, metrics: nil,
                                                         motion: bridge.guide.motion, cameraView: .lyingSide,
                                                         containerSize: containerSize, sample: sample)
            XCTAssertEqual(canFit, figure != nil)
            let calibrated = try XCTUnwrap(figure)
            let fit = CoordinateConverter.aspectFitRect(for: overlay.imageSize, in: containerSize)
            func expected(_ joint: LandmarkType) -> CGPoint {
                CoordinateConverter.normalizedToContainer(normalized: pose.joints[joint] ?? .zero,
                                                          imageSize: overlay.imageSize,
                                                          containerSize: containerSize)
            }
            XCTAssertEqual(calibrated.joints[.leftShoulder], expected(.rightShoulder))
            XCTAssertEqual(calibrated.joints[.leftAnkle], expected(.rightAnkle))
            XCTAssertEqual(calibrated.joints[.leftHip], expected(.rightHip))
            XCTAssertEqual(calibrated.joints[.leftKnee], expected(.rightKnee))
            XCTAssertTrue(fit.contains(expected(.rightShoulder)))

            let top = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                fitOverlay: overlay, metrics: nil, motion: bridge.guide.motion,
                cameraView: .lyingSide, containerSize: containerSize,
                sample: bridge.guide.motion.topSample
            ))
            let topHip = try XCTUnwrap(top.joints[.leftHip])
            let topKnee = try XCTUnwrap(top.joints[.leftKnee])
            let topAnkle = try XCTUnwrap(top.joints[.leftAnkle])
            let startHip = expected(.rightHip)
            let startKnee = expected(.rightKnee)
            let startAnkle = expected(.rightAnkle)
            XCTAssertLessThan(topHip.y, startHip.y)
            XCTAssertEqual(ArmGeometry.distance(topHip, topKnee),
                           ArmGeometry.distance(startHip, startKnee), accuracy: 0.01)
            XCTAssertEqual(ArmGeometry.distance(topKnee, topAnkle),
                           ArmGeometry.distance(startKnee, startAnkle), accuracy: 0.01)

            let geometry = WorkoutGhostGeometry.make(overlay: overlay, metrics: nil, motion: bridge.guide.motion,
                                                     cameraView: .lyingSide, containerSize: containerSize,
                                                     sample: sample)
            XCTAssertEqual(geometry.limbs.map(\.joints), [
                [.leftShoulder, .leftElbow, .leftWrist], [.leftAnkle, .leftKnee, .leftHip]
            ])
            XCTAssertTrue(geometry.limbs.allSatisfy { !$0.points.isEmpty })

            var incompleteJoints = pose.joints
            incompleteJoints[.rightKnee] = nil
            let incomplete = makeOverlay(incompleteJoints)
            XCTAssertFalse(GhostCalibration.canFit(overlay: incomplete, metrics: nil,
                                                   motion: bridge.guide.motion, cameraView: .lyingSide,
                                                   sample: sample))
            XCTAssertNil(WorkoutGhostGeometry.calibrated(fitOverlay: incomplete, metrics: nil,
                                                         motion: bridge.guide.motion, cameraView: .lyingSide,
                                                         containerSize: containerSize, sample: sample))
        }
    }

    func testLyingBridgeGhostTopUsesMeasuredProportionsAndStaysStraight() throws {
        let bridge = GluteBridgeExercise.definition()
        let cases: [(torso: CGFloat, thigh: CGFloat, shin: CGFloat, footDistance: CGFloat,
                     shoulder: CGPoint)] = [
            (80, 100, 80, 170, CGPoint(x: 300, y: 800)),
            (60, 120, 75, 210, CGPoint(x: 300, y: 800)),
            (110, 80, 100, 150, CGPoint(x: 300, y: 800)),
            (95, 85, 125, 245, CGPoint(x: 300, y: 800)),
            // The review's geometry: S (100,500), H (200,500), K (250,413.397), A (300,500).
            (100, 100, 100, 200, CGPoint(x: 100, y: 500))
        ]
        let halfway = ArmMotionSample(angles: bridge.guide.motion.startAngles, stepIndex: 0,
                                      shape: FigureShape(hipLift: 0.5))

        for item in cases {
            for facing: CGFloat in [-1, 1] {
                let shoulder = item.shoulder
                let hip = CGPoint(x: shoulder.x + facing * item.torso, y: shoulder.y)
                let ankle = CGPoint(x: shoulder.x + facing * item.footDistance, y: shoulder.y)
                let knee = ArmGeometry.twoBoneKnee(hip: hip, ankle: ankle,
                                                   thighLength: item.thigh, shinLength: item.shin,
                                                   bendDirection: facing)
                let overlay = makePixelOverlay([
                    .rightShoulder: shoulder, .rightHip: hip, .rightKnee: knee, .rightAnkle: ankle
                ])
                let start = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                    fitOverlay: overlay, metrics: nil, motion: bridge.guide.motion,
                    cameraView: .lyingSide, containerSize: containerSize,
                    sample: bridge.guide.motion.startSample
                ))
                let top = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                    fitOverlay: overlay, metrics: nil, motion: bridge.guide.motion,
                    cameraView: .lyingSide, containerSize: containerSize,
                    sample: bridge.guide.motion.topSample
                ))
                let middle = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                    fitOverlay: overlay, metrics: nil, motion: bridge.guide.motion,
                    cameraView: .lyingSide, containerSize: containerSize, sample: halfway
                ))
                let startShoulder = try XCTUnwrap(start.joints[.leftShoulder])
                let startHip = try XCTUnwrap(start.joints[.leftHip])
                let startKnee = try XCTUnwrap(start.joints[.leftKnee])
                let startAnkle = try XCTUnwrap(start.joints[.leftAnkle])
                let topHip = try XCTUnwrap(top.joints[.leftHip])
                let topKnee = try XCTUnwrap(top.joints[.leftKnee])
                let topAnkle = try XCTUnwrap(top.joints[.leftAnkle])
                let middleHip = try XCTUnwrap(middle.joints[.leftHip])
                let expectedShoulder = try XCTUnwrap(containerPoint(.rightShoulder, in: overlay))
                let expectedHip = try XCTUnwrap(containerPoint(.rightHip, in: overlay))
                let expectedKnee = try XCTUnwrap(containerPoint(.rightKnee, in: overlay))
                let expectedAnkle = try XCTUnwrap(containerPoint(.rightAnkle, in: overlay))
                let label = "torso \(item.torso), thigh \(item.thigh), shin \(item.shin), feet \(item.footDistance), facing \(facing)"

                XCTAssertEqual(startShoulder, expectedShoulder, label)
                XCTAssertEqual(startHip, expectedHip, label)
                XCTAssertEqual(startKnee, expectedKnee, label)
                XCTAssertEqual(startAnkle, expectedAnkle, label)
                XCTAssertEqual(topAnkle, expectedAnkle, label)
                XCTAssertEqual(middleHip.x, (startHip.x + topHip.x) / 2, accuracy: 0.01, label)
                XCTAssertEqual(middleHip.y, (startHip.y + topHip.y) / 2, accuracy: 0.01, label)
                XCTAssertEqual(ArmGeometry.distance(topHip, topKnee),
                               ArmGeometry.distance(startHip, startKnee), accuracy: 0.01, label)
                XCTAssertEqual(ArmGeometry.distance(topKnee, topAnkle),
                               ArmGeometry.distance(startKnee, startAnkle), accuracy: 0.01, label)
                XCTAssertEqual(ArmGeometry.distance(startShoulder, startHip),
                               ArmGeometry.distance(startShoulder, topHip), accuracy: 0.01, label)
                let angle = GluteBridgeAnalyzer.hipAngle(shoulder: startShoulder, hip: topHip,
                                                         knee: topKnee, facing: facing)
                XCTAssertGreaterThanOrEqual(angle, 175, label)
                XCTAssertGreaterThan(angle, 165, label)
            }
        }
    }

    func testLyingBridgeGhostClampsUnreachableTopWithoutNonfinitePoints() throws {
        let bridge = GluteBridgeExercise.definition()
        let shoulder = CGPoint(x: 300, y: 500)
        let hip = CGPoint(x: 550, y: 500)
        let ankle = CGPoint(x: 500, y: 500)
        let knee = ArmGeometry.twoBoneKnee(hip: hip, ankle: ankle,
                                           thighLength: 100, shinLength: 50, bendDirection: 1)
        let overlay = makePixelOverlay([
            .rightShoulder: shoulder, .rightHip: hip, .rightKnee: knee, .rightAnkle: ankle
        ])
        let top = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: overlay, metrics: nil, motion: bridge.guide.motion,
            cameraView: .lyingSide, containerSize: containerSize,
            sample: bridge.guide.motion.topSample
        ))
        for point in top.joints.values {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
        }
        let topHip = try XCTUnwrap(top.joints[.leftHip])
        let topKnee = try XCTUnwrap(top.joints[.leftKnee])
        let topAnkle = try XCTUnwrap(top.joints[.leftAnkle])
        XCTAssertEqual(ArmGeometry.distance(try XCTUnwrap(top.joints[.leftShoulder]), topHip),
                       ArmGeometry.distance(try XCTUnwrap(top.joints[.leftShoulder]),
                                            try XCTUnwrap(containerPoint(.rightHip, in: overlay))),
                       accuracy: 0.01)
        XCTAssertEqual(ArmGeometry.distance(topHip, topKnee), 100 * (containerSize.width / 1080), accuracy: 0.01)
        XCTAssertGreaterThan(ArmGeometry.distance(topKnee, topAnkle), 50 * (containerSize.width / 1080))
    }

    func testSideBodyIdealFitsHingeAndSplitStanceAtTwoSizes() throws {
        let motions = [
            sideMotion(shape: FigureShape(torsoPitch: 60, hipShift: 1, hipDrop: 0.2)),
            sideMotion(shape: FigureShape(torsoPitch: 0, hipShift: 1, hipDrop: 0.5, stride: 1.1))
        ]
        for motion in motions {
            for size in [containerSize, CGSize(width: 320, height: 568)] {
                let fit = CoordinateConverter.aspectFitRect(for: WorkoutGhostGeometry.defaultImageSize, in: size)
                let figure = WorkoutGhostGeometry.ideal(overlay: nil, motion: motion, cameraView: .side,
                                                        containerSize: size, sample: motion.topSample)
                XCTAssertFalse(figure.isEmpty)
                for point in figure.joints.values {
                    XCTAssertTrue(fit.contains(point), "A side-body joint fell outside the image fit at \(size)")
                }
            }
        }
    }

    func testNeutralAndRowSidePosesKeepTheirCanonicalGeometry() throws {
        let neutralAngles = ArmAngles(upperArmElevation: 15, forearmElevation: 35)
        let neutral = ExerciseDemoFigureView.pose(for: neutralAngles, cameraView: .side)
        for (joint, point) in ExerciseDemoFigureView.sideFigureJoints {
            XCTAssertEqual(neutral.jointLocations[joint], point, "Neutral \(joint) changed")
        }
        let shoulder = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftShoulder])
        let arm = ArmMotion.place(shoulder: shoulder, outward: 1,
                                  upperArm: ExerciseDemoFigureView.upperArm,
                                  forearm: ExerciseDemoFigureView.forearm, angles: neutralAngles)
        XCTAssertEqual(neutral.jointLocations[.leftElbow], arm.elbow)
        XCTAssertEqual(neutral.jointLocations[.leftWrist], arm.wrist)

        let row = DumbbellRowExercise.definition().guide.motion
        let rowPose = ExerciseDemoFigureView.pose(for: row.startSample, forearmPlane: row.forearmPlane,
                                                  cameraView: .side).jointLocations
        let hip = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftHip])
        let radians = row.torsoPitch * .pi / 180
        for joint in [LandmarkType.nose, .leftShoulder] {
            let point = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[joint])
            let dx = point.x - hip.x
            let dy = point.y - hip.y
            let expected = CGPoint(x: hip.x + dx * CGFloat(cos(radians)) - dy * CGFloat(sin(radians)),
                                   y: hip.y + dx * CGFloat(sin(radians)) + dy * CGFloat(cos(radians)))
            XCTAssertEqual(rowPose[joint], expected)
        }
        XCTAssertEqual(rowPose[.leftHip], hip)
        XCTAssertEqual(rowPose[.leftKnee], ExerciseDemoFigureView.sideFigureJoints[.leftKnee])
        XCTAssertEqual(rowPose[.leftAnkle], ExerciseDemoFigureView.sideFigureJoints[.leftAnkle])
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
                                                             cameraView: exercise.cameraView,
                                                             sample: exercise.guide.motion.startSample)
                        let figure = WorkoutGhostGeometry.calibrated(
                            fitOverlay: overlay,
                            metrics: harness.model.guideMetrics,
                            motion: exercise.guide.motion,
                            cameraView: exercise.cameraView,
                            containerSize: containerSize,
                            sample: exercise.guide.motion.startSample
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
                    case .side where exercise.guide.motion.movesSideBody:
                        missingOverlay.joints[.leftHip] = nil
                        missingOverlay.joints[.rightHip] = nil
                    case .side where exercise.guide.motion.plantedLayout != nil:
                        for side in BodySide.allCases {
                            missingOverlay.joints[side.shoulder] = nil
                            missingOverlay.joints[side.elbow] = nil
                            missingOverlay.joints[side.wrist] = nil
                            missingOverlay.joints[side.hip] = nil
                        }
                    case .side:
                        XCTAssertFalse(GhostCalibration.canFit(overlay: overlay, metrics: nil,
                                                               motion: exercise.guide.motion,
                                                               cameraView: exercise.cameraView,
                                                               sample: exercise.guide.motion.startSample))
                        XCTAssertNil(WorkoutGhostGeometry.calibrated(fitOverlay: overlay, metrics: nil,
                                                                     motion: exercise.guide.motion,
                                                                     cameraView: exercise.cameraView,
                                                                     containerSize: containerSize,
                                                                     sample: exercise.guide.motion.startSample))
                        continue
                    case .floor:
                        missingOverlay.joints[.leftWrist] = nil
                    case .lyingSide:
                        missingOverlay.joints[.leftAnkle] = nil
                        missingOverlay.joints[.rightAnkle] = nil
                    }
                    XCTAssertFalse(GhostCalibration.canFit(overlay: missingOverlay,
                                                           metrics: firstReadyMetrics,
                                                           motion: exercise.guide.motion,
                                                           cameraView: exercise.cameraView,
                                                           sample: exercise.guide.motion.startSample),
                                   "\(exercise.id) \(variant.name): negative fixture still fit")
                    XCTAssertNil(WorkoutGhostGeometry.calibrated(fitOverlay: missingOverlay,
                                                                  metrics: firstReadyMetrics,
                                                                  motion: exercise.guide.motion,
                                                                  cameraView: exercise.cameraView,
                                                                  containerSize: containerSize,
                                                                  sample: exercise.guide.motion.startSample))
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
                                                      sample: frontMotion.startSample)
        let frontFigure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: front.overlay, metrics: frontMetrics, motion: frontMotion, cameraView: .front,
            containerSize: containerSize, sample: frontMotion.startSample
        ))
        assertExactLimbs(frontGeometry, in: frontFigure, labels: nil)

        let sideExercise = TricepsExtensionExercise.definition()
        let side = try readyContext(for: sideExercise)
        let sideMetrics = try XCTUnwrap(side.harness.model.guideMetrics)
        let sideMotion = sideExercise.guide.motion
        let sideGeometry = WorkoutGhostGeometry.make(overlay: side.overlay, metrics: sideMetrics,
                                                     motion: sideMotion, cameraView: .side,
                                                     containerSize: containerSize,
                                                     sample: sideMotion.startSample)
        let sideFigure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: side.overlay, metrics: sideMetrics, motion: sideMotion, cameraView: .side,
            containerSize: containerSize, sample: sideMotion.startSample
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
            containerSize: containerSize, sample: exercise.guide.motion.startSample
        ))
        let shoulderMidpoint = ArmGeometry.midpoint(
            try XCTUnwrap(containerPoint(.leftShoulder, in: ready.overlay)),
            try XCTUnwrap(containerPoint(.rightShoulder, in: ready.overlay))
        )
        let hipMidpoint = ArmGeometry.midpoint(try XCTUnwrap(figure.joints[.leftHip]),
                                               try XCTUnwrap(figure.joints[.rightHip]))

        XCTAssertEqual(hipMidpoint.x, shoulderMidpoint.x, accuracy: 1)
    }

    func testShoulderLiftRaisesTheFrontFigureShouldersNeckAndArmsButNotTheNoseOrHips() throws {
        let motion = DumbbellShrugExercise.definition().guide.motion
        let top = motion.topSample
        XCTAssertEqual(top.shape.shoulderLift, 0.22, accuracy: 1e-12, "The lift alone selects the top keyframe")
        XCTAssertEqual(motion.sample(at: 1.4).shape.shoulderLift, 0.11, accuracy: 1e-9, "Halfway through the lift")
        XCTAssertFalse(motion.movesSideBody, "A front-view lift is not side-body motion")

        let relaxed = ExerciseDemoFigureView.pose(for: motion.startSample, cameraView: .front).jointLocations
        let lifted = ExerciseDemoFigureView.pose(for: top, cameraView: .front).jointLocations
        let rise = 0.22 * ExerciseDemoFigureView.upperArm
        let raised: [LandmarkType] = [.neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                                      .leftWrist, .rightWrist]
        for joint in raised {
            let start = try XCTUnwrap(relaxed[joint])
            let end = try XCTUnwrap(lifted[joint])
            XCTAssertEqual(end.x, start.x, accuracy: 1e-9, "\(joint)")
            XCTAssertEqual(end.y, start.y - rise, accuracy: 1e-9, "\(joint)")
        }
        for joint in [LandmarkType.nose, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle] {
            XCTAssertEqual(lifted[joint], relaxed[joint], "\(joint) moved")
        }
        XCTAssertEqual(ExerciseDemoFigureView.lifted(ExerciseDemoFigureView.figureJoints, shoulderLift: 0),
                       ExerciseDemoFigureView.figureJoints)
        for view in [ExerciseCameraView.side, .floor] {
            XCTAssertEqual(ExerciseDemoFigureView.pose(for: top, cameraView: view).jointLocations,
                           ExerciseDemoFigureView.pose(for: motion.startSample, cameraView: view).jointLocations,
                           "\(view) ignores the shoulder lift")
        }
    }

    func testRenderedShrugFigureCarriesGuideShapeIntoItsDisplayedPose() throws {
        let exercise = DumbbellShrugExercise.definition()
        let motion = exercise.guide.motion

        func figure(for sample: ArmMotionSample) -> ExerciseDemoFigureView {
            ExerciseDemoFigureView(angles: sample.angles, forearmPlane: motion.forearmPlane,
                                   cameraView: exercise.cameraView, holdsDumbbells: motion.holdsDumbbells,
                                   legs: sample.legs, torsoPitch: motion.torsoPitch, shape: sample.shape,
                                   figureBounds: ExerciseDemoFigureView.bounds(for: motion,
                                                                               cameraView: exercise.cameraView))
        }

        let relaxed = figure(for: motion.startSample).displayedPose.jointLocations
        let lifted = figure(for: motion.topSample).displayedPose.jointLocations
        let rise = CGFloat(motion.topSample.shape.shoulderLift) * ExerciseDemoFigureView.upperArm
        for joint in [LandmarkType.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist] {
            let start = try XCTUnwrap(relaxed[joint])
            let end = try XCTUnwrap(lifted[joint])
            XCTAssertEqual(end.x, start.x, accuracy: 1e-9, "\(joint) moved sideways")
            XCTAssertEqual(end.y, start.y - rise, accuracy: 1e-9, "\(joint) did not rise with the shoulders")
        }
        for joint in [LandmarkType.nose, .leftHip, .rightHip] {
            XCTAssertEqual(lifted[joint], relaxed[joint], "\(joint) moved while shrugging")
        }
    }

    func testZeroShoulderLiftLeavesEveryExistingGuideAndGhostUnchanged() throws {
        for exercise in ExerciseCatalog.all where exercise.id != .dumbbellShrug {
            let motion = exercise.guide.motion
            let samples = motionSamples(motion)
            for sample in samples {
                XCTAssertEqual(sample.shape.shoulderLift, 0, "\(exercise.id) has a shoulder lift")
                guard exercise.cameraView == .front else { continue }
                let pose = ExerciseDemoFigureView.pose(for: sample, forearmPlane: motion.forearmPlane,
                                                       cameraView: .front).jointLocations
                let expected = ExerciseDemoFigureView.lowered(ExerciseDemoFigureView.figureJoints, by: sample.legs)
                for joint in [LandmarkType.nose, .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip] {
                    XCTAssertEqual(pose[joint], expected[joint], "\(exercise.id) \(joint)")
                }
            }

            guard exercise.cameraView == .front, !motion.animatesLegs else { continue }
            let ready = try readyContext(for: exercise)
            let metrics = try XCTUnwrap(ready.harness.model.guideMetrics)
            let userLeft = try XCTUnwrap(containerPoint(.leftShoulder, in: ready.overlay))
            let userRight = try XCTUnwrap(containerPoint(.rightShoulder, in: ready.overlay))
            let userMidpoint = ArmGeometry.midpoint(userLeft, userRight)
            for sample in samples {
                let geometry = WorkoutGhostGeometry.make(overlay: ready.overlay, metrics: metrics, motion: motion,
                                                         cameraView: .front, containerSize: containerSize,
                                                         sample: sample)
                XCTAssertEqual(geometry.limbs.compactMap(\.points.first), [userLeft, userRight],
                               "\(exercise.id) ghost arms left the user's shoulders")

                let figure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                    fitOverlay: ready.overlay, metrics: metrics, motion: motion, cameraView: .front,
                    containerSize: containerSize, sample: sample))
                let pose = ExerciseDemoFigureView.pose(for: sample, forearmPlane: motion.forearmPlane,
                                                       cameraView: .front).jointLocations
                let figureMidpoint = ArmGeometry.midpoint(try XCTUnwrap(pose[.leftShoulder]),
                                                          try XCTUnwrap(pose[.rightShoulder]))
                let neck = try XCTUnwrap(figure.joints[.neck])
                XCTAssertEqual(neck.y - userMidpoint.y,
                               (try XCTUnwrap(pose[.neck]).y - figureMidpoint.y) * figure.bodyScale,
                               accuracy: 1e-6, "\(exercise.id) body no longer anchors on its own shoulders")
            }
        }
    }

    func testShrugGhostRaisesItsShouldersAndArmsByTheScaledLiftAtHalfAndDoubleScale() throws {
        let motion = DumbbellShrugExercise.definition().guide.motion
        var rises: [CGFloat] = []
        for scale in [CGFloat(0.5), 2] {
            let overlay = makeOverlay([
                .leftShoulder: CGPoint(x: 0.5 + 0.06 * scale, y: 0.6),
                .rightShoulder: CGPoint(x: 0.5 - 0.06 * scale, y: 0.6)
            ])
            let metrics = GuideMetrics(upperArm: 140 * scale, forearm: 124 * scale)
            let fit = CoordinateConverter.aspectFitRect(for: overlay.imageSize, in: containerSize)
            let rise = CGFloat(0.22) * metrics.upperArm * fit.width / overlay.imageSize.width
            rises.append(rise)

            let start = WorkoutGhostGeometry.make(overlay: overlay, metrics: metrics, motion: motion,
                                                  cameraView: .front, containerSize: containerSize,
                                                  sample: motion.startSample)
            let top = WorkoutGhostGeometry.make(overlay: overlay, metrics: metrics, motion: motion,
                                                cameraView: .front, containerSize: containerSize,
                                                sample: motion.topSample)
            guard start.limbs.count == 2, top.limbs.count == 2 else {
                return XCTFail("Expected two ghost arms at scale \(scale)")
            }
            for (startLimb, topLimb) in zip(start.limbs, top.limbs) {
                let shoulder = try XCTUnwrap(startLimb.joints.first)
                XCTAssertEqual(startLimb.points.first, try XCTUnwrap(containerPoint(shoulder, in: overlay)),
                               "The relaxed start must sit exactly on the user's shoulder")
                XCTAssertEqual(startLimb.points.count, topLimb.points.count)
                for (relaxed, lifted) in zip(startLimb.points, topLimb.points) {
                    XCTAssertEqual(lifted.x, relaxed.x, accuracy: 1e-9)
                    XCTAssertEqual(lifted.y, relaxed.y - rise, accuracy: 1e-9)
                }
            }

            let startFigure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                fitOverlay: overlay, metrics: metrics, motion: motion, cameraView: .front,
                containerSize: containerSize, sample: motion.startSample))
            let topFigure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                fitOverlay: overlay, metrics: metrics, motion: motion, cameraView: .front,
                containerSize: containerSize, sample: motion.topSample))
            for joint in [LandmarkType.nose, .leftHip, .rightHip] {
                let relaxed = try XCTUnwrap(startFigure.joints[joint])
                let lifted = try XCTUnwrap(topFigure.joints[joint])
                XCTAssertEqual(lifted.x, relaxed.x, accuracy: 1e-9, "\(joint) moved at scale \(scale)")
                XCTAssertEqual(lifted.y, relaxed.y, accuracy: 1e-9, "\(joint) moved at scale \(scale)")
            }
            XCTAssertLessThan(try XCTUnwrap(topFigure.joints[.neck]).y, try XCTUnwrap(startFigure.joints[.neck]).y)
            assertExactLimbs(top, in: topFigure, labels: nil)
        }
        guard rises.count == 2, let half = rises.first, let double = rises.last else {
            return XCTFail("Expected two rises")
        }
        XCTAssertEqual(double, half * 4, accuracy: 1e-9, "The lift scales with the user's upper arm")
    }

    func testShrugReadyGhostBlendsToExactlyTheCalibratedJoints() throws {
        let exercise = DumbbellShrugExercise.definition()
        let ready = try readyContext(for: exercise)
        let motion = exercise.guide.motion
        for sample in [motion.startSample, motion.topSample] {
            let calibrated = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                fitOverlay: ready.overlay, metrics: ready.harness.model.guideMetrics, motion: motion,
                cameraView: .front, containerSize: containerSize, sample: sample))
            let ideal = WorkoutGhostGeometry.ideal(overlay: nil, motion: motion, cameraView: .front,
                                                   containerSize: containerSize, sample: sample)
            let blended = WorkoutGhostGeometry.blended(from: ideal, to: calibrated, progress: 1)
            XCTAssertEqual(Set(blended.joints.keys), Set(calibrated.joints.keys))
            for (joint, point) in calibrated.joints {
                let end = try XCTUnwrap(blended.joints[joint])
                XCTAssertEqual(end.x, point.x, accuracy: 1e-9, "\(joint)")
                XCTAssertEqual(end.y, point.y, accuracy: 1e-9, "\(joint)")
            }
        }
    }

    func testCalibratedSquatAnklesEqualTheUsersAnkles() throws {
        let exercise = AirSquatExercise.definition()
        let ready = try readyContext(for: exercise)
        let keyframe = try XCTUnwrap(exercise.guide.motion.keyframes.first { $0.legs != .standing })
        let figure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: ready.overlay, metrics: ready.harness.model.guideMetrics,
            motion: exercise.guide.motion, cameraView: exercise.cameraView,
            containerSize: containerSize, sample: exercise.guide.motion.sample(of: keyframe)
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
                containerSize: containerSize, sample: exercise.guide.motion.sample(of: keyframe)
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

    /// Every resolved keyframe plus four interior samples per move.
    private func motionSamples(_ motion: ArmMotion) -> [ArmMotionSample] {
        var result: [ArmMotionSample] = []
        var elapsed: TimeInterval = 0
        for keyframe in motion.keyframes {
            result.append(motion.sample(of: keyframe))
            if keyframe.moveDuration > 0 {
                for step in 1...4 {
                    result.append(motion.sample(at: elapsed + keyframe.moveDuration * Double(step) / 5))
                }
            }
            elapsed += keyframe.moveDuration + keyframe.holdDuration
        }
        return result
    }

    private var hangingArms: ArmAngles {
        ArmAngles(upperArmElevation: -90, forearmElevation: -90)
    }

    private func sideMotion(shape: FigureShape) -> ArmMotion {
        ArmMotion(keyframes: [
            ArmKeyframe(angles: hangingArms, moveDuration: 0, holdDuration: 0.5, stepIndex: 0),
            ArmKeyframe(angles: hangingArms, moveDuration: 1, holdDuration: 0.5, stepIndex: 1, shape: shape)
        ])
    }

    private func sideBodyOverlay(motion: ArmMotion, scale: CGFloat, facing: CGFloat)
        -> (overlay: WorkoutOverlayState, nearSide: BodySide) {
        let imageSize = CGSize(width: 1080, height: 1920)
        let canonical = ExerciseDemoFigureView.pose(for: motion.startSample,
                                                    forearmPlane: motion.forearmPlane,
                                                    cameraView: .side).jointLocations
        let pixelScale = scale
        let xOffset = (imageSize.width - ExerciseDemoFigureView.canvasSize.width * pixelScale) / 2
        let yOffset = (imageSize.height - ExerciseDemoFigureView.canvasSize.height * pixelScale) / 2
        let nearSide: BodySide = facing > 0 ? .left : .right
        var landmarks: [LandmarkType: Landmark] = [:]
        for (joint, point) in canonical {
            let mappedJoint = facing > 0 ? joint : opposite(joint) ?? joint
            let x = facing > 0 ? point.x : ExerciseDemoFigureView.canvasSize.width - point.x
            let pixel = CGPoint(x: xOffset + x * pixelScale, y: yOffset + point.y * pixelScale)
            let normalized = CoordinateConverter.imagePixelToNormalized(pixel: pixel,
                                                                          imageWidth: imageSize.width,
                                                                          imageHeight: imageSize.height)
            landmarks[mappedJoint] = Landmark(type: mappedJoint, normalizedLocation: normalized,
                                               imageLocation: pixel, confidence: 0.9)
        }
        let required = [nearSide.shoulder, nearSide.hip, nearSide.knee, nearSide.ankle]
        let joints = Dictionary(uniqueKeysWithValues: required.compactMap { joint in
            landmarks[joint].map { (joint, OverlayJoint(location: $0.normalizedLocation, isStale: false)) }
        })
        let pose = BodyPose(landmarks: landmarks, imageWidth: imageSize.width, imageHeight: imageSize.height)
        return (WorkoutOverlayState(imageSize: imageSize, joints: joints, segments: [], endPositionSides: [],
                                    pose: pose), nearSide)
    }

    private func opposite(_ joint: LandmarkType) -> LandmarkType? {
        guard let side = BodySide.side(of: joint) else { return nil }
        let other: BodySide = side == .left ? .right : .left
        if joint == side.shoulder { return other.shoulder }
        if joint == side.elbow { return other.elbow }
        if joint == side.wrist { return other.wrist }
        if joint == side.hip { return other.hip }
        if joint == side.knee { return other.knee }
        if joint == side.ankle { return other.ankle }
        return nil
    }

    private func assertSideLegLengths(_ joints: [LandmarkType: CGPoint], side: BodySide,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let hip = try XCTUnwrap(joints[side.hip], file: file, line: line)
        let knee = try XCTUnwrap(joints[side.knee], file: file, line: line)
        let ankle = try XCTUnwrap(joints[side.ankle], file: file, line: line)
        let referenceHip = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftHip])
        let referenceKnee = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftKnee])
        let referenceAnkle = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftAnkle])
        XCTAssertEqual(ArmGeometry.distance(hip, knee), ArmGeometry.distance(referenceHip, referenceKnee),
                       accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(ArmGeometry.distance(knee, ankle), ArmGeometry.distance(referenceKnee, referenceAnkle),
                       accuracy: 0.0001, file: file, line: line)
    }

    private func assertFinite(_ joints: [LandmarkType: CGPoint],
                              file: StaticString = #filePath, line: UInt = #line) {
        for (joint, point) in joints {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite, "\(joint) was not finite", file: file, line: line)
        }
    }

    private func projectedX(of point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return start.x }
        let progress = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        return start.x + progress * dx
    }

    private func distance(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return ArmGeometry.distance(point, start) }
        let progress = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let nearest = CGPoint(x: start.x + progress * dx, y: start.y + progress * dy)
        return ArmGeometry.distance(point, nearest)
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

    private func makePixelOverlay(_ joints: [LandmarkType: CGPoint]) -> WorkoutOverlayState {
        let imageSize = CGSize(width: 1080, height: 1920)
        let normalized = joints.mapValues {
            CGPoint(x: $0.x / imageSize.width, y: $0.y / imageSize.height)
        }
        return makeOverlay(normalized)
    }

    private func overlay(from frame: PoseFrame) -> WorkoutOverlayState {
        WorkoutOverlayState(
            imageSize: frame.imageSize,
            joints: frame.pose.landmarks.mapValues { landmark in
                OverlayJoint(location: landmark.normalizedLocation, isStale: false)
            },
            segments: [],
            endPositionSides: [],
            pose: frame.pose
        )
    }
}
