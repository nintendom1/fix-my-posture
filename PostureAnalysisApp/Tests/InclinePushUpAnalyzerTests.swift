import CoreGraphics
import XCTest
@testable import PostureAnalysisApp

final class InclinePushUpAnalyzerTests: XCTestCase {
    private let exercise = InclinePushUpExercise.definition()

    // MARK: Counting

    func testGuideDemoCountsOncePerLoopFacingEitherWayAtScaleAndWithSegmentVariation() {
        let cases: [(CGFloat, CGFloat, CGFloat, Bool)] = [
            (1, 1, 1, false), (0.5, 1, 1, true), (2, 1, 1, false), (0.5, 1, 1, false), (2, 1, 1, true),
            (1, 1.15, 1, true), (1, 0.85, 1, false),
            (1, 1, 1.15, true), (1, 1, 0.85, false)
        ]
        for (scale, upper, forearm, mirrored) in cases {
            let result = run(exercise.guide.motion, analyzer: InclinePushUpAnalyzer(epoch: 1), loops: 3,
                             imageScale: scale, upperArmScale: upper, forearmScale: forearm,
                             mirrored: mirrored)
            XCTAssertEqual(result.reps, 3,
                           "scale \(scale), upper \(upper), forearm \(forearm), mirrored \(mirrored)")
            XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "Demo cues: \(result.forms)")
        }
    }

    func testGuideDemoMeetsItsMeasuredThresholds() throws {
        let upMetrics = try armMetrics(ExerciseDemoFigureView.inclinePushUpPose(for: up).jointLocations)
        let downMetrics = try armMetrics(ExerciseDemoFigureView.inclinePushUpPose(for: down).jointLocations)
        XCTAssertEqual(upMetrics.elbowAngle, 180, accuracy: 0.001)
        XCTAssertEqual(upMetrics.ratio, 1, accuracy: 0.001)
        XCTAssertEqual(downMetrics.elbowAngle, 80, accuracy: 0.001)
        XCTAssertEqual(downMetrics.ratio, 0.644, accuracy: 0.002)
        let configuration = PlantedPushUpConfiguration.incline
        XCTAssertGreaterThanOrEqual(upMetrics.ratio, configuration.upMinHorizontalRatio)
        XCTAssertLessThanOrEqual(downMetrics.ratio, configuration.downMaxHorizontalRatio)
        XCTAssertLessThanOrEqual(downMetrics.elbowAngle, configuration.downMaxElbowAngle)
        // On this slope the shoulder is only 0.82 arm lengths from the wrist across the image, short of the Up line,
        // so a horizontal-only distance could never see the demo's Up.
        XCTAssertEqual(upMetrics.horizontalRatio, 0.819, accuracy: 0.002)
        XCTAssertLessThan(upMetrics.horizontalRatio, configuration.upMinHorizontalRatio)
    }

    func testEightNearThresholdReturnsWithAShiftingArmSizeDoNotRatchetTheLockedRuler() {
        var player = Player(analyzer: InclinePushUpAnalyzer(epoch: 4), test: self)
        var currentScale: CGFloat = 1
        player.step(nearUp)
        player.step(nearUp)
        for repIndex in 0..<8 {
            // The arm looks 25% larger on every other return, as if the user leaned toward the phone.
            let nextScale: CGFloat = repIndex.isMultiple(of: 2) ? 1.25 : 1
            for step in 1...12 {
                let progress = Double(step) / 12
                player.step(interpolate(nearUp, down, progress),
                            segmentScale: currentScale + (1 - currentScale) * CGFloat(progress))
            }
            for _ in 0..<3 { player.step(down) }
            for step in 1...12 {
                let progress = Double(step) / 12
                player.step(interpolate(down, nearUp, progress),
                            segmentScale: 1 + (nextScale - 1) * CGFloat(progress))
            }
            player.step(nearUp, segmentScale: nextScale)
            player.step(nearUp, segmentScale: nextScale)
            currentScale = nextScale
        }
        XCTAssertEqual(player.reps, 8)
    }

    func testTheLockedRulerKeepsALargerBentArmOutOfDown() throws {
        var player = Player(analyzer: InclinePushUpAnalyzer(epoch: 21), test: self)
        player.play([(up, 3)])
        // Both segments 15% longer with no gap: the demo's Down reach is about 0.644 × 1.15 ≈ 0.74 of the locked
        // ruler, still outside Down. A live ruler would read 0.644 and confirm Down.
        for _ in 0..<4 { player.step(down, segmentScale: 1.15) }
        let output = try XCTUnwrap(player.lastOutput)
        let reading = try XCTUnwrap(output.readings[.left])
        XCTAssertGreaterThan(reading.signal, 0.7, "Measured against the locked ruler, not the live one.")
        XCTAssertNotEqual(reading.zone, .top)

        let thresholds = try XCTUnwrap(output.thresholds[.left])
        let largerFrame = frame(sample: ArmMotionSample(angles: down, stepIndex: 0, inclinePushUp: true), at: 0,
                                upperArmScale: 1.15, forearmScale: 1.15)
        let wrist = try XCTUnwrap(largerFrame.point(.leftWrist, minimumConfidence: 0.4))
        let line = thresholds.topLine
        let middle = CGPoint(x: (line.from.x + line.to.x) / 2, y: (line.from.y + line.to.y) / 2)
        XCTAssertEqual(ArmGeometry.distance(middle, wrist),
                       0.7 * (ExerciseDemoFigureView.upperArm + ExerciseDemoFigureView.forearm), accuracy: 0.001,
                       "The Down segment stays at the locked distance.")
    }

    func testGapClearsReferencesBeforeTranslatedAndScaledReacquisition() {
        let analyzer = InclinePushUpAnalyzer(epoch: 5)
        var first = Player(analyzer: analyzer, test: self)
        first.play([(up, 2), (down, 2)])
        XCTAssertEqual(first.reps, 0)

        // The user steps closer and shifts: a fresh Up, Down, and Up still count exactly one rep.
        var second = Player(analyzer: analyzer, test: self, start: first.time + 0.7, scale: 1.5,
                            translate: CGPoint(x: 50, y: -80))
        second.play([(up, 2), (down, 4), (partial, 2), (up, 3)])
        XCTAssertEqual(first.reps + second.reps, 1, "The interrupted cycle is not carried over.")
    }

    func testAGapClearsTheLockedRulerSoASmallerReacquiredPoseCounts() {
        let analyzer = InclinePushUpAnalyzer(epoch: 15)
        var first = Player(analyzer: analyzer, test: self)
        first.play([(up, 3), (down, 2)])
        var smaller = Player(analyzer: analyzer, test: self, start: first.time + 0.5, scale: 0.5)
        smaller.play([(up, 3)])
        XCTAssertEqual(smaller.lastOutput?.thresholds[.left]?.isLocked, true,
                       "The smaller pose locks its own ruler after the gap.")
        XCTAssertEqual(smaller.lastOutput?.readings[.left]?.zone, .bottom,
                       "A retained full-size ruler would put the half-size straight arm short of the Up line.")
        smaller.play([(down, 6), (up, 6)])
        XCTAssertEqual(first.reps + smaller.reps, 1)
    }

    func testLosingTheTrackedArmPicksTheOtherAfterAGapAndNeedsAFreshUp() {
        let analyzer = InclinePushUpAnalyzer(epoch: 11)
        // Left arm: Up, then most of the way down, then it leaves the frame.
        var left = Player(analyzer: analyzer, test: self)
        left.play([(up, 3), (down, 3)])
        XCTAssertEqual(left.reps, 0)

        var right = Player(analyzer: analyzer, test: self, start: left.time + 0.1, rightArm: true)
        let occluded = right.step(up)
        XCTAssertNil(occluded.readings[.right], "A brief occlusion keeps the chosen arm.")
        right.time = left.time + 0.4
        let switched = right.step(up)
        XCTAssertNotNil(switched.readings[.right], "After a tracking gap the visible arm takes over.")
        right.play([(up, 2)])
        XCTAssertEqual(right.reps, 0, "The half-finished rep on the other arm is not carried over.")
        right.play([(down, 6), (up, 6)])
        XCTAssertEqual(right.reps, 1)
    }

    // MARK: Form

    func testDeeperBodyLineAndLockoutCuesFireOnlyForTheirTriggers() {
        let shallow = motion(with: [(up, 0, 1.0, 0), (partial, 1.2, 0.3, 1), (up, 1.2, 0, 2)])
        let shallowRun = run(shallow, analyzer: InclinePushUpAnalyzer(epoch: 6), loops: 1)
        XCTAssertEqual(shallowRun.reps, 0)
        XCTAssertTrue(shallowRun.forms.contains { $0.flags.contains(.inclinePushUpDeeper) }, "\(shallowRun.forms)")
        XCTAssertFalse(shallowRun.forms.contains { $0.flags.contains(.inclinePushUpBodyLine) })

        let sagging = run(exercise.guide.motion, analyzer: InclinePushUpAnalyzer(epoch: 7), loops: 1,
                          hipOffsetOnDown: CGPoint(x: 0, y: 40))
        XCTAssertEqual(sagging.reps, 1)
        XCTAssertTrue(sagging.forms.contains { $0.flags.contains(.inclinePushUpBodyLine) }, "\(sagging.forms)")
        XCTAssertFalse(sagging.forms.contains { $0.flags.contains(.inclinePushUpDeeper) })

        let lockout = motion(with: [
            (up, 0, 1.0, 0), (down, 1.2, 0.3, 1), (partial, 0.8, 0.2, 1), (down, 0.8, 0.3, 1), (up, 1.2, 0, 2)
        ])
        let lockoutRun = run(lockout, analyzer: InclinePushUpAnalyzer(epoch: 8), loops: 1)
        XCTAssertEqual(lockoutRun.reps, 1)
        XCTAssertTrue(lockoutRun.forms.contains { $0.flags.contains(.inclinePushUpLockout) }, "\(lockoutRun.forms)")
    }

    func testBodyLineIsJudgedAtTheDeepestPointNotAtTheStart() {
        // The hips sag only while rising back to Up, long after the deepest point.
        var player = Player(analyzer: InclinePushUpAnalyzer(epoch: 16), test: self)
        player.play([(up, 3), (down, 8)])
        player.hipOffset = CGPoint(x: 0, y: 40)
        player.play([(up, 6)])
        XCTAssertEqual(player.reps, 1)
        XCTAssertFalse(player.forms.contains { $0.flags.contains(.inclinePushUpBodyLine) }, "\(player.forms)")
    }

    func testEstimatedElbowSkipsFormButDoesNotStopCounting() {
        let estimated = run(exercise.guide.motion, analyzer: InclinePushUpAnalyzer(epoch: 9), loops: 1,
                            hipOffsetOnDown: CGPoint(x: 0, y: 40), estimatedElbow: true)
        XCTAssertEqual(estimated.reps, 1)
        XCTAssertTrue(estimated.forms.isEmpty, "\(estimated.forms)")

        let measured = run(exercise.guide.motion, analyzer: InclinePushUpAnalyzer(epoch: 17), loops: 1,
                           hipOffsetOnDown: CGPoint(x: 0, y: 40))
        XCTAssertTrue(measured.forms.contains { $0.flags.contains(.inclinePushUpBodyLine) },
                      "The same sag is flagged when the elbow is measured.")
    }

    func testEachRepsFormArrivesBeforeItsRepWithExactlyTwoUpSamples() {
        var player = Player(analyzer: InclinePushUpAnalyzer(epoch: 12), test: self)
        player.play([(up, 2), (down, 8), (up, 2), (down, 8), (up, 2)])
        XCTAssertEqual(player.repTimes.count, 2)
        XCTAssertEqual(player.forms.count, 2, "\(player.forms)")
        for (form, rep) in zip(player.forms, player.repTimes) {
            XCTAssertLessThan(form.timestamp, rep, "Form must precede the rep that may end the set.")
        }
        XCTAssertTrue(player.forms.allSatisfy { $0.flags.isEmpty }, "\(player.forms)")
    }

    func testOneNoisyDownSampleStillAsksForDepthAndJitterAtDownIsNotALockout() throws {
        var single = Player(analyzer: InclinePushUpAnalyzer(epoch: 13), test: self)
        single.play([(up, 3), (partial, 4), (down, 1), (partial, 4), (up, 3)])
        XCTAssertEqual(single.reps, 0)
        XCTAssertTrue(single.forms.contains { $0.flags.contains(.inclinePushUpDeeper) }, "\(single.forms)")

        // Just above the Down line but below halfway back: holding near Down, not a new descent.
        let jitter = try XCTUnwrap(stride(from: 0.02, through: 0.5, by: 0.02).lazy
            .map { self.interpolate(self.down, self.up, $0) }
            .first { angles in
                guard let metrics = try? self.armMetrics(
                    ExerciseDemoFigureView.inclinePushUpPose(for: angles).jointLocations) else { return false }
                return metrics.ratio > 0.71 && metrics.ratio < 0.76
            })
        var held = Player(analyzer: InclinePushUpAnalyzer(epoch: 14), test: self)
        held.play([(up, 3), (down, 4), (jitter, 1), (down, 3), (jitter, 1), (down, 3), (up, 6)])
        XCTAssertEqual(held.reps, 1)
        XCTAssertFalse(held.forms.contains { $0.flags.contains(.inclinePushUpLockout) }, "\(held.forms)")
    }

    // MARK: Thresholds and definition

    func testThresholdLinesSitAtTheLockedDistancesFromThePlantedWrist() throws {
        let analyzer = InclinePushUpAnalyzer(epoch: 10)
        let sample = ArmMotionSample(angles: up, stepIndex: 0, inclinePushUp: true)
        let first = analyzer.process(frame(sample: sample, at: 0), counting: true)
        let upFrame = frame(sample: sample, at: 0.1)
        let second = analyzer.process(upFrame, counting: true)
        XCTAssertFalse(first.startPositionHeld)
        XCTAssertTrue(second.startPositionHeld)
        let thresholds = try XCTUnwrap(second.thresholds[.left])
        XCTAssertEqual(thresholds.startLine.label, "Up ↑")
        XCTAssertEqual(thresholds.topLine.label, "Down ↓")
        XCTAssertTrue(thresholds.isLocked)

        let shoulder = try XCTUnwrap(upFrame.point(.leftShoulder, minimumConfidence: 0.4))
        let wrist = try XCTUnwrap(upFrame.point(.leftWrist, minimumConfidence: 0.4))
        let armLength = ExerciseDemoFigureView.upperArm + ExerciseDemoFigureView.forearm
        let reach = ArmGeometry.distance(shoulder, wrist)
        let direction = CGVector(dx: (shoulder.x - wrist.x) / reach, dy: (shoulder.y - wrist.y) / reach)
        for (line, ratio) in [(thresholds.startLine, 0.85), (thresholds.topLine, 0.7)] {
            let middle = CGPoint(x: (line.from.x + line.to.x) / 2, y: (line.from.y + line.to.y) / 2)
            XCTAssertEqual(ArmGeometry.distance(middle, wrist), CGFloat(ratio) * armLength, accuracy: 0.001)
            XCTAssertEqual((middle.x - wrist.x) * direction.dy - (middle.y - wrist.y) * direction.dx, 0,
                           accuracy: 0.001, "The segment sits on the wrist-to-shoulder line.")
            let along = (line.to.x - line.from.x) * direction.dx + (line.to.y - line.from.y) * direction.dy
            XCTAssertEqual(along, 0, accuracy: 0.001, "The segment crosses that line square-on.")
            XCTAssertLessThan(line.from.y, line.to.y)
        }
    }

    func testDefinitionUsesTheSideViewBenchSetupAndPlaceholder() {
        XCTAssertEqual(exercise.id, .inclinePushUp)
        XCTAssertEqual(exercise.id.rawValue, "incline_push_up")
        XCTAssertEqual(exercise.displayName, "Incline Push-Up")
        XCTAssertEqual(exercise.presentation.shortName, "Incline Push-Up")
        XCTAssertEqual(exercise.spokenName, "incline push-up")
        XCTAssertEqual(exercise.sets, 2)
        XCTAssertEqual(exercise.targetReps, 6...10)
        XCTAssertEqual(exercise.autoCompleteReps, 10)
        XCTAssertEqual(exercise.restSeconds, 60)
        XCTAssertEqual(exercise.cameraView, .side)
        XCTAssertEqual(exercise.anyOfRequiredJoints.count, 2)
        XCTAssertTrue(exercise.requiredJoints.isEmpty)
        XCTAssertTrue(exercise.startsByHolding)
        XCTAssertEqual(exercise.plantedJoints, [.leftWrist, .rightWrist])
        XCTAssertEqual(exercise.equipment, .bodyweight)
        XCTAssertEqual(exercise.presentation.filterGroups, PushUpExercise.definition().presentation.filterGroups)
        XCTAssertNil(exercise.reducedRange)
        XCTAssertEqual(exercise.voiceAliases, ["incline push-up", "incline push-ups", "incline pushup",
                                               "incline pushups", "bench push-up", "bench push-ups"])
        XCTAssertEqual(ExercisePhotography.placeholders[.inclinePushUp], "figure.strengthtraining.functional")
        XCTAssertNil(ExercisePhotography.photograph(for: .inclinePushUp))
        XCTAssertEqual(exercise.guide.startPositionInstruction, "Hands on the bench, arms straight")
        XCTAssertEqual(exercise.guide.steps.count, 4)
        XCTAssertEqual(exercise.guide.tip, "Higher surface = easier.")
        XCTAssertEqual(exercise.coachingCues.map(\.id), [.inclinePushUpDeeper, .inclinePushUpBodyLine,
                                                         .inclinePushUpLockout])
    }

    func testVoiceAliasesSelectTheInclinePushUpWithoutStealingPushUp() {
        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        for alias in exercise.voiceAliases {
            XCTAssertEqual(parser.parse(alias)?.command, .selectExercise(.inclinePushUp), alias)
            XCTAssertEqual(parser.parse("switch to \(alias)")?.command, .selectExercise(.inclinePushUp), alias)
        }
        XCTAssertEqual(parser.parse("push ups")?.command, .selectExercise(.pushUp))
        XCTAssertEqual(parser.parse("wall push-up")?.command, .selectExercise(.wallPushUp))
    }

    // MARK: Guide figure

    func testGuideKeepsTheHandsOnTheBenchAndTheBodyInOneInclinedLine() throws {
        let motion = exercise.guide.motion
        let layout = PlantedBodyLayout.incline
        var steepest = 0.0
        var shallowest = 90.0
        for index in 0...Int(motion.duration * 10) {
            let sample = motion.sample(at: Double(index) / 10)
            let joints = ExerciseDemoFigureView.pose(for: sample, cameraView: .side).jointLocations
            let wrist = try XCTUnwrap(joints[.leftWrist])
            let shoulder = try XCTUnwrap(joints[.leftShoulder])
            let hip = try XCTUnwrap(joints[.leftHip])
            let ankle = try XCTUnwrap(joints[.leftAnkle])
            XCTAssertEqual(wrist, layout.wrist, "The hands stay planted at \(index)")
            XCTAssertEqual(ankle, layout.ankle)
            let cross = (shoulder.x - ankle.x) * (hip.y - ankle.y) - (shoulder.y - ankle.y) * (hip.x - ankle.x)
            XCTAssertEqual(cross, 0, accuracy: 0.01, "Shoulder, hip, and ankle stay one line at \(index)")
            let degrees = atan2(Double(ankle.y - shoulder.y), Double(shoulder.x - ankle.x)) * 180 / .pi
            steepest = max(steepest, degrees)
            shallowest = min(shallowest, degrees)
        }
        XCTAssertGreaterThanOrEqual(shallowest, 20, "The chest never reaches the floor.")
        XCTAssertGreaterThanOrEqual(steepest, 30)
        XCTAssertLessThanOrEqual(steepest, 45, "An incline push-up leans 30–45° from the floor at Up.")

        let upJoints = ExerciseDemoFigureView.inclinePushUpPose(for: up).jointLocations
        let upHip = try XCTUnwrap(upJoints[.leftHip])
        XCTAssertEqual(upHip.y, layout.wrist.y, accuracy: 3, "The bench top sits at the hips' height.")
        let wallJoints = ExerciseDemoFigureView.wallPushUpPose(for: up).jointLocations
        XCTAssertNotEqual(wallJoints[.leftShoulder], upJoints[.leftShoulder], "It is not the wall figure.")
    }

    func testBenchFigureBoundsHoldTheBenchAndFloorWhileOtherFiguresKeepTheCanvas() {
        let bounds = ExerciseDemoFigureView.bounds(for: exercise.guide.motion, cameraView: .side)
        let layout = PlantedBodyLayout.incline
        let segments = layout.surfaceSegments(wrist: layout.wrist, ankle: layout.ankle, facing: 1, scale: 1,
                                              verticalRange: 0...ExerciseDemoFigureView.canvasSize.height)
        XCTAssertEqual(segments.count, 3, "Bench top, one leg, and the floor")
        for segment in segments {
            XCTAssertTrue(bounds.contains(segment.from), "\(segment.from) is outside \(bounds)")
            XCTAssertTrue(bounds.contains(segment.to), "\(segment.to) is outside \(bounds)")
        }
        XCTAssertLessThan(bounds.height, bounds.width, "A bench figure is wide and low.")

        let canvas = CGRect(origin: .zero, size: ExerciseDemoFigureView.canvasSize)
        for other in [WallPushUpExercise.definition(), PushUpExercise.definition()] {
            let otherBounds = ExerciseDemoFigureView.bounds(for: other.guide.motion, cameraView: other.cameraView)
            XCTAssertTrue(otherBounds.contains(canvas), "\(other.id) keeps the original canvas framing.")
        }
    }

    func testWallSurfaceStaysOneVerticalLineBesideTheWrist() {
        let wrist = PlantedBodyLayout.wall.wrist
        let facing = PlantedBodyLayout.wall.surfaceSegments(wrist: wrist, ankle: .zero, facing: 1, scale: 1,
                                                            verticalRange: 10...400)
        XCTAssertEqual(facing.count, 1)
        XCTAssertEqual(facing.first?.from, CGPoint(x: wrist.x + 3, y: 10))
        XCTAssertEqual(facing.first?.to, CGPoint(x: wrist.x + 3, y: 400))
        let mirrored = PlantedBodyLayout.wall.surfaceSegments(wrist: wrist, ankle: .zero, facing: -1, scale: 2,
                                                              verticalRange: 10...400)
        XCTAssertEqual(mirrored.first?.from.x, wrist.x - 3)
    }

    // MARK: Helpers

    private struct Run {
        var reps = 0
        var forms: [RepForm] = []
    }

    private var up: ArmAngles { exercise.guide.motion.startAngles }
    private var down: ArmAngles { exercise.guide.motion.topAngles }
    /// Elbows at 152°: past the 150° Up line, short of the 160° true-rest refresh.
    private var nearUp: ArmAngles { ArmAngles(upperArmElevation: -35, forearmElevation: -7) }
    /// Elbows at 130°: out of Up, not yet at Down.
    private var partial: ArmAngles { ArmAngles(upperArmElevation: -50, forearmElevation: 0) }

    /// Feeds the analyzer one frame every 0.1 s, inside the 0.28 s gap limit.
    private struct Player {
        let analyzer: InclinePushUpAnalyzer
        let test: InclinePushUpAnalyzerTests
        var time: TimeInterval
        var rightArm = false
        var scale: CGFloat = 1
        var translate: CGPoint = .zero
        var hipOffset: CGPoint = .zero
        var reps = 0
        var repTimes: [TimeInterval] = []
        var forms: [RepForm] = []
        var lastOutput: ExerciseAnalysis?

        init(analyzer: InclinePushUpAnalyzer, test: InclinePushUpAnalyzerTests, start: TimeInterval = 0,
             rightArm: Bool = false, scale: CGFloat = 1, translate: CGPoint = .zero) {
            self.analyzer = analyzer
            self.test = test
            time = start
            self.rightArm = rightArm
            self.scale = scale
            self.translate = translate
        }

        @discardableResult
        mutating func step(_ angles: ArmAngles, segmentScale: CGFloat = 1) -> ExerciseAnalysis {
            let sample = ArmMotionSample(angles: angles, stepIndex: 0, inclinePushUp: true)
            let output = analyzer.process(test.frame(sample: sample, at: time, imageScale: scale,
                                                     upperArmScale: segmentScale, forearmScale: segmentScale,
                                                     mirrored: rightArm, translate: translate,
                                                     hipOffset: hipOffset), counting: true)
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

    private func run(_ motion: ArmMotion, analyzer: ExerciseAnalyzing, loops: Int,
                     imageScale: CGFloat = 1, upperArmScale: CGFloat = 1, forearmScale: CGFloat = 1,
                     mirrored: Bool = false, hipOffsetOnDown: CGPoint = .zero,
                     estimatedElbow: Bool = false) -> Run {
        var result = Run()
        let lastIndex = Int((motion.duration * Double(loops) * 10).rounded(.down))
        for index in 0...lastIndex {
            let time = Double(index) / 10
            let sample = motion.sample(at: time)
            let frame = frame(sample: sample, at: time, imageScale: imageScale,
                              upperArmScale: upperArmScale, forearmScale: forearmScale,
                              mirrored: mirrored,
                              hipOffset: sample.stepIndex == 2 ? hipOffsetOnDown : .zero,
                              estimatedElbow: estimatedElbow)
            let analysis = analyzer.process(frame, counting: true)
            result.reps += analysis.repEvents.count
            result.forms += analysis.repForms
        }
        return result
    }

    /// The guide figure as the phone would see it: scaled about the image center, optionally turned around.
    fileprivate func frame(sample: ArmMotionSample, at time: TimeInterval, imageScale: CGFloat = 1,
                           upperArmScale: CGFloat = 1, forearmScale: CGFloat = 1,
                           mirrored: Bool = false, translate: CGPoint = .zero,
                           hipOffset: CGPoint = .zero, estimatedElbow: Bool = false) -> PoseFrame {
        let pose = ExerciseDemoFigureView.inclinePushUpPose(for: sample.angles,
                                                            upperArm: ExerciseDemoFigureView.upperArm * upperArmScale,
                                                            forearm: ExerciseDemoFigureView.forearm * forearmScale)
        let entries = pose.jointLocations.map { type, point -> (LandmarkType, CGPoint) in
            var figurePoint = point
            if type == .leftHip {
                figurePoint.x += hipOffset.x
                figurePoint.y += hipOffset.y
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

    private func armMetrics(_ joints: [LandmarkType: CGPoint]) throws
        -> (elbowAngle: Double, ratio: Double, horizontalRatio: Double) {
        let shoulder = try XCTUnwrap(joints[.leftShoulder])
        let elbow = try XCTUnwrap(joints[.leftElbow])
        let wrist = try XCTUnwrap(joints[.leftWrist])
        let armLength = ArmGeometry.distance(shoulder, elbow) + ArmGeometry.distance(elbow, wrist)
        return (ArmGeometry.angle(at: elbow, shoulder, wrist),
                Double(ArmGeometry.distance(shoulder, wrist) / armLength),
                Double(abs(wrist.x - shoulder.x) / armLength))
    }

    private func interpolate(_ from: ArmAngles, _ to: ArmAngles, _ amount: Double) -> ArmAngles {
        ArmAngles(upperArmElevation: from.upperArmElevation + (to.upperArmElevation - from.upperArmElevation) * amount,
                  forearmElevation: from.forearmElevation + (to.forearmElevation - from.forearmElevation) * amount)
    }

    private func motion(with keyframes: [(ArmAngles, TimeInterval, TimeInterval, Int)]) -> ArmMotion {
        ArmMotion(keyframes: keyframes.map { angles, move, hold, step in
            ArmKeyframe(angles: angles, moveDuration: move, holdDuration: hold, stepIndex: step)
        }, holdsDumbbells: false, inclinePushUp: true)
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
