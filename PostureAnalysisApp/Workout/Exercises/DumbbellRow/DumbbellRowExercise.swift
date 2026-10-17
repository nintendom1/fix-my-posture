import CoreGraphics
import Foundation

extension ExerciseID {
    static let dumbbellRow = ExerciseID(rawValue: "dumbbell_row")
}

extension CoachingCueID {
    static let rowPullHigher = CoachingCueID(rawValue: "row.pull_higher")
    static let rowStraighten = CoachingCueID(rawValue: "row.straighten")
    static let rowControlledLowering = CoachingCueID(rawValue: "row.controlled_lowering")
    static let rowBackStill = CoachingCueID(rawValue: "row.back_still")
}

/// Prototype thresholds for a one-arm dumbbell row filmed from the side, rowing arm nearer the phone.
/// Heuristics to tune on device.
///
/// - Signal `e` is the elbow's height above its shoulder in upper-arm lengths. Hanging straight it's about
///   −1; pulled up past the back, about −0.2. From the side the upper arm swings in the image plane, so its
///   longest recent length is a full ruler at any distance and for any proportions.
/// - The start also needs a nearly straight elbow, so a bent arm hanging low isn't mistaken for the start.
struct DumbbellRowConfiguration {
    /// Start: arm hanging straight below the shoulder.
    var bottomMaxRatio: Double = -0.85
    var bottomMinElbowAngle: Double = 150
    /// Top: elbow pulled up near the height of the back.
    var topMinRatio: Double = -0.35
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 0.8
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var rulerWindow = 10
    var shoulderSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 6

    // Form coaching. The guide's own demonstration raises none of these.

    var attemptMinimumRise: Double = 0.3
    /// "Lower all the way down": after the top, the elbow dipped this far and pulled again without the arm
    /// hanging straight.
    var returnDip: Double = 0.35
    /// "Lower with control": the elbow took less than this from the Top line to the Start line. The demo's
    /// 1.5 s lowering reads about 0.5 s; 0.25 s is a lowering faster than about 0.75 s.
    var minimumDescentTime: TimeInterval = 0.25
    /// "Keep your back still": the shoulder-to-hip line tipped this many degrees from where it was at the
    /// start of the set. Skipped while the hip isn't visible.
    var backDriftTolerance: Double = 15
    var baselineSamples = 5

    static let standard = DumbbellRowConfiguration()
}

enum DumbbellRowExercise {
    static func definition(configuration: DumbbellRowConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .dumbbellRow,
            displayName: "One-Arm Dumbbell Row",
            presentation: ExercisePresentation(
                shortName: "Dumbbell Row",
                muscles: ["Back", "Biceps"],
                filterGroups: [.upper, .dumbbells],
                gradient: ExerciseGradient(token: .row, stops: ["#3a8dff", "#6fd6ff"], angle: 135),
                symbolName: "dumbbell.fill",
                equipmentLine: "One dumbbell",
                cameraSetupLine: "Side-on, one arm at a time",
                watchesFor: [
                    WatchItem(cueID: .rowPullHigher, text: "Pulling high enough"),
                    WatchItem(cueID: .rowStraighten, text: "Full arm extension"),
                    WatchItem(cueID: .rowBackStill, text: "Torso angle holding steady")
                ]
            ),
            spokenName: "one-arm dumbbell row",
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
                FocusSegment(from: .rightShoulder, to: .rightHip, style: .reference)
            ],
            headroomArmLengths: nil,
            countsArmsIndependently: false,
            setupLine: "One-arm dumbbell rows, two sets of 8 to 10 each arm. Stand side-on to the phone with your left arm nearer it, bend forward, and rest your other hand on a bench.",
            voiceAliases: ["one arm dumbbell row", "one arm row", "dumbbell row", "dumbbell rows", "rows", "row"],
            guide: guide,
            coachingCues: coachingCues,
            reminders: [
                .reminder(CoachingCueID(rawValue: "row.reminder.squeeze"), "Squeeze your shoulder blade."),
                .reminder(CoachingCueID(rawValue: "row.reminder.neck"), "Keep your neck neutral."),
                .reminder(CoachingCueID(rawValue: "row.reminder.brace"), "Brace your core.")
            ],
            // Around the near shoulder: down past the hanging dumbbell and back past the raised elbow.
            motionEnvelope: MotionEnvelope(above: 0.5, below: 1.15, outward: 0.9),
            cameraView: .side,
            anyOfRequiredJoints: [[.leftShoulder, .leftElbow, .leftWrist], [.rightShoulder, .rightElbow, .rightWrist]],
            perSide: true,
            makeAnalyzer: { epoch in DumbbellRowAnalyzer(epoch: epoch, configuration: configuration) }
        )
    }

    private static var coachingCues: [CoachingCue] {
        let arms: Set<LandmarkType> = [.leftElbow, .rightElbow, .leftWrist, .rightWrist]
        return [
            .corrective(.rowPullHigher, "Pull your elbow up past your back.", trigger: .perRep, priority: 50, joints: arms),
            .corrective(.rowStraighten, "Lower all the way down.", trigger: .perRep, priority: 40, joints: arms),
            .corrective(.rowControlledLowering, "Lower with control.", trigger: .perRep, priority: 30, joints: arms),
            .corrective(.rowBackStill, "Keep your back still.", trigger: .continuous, priority: 20,
                        joints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip])
        ]
    }

    private static var guide: ExerciseGuide {
        // Side view, bent forward 50°: the arm hangs straight down (270°), and rowing pulls the elbow back
        // and up behind the shoulder (190°) with the forearm hanging below it.
        let start = ArmAngles(upperArmElevation: 270, forearmElevation: 270)
        let top = ArmAngles(upperArmElevation: 190, forearmElevation: 270)
        return ExerciseGuide(
            summary: "2 sets × 8–10 reps each arm · One dumbbell · Bench or sturdy chair · Stand side-on",
            steps: [
                GuideStep(title: "Start", detail: "Stand side-on to the phone with the rowing arm nearer it. Bend forward with your other hand on a bench and let the dumbbell hang with a straight arm."),
                GuideStep(title: "Row", detail: "Pull your elbow up past your back, keeping it close to your side."),
                GuideStep(title: "Lower", detail: "Lower the dumbbell with control until your arm is straight. Do all your reps, then switch arms.")
            ],
            tip: "Each set is one arm, then the other. When the coach says to switch, turn around so your other arm is nearer the phone.",
            walkthrough: "This is the one-arm dumbbell row. Stand side-on to the phone with the rowing arm nearer it. "
                + "Bend forward with your other hand on a bench, and let the dumbbell hang with a straight arm. "
                + "Pull your elbow up past your back, keeping it close to your side. "
                + "Then lower the dumbbell with control until your arm is straight. Do all your reps, then switch arms.",
            startPositionInstruction: "Let the dumbbell hang with a straight arm",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: top, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
                ArmKeyframe(angles: start, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
            ], torsoPitch: 50)
        )
    }
}
