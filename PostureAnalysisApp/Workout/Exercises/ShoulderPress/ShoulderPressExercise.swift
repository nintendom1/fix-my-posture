import CoreGraphics
import Foundation

extension ExerciseID {
    static let shoulderPress = ExerciseID(rawValue: "shoulder_press")
}

/// Prototype thresholds for a standing dumbbell shoulder press filmed from the front.
/// The Start and Top lines drawn during a set are these same values.
/// These are heuristics to tune on device, not biomechanical standards.
///
/// - Height `h` is the wrist's height above its shoulder in that arm's own length (upper arm + forearm),
///   measured in image pixels. Using the moving arm as the ruler makes the rule the same at any
///   distance and for any body proportions, without needing the hips.
/// - The elbow angle is the 2D interior angle, so front-view foreshortening makes it approximate.
///   It is paired with `h` so that neither signal alone decides an end position.
/// - The usual start (upper arms about level, forearms vertical) gives `h` ≈ 0.35–0.5. A straight arm
///   overhead gives `h` ≈ 0.95–1.0, and `h` = sin(elevation) for any straight arm, so the top needs a
///   straight arm at least about 53° above horizontal. Side raises don't count.
/// - Raise `bottomMaxHeight` if a user's start position never registers; Show Measurements helps.
struct ShoulderPressConfiguration {
    /// Start: elbows bent, forearms pointing up, wrists at most this many arm lengths above the shoulders.
    var bottomMaxHeight: Double = 0.6
    var bottomMaxElbowAngle: Double = 115
    /// Top: arms nearly straight, wrists at least this many arm lengths above the shoulders.
    var topMinHeight: Double = 0.8
    var topMinElbowAngle: Double = 140
    /// Consecutive 10 Hz samples needed to confirm an end position.
    var confirmationSamples = 2
    /// Faster bottom-to-bottom cycles are treated as noise.
    var minimumRepDuration: TimeInterval = 0.8
    /// A longer gap between complete samples requires a fresh bottom. This tolerates one dropped
    /// sample at the 100–133 ms capture cadence; two dropped samples invalidate the rep.
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    /// Recent samples (about 1 s at 10 Hz) whose longest arm length is the live ruler.
    var rulerWindow = 10
    /// Smoothing for the shoulder height while an arm's reference is not locked.
    var shoulderSmoothing: CGFloat = 0.4
    /// A locked reference is dropped if its arm stays away from the start this long, for example
    /// after stepping closer mid-rep.
    var referenceTimeout: TimeInterval = 6

    static let standard = ShoulderPressConfiguration()
}

enum ShoulderPressExercise {
    static func definition(configuration: ShoulderPressConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .shoulderPress,
            displayName: "Dumbbell Shoulder Press",
            spokenName: "dumbbell shoulder press",
            sets: 2,
            targetReps: 8...10,
            autoCompleteReps: 10,
            targetRangeAnnouncementReps: 8,
            restSeconds: 90,
            // Hips aren't needed for counting, so users can stand closer for steadier tracking.
            requiredJoints: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist],
            focusSegments: [
                FocusSegment(from: .leftShoulder, to: .leftElbow, style: .limb),
                FocusSegment(from: .leftElbow, to: .leftWrist, style: .limb),
                FocusSegment(from: .rightShoulder, to: .rightElbow, style: .limb),
                FocusSegment(from: .rightElbow, to: .rightWrist, style: .limb),
                FocusSegment(from: .leftShoulder, to: .rightShoulder, style: .reference),
                FocusSegment(from: .leftHip, to: .rightHip, style: .reference)
            ],
            headroomArmLengths: 1.05,
            countsArmsIndependently: false,
            setupLine: "Dumbbell shoulder press, two sets of 8 to 10. Face the phone and hold a dumbbell in each hand just above your shoulders.",
            voiceAliases: ["dumbbell shoulder press", "shoulder press", "shoulder presses", "dumbbell press", "overhead press"],
            guide: guide,
            makeAnalyzer: { epoch in ShoulderPressAnalyzer(epoch: epoch, configuration: configuration) }
        )
    }

    private static var guide: ExerciseGuide {
        // Elbows slightly below the shoulders puts the dumbbells just above them.
        let start = ArmAngles(upperArmElevation: -10, forearmElevation: 88)
        let top = ArmAngles(upperArmElevation: 78, forearmElevation: 85)
        return ExerciseGuide(
            summary: "2 sets × 8–10 reps · Two dumbbells · Room to reach overhead",
            steps: [
                GuideStep(title: "Start", detail: "Stand tall facing the phone. Hold a dumbbell in each hand just above your shoulders, elbows bent and out to the sides."),
                GuideStep(title: "Press", detail: "Push both dumbbells straight up until your arms are straight overhead."),
                GuideStep(title: "Lower", detail: "Bring them back down to your shoulders with control. That's one rep.")
            ],
            tip: "Pick a weight you can lift 8 to 10 times with control.",
            walkthrough: "This is the dumbbell shoulder press. Start by standing tall, facing the phone. "
                + "Hold a dumbbell in each hand just above your shoulders, with your elbows bent and out to the sides. "
                + "Press both dumbbells straight up until your arms are straight overhead. "
                + "Then lower them back down to your shoulders with control. That's one rep.",
            startPositionInstruction: "Hold the dumbbells just above your shoulders",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: top, moveDuration: 1.0, holdDuration: 0.5, stepIndex: 1),
                ArmKeyframe(angles: start, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
            ])
        )
    }
}
