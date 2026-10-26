import XCTest
@testable import PostureAnalysisApp

@MainActor
final class WorkoutFramePipelineTests: XCTestCase {
    func testGuideDemonstrationHasScaleInvariantEventsAndRepCount() {
        let motion = ShoulderPressExercise.definition().guide.motion
        let base = run(motion, scale: 1)

        for scale in [CGFloat(0.5), 2] {
            let scaled = run(motion, scale: scale)
            XCTAssertEqual(scaled.events, base.events, "Reducer events should not depend on pixel scale.")
            XCTAssertEqual(scaled.repCount, base.repCount)
        }
        XCTAssertEqual(base.repCount, 3)
    }

    func testTiltIsReportedOnlyAfterExistingDebounce() {
        var pipeline = WorkoutFramePipeline(exercise: ShoulderPressExercise.definition())

        XCTAssertNil(pipeline.processTiltSample(pitchDegrees: 20, at: 0))
        XCTAssertNil(pipeline.processTiltSample(pitchDegrees: 20, at: 0.99))
        XCTAssertEqual(pipeline.processTiltSample(pitchDegrees: 20, at: 1), .phoneTiltChanged(true))
    }

    func testChangingViewRebuildsAnalyzerWithoutCompletingOldRep() {
        let exercise = ShoulderPressExercise.definition()
        let motion = exercise.guide.motion
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)

        for index in 0...15 {
            _ = pipeline.process(frame: frame(motion: motion, at: Double(index) / 10), at: Double(index) / 10)
        }
        pipeline.viewChanged(to: .side, analyzerEpoch: 2)

        var events: [WorkoutEvent] = []
        let end = motion.duration
        for index in 16...Int(end * 10) {
            let time = Double(index) / 10
            events += pipeline.process(frame: frame(motion: motion, at: time), at: time).events
        }

