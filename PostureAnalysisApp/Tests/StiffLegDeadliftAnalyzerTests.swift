import CoreGraphics
import Foundation
import XCTest
@testable import PostureAnalysisApp

final class StiffLegDeadliftAnalyzerTests: XCTestCase {
    private let exercise = StiffLegDeadliftExercise.definition()
    private var motion: ArmMotion { exercise.guide.motion }

    func testGuideCountsOncePerLoopAcrossScaleFacingAndSegmentProportions() throws {
        let variants: [(CGFloat, CGFloat, CGFloat, CGFloat, Bool)] = [
            (0.5, 1, 1, 1, false), (2, 1, 1, 1, true),
            (1, 0.85, 1, 1, true), (1, 1.15, 1, 1, false),
            (1, 1, 0.85, 1, false), (1, 1, 1.15, 1, true),
            (1, 1, 1, 0.85, true), (1, 1, 1, 1.15, false)
        ]

        for (scale, thigh, shin, torso, mirrored) in variants {
            let result = try run(motion, loops: 2, scale: scale, thigh: thigh, shin: shin,
                                 torso: torso, mirrored: mirrored)
            let label = "scale \(scale), thigh \(thigh), shin \(shin), torso \(torso), mirrored \(mirrored)"
            XCTAssertEqual(result.reps, 2, label)
            if thigh == 1, shin == 1, torso == 1 {
                XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "The demonstration raises no cues: \(result.forms)")
                XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), label)
            }
        }

        let startPitch = try measuredPitch(motion.startSample)
        let hingePitch = try measuredPitch(motion.topSample)
        XCTAssertEqual(startPitch, 0, accuracy: 0.001)
        XCTAssertEqual(hingePitch, 62, accuracy: 0.001)
    }

    func testEveryWholeBodyRepEventCreditsBothSides() throws {
        let result = try run(motion)

        XCTAssertEqual(result.eventSides, [Set(BodySide.allCases)])
    }

    func testShallowHingeDoesNotCountAndAsksForMoreDepth() throws {
        let shallow = motionWithHinge(pitch: 45)
        let result = try run(shallow)

        XCTAssertEqual(result.reps, 0)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.deadliftDeeper) })
    }

    func testSquatLikeAttemptAsksForHipsBack() throws {
        let squat = motionWithHinge(pitch: 62, hipDrop: 0.35)
        let result = try run(squat)

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.deadliftHipsBack) }, "\(result.forms)")
    }

    func testTransientKneeBendAwayFromDeepestHingeDoesNotRaiseHipsBackCue() throws {
        let result = try run(motion, kneeAngleAtTime: { time in
            if (1.9...2.1).contains(time) { return 135 }
            if (2.5...2.9).contains(time) { return 155 }
            return nil
        })

        XCTAssertEqual(result.reps, 1)
        XCTAssertFalse(result.forms.contains { $0.flags.contains(.deadliftHipsBack) }, "\(result.forms)")
    }

    func testRehingingWithoutStandingAsksToStandTall() throws {
        let start = motion.startAngles
        let arms = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        let rehinge = ArmMotion(keyframes: [
            ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1, stepIndex: 0),
            ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0.2, stepIndex: 1,
                        shape: FigureShape(torsoPitch: 62, hipShift: 1, hipDrop: 0.2)),
            ArmKeyframe(angles: arms, moveDuration: 0.8, holdDuration: 0.2, stepIndex: 1,
                        shape: FigureShape(torsoPitch: 32, hipShift: 0.5, hipDrop: 0.1)),
            ArmKeyframe(angles: arms, moveDuration: 0.8, holdDuration: 0.2, stepIndex: 1,
                        shape: FigureShape(torsoPitch: 62, hipShift: 1, hipDrop: 0.2)),
            ArmKeyframe(angles: start, moveDuration: 1.3, holdDuration: 0, stepIndex: 2)
        ])
        let result = try run(rehinge)

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.deadliftStandTall) }, "\(result.forms)")
    }

    func testDriftingWeightsRaiseCueOnlyWhenWristIsVisible() throws {
        let visible = try run(motion, wristDrift: 0.6)
        let hidden = try run(motion, wristDrift: 0.6, includesWrist: false)

        XCTAssertTrue(visible.signals.contains { $0.contains(.deadliftWeightsClose) })
        XCTAssertTrue(hidden.signals.allSatisfy { !$0.contains(.deadliftWeightsClose) })
        XCTAssertEqual(hidden.reps, 1, "The wrist is optional for counting.")
    }

    func testEstimatedWristStillCountsWithoutFormFlagsOrSignals() throws {
        let result = try run(motion, wristDrift: 0.6, estimatedJoints: [.leftWrist])

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "\(result.forms)")
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), "\(result.signals)")
    }

    func testTrackingGapInvalidatesTheCycle() throws {
        let result = try run(motion, gapAfter: 2.0)
        XCTAssertEqual(result.reps, 0)
    }

    func testStandAndHingeBoundariesNeedTwoConsecutiveSamples() throws {
        let atStand = StiffLegDeadliftAnalyzer(epoch: 1)
        XCTAssertFalse(atStand.process(try frame(pitch: 15, time: 0), counting: true).startPositionHeld)
        XCTAssertTrue(atStand.process(try frame(pitch: 15, time: 0.1), counting: true).startPositionHeld)

        let aboveStand = StiffLegDeadliftAnalyzer(epoch: 1)
        XCTAssertFalse(aboveStand.process(try frame(pitch: 16, time: 0), counting: true).startPositionHeld)
        XCTAssertFalse(aboveStand.process(try frame(pitch: 16, time: 0.1), counting: true).startPositionHeld)

        let belowHinge = StiffLegDeadliftAnalyzer(epoch: 1)
        XCTAssertTrue(belowHinge.process(try frame(pitch: 54, time: 0), counting: true).endPositionSides.isEmpty)
        XCTAssertTrue(belowHinge.process(try frame(pitch: 54, time: 0.1), counting: true).endPositionSides.isEmpty)

        let atHinge = StiffLegDeadliftAnalyzer(epoch: 1)
        XCTAssertTrue(atHinge.process(try frame(pitch: 55, time: 0), counting: true).endPositionSides.isEmpty)
        XCTAssertEqual(atHinge.process(try frame(pitch: 55, time: 0.1), counting: true).endPositionSides, [.left])
    }

    func testThresholdLinesUseTheStandingLockedHipAndTorsoLength() throws {
        let result = try run(motion, loops: 1)
        let stand = try XCTUnwrap(result.lockedStandThresholds)
        let hinge = try XCTUnwrap(result.hingeThresholds)

        XCTAssertEqual(stand.startLine.label, "Stand ↑")
        XCTAssertEqual(stand.topLine.label, "Hinge ↓")
        XCTAssertEqual(stand.startLine, hinge.startLine)
        XCTAssertEqual(stand.topLine, hinge.topLine)
        XCTAssertEqual(stand.startLine.to.x - stand.startLine.from.x, 0.6 * 130, accuracy: 0.01)
    }

    func testCatalogVoiceAliasesAndPhotoRecord() throws {
        XCTAssertEqual(ExerciseCatalog.definition(for: .stiffLegDeadlift)?.id, .stiffLegDeadlift)
        XCTAssertEqual(exercise.id.rawValue, "stiff_leg_deadlift")

        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        for alias in exercise.voiceAliases {
            XCTAssertEqual(parser.parse(alias)?.command, .selectExercise(.stiffLegDeadlift), alias)
        }

        let photo = try XCTUnwrap(ExercisePhotography.photograph(for: .stiffLegDeadlift))
        XCTAssertEqual(photo.exerciseName, "Stiff-Legged Dumbbell Deadlift")
        XCTAssertEqual(photo.assetName, "ExerciseThumbnails/stiff_leg_deadlift")
        XCTAssertEqual(photo.photographer, "marcuschanmedia")
        XCTAssertEqual(photo.source, "Pexels")
        XCTAssertEqual(photo.sourceURL.absoluteString,
                       "https://www.pexels.com/photo/female-weightlifter-performing-deadlift-in-gym-29825217/")
        XCTAssertEqual(photo.license, "Pexels License")
    }

    func testDefinitionUsesSideOnWholeBodyFramingAndDoesNotHoldToStart() throws {
        XCTAssertEqual(exercise.requiredJoints, [])
        XCTAssertEqual(exercise.anyOfRequiredJoints, [
            [.leftShoulder, .leftHip, .leftKnee, .leftAnkle],
            [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
        ])
        XCTAssertEqual(exercise.cameraView, .side)
        XCTAssertFalse(exercise.startsByHolding)
        XCTAssertEqual(exercise.guide.startPositionInstruction, "Stand tall, dumbbells in front of your thighs")

        var framing = FramingEvaluator(requiredJoints: exercise.requiredJoints,
                                       anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                                       headroomArmLengths: exercise.headroomArmLengths,
                                       cameraView: exercise.cameraView)
        var pose = try demoPose(motion.startSample)
        pose[.leftAnkle] = nil
        let status = framing.evaluate(try frame(joints: pose, time: 0))
        XCTAssertFalse(status.isReliable)
        XCTAssertEqual(status.guidance, .stepBackSideFullBody)
    }

    private struct Run {
        var reps = 0
        var eventSides: [Set<BodySide>] = []
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
        var lockedStandThresholds: ArmThresholds?
        var hingeThresholds: ArmThresholds?
    }

    private func run(_ motion: ArmMotion, loops: Int = 1, scale: CGFloat = 1,
                     thigh: CGFloat = 1, shin: CGFloat = 1, torso: CGFloat = 1,
                     mirrored: Bool = false, wristDrift: CGFloat = 0,
                     includesWrist: Bool = true, gapAfter: TimeInterval? = nil,
                     estimatedJoints: Set<LandmarkType> = [],
                     kneeAngleAtTime: ((TimeInterval) -> Double?)? = nil) throws -> Run {
        let analyzer = StiffLegDeadliftAnalyzer(epoch: 1)
        var result = Run()
        let sampleCount = Int(motion.duration * Double(loops) * 10)
        var timestampOffset: TimeInterval = 0
        for index in 0..<sampleCount {
            let motionTime = Double(index) / 10
            if let gapAfter, motionTime >= gapAfter, timestampOffset == 0 { timestampOffset = 0.4 }
            let sample = motion.sample(at: motionTime)
            var joints = try demoPose(sample)
            adjust(joints: &joints, sample: sample, thigh: thigh, shin: shin, torso: torso,
                   wristDrift: wristDrift, includesWrist: includesWrist)
            if let angle = kneeAngleAtTime?(motionTime),
               let hip = joints[.leftHip], let ankle = joints[.leftAnkle] {
                joints[.leftKnee] = kneePoint(hip: hip, ankle: ankle, angle: angle)
            }
            if mirrored { joints = joints.mapValues { CGPoint(x: 300 - $0.x, y: $0.y) } }
            joints = joints.mapValues { CGPoint(x: $0.x * scale + 300, y: $0.y * scale + 400) }

            let analysis = analyzer.process(try frame(joints: joints, time: motionTime + timestampOffset,
                                                      estimatedJoints: estimatedJoints), counting: true)
            result.reps += analysis.repEvents.count
            result.eventSides += analysis.repEvents.map(\.sides)
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
            if let thresholds = analysis.thresholds[.left], thresholds.isLocked {
                let pitch = sample.shape.torsoPitch ?? 0
                if pitch >= 55 {
                    result.hingeThresholds = thresholds
                } else if result.hingeThresholds == nil, pitch <= 15 {
                    result.lockedStandThresholds = thresholds
                }
            }
        }
        return result
    }

    private func motionWithHinge(pitch: Double, hipDrop: Double = 0.2) -> ArmMotion {
        let arms = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        return ArmMotion(keyframes: [
            ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1, stepIndex: 0),
            ArmKeyframe(angles: arms, moveDuration: 1.5, holdDuration: 0.4, stepIndex: 1,
                        shape: FigureShape(torsoPitch: pitch, hipShift: 1, hipDrop: hipDrop)),
            ArmKeyframe(angles: arms, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
    }

    private func measuredPitch(_ sample: ArmMotionSample) throws -> Double {
        let joints = try demoPose(sample)
        let hip = try XCTUnwrap(joints[.leftHip])
        let shoulder = try XCTUnwrap(joints[.leftShoulder])
        return Double(atan2(abs(shoulder.x - hip.x), abs(hip.y - shoulder.y))) * 180 / .pi
    }

    private func adjust(joints: inout [LandmarkType: CGPoint], sample: ArmMotionSample,
                        thigh: CGFloat, shin: CGFloat, torso: CGFloat, wristDrift: CGFloat,
                        includesWrist: Bool) {
        guard let hip = joints[.leftHip], let shoulder = joints[.leftShoulder],
              let ankle = joints[.leftAnkle] else { return }
        if torso != 1 {
            let adjusted = CGPoint(x: hip.x + (shoulder.x - hip.x) * torso,
                                   y: hip.y + (shoulder.y - hip.y) * torso)
            let shift = CGPoint(x: adjusted.x - shoulder.x, y: adjusted.y - shoulder.y)
            joints[.leftShoulder] = adjusted
            if let nose = joints[.nose] { joints[.nose] = CGPoint(x: nose.x + shift.x, y: nose.y + shift.y) }
        }
        if let newShoulder = joints[.leftShoulder] {
            let arm = ArmMotion.place(shoulder: newShoulder, outward: 1,
                                      upperArm: ExerciseDemoFigureView.upperArm,
                                      forearm: ExerciseDemoFigureView.forearm, angles: sample.angles)
            joints[.leftElbow] = arm.elbow
            joints[.leftWrist] = arm.wrist
        }
        let standingThigh = ArmGeometry.distance(ExerciseDemoFigureView.sideFigureJoints[.leftHip] ?? .zero,
                                                 ExerciseDemoFigureView.sideFigureJoints[.leftKnee] ?? .zero)
        let standingShin = ArmGeometry.distance(ExerciseDemoFigureView.sideFigureJoints[.leftKnee] ?? .zero,
                                                ExerciseDemoFigureView.sideFigureJoints[.leftAnkle] ?? .zero)
        joints[.leftKnee] = ArmGeometry.twoBoneKnee(hip: hip, ankle: ankle,
                                                   thighLength: standingThigh * thigh,
                                                   shinLength: standingShin * shin, bendDirection: 1)
        if (sample.shape.torsoPitch ?? 0) >= 40, wristDrift > 0,
           let wrist = joints[.leftWrist] {
            joints[.leftWrist] = CGPoint(x: wrist.x + wristDrift * standingThigh, y: wrist.y)
        }
        if !includesWrist { joints[.leftWrist] = nil }
    }

    private func demoPose(_ sample: ArmMotionSample) throws -> [LandmarkType: CGPoint] {
        let pose = ExerciseDemoFigureView.pose(for: sample, cameraView: .side)
        return pose.jointLocations
    }

    private func frame(pitch: Double, time: TimeInterval) throws -> PoseFrame {
        let sample = ArmMotionSample(angles: ArmAngles(upperArmElevation: -90, forearmElevation: -90),
                                     stepIndex: 0, shape: FigureShape(torsoPitch: pitch, hipShift: 1, hipDrop: 0.2))
        return try frame(joints: demoPose(sample), time: time)
    }

    private func frame(joints: [LandmarkType: CGPoint], time: TimeInterval,
                       estimatedJoints: Set<LandmarkType> = []) throws -> PoseFrame {
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                         timestamp: time, estimatedJoints: estimatedJoints)
    }

    private func kneePoint(hip: CGPoint, ankle: CGPoint, angle: Double) -> CGPoint {
        let dx = ankle.x - hip.x
        let dy = ankle.y - hip.y
        let chord = hypot(dx, dy)
        let halfChord = chord / 2
        let height = halfChord / CGFloat(tan(angle * .pi / 360))
        let midpoint = ArmGeometry.midpoint(hip, ankle)
        return CGPoint(x: midpoint.x - dy / chord * height,
                       y: midpoint.y + dx / chord * height)
    }
}
