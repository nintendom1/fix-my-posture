import CoreGraphics
import Foundation
import XCTest
@testable import PostureAnalysisApp

final class GluteBridgeAnalyzerTests: XCTestCase {
    private let exercise = GluteBridgeExercise.definition()
    private var motion: ArmMotion { exercise.guide.motion }

    func testGuideCountsOneRepPerLoopAcrossScaleFacingAndLegProportions() throws {
        let proportions: [(CGFloat, CGFloat)] = [(1, 1), (0.85, 1), (1.15, 1), (1, 0.85), (1, 1.15)]
        let scales: [CGFloat] = [0.5, 2]
        for scale in scales {
            for facingLeft in [false, true] {
                for (thigh, shin) in proportions {
                    let result = try run(motion, loops: 2, scale: scale, thigh: thigh, shin: shin,
                                         facingLeft: facingLeft)
                    let label = "scale \(scale), thigh \(thigh), shin \(shin), facingLeft \(facingLeft)"
                    XCTAssertEqual(result.reps, 2, label)
                    if thigh == 1, shin == 1 {
                        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "Demo cues: \(result.forms)")
                        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), label)
                    }
                }
            }
        }

        let down = try demoAngle(motion.startSample)
        let up = try demoAngle(motion.topSample)
        XCTAssertEqual(down, 134.427, accuracy: 0.1)
        XCTAssertLessThanOrEqual(down, 145)
        XCTAssertGreaterThanOrEqual(up, 165)
        XCTAssertEqual(up, 180, accuracy: 0.01)
    }

    func testDownAndUpBoundariesRequireTwoSamplesAndCountOnReturn() throws {
        let downBoundary = GluteBridgeAnalyzer(epoch: 1)
        XCTAssertFalse(downBoundary.process(try angleFrame(145.00005, time: 0), counting: true).startPositionHeld)
        XCTAssertTrue(downBoundary.process(try angleFrame(145.00005, time: 0.1), counting: true).startPositionHeld)
        for index in 2...7 {
            _ = downBoundary.process(try angleFrame(155, time: Double(index) / 10), counting: true)
        }
        _ = downBoundary.process(try angleFrame(164.99995, time: 0.8), counting: true)
        XCTAssertTrue(downBoundary.process(try angleFrame(164.99995, time: 0.9), counting: true).repEvents.isEmpty,
                      "Reaching Up does not count until Down is confirmed again.")
        XCTAssertTrue(downBoundary.process(try angleFrame(145, time: 0.95), counting: true).repEvents.isEmpty)
        XCTAssertTrue(downBoundary.process(try angleFrame(145, time: 1.0), counting: true).repEvents.isEmpty,
                      "The confirmed Down return is too soon after movement started.")

        let valid = GluteBridgeAnalyzer(epoch: 1)
        _ = valid.process(try angleFrame(145, time: 0), counting: true)
        XCTAssertTrue(valid.process(try angleFrame(145, time: 0.1), counting: true).startPositionHeld)
        for index in 2...17 {
            _ = valid.process(try angleFrame(155, time: Double(index) / 10), counting: true)
        }
        _ = valid.process(try angleFrame(165, time: 1.8), counting: true)
        XCTAssertTrue(valid.process(try angleFrame(165, time: 1.9), counting: true).repEvents.isEmpty)
        XCTAssertTrue(valid.process(try angleFrame(155, time: 2.0), counting: true).repEvents.isEmpty)
        XCTAssertTrue(valid.process(try angleFrame(145, time: 2.1), counting: true).repEvents.isEmpty)
        let returned = valid.process(try angleFrame(145, time: 2.2), counting: true)
        XCTAssertEqual(returned.repEvents.count, 1)
        XCTAssertEqual(returned.repEvents.first?.sides, Set(BodySide.allCases))

        let outsideDown = GluteBridgeAnalyzer(epoch: 1)
        _ = outsideDown.process(try angleFrame(145.01, time: 0), counting: true)
        XCTAssertFalse(outsideDown.process(try angleFrame(145.01, time: 0.1), counting: true).startPositionHeld)
        let outsideUp = GluteBridgeAnalyzer(epoch: 1)
        _ = outsideUp.process(try angleFrame(145, time: 0), counting: true)
        _ = outsideUp.process(try angleFrame(145, time: 0.1), counting: true)
        for index in 2...10 {
            _ = outsideUp.process(try angleFrame(155, time: Double(index) / 10), counting: true)
        }
        _ = outsideUp.process(try angleFrame(164.99, time: 1.1), counting: true)
        _ = outsideUp.process(try angleFrame(164.99, time: 1.2), counting: true)
        _ = outsideUp.process(try angleFrame(145, time: 1.3), counting: true)
        XCTAssertTrue(outsideUp.process(try angleFrame(145, time: 1.4), counting: true).repEvents.isEmpty)
    }

    func testIdleDownDoesNotCountTowardMinimumRepDuration() throws {
        let tooFast = GluteBridgeAnalyzer(epoch: 1)
        for index in 0...20 {
            _ = tooFast.process(try angleFrame(130, time: Double(index) / 10), counting: true)
        }
        _ = tooFast.process(try angleFrame(180, time: 2.01), counting: true)
        XCTAssertTrue(tooFast.process(try angleFrame(180, time: 2.1), counting: true).repEvents.isEmpty)
        _ = tooFast.process(try angleFrame(130, time: 2.11), counting: true)
        XCTAssertTrue(tooFast.process(try angleFrame(130, time: 2.2), counting: true).repEvents.isEmpty,
                      "A 0.2 s jump after a long still Down must not count.")

        let valid = GluteBridgeAnalyzer(epoch: 1)
        for index in 0...20 {
            _ = valid.process(try angleFrame(130, time: Double(index) / 10), counting: true)
        }
        for index in 21...29 {
            _ = valid.process(try angleFrame(155, time: Double(index) / 10), counting: true)
        }
        _ = valid.process(try angleFrame(180, time: 3.0), counting: true)
        _ = valid.process(try angleFrame(180, time: 3.1), counting: true)
        _ = valid.process(try angleFrame(130, time: 3.2), counting: true)
        let returned = valid.process(try angleFrame(130, time: 3.3), counting: true)
        XCTAssertEqual(returned.repEvents.count, 1,
                       "A valid lift after the same idle period should count on the Down return.")
    }

    func testThresholdLinesMatchTheLockedDownAndUpAngles() throws {
        let analyzer = GluteBridgeAnalyzer(epoch: 1)
        _ = analyzer.process(try angleFrame(120, time: 0), counting: true)
        let output = analyzer.process(try angleFrame(120, time: 0.1), counting: true)
        let thresholds = try XCTUnwrap(output.thresholds[.left])

        XCTAssertTrue(thresholds.isLocked)
        XCTAssertEqual(thresholds.startLine.label, "Down ↓")
        XCTAssertEqual(thresholds.topLine.label, "Up ↑")
        XCTAssertEqual(thresholds.startLine.from.y, thresholds.startLine.to.y, accuracy: 0.001)
        XCTAssertEqual(thresholds.topLine.from.y, thresholds.topLine.to.y, accuracy: 0.001)
        XCTAssertEqual(thresholds.startLine.to.x - thresholds.startLine.from.x,
                       1.2 * ArmGeometry.distance(CGPoint(x: 150, y: 300),
                                                  CGPoint(x: 200, y: 300 + 50 / CGFloat(tan(Double.pi / 3)))),
                       accuracy: 0.01)

        let shoulder = CGPoint(x: 100, y: 300)
        let knee = CGPoint(x: 200, y: 300)
        let downHip = CGPoint(x: (thresholds.startLine.from.x + thresholds.startLine.to.x) / 2,
                              y: thresholds.startLine.y)
        let upHip = CGPoint(x: (thresholds.topLine.from.x + thresholds.topLine.to.x) / 2,
                            y: thresholds.topLine.y)
        XCTAssertEqual(GluteBridgeAnalyzer.hipAngle(shoulder: shoulder, hip: downHip, knee: knee, facing: 1),
                       145, accuracy: 0.01)
        XCTAssertEqual(GluteBridgeAnalyzer.hipAngle(shoulder: shoulder, hip: upHip, knee: knee, facing: 1),
                       165, accuracy: 0.01)
    }

    func testHalfBridgeAsksToLiftHigher() throws {
        let shallow = ArmMotion(keyframes: [
            keyframe(hipLift: 0, move: 0, hold: 1, step: 0),
            keyframe(hipLift: 0.5, move: 1.2, hold: 0.2, step: 1),
            keyframe(hipLift: 0, move: 1.2, hold: 0, step: 2)
        ], holdsDumbbells: false)
        let result = try run(shallow)

        XCTAssertEqual(result.reps, 0)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.bridgeHigher) }, "\(result.forms)")
    }

    func testFormSchedulerReceivesOneObservationForBadCleanCleanBadAttempts() throws {
        let analyzer = GluteBridgeAnalyzer(epoch: 1)
        var scheduler = CoachingCueScheduler(cues: exercise.coachingCues, reminders: [])
        let attempts: [[Double]] = [
            [130, 130, 155, 155, 130, 130],
            [130, 155, 165, 165, 155, 130, 130],
            [130, 155, 165, 165, 155, 130, 130],
            [130, 130, 155, 155, 130, 130]
        ]
        var time: TimeInterval = 0
        var forms: [RepForm] = []
        var cues: [CoachingCueID] = []
        for attempt in attempts {
            for angle in attempt {
                let analysis = analyzer.process(try angleFrame(angle, time: time), counting: true)
                forms.append(contentsOf: analysis.repForms)
                let observation = FormObservation(epoch: 1, repForms: analysis.repForms)
                if let cue = scheduler.update(observation, speaking: false, at: time) {
                    cues.append(cue.id)
                }
                time += 0.1
            }
        }

        let expected: [Set<CoachingCueID>] = [[.bridgeHigher], [], [], [.bridgeHigher]]
        XCTAssertEqual(forms.map(\.flags), expected)
        XCTAssertTrue(cues.isEmpty, "Two shallow attempts separated by clean ones must not trigger the cue.")
    }

    func testOneAttemptCombinesAllPeakAndLoweringFaultsIntoOneForm() throws {
        let analyzer = GluteBridgeAnalyzer(epoch: 1)
        let angles = [130, 130, 155] + Array(repeating: 200.0, count: 10)
            + [160, 160, 172, 155, 130, 130]
        var forms: [RepForm] = []
        for (index, angle) in angles.enumerated() {
            let analysis = analyzer.process(try angleFrame(angle, time: Double(index) / 10), counting: true)
            forms.append(contentsOf: analysis.repForms)
        }

        guard forms.count == 1 else {
            return XCTFail("Expected one observation for the completed attempt, got \(forms.count).")
        }
        XCTAssertEqual(forms.first?.flags, [.bridgeStraightLine, .bridgeFeetCloser, .bridgeLower])
    }

    func testOverarchedPeakAsksToStopAtStraightLine() throws {
        let overArch = ArmMotion(keyframes: [
            keyframe(hipLift: 0, move: 0, hold: 1, step: 0),
            keyframe(hipLift: 1.4, move: 1.2, hold: 0.2, step: 1),
            keyframe(hipLift: 0, move: 1.2, hold: 0, step: 2)
        ], holdsDumbbells: false)
        let result = try run(overArch)

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.bridgeStraightLine) }, "\(result.forms)")
    }

    func testFeetTooFarAtTheTopAskToBringThemCloser() throws {
        let result = try run(motion, ankleOffsetAtTop: 120)

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.bridgeFeetCloser) },
                      "forms: \(result.forms); top readings: \(result.topReadings); final readings: \(result.readings)")
    }

    func testKneeAngleAwayFromThePeakDoesNotTriggerFeetCue() throws {
        let result = try run(motion, ankleOffsetBeforeTop: 150)

        XCTAssertEqual(result.reps, 1)
        XCTAssertFalse(result.forms.contains { $0.flags.contains(.bridgeFeetCloser) }, "\(result.forms)")
        XCTAssertGreaterThan(result.maximumPrePeakKneeAngle, 120)
        XCTAssertLessThan(result.kneeAngleAtPeak ?? 180, 120)
    }

    func testReliftingWithoutReturningToDownAsksToLowerAllTheWay() throws {
        let relift = ArmMotion(keyframes: [
            keyframe(hipLift: 0, move: 0, hold: 1, step: 0),
            keyframe(hipLift: 1, move: 1.2, hold: 0.2, step: 1),
            keyframe(hipLift: 0.6, move: 0.6, hold: 0.1, step: 2),
            keyframe(hipLift: 1, move: 0.6, hold: 0.2, step: 1),
            keyframe(hipLift: 0, move: 1.2, hold: 0, step: 2)
        ], holdsDumbbells: false)
        let result = try run(relift)

        XCTAssertTrue(result.forms.contains { $0.flags.contains(.bridgeLower) }, "\(result.forms)")
    }

    func testGapInvalidatesTheCurrentCycle() throws {
        let result = try run(motion, gapAfter: 1.6)
        XCTAssertEqual(result.reps, 0)
    }

    func testEstimatedFormJointSkipsFormUpdateButCountingContinues() throws {
        let result = try run(motion, estimatedJoints: [.leftHip], ankleOffsetAtTop: 120)

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "\(result.forms)")
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), "\(result.signals)")
    }

    func testEightRepsAndNearThresholdReturnsKeepTheLockedLines() throws {
        let analyzer = GluteBridgeAnalyzer(epoch: 1)
        var time: TimeInterval = 0
        var reps = 0
        var locked: ArmThresholds?
        for _ in 0..<8 {
            for _ in 0..<2 {
                let output = analyzer.process(try angleFrame(120, time: time), counting: true)
                time += 0.1
                reps += output.repEvents.count
                if output.thresholds[.left]?.isLocked == true {
                    locked = locked ?? output.thresholds[.left]
                }
            }
            for _ in 0..<10 {
                let output = analyzer.process(try angleFrame(155, time: time), counting: true)
                time += 0.1
                reps += output.repEvents.count
            }
            for _ in 0..<2 {
                let output = analyzer.process(try angleFrame(175, time: time), counting: true)
                time += 0.1
                reps += output.repEvents.count
            }
            for _ in 0..<2 {
                let output = analyzer.process(try angleFrame(144, time: time), counting: true)
                time += 0.1
                reps += output.repEvents.count
                if let current = output.thresholds[.left], current.isLocked, let locked {
                    XCTAssertEqual(current.startLine, locked.startLine)
                    XCTAssertEqual(current.topLine, locked.topLine)
                }
            }
        }

        XCTAssertEqual(reps, 8)
    }

    func testGapAndSideSwitchReacquireTranslatedAndScaledReferences() throws {
        for reacquisition in ["gap", "side switch"] {
            let analyzer = GluteBridgeAnalyzer(epoch: 1)
            _ = analyzer.process(try angleFrame(120, time: 0), counting: true)
            let initial = analyzer.process(try angleFrame(120, time: 0.1), counting: true)
            let initialLine = try XCTUnwrap(initial.thresholds[.left]?.startLine)

            let switchedSide: BodySide = reacquisition == "gap" ? .left : .right
            let shift = CGPoint(x: 180, y: 120)
            let scale: CGFloat = 0.8
            let firstTime = reacquisition == "gap" ? 0.6 : 0.2
            let moved = try angleFrame(120, time: firstTime, side: switchedSide,
                                       scale: scale, shift: shift)
            _ = analyzer.process(moved, counting: true)
            let reacquired = analyzer.process(try angleFrame(120, time: firstTime + 0.1,
                                                             side: switchedSide, scale: scale,
                                                             shift: shift), counting: true)
            let movedLine = try XCTUnwrap(reacquired.thresholds[switchedSide]?.startLine)

            XCTAssertEqual(movedLine.y, initialLine.y * scale + shift.y, accuracy: 0.01, reacquisition)
            let initialCenterX = (initialLine.from.x + initialLine.to.x) / 2
            let movedCenterX = (movedLine.from.x + movedLine.to.x) / 2
            let expectedCenterX = (switchedSide == .right ? 300 - initialCenterX : initialCenterX)
                * scale + shift.x
            XCTAssertEqual(movedCenterX, expectedCenterX, accuracy: 0.01, reacquisition)
        }
    }

    func testFramingUsesEitherCompleteSideAndNamesTheLyingSetup() throws {
        var framing = FramingEvaluator(requiredJoints: exercise.requiredJoints,
                                       anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                                       headroomArmLengths: exercise.headroomArmLengths,
                                       cameraView: exercise.cameraView)
        var incomplete = demoPose(motion.startSample)
        incomplete[.leftAnkle] = nil
        XCTAssertEqual(framing.evaluate(try frame(joints: incomplete, time: 0)).guidance, .stepBackLyingSide)

        let full = demoPose(motion.startSample)
        XCTAssertTrue(framing.evaluate(try frame(joints: full, time: 0.1)).guidance == nil)
        XCTAssertTrue(framing.evaluate(try frame(joints: full, time: 0.7)).isReliable)
        XCTAssertEqual(FramingGuidance.stepBackLyingSide.spokenText,
                       "Lie on your back side-on to the phone, knees bent, with your whole body in view.")
        XCTAssertEqual(exercise.anyOfRequiredJoints, [
            [.leftShoulder, .leftHip, .leftKnee, .leftAnkle],
            [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
        ])
    }

    func testDefinitionAliasesAndPhotographMatchTheBridgeCatalogEntry() throws {
        XCTAssertEqual(ExerciseCatalog.definition(for: .gluteBridge)?.id, .gluteBridge)
        XCTAssertEqual(exercise.id.rawValue, "glute_bridge")
        XCTAssertEqual(exercise.displayName, "Glute Bridge")
        XCTAssertEqual(exercise.spokenName, "glute bridge")
        XCTAssertEqual(exercise.sets, 2)
        XCTAssertEqual(exercise.targetReps, 12...12)
        XCTAssertEqual(exercise.autoCompleteReps, 12)
        XCTAssertEqual(exercise.restSeconds, 60)
        XCTAssertEqual(exercise.equipment, .bodyweight)
        XCTAssertEqual(exercise.presentation.filterGroups, [.lower, .bodyweight])
        XCTAssertEqual(exercise.cameraView, .lyingSide)
        XCTAssertFalse(exercise.startsByHolding)
        XCTAssertTrue(exercise.warnsAboutTilt)
        XCTAssertEqual(exercise.plantedJoints, [.leftAnkle, .rightAnkle])

        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        for alias in exercise.voiceAliases {
            XCTAssertEqual(parser.parse(alias)?.command, .selectExercise(.gluteBridge), alias)
        }
        let photograph = try XCTUnwrap(ExercisePhotography.photograph(for: .gluteBridge))
        XCTAssertEqual(photograph.exerciseName, "Glute Bridge")
        XCTAssertEqual(photograph.assetName, "ExerciseThumbnails/glute_bridge")
        XCTAssertEqual(photograph.photographer, "Vlada Karpovich")
        XCTAssertEqual(photograph.source, "Pexels")
        XCTAssertEqual(photograph.sourceURL.absoluteString,
                       "https://www.pexels.com/photo/a-woman-doing-yoga-in-the-room-4534643/")
        XCTAssertEqual(photograph.license, "Pexels License")

        let startPose = demoPose(motion.startSample)
        let topPose = demoPose(motion.topSample)
        let startArmLength = ArmGeometry.distance(try XCTUnwrap(startPose[.leftShoulder]),
                                                  try XCTUnwrap(startPose[.leftWrist]))
        let topArmLength = ArmGeometry.distance(try XCTUnwrap(topPose[.leftShoulder]),
                                                try XCTUnwrap(topPose[.leftWrist]))
        let guideArmLength = ExerciseDemoFigureView.upperArm + ExerciseDemoFigureView.forearm
        XCTAssertEqual(startArmLength, guideArmLength, accuracy: 0.001)
        XCTAssertEqual(topArmLength, guideArmLength, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(exercise.motionEnvelope.outward * guideArmLength, startArmLength)
        XCTAssertEqual(exercise.motionEnvelope.above, 0.1)
        XCTAssertEqual(exercise.motionEnvelope.below, 0.1)
    }

    private struct Run {
        var reps = 0
        var eventSides: [Set<BodySide>] = []
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
        var readings: [FormReading] = []
        var topReadings: [FormReading] = []
        var startLine: ThresholdLine?
        var upLine: ThresholdLine?
        var peakAngle = -Double.infinity
        var kneeAngleAtPeak: Double?
        var maximumPrePeakKneeAngle: Double = 0
    }

    private func run(_ motion: ArmMotion, loops: Int = 1, scale: CGFloat = 1,
                     thigh: CGFloat = 1, shin: CGFloat = 1, facingLeft: Bool = false,
                     gapAfter: TimeInterval? = nil,
                     estimatedJoints: Set<LandmarkType> = [],
                     ankleOffsetAtTop: CGFloat = 0,
                     ankleOffsetBeforeTop: CGFloat = 0) throws -> Run {
        let analyzer = GluteBridgeAnalyzer(epoch: 1)
        var result = Run()
        let sampleCount = Int(ceil(motion.duration * Double(loops) * 10)) + 1
        var timestampOffset: TimeInterval = 0
        for index in 0..<sampleCount {
            let time = Double(index) / 10
            if let gapAfter, time >= gapAfter, timestampOffset == 0 { timestampOffset = 0.4 }
            let sample = motion.sample(at: time)
            var joints = demoPose(sample)
            adjust(joints: &joints, sample: sample, thigh: thigh, shin: shin,
                   ankleOffsetAtTop: ankleOffsetAtTop, ankleOffsetBeforeTop: ankleOffsetBeforeTop,
                   time: time)
            if facingLeft { joints = mirrored(joints) }
            joints = joints.mapValues { CGPoint(x: $0.x * scale + 300, y: $0.y * scale + 200) }
            if let shoulder = joints[.leftShoulder], let hip = joints[.leftHip],
               let knee = joints[.leftKnee], let ankle = joints[.leftAnkle] {
                let direction: CGFloat = ankle.x >= shoulder.x ? 1 : -1
                let angle = GluteBridgeAnalyzer.hipAngle(shoulder: shoulder, hip: hip, knee: knee,
                                                         facing: direction)
                let kneeAngle = ArmGeometry.angle(at: knee, hip, ankle)
                if sample.shape.hipLift >= 0.25, sample.shape.hipLift < 0.9 {
                    result.maximumPrePeakKneeAngle = max(result.maximumPrePeakKneeAngle, kneeAngle)
                }
                if angle > result.peakAngle {
                    result.peakAngle = angle
                    result.kneeAngleAtPeak = kneeAngle
                }
            }
            let analysis = analyzer.process(try frame(joints: joints, time: time + timestampOffset,
                                                      estimatedJoints: estimatedJoints), counting: true)
            result.reps += analysis.repEvents.count
            result.eventSides += analysis.repEvents.map(\.sides)
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
            result.readings = analysis.formReadings
            if !analysis.endPositionSides.isEmpty { result.topReadings = analysis.formReadings }
            if let thresholds = analysis.thresholds.values.first {
                result.startLine = result.startLine ?? thresholds.startLine
                result.upLine = result.upLine ?? thresholds.topLine
            }
        }
        return result
    }

    private func adjust(joints: inout [LandmarkType: CGPoint], sample: ArmMotionSample,
                        thigh: CGFloat, shin: CGFloat, ankleOffsetAtTop: CGFloat,
                        ankleOffsetBeforeTop: CGFloat, time _: TimeInterval) {
        let downHip = ExerciseDemoFigureView.lyingSideDownHip
        guard let hip = joints[.leftHip], var ankle = joints[.leftAnkle],
              joints[.leftKnee] != nil else { return }
        let hipDX = hip.x - downHip.x
        let hipDY = hip.y - downHip.y
        let adjustedHip = CGPoint(x: downHip.x + hipDX * thigh, y: downHip.y + hipDY * thigh)
        joints[.leftHip] = adjustedHip

        let lift = sample.shape.hipLift
        if lift >= 0.9, lift <= 1.2 { ankle.x += ankleOffsetAtTop }
        if ankleOffsetBeforeTop > 0, lift >= 0.25, lift < 0.7 { ankle.x += ankleOffsetBeforeTop }
        // Keep the guide's two-bone knee while changing only the ankle in form-isolation cases.
        if ankleOffsetAtTop == 0, ankleOffsetBeforeTop == 0 {
            joints[.leftKnee] = ArmGeometry.twoBoneKnee(
                hip: adjustedHip, ankle: ankle,
                thighLength: ExerciseDemoFigureView.lyingSideThigh * thigh,
                shinLength: ExerciseDemoFigureView.lyingSideShin * shin,
                bendDirection: 1
            )
        }
        joints[.leftAnkle] = ankle
    }

    private func keyframe(hipLift: Double, move: TimeInterval, hold: TimeInterval,
                          step: Int) -> ArmKeyframe {
        ArmKeyframe(angles: ArmAngles(upperArmElevation: 0, forearmElevation: 0),
                    moveDuration: move, holdDuration: hold, stepIndex: step,
                    shape: FigureShape(hipLift: hipLift))
    }

    private func demoPose(_ sample: ArmMotionSample) -> [LandmarkType: CGPoint] {
        ExerciseDemoFigureView.pose(for: sample, cameraView: .lyingSide).jointLocations
    }

    private func demoAngle(_ sample: ArmMotionSample) throws -> Double {
        let joints = demoPose(sample)
        return GluteBridgeAnalyzer.hipAngle(
            shoulder: try XCTUnwrap(joints[.leftShoulder]),
            hip: try XCTUnwrap(joints[.leftHip]),
            knee: try XCTUnwrap(joints[.leftKnee]),
            facing: 1
        )
    }

    private func angleFrame(_ angle: Double, time: TimeInterval, side: BodySide = .left,
                            scale: CGFloat = 1, shift: CGPoint = .zero) throws -> PoseFrame {
        let shoulder = CGPoint(x: 100, y: 300)
        let knee = CGPoint(x: 200, y: 300)
        let minorAngle = angle > 180 ? 360 - angle : angle
        let height = 50 / CGFloat(tan(minorAngle * .pi / 360))
        let hip = CGPoint(x: 150, y: angle <= 180 ? 300 + height : 300 - height)
        let ankle = CGPoint(x: 230, y: 370)
        let base: [LandmarkType: CGPoint] = [
            .nose: CGPoint(x: 55, y: 285), .neck: CGPoint(x: 80, y: 300),
            .leftShoulder: shoulder, .leftHip: hip, .leftKnee: knee, .leftAnkle: ankle
        ]
        var joints = base
        if side == .right { joints = mirrored(base).reduce(into: [:]) { $0[opposite($1.key)] = $1.value } }
        joints = joints.mapValues { CGPoint(x: $0.x * scale + shift.x, y: $0.y * scale + shift.y) }
        return try frame(joints: joints, time: time)
    }

    private func frame(joints: [LandmarkType: CGPoint], time: TimeInterval,
                       estimatedJoints: Set<LandmarkType> = []) throws -> PoseFrame {
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 800, imageHeight: 900),
                         timestamp: time, estimatedJoints: estimatedJoints)
    }

    private func mirrored(_ joints: [LandmarkType: CGPoint]) -> [LandmarkType: CGPoint] {
        Dictionary(uniqueKeysWithValues: joints.map { type, point in
            (type, CGPoint(x: 300 - point.x, y: point.y))
        })
    }

    private func opposite(_ joint: LandmarkType) -> LandmarkType {
        switch joint {
        case .leftShoulder: return .rightShoulder
        case .rightShoulder: return .leftShoulder
        case .leftHip: return .rightHip
        case .rightHip: return .leftHip
        case .leftKnee: return .rightKnee
        case .rightKnee: return .leftKnee
        case .leftAnkle: return .rightAnkle
        case .rightAnkle: return .leftAnkle
        default: return joint
        }
    }
}