        XCTAssertFalse(events.contains { if case .repCompleted = $0 { true } else { false } })
    }

    func testChangingExerciseRebuildsAnalyzerWithoutCompletingOldRep() {
        let oldExercise = ShoulderPressExercise.definition()
        let newExercise = HammerCurlExercise.definition()
        let motion = oldExercise.guide.motion
        var pipeline = WorkoutFramePipeline(exercise: oldExercise, analyzerEpoch: 1, isCounting: true)

        for index in 0...15 {
            _ = pipeline.process(frame: frame(motion: motion, at: Double(index) / 10), at: Double(index) / 10)
        }
        pipeline.exerciseChanged(to: newExercise, analyzerEpoch: 2)

        var events: [WorkoutEvent] = []
        for index in 16...Int(motion.duration * 10) {
            let time = Double(index) / 10
            events += pipeline.process(frame: frame(motion: motion, at: time), at: time).events
        }

        XCTAssertFalse(events.contains { if case .repCompleted = $0 { true } else { false } })
    }

    func testTricepsMetricsUseUpperArmFallbackWithoutHipOrWrist() throws {
        let shoulder = CGPoint(x: 400, y: 300)
        let elbow = CGPoint(x: 400, y: 420)
        var pipeline = WorkoutFramePipeline(exercise: TricepsExtensionExercise.definition())

        // Read the first frame so no smoothing has been applied yet.
        let output = pipeline.process(frame: measurementFrame([.leftShoulder: shoulder,
                                                                .leftElbow: elbow], at: 0), at: 0)
        let metrics = try XCTUnwrap(output.guideMetrics)
        let upperArmLength = ArmGeometry.distance(shoulder, elbow)

        XCTAssertEqual(GuideMetrics.forearmToUpperArm,
                       GuideMetrics.forearmToTorso / GuideMetrics.upperArmToTorso, accuracy: 0.01)
        XCTAssertEqual(metrics.upperArm, upperArmLength, accuracy: 0.01)
        XCTAssertEqual(metrics.forearm, upperArmLength * GuideMetrics.forearmToUpperArm, accuracy: 0.01)
    }

    func testRowMetricsUseMeasuredArmWhenHipIsOutOfFrame() throws {
        let shoulder = CGPoint(x: 320, y: 260)
        let elbow = CGPoint(x: 400, y: 340)
        let wrist = CGPoint(x: 460, y: 430)
        var pipeline = WorkoutFramePipeline(exercise: DumbbellRowExercise.definition())

        // Read the first frame so no smoothing has been applied yet.
        let output = pipeline.process(frame: measurementFrame([.leftShoulder: shoulder,
                                                                .leftElbow: elbow,
                                                                .leftWrist: wrist], at: 0), at: 0)
        let metrics = try XCTUnwrap(output.guideMetrics)

        XCTAssertEqual(metrics.upperArm, ArmGeometry.distance(shoulder, elbow), accuracy: 0.01)
        XCTAssertEqual(metrics.forearm, ArmGeometry.distance(elbow, wrist), accuracy: 0.01)
    }

    func testRowMetricsKeepTorsoReferenceWhenHipIsVisible() throws {
        let shoulder = CGPoint(x: 320, y: 260)
        let hip = CGPoint(x: 320, y: 460)
        let elbow = CGPoint(x: 390, y: 300)
        let wrist = CGPoint(x: 450, y: 380)
        var pipeline = WorkoutFramePipeline(exercise: DumbbellRowExercise.definition())

        // Read the first frame so no smoothing has been applied yet.
        let output = pipeline.process(frame: measurementFrame([.leftShoulder: shoulder,
                                                                .leftHip: hip,
                                                                .leftElbow: elbow,
                                                                .leftWrist: wrist], at: 0), at: 0)
        let metrics = try XCTUnwrap(output.guideMetrics)
        let torsoLength = ArmGeometry.distance(shoulder, hip)
        let upperArmLength = ArmGeometry.distance(shoulder, elbow)
        let forearmLength = ArmGeometry.distance(elbow, wrist)
        let expectedUpperArm = GuideMetrics.plausibleTorsoRatio.contains(upperArmLength / torsoLength)
            ? upperArmLength : torsoLength * GuideMetrics.upperArmToTorso
        let expectedForearm = GuideMetrics.plausibleTorsoRatio.contains(forearmLength / torsoLength)
            ? forearmLength : torsoLength * GuideMetrics.forearmToTorso

        XCTAssertEqual(metrics.upperArm, expectedUpperArm, accuracy: 0.01)
        XCTAssertEqual(metrics.forearm, expectedForearm, accuracy: 0.01)
    }

    func testSideBodyMetricsReferenceUsesOnlyReadyJoints() throws {
        let angles = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        let motion = ArmMotion(keyframes: [
            ArmKeyframe(angles: angles, moveDuration: 0, holdDuration: 0.5, stepIndex: 0),
            ArmKeyframe(angles: angles, moveDuration: 1, holdDuration: 0.5, stepIndex: 1,
                        shape: FigureShape(torsoPitch: 60, hipShift: 1, hipDrop: 0.2))
        ])
        let required: [LandmarkType] = [.leftShoulder, .leftHip, .leftKnee, .leftAnkle]
        let landmarks = Dictionary(uniqueKeysWithValues: required.compactMap { joint in
            ExerciseDemoFigureView.sideFigureJoints[joint].map { point in
                (joint, Landmark(type: joint, normalizedLocation: .zero,
                                 imageLocation: point, confidence: 0.9))
            }
        })
        let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 300, imageHeight: 470), timestamp: 0)
        let pipeline = WorkoutFramePipeline(exercise: TricepsExtensionExercise.definition())

        let reference = try XCTUnwrap(pipeline.metricsReference(frame, confidence: 0.8,
                                                               cameraView: .side, motion: motion))
        let hip = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftHip])
        let knee = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftKnee])
        let ankle = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftAnkle])
        let legLength = ArmGeometry.distance(hip, knee) + ArmGeometry.distance(knee, ankle)
        XCTAssertEqual(reference.length, legLength, accuracy: 0.001)
        XCTAssertEqual(reference.length * reference.upperArm,
                       ExerciseDemoFigureView.upperArm, accuracy: 0.001)
        XCTAssertEqual(reference.length * reference.forearm,
                       ExerciseDemoFigureView.forearm, accuracy: 0.001)
    }

    func testLyingSideBridgeMetricsUseTheLyingGuideLegProportions() throws {
        let bridge = GluteBridgeExercise.definition()
        let hip = CGPoint(x: 250, y: 700)
        let knee = CGPoint(x: 340, y: 760)
        let ankle = CGPoint(x: 430, y: 700)
        let frame = measurementFrame([
            .leftShoulder: CGPoint(x: 170, y: 700),
            .leftHip: hip,
            .leftKnee: knee,
            .leftAnkle: ankle
        ], at: 0)
        let pipeline = WorkoutFramePipeline(exercise: bridge)

        let reference = try XCTUnwrap(pipeline.metricsReference(frame, confidence: 0.8,
                                                               cameraView: .lyingSide,
                                                               motion: bridge.guide.motion))
        let legLength = ArmGeometry.distance(hip, knee) + ArmGeometry.distance(knee, ankle)
        let guideLegLength = ExerciseDemoFigureView.lyingSideThigh + ExerciseDemoFigureView.lyingSideShin

        XCTAssertEqual(reference.length, legLength, accuracy: 0.001)
        XCTAssertEqual(reference.upperArm, ExerciseDemoFigureView.upperArm / guideLegLength, accuracy: 0.001)
        XCTAssertEqual(reference.forearm, ExerciseDemoFigureView.forearm / guideLegLength, accuracy: 0.001)
    }

    func testRowMetricsUseTypicalForearmWhenMeasuredForearmIsImplausible() throws {
        let shoulder = CGPoint(x: 320, y: 260)
        let elbow = CGPoint(x: 420, y: 260)
        let wrist = CGPoint(x: 420, y: 460)
        var pipeline = WorkoutFramePipeline(exercise: DumbbellRowExercise.definition())

        // Read the first frame so no smoothing has been applied yet.
        let output = pipeline.process(frame: measurementFrame([.leftShoulder: shoulder,
                                                                .leftElbow: elbow,
                                                                .leftWrist: wrist], at: 0), at: 0)
        let metrics = try XCTUnwrap(output.guideMetrics)
        let upperArmLength = ArmGeometry.distance(shoulder, elbow)

        XCTAssertEqual(metrics.upperArm, upperArmLength, accuracy: 0.01)
        XCTAssertEqual(metrics.forearm, upperArmLength * GuideMetrics.forearmToUpperArm, accuracy: 0.01)
    }

    func testNoPoseClearsOverlayAndReportsFramingLost() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0), at: 0)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0.6), at: 0.6)

        let noPose = PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: 0.91)
        let output = pipeline.process(frame: noPose, at: 0.91)

        XCTAssertNil(output.overlay)
        XCTAssertTrue(output.events.contains {
            if case .framingChanged(let status) = $0 { return !status.isReliable }
            return false
        })
    }

    func testGhostFitOverlayCalibratesAndSurvivesBriefDropout() throws {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise)

        for index in 0...6 {
            let time = Double(index) / 10
            let output = pipeline.process(frame: frame(motion: exercise.guide.motion, at: time), at: time)
            if index < 6 {
                XCTAssertNil(output.ghostFitOverlay)
            } else {
                XCTAssertNotNil(output.ghostFitOverlay)
            }
        }

        let lastAvailable = try XCTUnwrap(pipeline.ghostFitOverlay)
        for index in 7...11 {
            let time = Double(index) / 10
            let output = pipeline.process(frame: emptyFrame(at: time), at: time)
            XCTAssertNil(output.overlay)
            XCTAssertEqual(output.ghostFitOverlay, lastAvailable)
        }

        for index in 12...15 {
            let time = Double(index) / 10
            XCTAssertEqual(pipeline.process(frame: emptyFrame(at: time), at: time).ghostFitOverlay, lastAvailable)
        }
        XCTAssertNil(pipeline.process(frame: emptyFrame(at: 1.6), at: 1.6).ghostFitOverlay)
    }

    func testResetTrackingClearsGhostFitOverlay() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = calibratedPipeline(for: exercise)
        XCTAssertNotNil(pipeline.ghostFitOverlay)

        _ = pipeline.resetTracking()

        XCTAssertNil(pipeline.ghostFitOverlay)
    }

    func testChangingExerciseClearsGhostFitOverlay() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = calibratedPipeline(for: exercise)
        XCTAssertNotNil(pipeline.ghostFitOverlay)

        pipeline.exerciseChanged(to: HammerCurlExercise.definition(), analyzerEpoch: 2)

        XCTAssertNil(pipeline.ghostFitOverlay)
    }

    func testFramingReliabilityChangesAnalyzerCountingOnThatFrame() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0), at: 0)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0.6), at: 0.6)
        XCTAssertTrue(pipeline.isCounting)

        let empty = PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: 0.91)
        _ = pipeline.process(frame: empty, at: 0.91)
        XCTAssertFalse(pipeline.isCounting)

        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 1), at: 1)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 1.6), at: 1.6)
        XCTAssertTrue(pipeline.isCounting)
    }

    func testLateralSideRoomFeedsFramingReliabilityFromPipeline() {
        let exercise = LateralRaiseExercise.definition()
        let closePose: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 680, y: 600), .leftElbow: CGPoint(x: 680, y: 825),
            .leftWrist: CGPoint(x: 680, y: 1050), .rightShoulder: CGPoint(x: 400, y: 600),
            .rightElbow: CGPoint(x: 400, y: 825), .rightWrist: CGPoint(x: 400, y: 1050)
        ]
        var closePipeline = WorkoutFramePipeline(exercise: exercise)
        var closeStatuses: [FramingStatus] = []
        for index in 0...8 {
            let time = Double(index) / 10
            let output = closePipeline.process(frame: measurementFrame(closePose, at: time), at: time)
            closeStatuses += output.events.compactMap { event in
                guard case .framingChanged(let status) = event else { return nil }
                return status
            }
        }
        XCTAssertTrue(closeStatuses.contains {
            !$0.isReliable && $0.guidance == .stepBackSideRoom
        })
        XCTAssertFalse(closeStatuses.contains(where: \.isReliable))

        let fartherPose: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 630, y: 600), .leftElbow: CGPoint(x: 630, y: 750),
            .leftWrist: CGPoint(x: 630, y: 900), .rightShoulder: CGPoint(x: 450, y: 600),
            .rightElbow: CGPoint(x: 450, y: 750), .rightWrist: CGPoint(x: 450, y: 900)
        ]
        var fartherPipeline = WorkoutFramePipeline(exercise: exercise)
        var fartherStatuses: [FramingStatus] = []
        for index in 0...6 {
            let time = Double(index) / 10
            let output = fartherPipeline.process(frame: measurementFrame(fartherPose, at: time), at: time)
            fartherStatuses += output.events.compactMap { event in
                guard case .framingChanged(let status) = event else { return nil }
                return status
            }
        }
        XCTAssertTrue(fartherStatuses.contains { $0.isReliable && $0.guidance == nil })
    }

    func testLateralRaiseCalibratedGhostAndDumbbellsFitAtAcceptedSideRoomDistance() throws {
        let exercise = LateralRaiseExercise.definition()
        let imageSize = CGSize(width: 1080, height: 1920)
        let containerSize = imageSize
        let points: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 630, y: 600), .leftElbow: CGPoint(x: 630, y: 750),
            .leftWrist: CGPoint(x: 630, y: 900), .rightShoulder: CGPoint(x: 450, y: 600),
            .rightElbow: CGPoint(x: 450, y: 750), .rightWrist: CGPoint(x: 450, y: 900)
        ]
        let frame = measurementFrame(points, at: 0)
        let overlay = WorkoutOverlayState(
            imageSize: imageSize,
            joints: frame.pose.landmarks.mapValues { OverlayJoint(location: $0.normalizedLocation, isStale: false) },
            segments: [],
            endPositionSides: [],
            pose: frame.pose
        )
        let metrics = GuideMetrics(upperArm: 150, forearm: 150)
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let shoulderEdgeRoom: CGFloat = 450
        let requiredEdgeRoom = try XCTUnwrap(exercise.sideroomArmLengths) * 300 + 0.02 * imageSize.width
        XCTAssertGreaterThan(shoulderEdgeRoom, requiredEdgeRoom)

        for (index, keyframe) in exercise.guide.motion.keyframes.enumerated() {
            let figure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                fitOverlay: overlay,
                metrics: metrics,
                motion: exercise.guide.motion,
                cameraView: exercise.cameraView,
                containerSize: containerSize,
                sample: exercise.guide.motion.sample(of: keyframe)
            ), "Keyframe \(index) did not calibrate")
            XCTAssertTrue(figure.isCalibrated)
            XCTAssertEqual(figure.dumbbells.count, 2, "Keyframe \(index) must include both dumbbells")
            for (joint, point) in figure.joints {
                XCTAssertTrue(imageBounds.contains(point), "Keyframe \(index) \(joint) fell outside the image: \(point)")
            }
            if let nose = figure.joints[.nose] {
                let headRadius = figure.bodyScale * ExerciseDemoFigureView.canvasSize.width * 0.05
                let headBounds = CGRect(x: nose.x - headRadius,
                                        y: nose.y - headRadius * 1.2,
                                        width: headRadius * 2,
                                        height: headRadius * 2.4)
                XCTAssertTrue(imageBounds.contains(headBounds), "Keyframe \(index) head fell outside the image")
            }
            for (dumbbellIndex, dumbbell) in figure.dumbbells.enumerated() {
                let bounds = DumbbellDrawing.bounds(elbow: dumbbell.elbow, wrist: dumbbell.wrist,
                                                    forearmLength: figure.forearmLength)
                XCTAssertTrue(imageBounds.contains(bounds),
                              "Keyframe \(index) dumbbell \(dumbbellIndex) fell outside the image: \(bounds)")
            }
        }
    }

    func testOffscreenWristsKeepSetFramingReliableAndDoNotEnterOverlay() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        var repCount = 0
        var sawDropout = false
        var becameReliable = false

        for index in 0...Int(exercise.guide.motion.duration * 10) {
            let time = Double(index) / 10
            let raw = pressFrame(exercise.guide.motion, at: time)
            let output = pipeline.process(frame: raw, at: time)
            repCount += output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
            XCTAssertTrue(pipeline.isCounting)
            for event in output.events {
                guard case .framingChanged(let status) = event else { continue }
                if status.isReliable {
                    becameReliable = true
                } else if becameReliable {
                    XCTFail("Framing became unreliable during the set at \(time)s.")
                }
            }

            if raw.pose[.leftWrist] == nil {
                sawDropout = true
                XCTAssertNil(output.overlay?.pose[.leftWrist])
                XCTAssertNil(output.overlay?.pose[.rightWrist])
                XCTAssertTrue(output.overlay?.joints[.leftWrist]?.isStale ?? true)
                XCTAssertTrue(output.overlay?.joints[.rightWrist]?.isStale ?? true)
            }
        }

        XCTAssertTrue(sawDropout)
        XCTAssertTrue(becameReliable)
        XCTAssertGreaterThan(repCount, 0, "Completed wrist estimates should keep the rep cycle alive.")
    }

    func testOffscreenWristsStillLoseFramingBeforeAndAtReady() {
        let exercise = ShoulderPressExercise.definition()
        for phase in [WorkoutPhase.framing, .ready] {
            var pipeline = WorkoutFramePipeline(exercise: exercise)
            pipeline.setSessionPhase(phase)
            var becameReliable = false
            var lostReliability = false
            for index in 0...Int(exercise.guide.motion.duration * 10) {
                let time = Double(index) / 10
                let output = pipeline.process(frame: pressFrame(exercise.guide.motion, at: time), at: time)
                for event in output.events {
                    guard case .framingChanged(let status) = event else { continue }
                    if status.isReliable {
                        becameReliable = true
                    } else if becameReliable {
                        lostReliability = true
                    }
                }
            }
            XCTAssertTrue(becameReliable, "\(phase) framing should first become reliable.")
            XCTAssertTrue(lostReliability, "Raw wrist loss must then make \(phase) framing unreliable.")
        }
    }

    private func run(_ motion: ArmMotion, scale: CGFloat) -> (events: [WorkoutEvent], repCount: Int) {
        let exercise = ShoulderPressExercise.definition()
        var session = WorkoutSession(exercises: [exercise], initialExercise: exercise.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 0)
        _ = session.handle(.command(.start), at: 0)
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: session.analyzerEpoch, isCounting: true)
        var events: [WorkoutEvent] = []

        for index in 0..<(Int(motion.duration * 10) * 3) {
            let time = Double(index) / 10
            let output = pipeline.process(frame: frame(motion: motion, at: time, scale: scale), at: time)
            events += output.events
            for event in output.events {
                if case .repCompleted = event {
                    _ = session.handle(event, at: time)
                }
            }
        }
        return (events, session.repCount)
    }

    private func calibratedPipeline(for exercise: ExerciseDefinition) -> WorkoutFramePipeline {
        var pipeline = WorkoutFramePipeline(exercise: exercise)
        for index in 0...6 {
            let time = Double(index) / 10
            _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: time), at: time)
        }
        return pipeline
    }

    private func frame(motion: ArmMotion, at time: TimeInterval, scale: CGFloat = 1) -> PoseFrame {
        let sample = motion.sample(at: time)
        let reference = ExerciseDemoFigureView.pose(for: sample.angles, legs: sample.legs,
                                                     forearmPlane: motion.forearmPlane)
        let width = 1080 * scale
        let height = 1920 * scale
        let landmarks = Dictionary(uniqueKeysWithValues: reference.jointLocations.map { type, point in
            let pixel = CGPoint(x: point.x * scale, y: point.y * scale)
            return (type, Landmark(type: type,
                                   normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                    pixel: pixel, imageWidth: width, imageHeight: height),
                                   imageLocation: pixel,
                                   confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height), timestamp: time)
    }

    private func pressFrame(_ motion: ArmMotion, at time: TimeInterval) -> PoseFrame {
        let sample = motion.sample(at: time)
        let reference = ExerciseDemoFigureView.pose(for: sample.angles, legs: sample.legs,
                                                     forearmPlane: motion.forearmPlane)
        let landmarks = Dictionary(uniqueKeysWithValues: reference.jointLocations.compactMap { type, point -> (LandmarkType, Landmark)? in
            let pixel = CGPoint(x: point.x, y: point.y - 50)
            if [.leftWrist, .rightWrist].contains(type), pixel.y < 0 { return nil }
            return (type, Landmark(type: type,
                                   normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                    pixel: pixel, imageWidth: 1080, imageHeight: 1920),
                                   imageLocation: pixel,
                                   confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }

    private func measurementFrame(_ points: [LandmarkType: CGPoint], at time: TimeInterval) -> PoseFrame {
        let width: CGFloat = 1080
        let height: CGFloat = 1920
        let landmarks = Dictionary(uniqueKeysWithValues: points.map { type, pixel in
            (type, Landmark(type: type,
                            normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                pixel: pixel, imageWidth: width, imageHeight: height),
                            imageLocation: pixel,
                            confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height), timestamp: time)
    }

    private func emptyFrame(at time: TimeInterval) -> PoseFrame {
        PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }
}
