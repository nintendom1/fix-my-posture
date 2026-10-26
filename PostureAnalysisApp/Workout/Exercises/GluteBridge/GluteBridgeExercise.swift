import CoreGraphics
import Foundation

extension ExerciseID {
    static let gluteBridge = ExerciseID(rawValue: "glute_bridge")
}

extension CoachingCueID {
    static let bridgeHigher = CoachingCueID(rawValue: "bridge.higher")
    static let bridgeStraightLine = CoachingCueID(rawValue: "bridge.straight_line")
    static let bridgeFeetCloser = CoachingCueID(rawValue: "bridge.feet_closer")
    static let bridgeLower = CoachingCueID(rawValue: "bridge.lower")
}

/// Prototype thresholds for a supine side-view bridge. The signed hip angle is scale-free.
struct GluteBridgeConfiguration: Codable {
    var downMaxAngle: Double = 145
    var upMinAngle: Double = 165
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 1.0
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var sideSwitchMargin: Double = 0.2
    var referenceRefreshAngle: Double = 2
    var thresholdAngleTolerance: Double = 0.0001
    var thresholdHalfWidthThighRatio: CGFloat = 0.6
    var attemptMinimumRise: Double = 10
    var overArchPeakAngle: Double = 195
    var feetFarKneeAngle: Double = 120
    var lowerAmount: Double = 10

    static let standard = GluteBridgeConfiguration()
}

enum GluteBridgeExercise {
    static func definition(configuration: GluteBridgeConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .gluteBridge,
            displayName: "Glute Bridge",
            presentation: ExercisePresentation(
                shortName: "Glute Bridge",
                muscles: ["Glutes", "Hamstrings"],
                filterGroups: [.lower, .bodyweight],
                gradient: ExerciseGradient(token: .bridge, stops: ["#e98575", "#f6b77b"], angle: 135),
                symbolName: "figure.cooldown",
                equipmentLine: "Bodyweight",
                cameraSetupLine: "Floor-level side camera",
                watchesFor: [
                    WatchItem(cueID: .bridgeHigher, text: "Hip lift height"),
                    WatchItem(cueID: .bridgeStraightLine, text: "Straight-line finish"),
                    WatchItem(cueID: .bridgeFeetCloser, text: "Foot position"),
                    WatchItem(cueID: .bridgeLower, text: "Full lowering between reps")
                ]
            ),
            spokenName: "glute bridge",
            sets: 2,
            targetReps: 12...12,
            autoCompleteReps: 12,
            targetRangeAnnouncementReps: nil,
            restSeconds: 60,
            requiredJoints: [],
            focusSegments: [
                FocusSegment(from: .leftShoulder, to: .leftElbow, style: .limb),
                FocusSegment(from: .leftElbow, to: .leftWrist, style: .limb),
                FocusSegment(from: .rightShoulder, to: .rightElbow, style: .limb),
                FocusSegment(from: .rightElbow, to: .rightWrist, style: .limb),
                FocusSegment(from: .leftShoulder, to: .leftHip, style: .reference),
                FocusSegment(from: .rightShoulder, to: .rightHip, style: .reference),
                FocusSegment(from: .leftHip, to: .leftKnee, style: .limb),
                FocusSegment(from: .leftKnee, to: .leftAnkle, style: .limb),
                FocusSegment(from: .rightHip, to: .rightKnee, style: .limb),
                FocusSegment(from: .rightKnee, to: .rightAnkle, style: .limb)
            ],
            headroomArmLengths: nil,
            countsArmsIndependently: false,
            setupLine: "Glute bridges, two sets of 12. Lie on your back side-on to the upright phone, knees bent, with your whole body in view.",
            voiceAliases: ["glute bridge", "glute bridges", "hip bridge", "hip bridges", "bridge", "bridges"],
            guide: guide,
            coachingCues: [
                .corrective(.bridgeHigher, "Lift your hips higher.", trigger: .perRep, priority: 50,
                            joints: [.leftHip, .rightHip]),
                .corrective(.bridgeStraightLine, "Stop at a straight line.", trigger: .perRep, priority: 40,
                            joints: [.leftHip, .rightHip]),
                .corrective(.bridgeFeetCloser, "Bring your feet a little closer.", trigger: .perRep, priority: 30,
                            joints: [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle]),
                .corrective(.bridgeLower, "Lower all the way down.", trigger: .perRep, priority: 20,
                            joints: [.leftHip, .rightHip])
            ],
            reminders: [
                .reminder(CoachingCueID(rawValue: "bridge.reminder.heels"), "Press through your heels."),
                .reminder(CoachingCueID(rawValue: "bridge.reminder.squeeze"), "Squeeze at the top."),
                .reminder(CoachingCueID(rawValue: "bridge.reminder.ribs"), "Keep your ribs down.")
            ],
            motionEnvelope: MotionEnvelope(above: 0.1, below: 0.1, outward: 1.1),
            cameraView: .lyingSide,
            anyOfRequiredJoints: [
                [.leftShoulder, .leftHip, .leftKnee, .leftAnkle],
                [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
            ],
            startsByHolding: false,
            equipment: .bodyweight,
            plantedJoints: [.leftAnkle, .rightAnkle],
            makeAnalyzer: { epoch in GluteBridgeAnalyzer(epoch: epoch, configuration: configuration) },
            diagnostics: ExerciseDiagnostics(configuration, definition: definition(configuration:))
        )
    }

    private static var guide: ExerciseGuide {
        let arms = ArmAngles(upperArmElevation: 0, forearmElevation: 0)
        return ExerciseGuide(
            summary: "2 sets × 12 reps · No equipment · Side camera at floor level",
            steps: [
                GuideStep(title: "Start", detail: "Lie on your back with your knees bent and feet flat, hip-width apart."),
                GuideStep(title: "Lift", detail: "Press through your heels to lift your hips until your shoulders, hips, and knees form a straight line."),
                GuideStep(title: "Lower", detail: "Pause, then lower your hips all the way down.")
            ],
            tip: "Stop at a straight line; don't push past it.",
            walkthrough: "This is the glute bridge. Lie on your back with your knees bent and feet flat, hip-width apart. Press through your heels to lift your hips until your shoulders, hips, and knees form a straight line. Pause, then lower all the way down.",
            startPositionInstruction: "Lie on your back, knees bent, feet flat",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0,
                            shape: FigureShape(hipLift: 0)),
                ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0.6, stepIndex: 1,
                            shape: FigureShape(hipLift: 1)),
                ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0, stepIndex: 2,
                            shape: FigureShape(hipLift: 0))
            ], holdsDumbbells: false)
        )
    }
}
