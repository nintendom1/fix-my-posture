import CoreGraphics
import Foundation

extension ExerciseID {
    static let airSquat = ExerciseID(rawValue: "air_squat")
}

extension CoachingCueID {
    static let squatDeeper = CoachingCueID(rawValue: "squat.deeper")
    static let squatStandUp = CoachingCueID(rawValue: "squat.stand_up")
    static let squatKneesOut = CoachingCueID(rawValue: "squat.knees_out")
    static let squatChestUp = CoachingCueID(rawValue: "squat.chest_up")
}

/// Prototype thresholds for bodyweight squats filmed from the front, whole body in view. Heuristics to
/// tune on device.
///
/// - Signal `d` is how far the hips sit above the knees, in thigh lengths, averaged over both legs. Standing,
///   the thigh is vertical and `d` is about 1. Squatting, the thigh points toward the camera, so the hips
///   drop to the knees' height on screen and `d` falls toward 0. The thigh is its own ruler (longest recent
///   hip-to-knee length, locked while standing), so the rule is the same at any distance and for any build.
/// - Standing is the start; the squat is the counted end of the rep.
struct AirSquatConfiguration {
    /// Standing: hips at least this many thigh lengths above the knees.
    var standMinRatio: Double = 0.85
    /// Squat: hips at most this far above the knees.
    var squatMaxRatio: Double = 0.45
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 1.0
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var rulerWindow = 10
    var kneeSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 8

    // Form coaching. The guide's own demonstration raises none of these.

    /// Hips dropping this far below standing starts an attempt, counted or not.
    var attemptMinimumDrop: Double = 0.3
    /// "Stand all the way up": after the squat, rose this far and squatted again without standing.
    var returnRise: Double = 0.3
    /// "Keep your knees in line with your toes": a knee moved inside its ankle by more than this share of
    /// hip width compared with standing, while squatting.
    var kneeInTolerance: Double = 0.25
    /// "Keep your chest up": at depth, the shoulders-to-hips height shrank below this share of standing
    /// (a forward lean seen from the front). Skipped without shoulders.
    var minimumTorsoRatio: Double = 0.75
    /// Form checks for knees and chest apply only below this depth.
    var formDepthRatio: Double = 0.6
    var baselineSamples = 5

    static let standard = AirSquatConfiguration()
}

enum AirSquatExercise {
    static func definition(configuration: AirSquatConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .airSquat,
            displayName: "Air Squat",
            presentation: ExercisePresentation(
                shortName: "Air Squat",
                muscles: ["Legs", "Glutes"],
                filterGroups: [.lower, .bodyweight],
                gradient: ExerciseGradient(token: .squat, stops: ["#ff6f91", "#ffa36c"], angle: 135),
                symbolName: "figure.strengthtraining.traditional",
                equipmentLine: "Bodyweight",
                cameraSetupLine: "Front, full body",
                watchesFor: [
                    WatchItem(cueID: .squatDeeper, text: "Depth of each squat"),
                    WatchItem(cueID: .squatKneesOut, text: "Knees tracking outward"),
                    WatchItem(cueID: .squatStandUp, text: "Standing fully between reps")
                ]
            ),
            spokenName: "air squat",
            sets: 2,
            targetReps: 15...15,
            autoCompleteReps: 15,
            targetRangeAnnouncementReps: nil,
            restSeconds: 60,
            requiredJoints: [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle],
            focusSegments: [
                FocusSegment(from: .leftHip, to: .leftKnee, style: .limb),
                FocusSegment(from: .leftKnee, to: .leftAnkle, style: .limb),
                FocusSegment(from: .rightHip, to: .rightKnee, style: .limb),
                FocusSegment(from: .rightKnee, to: .rightAnkle, style: .limb),
                FocusSegment(from: .leftHip, to: .rightHip, style: .reference),
                FocusSegment(from: .leftShoulder, to: .rightShoulder, style: .reference)
            ],
            headroomArmLengths: nil,
            countsArmsIndependently: false,
            setupLine: "Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart.",
            voiceAliases: ["air squats", "air squat", "squats", "squat", "bodyweight squats"],
            guide: guide,
            coachingCues: coachingCues,
            reminders: [
                .reminder(CoachingCueID(rawValue: "squat.reminder.heels"), "Weight in your heels."),
                .reminder(CoachingCueID(rawValue: "squat.reminder.brace"), "Brace your core."),
                .reminder(CoachingCueID(rawValue: "squat.reminder.breathe"), "Breathe in on the way down.")
            ],
            // From just above the head down to the feet, a little wider than the shoulders.
            motionEnvelope: MotionEnvelope(above: 0.4, below: 2.4, outward: 0.3),
            startsByHolding: false,
            equipment: .bodyweight,
            plantedJoints: [.leftAnkle, .rightAnkle],
            makeAnalyzer: { epoch in AirSquatAnalyzer(epoch: epoch, configuration: configuration) }
        )
    }

    private static var coachingCues: [CoachingCue] {
        let legs: Set<LandmarkType> = [.leftHip, .rightHip, .leftKnee, .rightKnee]
        return [
            .corrective(.squatDeeper, "Squat a little deeper.", trigger: .perRep, priority: 50, joints: legs),
            .corrective(.squatStandUp, "Stand all the way up.", trigger: .perRep, priority: 40, joints: legs),
            .corrective(.squatKneesOut, "Keep your knees in line with your toes.", trigger: .continuous, priority: 20,
                        joints: [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle]),
            .corrective(.squatChestUp, "Keep your chest up.", trigger: .continuous, priority: 10,
                        joints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip])
        ]
    }

    private static var guide: ExerciseGuide {
        let arms = ArmAngles(upperArmElevation: -85, forearmElevation: -85)
        return ExerciseGuide(
            summary: "2 sets × 15 reps · No equipment · Whole body in view",
            steps: [
                GuideStep(title: "Start", detail: "Face the phone and step back until your whole body is in view. Stand tall with your feet about shoulder-width apart."),
                GuideStep(title: "Squat", detail: "Push your hips back and bend your knees until your thighs are about level with the floor, knees over your toes."),
                GuideStep(title: "Stand", detail: "Drive through your heels to stand all the way up. That's one rep.")
            ],
            tip: "Say \u{201C}start\u{201D} or tap Start when you're ready; standing still won't start the set.",
            walkthrough: "This is the air squat. Face the phone and step back until your whole body is in view. "
                + "Stand tall with your feet about shoulder-width apart. "
                + "Push your hips back and bend your knees until your thighs are about level with the floor, keeping your knees over your toes. "
                + "Then drive through your heels to stand all the way up. That's one rep.",
            startPositionInstruction: "Stand tall, feet shoulder-width apart",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0.3, stepIndex: 1,
                            legs: LegPose(hipDrop: 0.9, kneeSpread: 0.3)),
                ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0, stepIndex: 2)
            ], holdsDumbbells: false)
        )
    }
}
