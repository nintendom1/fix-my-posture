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
}
