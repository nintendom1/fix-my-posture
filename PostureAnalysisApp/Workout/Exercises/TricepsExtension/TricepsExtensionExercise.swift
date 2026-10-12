import CoreGraphics
import Foundation

extension ExerciseID {
    static let tricepsExtension = ExerciseID(rawValue: "triceps_extension")
}

extension CoachingCueID {
    static let tricepsFullExtension = CoachingCueID(rawValue: "triceps.full_extension")
    static let tricepsLowerBehindHead = CoachingCueID(rawValue: "triceps.lower_behind_head")
    static let tricepsControlledLowering = CoachingCueID(rawValue: "triceps.controlled_lowering")
    static let tricepsElbowsUp = CoachingCueID(rawValue: "triceps.elbows_up")
}

/// Prototype thresholds for an overhead band triceps extension filmed from the side. Standing side-on keeps
/// the near arm in view the whole time; from the front, the hands hide behind the head at the start.
/// These are heuristics to tune on device.
///
/// - Signal `s` is the wrist's height above its elbow in forearm lengths. From the side the forearm swings
///   in the image plane, so its longest recent length is a full-length ruler at any distance and for any
///   proportions. Folded behind the head reads about −0.7; straight overhead about 1.0.
/// - The elbow angle (2D) pairs with `s` so a forearm that's merely tilted back doesn't count as the top.
struct TricepsExtensionConfiguration {
    /// Start: hands lowered behind the head, elbow bent.
    var bottomMaxRatio: Double = -0.4
    var bottomMaxElbowAngle: Double = 100
    /// Top: arm straight overhead.
    var topMinRatio: Double = 0.75
    var topMinElbowAngle: Double = 140
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 0.8
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var rulerWindow = 10
    var elbowSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 6

    // Form coaching. The guide's own demonstration raises none of these.

    var attemptMinimumRise: Double = 0.5
    /// "Straighten your arms fully": the top was missed, or the peak 2D elbow angle stayed below this.
    var fullExtensionElbowAngle: Double = 155
    /// "Lower behind your head": after the top, the hands dipped this far and extended again without
    /// reaching the start.
    var returnDip: Double = 0.5
    /// "Lower with control": the wrist took less than this from the Top line to the Start line. The demo's
    /// 1.5 s lowering reads 0.57 s; 0.3 s is a lowering faster than about 0.8 s.
    var minimumDescentTime: TimeInterval = 0.3
    /// "Keep your elbows pointing up": the upper arm tipped this many degrees from where it pointed at the
    /// start of the set.
    var elbowDriftTolerance: Double = 25
    var baselineSamples = 5

    static let standard = TricepsExtensionConfiguration()
}

enum TricepsExtensionExercise {
    static func definition(configuration: TricepsExtensionConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .tricepsExtension,
            displayName: "Band Triceps Extension",
            spokenName: "band triceps extension",
            sets: 2,
            targetReps: 10...10,
            autoCompleteReps: 10,
            targetRangeAnnouncementReps: nil,
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
            headroomArmLengths: 1.05,
            countsArmsIndependently: false,
            setupLine: "Band triceps extension, two sets of 10. Stand side-on to the phone with the band under your feet and your hands behind your head.",
            voiceAliases: ["band triceps extension", "triceps extension", "triceps extensions", "tricep extension",
                           "tricep extensions", "overhead triceps", "triceps"],
            guide: guide,
            coachingCues: coachingCues,
            reminders: [
                .reminder(CoachingCueID(rawValue: "triceps.reminder.ribs"), "Keep your ribs down."),
                .reminder(CoachingCueID(rawValue: "triceps.reminder.elbows"), "Elbows close to your head."),
                .reminder(CoachingCueID(rawValue: "triceps.reminder.breathe"), "Breathe out as you extend.")
            ],
            // Around the near shoulder: up one arm length overhead, and forward and back past the hands.
            motionEnvelope: MotionEnvelope(above: 1.05, below: 0.2, outward: 0.6),
            cameraView: .side,
            anyOfRequiredJoints: [[.leftShoulder, .leftElbow, .leftWrist], [.rightShoulder, .rightElbow, .rightWrist]],
            equipment: .band,
            makeAnalyzer: { epoch in TricepsExtensionAnalyzer(epoch: epoch, configuration: configuration) }
        )
    }

    private static var coachingCues: [CoachingCue] {
        let arms: Set<LandmarkType> = [.leftElbow, .rightElbow, .leftWrist, .rightWrist]
        return [
            .corrective(.tricepsFullExtension, "Straighten your arms fully.", trigger: .perRep, priority: 50, joints: arms),
            .corrective(.tricepsLowerBehindHead, "Lower behind your head.", trigger: .perRep, priority: 40, joints: arms),
            .corrective(.tricepsControlledLowering, "Lower with control.", trigger: .perRep, priority: 30, joints: arms),
            .corrective(.tricepsElbowsUp, "Keep your elbows pointing up.", trigger: .continuous, priority: 20,
                        joints: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow])
        ]
    }

    private static var guide: ExerciseGuide {
        // Seen from the side, facing forward: the upper arm points up, and the forearm folds down behind
        // the head (225° is down and back), then straightens overhead.
        let start = ArmAngles(upperArmElevation: 85, forearmElevation: 225)
        let top = ArmAngles(upperArmElevation: 85, forearmElevation: 88)
        return ExerciseGuide(
            summary: "2 sets × 10 reps · Resistance band · Stand side-on",
            steps: [
                GuideStep(title: "Start", detail: "Stand side-on to the phone with the band under your feet. Hold it behind your head with your elbows pointing up."),
                GuideStep(title: "Extend", detail: "Straighten your arms overhead, keeping your elbows pointing up."),
                GuideStep(title: "Lower", detail: "Bend your elbows to lower your hands behind your head with control. That's one rep.")
            ],
            tip: "Standing side-on lets the phone see your arm the whole time; either side works.",
            walkthrough: "This is the band triceps extension. Stand side-on to the phone with the band under your feet. "
                + "Hold the band behind your head, with your elbows pointing up. "
                + "Straighten your arms overhead, keeping your elbows pointing up. "
                + "Then bend your elbows to lower your hands behind your head, with control. That's one rep.",
            startPositionInstruction: "Hold the band behind your head, elbows up",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: top, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
                ArmKeyframe(angles: start, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
            ], holdsDumbbells: false)
        )
    }
}
