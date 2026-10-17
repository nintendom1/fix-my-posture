import CoreGraphics
import Foundation

extension ExerciseID {
    static let hammerCurl = ExerciseID(rawValue: "hammer_curl")
}

extension CoachingCueID {
    static let curlFullRange = CoachingCueID(rawValue: "curl.full_range")
    static let curlStraightenAtBottom = CoachingCueID(rawValue: "curl.straighten_at_bottom")
    static let curlElbowsIn = CoachingCueID(rawValue: "curl.elbows_in")
    static let curlBodyStill = CoachingCueID(rawValue: "curl.body_still")
}

/// Prototype thresholds for standing hammer curls filmed from the front. Each arm counts on its own,
/// so alternating and simultaneous curls both work. These are heuristics to tune on device.
///
/// - Signal `r` is the wrist's height above its elbow in upper-arm lengths. From the front the upper arm
///   hangs nearly vertical, so it's a steady ruler at any distance, while the forearm swings toward the
///   camera and looks shorter. Hanging straight reads about −0.75 to −1.0 for typical proportions; at the
///   top the wrist is well above the elbow (about 0.7 to 1.0).
/// - The elbow height and ruler are locked while an arm hangs at the start, so the lines hold still.
struct HammerCurlConfiguration {
    /// Start: arm hanging straight, wrist at least this far below the elbow.
    var bottomMaxRatio: Double = -0.6
    /// Top: wrist at least this far above the elbow.
    var topMinRatio: Double = 0.25
    var confirmationSamples = 2
    /// A faster bottom-to-bottom cycle for one arm is treated as noise.
    var minimumRepDuration: TimeInterval = 0.8
    /// A longer gap between an arm's samples requires a fresh start.
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    /// Recent samples whose longest upper arm is the live ruler.
    var rulerWindow = 10
    var elbowSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 6

    // Form coaching, in the same units. The guide's own demonstration raises none of these.

    /// A wrist rising this far above where it hung starts an attempt, counted or not.
    var attemptMinimumRise: Double = 0.5
    /// "Straighten at the bottom": after the top, the wrist dipped at least this far and curled up
    /// again without hanging straight.
    var returnDip: Double = 0.4
    /// "Keep your elbows by your sides": an elbow's sideways distance from its shoulder grew by more than
    /// this fraction of shoulder width compared with the start of the set.
    var elbowFlareTolerance: Double = 0.25
    /// "Keep your body still": the shoulder midpoint moved more than this many upper-arm lengths relative
    /// to the hip midpoint compared with the start of the set. Skipped while hips aren't visible.
    var swayTolerance: Double = 0.35
    /// Samples with both arms hanging that set the baselines.
    var baselineSamples = 5

    static let standard = HammerCurlConfiguration()
}

enum HammerCurlExercise {
    static func definition(configuration: HammerCurlConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .hammerCurl,
            displayName: "Hammer Curl",
            presentation: ExercisePresentation(
                shortName: "Hammer Curl",
                muscles: ["Biceps", "Forearms"],
                filterGroups: [.upper, .dumbbells],
                gradient: ExerciseGradient(token: .curl, stops: ["#b04bff", "#ff7fc8"], angle: 135),
                symbolName: "dumbbell.fill",
                equipmentLine: "Two dumbbells",
                cameraSetupLine: "Front, full arms",
                watchesFor: [
                    WatchItem(cueID: .curlFullRange, text: "Full range of motion"),
                    WatchItem(cueID: .curlElbowsIn, text: "Elbows staying by your sides")
                ]
            ),
            spokenName: "hammer curl",
            sets: 2,
            targetReps: 10...10,
            autoCompleteReps: 10,
            targetRangeAnnouncementReps: nil,
            restSeconds: 60,
            requiredJoints: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist],
            focusSegments: [
                FocusSegment(from: .leftShoulder, to: .leftElbow, style: .limb),
                FocusSegment(from: .leftElbow, to: .leftWrist, style: .limb),
                FocusSegment(from: .rightShoulder, to: .rightElbow, style: .limb),
                FocusSegment(from: .rightElbow, to: .rightWrist, style: .limb),
                FocusSegment(from: .leftShoulder, to: .rightShoulder, style: .reference),
                FocusSegment(from: .leftHip, to: .rightHip, style: .reference)
            ],
            headroomArmLengths: nil,
            countsArmsIndependently: true,
            setupLine: "Hammer curls, two sets of 10. Face the phone and let the dumbbells hang at your sides with straight arms.",
            voiceAliases: ["hammer curl", "hammer curls", "curl", "curls", "dumbbell curls"],
            guide: guide,
            coachingCues: coachingCues,
            reminders: [
                .reminder(CoachingCueID(rawValue: "curl.reminder.elbows"), "Elbows stay close."),
                .reminder(CoachingCueID(rawValue: "curl.reminder.lower"), "Lower slowly."),
                .reminder(CoachingCueID(rawValue: "curl.reminder.tall"), "Stand tall.")
            ],
            // From the shoulders down past the hanging dumbbells, and out past them to the sides.
            motionEnvelope: MotionEnvelope(above: 0.15, below: 1.15, outward: 0.35),
            makeAnalyzer: { epoch in HammerCurlAnalyzer(epoch: epoch, configuration: configuration) }
        )
    }

    /// Missing the top or the bottom explains why a rep didn't count, so those come first.
    private static var coachingCues: [CoachingCue] {
        let arms: Set<LandmarkType> = [.leftElbow, .rightElbow, .leftWrist, .rightWrist]
        return [
            .corrective(.curlFullRange, "Curl all the way up.", trigger: .perRep, priority: 50, joints: arms),
            .corrective(.curlStraightenAtBottom, "Straighten at the bottom.", trigger: .perRep, priority: 40, joints: arms),
            .corrective(.curlElbowsIn, "Keep your elbows by your sides.", trigger: .continuous, priority: 20,
                        joints: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow]),
            .corrective(.curlBodyStill, "Keep your body still.", trigger: .continuous, priority: 10,
                        joints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip])
        ]
    }

    private static var guide: ExerciseGuide {
        // The upper arms hang by the sides; the forearms swing forward, toward the camera.
        let start = ArmAngles(upperArmElevation: -85, forearmElevation: -85)
        let top = ArmAngles(upperArmElevation: -80, forearmElevation: 70)
        return ExerciseGuide(
            summary: "2 sets × 10 reps · Two dumbbells · Palms facing in",
            steps: [
                GuideStep(title: "Start", detail: "Stand tall facing the phone. Let the dumbbells hang at your sides with straight arms, palms facing in."),
                GuideStep(title: "Curl", detail: "Keeping your elbows by your sides, curl the dumbbells up toward your shoulders. Curl one arm at a time or both together."),
                GuideStep(title: "Lower", detail: "Lower them slowly until your arms are straight again. That's one rep for each arm.")
            ],
            tip: "Each arm counts on its own; the rep count is the number both arms have done.",
            walkthrough: "This is the hammer curl. Stand tall, facing the phone, with a dumbbell in each hand and your palms facing in. "
                + "Let the dumbbells hang at your sides with straight arms. "
                + "Keeping your elbows by your sides, curl the dumbbells up toward your shoulders. "
                + "Then lower them slowly until your arms are straight. You can curl one arm at a time or both together.",
            startPositionInstruction: "Let the dumbbells hang with straight arms",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: top, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
                ArmKeyframe(angles: start, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
            ], forearmPlane: .sagittal)
        )
    }
}
