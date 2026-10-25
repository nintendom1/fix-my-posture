import CoreGraphics
import Foundation

extension ExerciseID {
    static let stiffLegDeadlift = ExerciseID(rawValue: "stiff_leg_deadlift")
}

extension CoachingCueID {
    static let deadliftDeeper = CoachingCueID(rawValue: "deadlift.deeper")
    static let deadliftHipsBack = CoachingCueID(rawValue: "deadlift.hips_back")
    static let deadliftStandTall = CoachingCueID(rawValue: "deadlift.stand_tall")
    static let deadliftWeightsClose = CoachingCueID(rawValue: "deadlift.weights_close")
}

/// Prototype thresholds for a side-view dumbbell hip hinge. All angles come from pixel geometry and are
/// scale-free; tune them on device.
struct StiffLegDeadliftConfiguration {
    var standMaxPitch: Double = 15
    var hingeMinPitch: Double = 55
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 1.0
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var sideSwitchMargin: Double = 0.2
    var referenceTimeout: TimeInterval = 8
    var thresholdAngleTolerance: Double = 0.0001

    // Form coaching. The guide's own demonstration raises none of these.
    var attemptMinimumRise: Double = 25
    var incompleteHingeRetreat: Double = 20
    var squatKneeAngleMaximum: Double = 140
    var weightsCloseMinimumPitch: Double = 40
    var weightsCloseMaximumThighRatio: Double = 0.35
    var thresholdHalfWidthTorsoRatio: CGFloat = 0.3

    static let standard = StiffLegDeadliftConfiguration()
}

enum StiffLegDeadliftExercise {
    static func definition(configuration: StiffLegDeadliftConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .stiffLegDeadlift,
            displayName: "Stiff-Legged Dumbbell Deadlift",
            presentation: ExercisePresentation(
                shortName: "Stiff-Leg Deadlift",
                muscles: ["Hamstrings", "Glutes"],
                filterGroups: [.lower, .dumbbells],
                gradient: ExerciseGradient(token: .deadlift, stops: ["#d87653", "#f2b46d"], angle: 135),
                symbolName: "dumbbell.fill",
                equipmentLine: "Two dumbbells",
                cameraSetupLine: "Side-on, full body",
                watchesFor: [
                    WatchItem(cueID: .deadliftDeeper, text: "Hinge depth"),
                    WatchItem(cueID: .deadliftHipsBack, text: "Hips back, knees soft"),
                    WatchItem(cueID: .deadliftStandTall, text: "Stand fully between reps"),
                    WatchItem(cueID: .deadliftWeightsClose, text: "Weights close to legs")
                ]
            ),
            spokenName: "stiff-legged deadlift",
            sets: 2,
            targetReps: 8...10,
            autoCompleteReps: 10,
            targetRangeAnnouncementReps: 8,
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
            setupLine: "Stiff-legged dumbbell deadlifts, two sets of 8 to 10. Stand side-on to the phone with your whole body in view, holding the dumbbells in front of your thighs.",
            voiceAliases: [
                "stiff legged deadlift", "stiff leg deadlift", "stiff-legged deadlift",
                "dumbbell deadlift", "deadlift", "deadlifts"
            ],
            guide: guide,
            coachingCues: coachingCues,
            reminders: [
                .reminder(CoachingCueID(rawValue: "deadlift.reminder.knees"), "Soft knees, hips back."),
                .reminder(CoachingCueID(rawValue: "deadlift.reminder.brace"), "Brace your core."),
                .reminder(CoachingCueID(rawValue: "deadlift.reminder.neck"), "Keep your neck neutral.")
            ],
            // The arms and dumbbells travel down from the shoulders toward shin level; protect the head-to-feet
            // side-view movement and the space in front of the torso.
            motionEnvelope: MotionEnvelope(above: 0.6, below: 2.3, outward: 0.9),
            cameraView: .side,
            anyOfRequiredJoints: [
                [.leftShoulder, .leftHip, .leftKnee, .leftAnkle],
                [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
            ],
            startsByHolding: false,
            equipment: .dumbbells,
            plantedJoints: [.leftAnkle, .rightAnkle],
            makeAnalyzer: { epoch in StiffLegDeadliftAnalyzer(epoch: epoch, configuration: configuration) }
        )
    }

    private static var coachingCues: [CoachingCue] {
        [
            .corrective(.deadliftDeeper, "Hinge a little deeper.", trigger: .perRep, priority: 50,
                        joints: [.leftHip, .rightHip, .leftShoulder, .rightShoulder]),
            .corrective(.deadliftHipsBack, "Push your hips back, knees soft.", trigger: .perRep, priority: 40,
                        joints: [.leftKnee, .rightKnee]),
            .corrective(.deadliftStandTall, "Stand all the way up.", trigger: .perRep, priority: 30,
                        joints: [.leftHip, .rightHip, .leftShoulder, .rightShoulder]),
            .corrective(.deadliftWeightsClose, "Keep the weights close to your legs.", trigger: .continuous,
                        priority: 20, joints: [.leftWrist, .rightWrist])
        ]
    }

    private static var guide: ExerciseGuide {
        let hangingArms = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        // The figure's torso is long for its legs, so at the bottom the arms angle slightly back toward the shins
        // to keep the dumbbells close to the legs, as a real hinge does. The shins stay near vertical.
        let hingeArms = ArmAngles(upperArmElevation: -108, forearmElevation: -108)
        let hinge = FigureShape(torsoPitch: 62, hipShift: 0.8, hipDrop: 0.12)
        return ExerciseGuide(
            summary: "2 sets × 8–10 reps · Two dumbbells · Stand side-on, head to feet",
            steps: [
                GuideStep(title: "Start", detail: "Stand tall, side-on to the phone, holding the dumbbells in front of your thighs with your whole body in view."),
                GuideStep(title: "Hinge", detail: "Push your hips back with soft knees. Keep the dumbbells close to your legs as they lower to about shin level, with a flat torso."),
                GuideStep(title: "Stand", detail: "Drive your hips forward and stand tall. That's one rep.")
            ],
            tip: "Keep the dumbbells close to your legs as you hinge.",
            walkthrough: "This is the stiff-legged dumbbell deadlift. Stand tall, side-on to the phone, holding the dumbbells in front of your thighs with your whole body in view. "
                + "Push your hips back with soft knees, keeping the dumbbells close to your legs. Lower them to about shin level with a flat torso. "
                + "Then drive your hips forward and stand tall. That's one rep.",
            startPositionInstruction: "Stand tall, dumbbells in front of your thighs",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: hangingArms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0, shape: .neutral),
                ArmKeyframe(angles: hingeArms, moveDuration: 1.5, holdDuration: 0.4, stepIndex: 1, shape: hinge),
                ArmKeyframe(angles: hangingArms, moveDuration: 1.5, holdDuration: 0, stepIndex: 2, shape: .neutral)
            ], holdsDumbbells: true)
        )
    }
}
