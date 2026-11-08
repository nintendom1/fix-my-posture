import CoreGraphics
import XCTest
@testable import PostureAnalysisApp

final class WallPushUpAnalyzerTests: XCTestCase {
    private let exercise = WallPushUpExercise.definition()

    func testGuideDemoCountsOncePerLoopFacingEitherWayAtScaleAndWithSegmentVariation() {
        let cases: [(CGFloat, CGFloat, CGFloat, Bool)] = [
            (1, 1, 1, false), (0.5, 1, 1, true), (2, 1, 1, false),
            (1, 1.15, 1, true), (1, 0.85, 1, false),
            (1, 1, 1.15, true), (1, 1, 0.85, false)
        ]
        for (scale, upper, forearm, mirrored) in cases {
            let result = run(exercise.guide.motion, analyzer: WallPushUpAnalyzer(epoch: 1), loops: 3,
                             imageScale: scale, upperArmScale: upper, forearmScale: forearm,
                             mirrored: mirrored)
            XCTAssertEqual(result.reps, 3,
                           "scale \(scale), upper \(upper), forearm \(forearm), mirrored \(mirrored)")
            XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "Demo cues: \(result.forms)")
        }
    }

    func testFullAndShallowGuideDemosMeetTheirMeasuredThresholds() throws {
        let fullStart = try XCTUnwrap(ExerciseDemoFigureView.wallPushUpPose(for: exercise.guide.motion.startAngles)
            .jointLocations[.leftShoulder])
        let fullDown = try XCTUnwrap(ExerciseDemoFigureView.wallPushUpPose(for: exercise.guide.motion.topAngles)
            .jointLocations[.leftShoulder])
        let fullStartPose = ExerciseDemoFigureView.wallPushUpPose(for: exercise.guide.motion.startAngles)
        let fullDownPose = ExerciseDemoFigureView.wallPushUpPose(for: exercise.guide.motion.topAngles)
        let up = try armMetrics(fullStartPose.jointLocations)
        let down = try armMetrics(fullDownPose.jointLocations)
        XCTAssertEqual(up.elbowAngle, 180, accuracy: 0.001)
        XCTAssertEqual(up.horizontalRatio, 1, accuracy: 0.001)
        XCTAssertEqual(down.elbowAngle, 70, accuracy: 0.001)
        XCTAssertEqual(down.horizontalRatio, 0.556, accuracy: 0.002)
        XCTAssertNotEqual(fullStart, fullDown)

        let shallow = try XCTUnwrap(exercise.reducedRange?())
        let shallowMetrics = try armMetrics(
            ExerciseDemoFigureView.wallPushUpPose(for: shallow.guide.motion.topAngles).jointLocations
        )
        XCTAssertEqual(shallowMetrics.elbowAngle, 120, accuracy: 0.001)
        XCTAssertEqual(shallowMetrics.horizontalRatio, 0.866, accuracy: 0.002)
        XCTAssertEqual(shallow.displayName, "Shallow Wall Push-Up")
        XCTAssertEqual(shallow.id, exercise.id)
    }

    func testNormalNinetyDegreeWallPushUpCountsWithFifteenPercentSegmentVariation() {
        let up = exercise.guide.motion.startAngles
        let normalDown = ArmAngles(upperArmElevation: -65, forearmElevation: 25)
        let motion = motion(with: [(up, 0, 1.0, 0), (normalDown, 1.2, 0.3, 1), (up, 1.2, 0, 2)])
        for (upper, forearm) in [(CGFloat(0.85), CGFloat(1.15)), (CGFloat(1.15), CGFloat(0.85))] {
            let result = run(motion, analyzer: WallPushUpAnalyzer(epoch: 20), loops: 1,
                             upperArmScale: upper, forearmScale: forearm)
            XCTAssertEqual(result.reps, 1, "upper \(upper), forearm \(forearm)")
        }
    }

    func testPlantedPushUpsFrameAndCountWithoutTheHipAndIgnoreALowConfidenceHip() throws {
        let definitions = [exercise, try XCTUnwrap(exercise.reducedRange?()), InclinePushUpExercise.definition()]
        for definition in definitions {
            XCTAssertFalse(definition.centersInFrame, definition.displayName)

            var framing = framingEvaluator(for: definition)
            var reliable = false
            for index in 0...8 {
                let frame = plantedFrame(definition, at: Double(index) / 10, includeHip: false,
                                         hipConfidence: 0.3, xOffset: 180)
                let status = framing.evaluate(frame)
                reliable = status.isReliable
                if let guidance = status.guidance {
                    XCTAssertFalse([FramingGuidance.moveLeft, .moveRight].contains(guidance),
                                   definition.displayName + " emitted side-view centering guidance")
                }
            }
            XCTAssertTrue(reliable, definition.displayName + " lost framing without a hip")
            XCTAssertTrue(definition.anyOfRequiredJoints.allSatisfy {
                $0 == [.leftShoulder, .leftElbow, .leftWrist] || $0 == [.rightShoulder, .rightElbow, .rightWrist]
            }, definition.displayName)

            let analyzer = definition.makeAnalyzer(30)
            var reps = 0
            let motion = definition.guide.motion
            for index in 0...Int((motion.duration * 10).rounded()) {
                let time = Double(index) / 10
                let frame = plantedFrame(definition, at: time, includeHip: false, hipConfidence: 0.3)
                reps += analyzer.process(frame, counting: true).repEvents.count
            }
            XCTAssertEqual(reps, 1, definition.displayName + " should count from its arm alone")

            var lowHipFraming = framingEvaluator(for: definition)
            for index in 0...8 {
                let frame = plantedFrame(definition, at: Double(index) / 10, includeHip: true,
                                         hipConfidence: 0.3)
                reliable = lowHipFraming.evaluate(frame).isReliable
            }
            XCTAssertTrue(reliable, "A hip at confidence 0.3 must not drop " + definition.displayName + " framing")
        }

        let other = ShoulderPressExercise.definition()
        XCTAssertTrue(other.centersInFrame)
        var otherFraming = framingEvaluator(for: other)
        let fixture = try XCTUnwrap(ReadyPoseFixtures.variants(for: other).first { $0.name == "full" })
        var centeredGuide = fixture.pose.landmarks
        centeredGuide = centeredGuide.mapValues { landmark in
            let pixel = CGPoint(x: landmark.imageLocation.x + 420, y: landmark.imageLocation.y)
            return Landmark(type: landmark.type,
                            normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                pixel: pixel, imageWidth: fixture.pose.imageWidth, imageHeight: fixture.pose.imageHeight),
                            imageLocation: pixel, confidence: landmark.confidence)
        }
        let offCenter = PoseFrame(pose: BodyPose(landmarks: centeredGuide, imageWidth: fixture.pose.imageWidth,
                                                 imageHeight: fixture.pose.imageHeight), timestamp: 0)
        XCTAssertEqual(otherFraming.evaluate(offCenter).guidance, .moveRight,
                       "Center guidance stays enabled for exercises that use the default.")
    }

    func testShallowVariantCountsItsDemoAndAcceptsFullDepth() throws {
        let shallow = try XCTUnwrap(exercise.reducedRange?())
        let shallowRun = run(shallow.guide.motion, analyzer: shallow.makeAnalyzer(2), loops: 1)
        XCTAssertEqual(shallowRun.reps, 1)
        XCTAssertTrue(shallowRun.forms.allSatisfy { $0.flags.isEmpty }, "Shallow demo cues: \(shallowRun.forms)")

        let fullRun = run(exercise.guide.motion,
                          analyzer: WallPushUpAnalyzer(epoch: 3, configuration: .reducedRange), loops: 1)
        XCTAssertEqual(fullRun.reps, 1, "A full-depth wall push-up also passes the shallow line.")
    }

    func testEightNearThresholdReturnsDoNotRatchetTheLockedArmRuler() {
        let analyzer = WallPushUpAnalyzer(epoch: 4)
        var time = 0.0
        var reps = 0
        var currentScale: CGFloat = 1
        var currentAngles = nearThresholdUpAngles(segmentScale: 1)

        func send(_ angles: ArmAngles, segmentScale: CGFloat) {
            let sample = ArmMotionSample(angles: angles, stepIndex: 0, wallPushUp: true)
            let output = analyzer.process(frame(sample: sample, at: time, upperArmScale: segmentScale,
                                                forearmScale: segmentScale), counting: true)
            reps += output.repEvents.count
            time += 0.1
        }

        send(currentAngles, segmentScale: currentScale)
        send(currentAngles, segmentScale: currentScale)
        for repIndex in 0..<8 {
            let nextScale = 1 + CGFloat(repIndex + 1) * 0.05
            let nextAngles = nearThresholdUpAngles(segmentScale: nextScale)
            for step in 1...12 {
                let progress = Double(step) / 12
                send(interpolate(currentAngles, fullDownAngles, progress),
                     segmentScale: currentScale + (1 - currentScale) * CGFloat(progress))
            }
            for _ in 0..<3 { send(fullDownAngles, segmentScale: 1) }
            for step in 1...12 {
                let progress = Double(step) / 12
                send(interpolate(fullDownAngles, nextAngles, progress),
                     segmentScale: 1 + (nextScale - 1) * CGFloat(progress))
            }
            send(nextAngles, segmentScale: nextScale)
            send(nextAngles, segmentScale: nextScale)
            currentAngles = nextAngles
            currentScale = nextScale
        }

        XCTAssertEqual(reps, 8)
    }

    func testGapClearsReferencesBeforeTranslatedAndScaledReacquisition() {
        let analyzer = WallPushUpAnalyzer(epoch: 5)
        var reps = 0
        var trace: [String] = []
        func send(_ angles: ArmAngles, at time: TimeInterval, scale: CGFloat = 1,
                  translate: CGPoint = .zero) {
            let sample = ArmMotionSample(angles: angles, stepIndex: 0, wallPushUp: true)
            let output = analyzer.process(frame(sample: sample, at: time, imageScale: scale,
                                                translate: translate), counting: true)
            trace.append("t=\(time): reading=\(String(describing: output.readings[.left])), held=\(output.startPositionHeld), reps=\(output.repEvents.count), rejected=\(output.rejections)")
            reps += output.repEvents.count
        }

        send(exercise.guide.motion.startAngles, at: 0)
        send(exercise.guide.motion.startAngles, at: 0.1)
        send(exercise.guide.motion.topAngles, at: 0.2)
        send(exercise.guide.motion.topAngles, at: 0.3)
        send(exercise.guide.motion.startAngles, at: 1.0, scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(exercise.guide.motion.startAngles, at: 1.1, scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(exercise.guide.motion.topAngles, at: 1.2, scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(exercise.guide.motion.topAngles, at: 1.3, scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(exercise.guide.motion.topAngles, at: 1.4, scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(exercise.guide.motion.topAngles, at: 1.5, scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(ArmAngles(upperArmElevation: -37.5, forearmElevation: 2.5), at: 1.7,
             scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(ArmAngles(upperArmElevation: -37.5, forearmElevation: 2.5), at: 1.8,
             scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(exercise.guide.motion.startAngles, at: 1.9, scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(exercise.guide.motion.startAngles, at: 2.0, scale: 1.5, translate: CGPoint(x: 50, y: -80))
        send(exercise.guide.motion.startAngles, at: 2.1, scale: 1.5, translate: CGPoint(x: 50, y: -80))

        XCTAssertEqual(reps, 1, trace.joined(separator: "\n"))
    }

    func testDeeperBodyLineAndLockoutCuesFireOnlyForTheirTriggers() {
        let partial = motion(with: [
            (exercise.guide.motion.startAngles, 0, 1.0, 0),
            (ArmAngles(upperArmElevation: -37.5, forearmElevation: 2.5), 1.2, 0.3, 1),
            (exercise.guide.motion.startAngles, 1.2, 0, 2)
        ])
        let partialRun = run(partial, analyzer: WallPushUpAnalyzer(epoch: 6), loops: 1)
        XCTAssertEqual(partialRun.reps, 0)
        XCTAssertTrue(partialRun.forms.contains { $0.flags.contains(.wallPushUpDeeper) }, "\(partialRun.forms)")
        XCTAssertFalse(partialRun.forms.contains { $0.flags.contains(.wallPushUpBodyLine) })

        let bentRun = run(exercise.guide.motion, analyzer: WallPushUpAnalyzer(epoch: 7), loops: 1,
                          hipOffsetOnDown: CGPoint(x: 65, y: 0))
        XCTAssertEqual(bentRun.reps, 1)
        XCTAssertTrue(bentRun.forms.contains { $0.flags.contains(.wallPushUpBodyLine) }, "\(bentRun.forms)")

        let lockout = motion(with: [
            (exercise.guide.motion.startAngles, 0, 1.0, 0),
            (fullDownAngles, 1.2, 0.3, 1),
            (ArmAngles(upperArmElevation: -37.5, forearmElevation: 2.5), 0.8, 0.2, 1),
            (fullDownAngles, 0.8, 0.3, 1),
            (exercise.guide.motion.startAngles, 1.2, 0, 2)
        ])
        let lockoutRun = run(lockout, analyzer: WallPushUpAnalyzer(epoch: 8), loops: 1)
        XCTAssertEqual(lockoutRun.reps, 1)
        XCTAssertTrue(lockoutRun.forms.contains { $0.flags.contains(.wallPushUpLockout) }, "\(lockoutRun.forms)")
    }

    func testLosingTheTrackedArmPicksTheOtherAfterAGapAndNeedsAFreshUp() {
        let up = exercise.guide.motion.startAngles
        let analyzer = WallPushUpAnalyzer(epoch: 11)
        // Left arm: Up, then most of the way down, then it leaves the frame.
        var left = Player(analyzer: analyzer, test: self)
        left.play([(up, 3), (fullDownAngles, 3)])
        XCTAssertEqual(left.reps, 0)

        var right = Player(analyzer: analyzer, test: self, start: left.time + 0.1, rightArm: true)
        let occluded = right.step(up)
        XCTAssertNil(occluded.readings[.right], "A brief occlusion keeps the chosen arm.")
        right.time = left.time + 0.4
        let switched = right.step(up)
        XCTAssertNotNil(switched.readings[.right], "After a tracking gap the visible arm takes over.")
        right.play([(up, 2)])
        XCTAssertEqual(right.reps, 0, "The half-finished rep on the other arm is not carried over.")
        right.play([(fullDownAngles, 6), (up, 6)])
        XCTAssertEqual(right.reps, 1)
    }

    func testEachRepsFormArrivesBeforeItsRepWithExactlyTwoUpSamples() {
        let up = exercise.guide.motion.startAngles
        var player = Player(analyzer: WallPushUpAnalyzer(epoch: 12), test: self)
        player.play([(up, 2), (fullDownAngles, 8), (up, 2), (fullDownAngles, 8), (up, 2)])
        XCTAssertEqual(player.repTimes.count, 2)
        XCTAssertEqual(player.forms.count, 2, "\(player.forms)")
        for (form, rep) in zip(player.forms, player.repTimes) {
            XCTAssertLessThan(form.timestamp, rep, "Form must precede the rep that may end the set.")
        }
        XCTAssertTrue(player.forms.allSatisfy { $0.flags.isEmpty }, "\(player.forms)")
    }

    func testOneNoisyDownSampleStillAsksForDepthAndJitterAtDownIsNotALockout() throws {
        let up = exercise.guide.motion.startAngles
        let partial = ArmAngles(upperArmElevation: -37.5, forearmElevation: 2.5)
        var single = Player(analyzer: WallPushUpAnalyzer(epoch: 13), test: self)
        single.play([(up, 3), (partial, 4), (fullDownAngles, 1), (partial, 4), (up, 3)])
        XCTAssertEqual(single.reps, 0)
        XCTAssertTrue(single.forms.contains { $0.flags.contains(.wallPushUpDeeper) }, "\(single.forms)")

        // Just above the Down line but below halfway back: holding near Down, not a new descent.
        let jitter = try XCTUnwrap(stride(from: 0.02, through: 0.5, by: 0.02).lazy
            .map { self.interpolate(self.fullDownAngles, up, $0) }
            .first { angles in
                guard let metrics = try? self.armMetrics(
                    ExerciseDemoFigureView.wallPushUpPose(for: angles).jointLocations) else { return false }
                return metrics.horizontalRatio > 0.73 && metrics.horizontalRatio < 0.78
            })
        var held = Player(analyzer: WallPushUpAnalyzer(epoch: 14), test: self)
        held.play([(up, 3), (fullDownAngles, 4), (jitter, 1), (fullDownAngles, 3), (jitter, 1), (fullDownAngles, 3),
                   (up, 6)])
        XCTAssertEqual(held.reps, 1)
        XCTAssertFalse(held.forms.contains { $0.flags.contains(.wallPushUpLockout) }, "\(held.forms)")
    }

    func testAGapClearsTheLockedRulerSoASmallerReacquiredPoseCounts() {
        let up = exercise.guide.motion.startAngles
        let analyzer = WallPushUpAnalyzer(epoch: 15)
        var first = Player(analyzer: analyzer, test: self)
        first.play([(up, 3), (fullDownAngles, 2)])
        var smaller = Player(analyzer: analyzer, test: self, start: first.time + 0.5, scale: 0.5)
        smaller.play([(up, 3)])
        XCTAssertEqual(smaller.lastOutput?.thresholds[.left]?.isLocked, true,
                       "The smaller pose locks its own ruler after the gap.")
        smaller.play([(fullDownAngles, 6), (up, 6)])
        XCTAssertEqual(first.reps + smaller.reps, 1)
    }

    /// Feeds the analyzer one frame every 0.1 s, inside the 0.28 s gap limit.
    private struct Player {
        let analyzer: WallPushUpAnalyzer
        let test: WallPushUpAnalyzerTests
        var time: TimeInterval
        var rightArm = false
        var scale: CGFloat = 1
        var reps = 0
        var repTimes: [TimeInterval] = []
        var forms: [RepForm] = []
        var lastOutput: ExerciseAnalysis?

        init(analyzer: WallPushUpAnalyzer, test: WallPushUpAnalyzerTests, start: TimeInterval = 0,
             rightArm: Bool = false, scale: CGFloat = 1) {
            self.analyzer = analyzer
            self.test = test
            time = start
            self.rightArm = rightArm
            self.scale = scale
        }

        @discardableResult
        mutating func step(_ angles: ArmAngles) -> ExerciseAnalysis {
            let sample = ArmMotionSample(angles: angles, stepIndex: 0, wallPushUp: true)
            let output = analyzer.process(test.frame(sample: sample, at: time, imageScale: scale,
                                                     mirrored: rightArm), counting: true)
            reps += output.repEvents.count
            repTimes += output.repEvents.map(\.timestamp)
            forms += output.repForms
            lastOutput = output
            time += 0.1
            return output
        }

        mutating func play(_ segments: [(ArmAngles, Int)]) {
            for (angles, count) in segments {
                for _ in 0..<count { step(angles) }
            }
        }
    }

    func testEstimatedElbowSkipsFormButDoesNotStopCounting() {
        let result = run(exercise.guide.motion, analyzer: WallPushUpAnalyzer(epoch: 9), loops: 1,
                         estimatedElbow: true)
        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "\(result.forms)")
    }

    func testThresholdLinesUseTheLockedWallSideShoulderPositions() throws {
        let analyzer = WallPushUpAnalyzer(epoch: 10)
        let sample = ArmMotionSample(angles: exercise.guide.motion.startAngles, stepIndex: 0, wallPushUp: true)
        let first = analyzer.process(frame(sample: sample, at: 0), counting: true)
        let second = analyzer.process(frame(sample: sample, at: 0.1), counting: true)
        XCTAssertFalse(first.startPositionHeld)
        XCTAssertTrue(second.startPositionHeld)
        let thresholds = try XCTUnwrap(second.thresholds[.left])
        let upFrame = frame(sample: sample, at: 0.1)
        let shoulder = try XCTUnwrap(upFrame.point(.leftShoulder, minimumConfidence: 0.4))
        let wrist = try XCTUnwrap(upFrame.point(.leftWrist, minimumConfidence: 0.4))
        let expectedStartX = wrist.x - 0.75 * (ExerciseDemoFigureView.upperArm + ExerciseDemoFigureView.forearm)
        XCTAssertEqual(thresholds.startLine.from.x, expectedStartX, accuracy: 0.001)
        XCTAssertEqual(thresholds.startLine.to.x, expectedStartX, accuracy: 0.001)
        XCTAssertEqual(thresholds.startLine.label, "Up ↑")
        XCTAssertEqual(thresholds.topLine.label, "Down ↓")
        XCTAssertTrue(thresholds.isLocked)
        XCTAssertNotEqual(thresholds.startLine.from.y, thresholds.startLine.to.y)
        XCTAssertGreaterThan(shoulder.x, 0)
    }

    func testDefinitionUsesTheSideViewWallSetupAndPlaceholder() throws {
        XCTAssertEqual(exercise.id, .wallPushUp)
        XCTAssertEqual(exercise.displayName, "Wall Push-Up")
        XCTAssertEqual(exercise.spokenName, "wall push-up")
        XCTAssertEqual(exercise.sets, 2)
        XCTAssertEqual(exercise.targetReps, 6...10)
        XCTAssertEqual(exercise.autoCompleteReps, 10)
        XCTAssertEqual(exercise.restSeconds, 45)
        XCTAssertEqual(exercise.cameraView, .side)
        XCTAssertEqual(exercise.anyOfRequiredJoints, [Set([LandmarkType.leftShoulder, .leftElbow, .leftWrist]),
                                                      Set([.rightShoulder, .rightElbow, .rightWrist])])
        XCTAssertFalse(exercise.centersInFrame)
        XCTAssertEqual(exercise.plantedJoints, [.leftWrist, .rightWrist])
        XCTAssertEqual(exercise.equipment, .bodyweight)
        XCTAssertEqual(ExercisePhotography.placeholders[.wallPushUp], "figure.strengthtraining.functional")
        XCTAssertEqual(exercise.guide.startPositionInstruction, "Hands on the wall, arms straight")
    }

    // MARK: Helpers

    private struct Run {
        var reps = 0
        var forms: [RepForm] = []
    }

    private var fullDownAngles: ArmAngles { ArmAngles(upperArmElevation: -65, forearmElevation: 45) }

    private func framingEvaluator(for exercise: ExerciseDefinition) -> FramingEvaluator {
        FramingEvaluator(requiredJoints: exercise.requiredJoints,
                         anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                         headroomArmLengths: exercise.headroomArmLengths,
                         sideroomArmLengths: exercise.sideroomArmLengths,
                         maximumShoulderSpan: exercise.maximumShoulderSpan,
                         centersInFrame: exercise.centersInFrame,
                         cameraView: exercise.cameraView)
    }

    private func plantedFrame(_ exercise: ExerciseDefinition, at time: TimeInterval,
                              includeHip: Bool, hipConfidence: Double, xOffset: CGFloat = 0) -> PoseFrame {
        let motion = exercise.guide.motion
        let sample = motion.sample(at: time)
        let joints = ExerciseDemoFigureView.pose(for: sample, forearmPlane: motion.forearmPlane,
                                                 cameraView: exercise.cameraView).jointLocations
        var wanted: Set<LandmarkType> = [.leftShoulder, .leftElbow, .leftWrist]
        if includeHip { wanted.insert(.leftHip) }
        let landmarks = Dictionary(uniqueKeysWithValues: wanted.compactMap { joint in
            joints[joint].map { original in
                let point = CGPoint(x: original.x + xOffset, y: original.y)
                return (joint, Landmark(type: joint,
                                        normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                            pixel: point, imageWidth: 300, imageHeight: 470),
                                        imageLocation: point,
                                        confidence: joint == .leftHip ? hipConfidence : 0.9))
            }
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 300, imageHeight: 470), timestamp: time)
    }

    private func run(_ motion: ArmMotion, analyzer: ExerciseAnalyzing, loops: Int,
                     imageScale: CGFloat = 1, upperArmScale: CGFloat = 1, forearmScale: CGFloat = 1,
                     mirrored: Bool = false, estimatedElbow: Bool = false,
                     hipOffsetOnDown: CGPoint = .zero) -> Run {
        var result = Run()
        let end = motion.duration * Double(loops)
        let lastIndex = Int((end * 10).rounded(.down))
        for index in 0...lastIndex {
            let time = Double(index) / 10
            let sample = motion.sample(at: time)
            let frame = frame(sample: sample, at: time, imageScale: imageScale,
                              upperArmScale: upperArmScale, forearmScale: forearmScale,
                              mirrored: mirrored,
                              hipOffsetOnDown: sample.stepIndex == 1 ? hipOffsetOnDown : .zero,
                              estimatedElbow: estimatedElbow)
            let analysis = analyzer.process(frame, counting: true)
            result.reps += analysis.repEvents.count
            result.forms += analysis.repForms
        }
        return result
    }

    fileprivate func frame(sample: ArmMotionSample, at time: TimeInterval, imageScale: CGFloat = 1,
                       upperArmScale: CGFloat = 1, forearmScale: CGFloat = 1,
                       mirrored: Bool = false, translate: CGPoint = .zero,
                       hipOffsetOnDown: CGPoint = .zero, estimatedElbow: Bool = false) -> PoseFrame {
        let pose = ExerciseDemoFigureView.wallPushUpPose(for: sample.angles,
                                                         upperArm: ExerciseDemoFigureView.upperArm * upperArmScale,
                                                         forearm: ExerciseDemoFigureView.forearm * forearmScale)
        let entries = pose.jointLocations.map { type, point -> (LandmarkType, CGPoint) in
            var figurePoint = point
            if type == .leftHip {
                figurePoint.x += hipOffsetOnDown.x
                figurePoint.y += hipOffsetOnDown.y
            }
            let sourceX = mirrored ? ExerciseDemoFigureView.canvasSize.width - figurePoint.x : figurePoint.x
            let transformed = CGPoint(
                x: 540 + (sourceX - ExerciseDemoFigureView.canvasSize.width / 2) * imageScale + translate.x,
                y: 850 + (figurePoint.y - ExerciseDemoFigureView.canvasSize.height / 2) * imageScale + translate.y
            )
            return (mirrored ? oppositeSide(of: type) : type, transformed)
        }
        let landmarks = Dictionary(uniqueKeysWithValues: entries.map { type, point in
            (type, Landmark(type: type,
                            normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                pixel: point, imageWidth: 1080, imageHeight: 1920),
                            imageLocation: point, confidence: 0.9))
        })
        let estimated: Set<LandmarkType> = estimatedElbow ? [mirrored ? .rightElbow : .leftElbow] : []
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                         timestamp: time, estimatedJoints: estimated)
    }

    private func armMetrics(_ joints: [LandmarkType: CGPoint]) throws -> (elbowAngle: Double, horizontalRatio: Double) {
        let shoulder = try XCTUnwrap(joints[.leftShoulder])
        let elbow = try XCTUnwrap(joints[.leftElbow])
        let wrist = try XCTUnwrap(joints[.leftWrist])
        let armLength = ArmGeometry.distance(shoulder, elbow) + ArmGeometry.distance(elbow, wrist)
        return (ArmGeometry.angle(at: elbow, shoulder, wrist),
                Double(abs(wrist.x - shoulder.x) / armLength))
    }

    private func nearThresholdUpAngles(segmentScale: CGFloat) -> ArmAngles {
        let targetX = (ExerciseDemoFigureView.upperArm + ExerciseDemoFigureView.forearm) * 0.76
        let upperLength = ExerciseDemoFigureView.upperArm * segmentScale
        let forearmLength = ExerciseDemoFigureView.forearm * segmentScale
        var lower = 0.0
        var upper = 90.0
        for _ in 0..<36 {
            let angle = (lower + upper) / 2
            let forearmAngle = angle - 29
            let projectedX = Double(upperLength) * cos(angle * .pi / 180)
                + Double(forearmLength) * cos(forearmAngle * .pi / 180)
            if projectedX > Double(targetX) {
                lower = angle
            } else {
                upper = angle
            }
        }
        let angle = (lower + upper) / 2
        return ArmAngles(upperArmElevation: angle, forearmElevation: angle - 29)
    }

    private func interpolate(_ from: ArmAngles, _ to: ArmAngles, _ amount: Double) -> ArmAngles {
        ArmAngles(upperArmElevation: from.upperArmElevation + (to.upperArmElevation - from.upperArmElevation) * amount,
                  forearmElevation: from.forearmElevation + (to.forearmElevation - from.forearmElevation) * amount)
    }

    private func motion(with keyframes: [(ArmAngles, TimeInterval, TimeInterval, Int)]) -> ArmMotion {
        ArmMotion(keyframes: keyframes.map { angles, move, hold, step in
            ArmKeyframe(angles: angles, moveDuration: move, holdDuration: hold, stepIndex: step)
        }, holdsDumbbells: false, wallPushUp: true)
    }

    private func oppositeSide(of joint: LandmarkType) -> LandmarkType {
        guard let side = BodySide.side(of: joint) else { return joint }
        let other: BodySide = side == .left ? .right : .left
        if joint == side.shoulder { return other.shoulder }
        if joint == side.elbow { return other.elbow }
        if joint == side.wrist { return other.wrist }
        if joint == side.hip { return other.hip }
        if joint == side.knee { return other.knee }
        if joint == side.ankle { return other.ankle }
        return joint
    }
}
