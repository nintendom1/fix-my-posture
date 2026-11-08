import CoreGraphics
import Foundation

extension ExerciseID {
    static let sitToStand = ExerciseID(rawValue: "sit_to_stand")
}

extension CoachingCueID {
    static let sitToStandTall = CoachingCueID(rawValue: "sitstand.stand_tall")
    static let sitToStandControl = CoachingCueID(rawValue: "sitstand.control")
    static let sitToStandKnees = CoachingCueID(rawValue: "sitstand.knees")
}

/// Prototype thresholds for sit-to-stands filmed from the front, whole body in view, a chair behind the user.
/// Heuristics to tune on device.
///
/// - Signal `u` is the vertical distance from the ankle midpoint to the shoulder midpoint, divided by standing `u`.
/// - The standing ruler only grows while standing. A seated start bootstraps from its lowest held `u` and confirms
///   the first stand only after `u` rises by the configured ratio with the ankles planted.
/// - Seated is the start; standing is the counted end of the rep.
struct SitToStandConfiguration: Codable {
    /// Seated: shoulders at most this far above the ankles relative to the standing ruler.
    var seatedMaxRatio: Double = 0.80
    /// Standing: shoulders at least this far above the ankles relative to the standing ruler.
    var standMinRatio: Double = 0.90
    /// With no ruler, a seated start must rise by this ratio to confirm its first stand.
    var bootstrapStandRiseRatio: Double = 1.30
    /// A higher seat uses a lower initial rise ratio derived from its seated line.
    var partialBootstrapStandRiseRatio: Double = 1.17
    /// The initial low `u` or high `u` must hold this long before bootstrap can use it.
    var minimumReferenceHold: TimeInterval = 0.35
    /// The ankle midpoint may move this share of `u` vertically during bootstrap or a counted rep.
    var ankleStabilityRatio: Double = 0.06
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 1.2
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    /// Knees are optional for counting and only enter the knee cue at this confidence.
    var minimumKneeConfidence: Double = 0.4
    /// Recent upper-body heights retained at the 10 Hz sample rate.
    var rulerWindow = 10

    // Form coaching. The guide's own demonstration raises none of these.

    /// "Stand all the way up": shoulder-to-ankle `u` rose this share of the standing ruler, but did not reach Stand.
    var attemptMinimumRise: Double = 0.12
    /// "Sit down slowly": `u` went from the standing line to the seated line in less than this.
    var minimumSitDuration: TimeInterval = 0.35
    /// "Keep your knees apart": while rising, the knee gap fell below this share of the ankle gap.
    var kneeGapMinimum: Double = 0.7
    /// The reduced-range variant for the squat family's floor rung.
    var partial = false

    static let standard = SitToStandConfiguration()

    /// Hip-to-ankle corroboration for the lower checkpoint. Partial seats use a higher line.
    var hipSeatedMaxRatio: Double { partial ? 0.92 : 0.88 }
    /// Minimum shoulder-to-ankle rise from the held seat to confirmed stand.
    var minimumRepExcursionRatio: Double { partial ? 0.08 : 0.12 }

    /// Partial seated at `u/R ≤ 0.86`: a higher seat, or touching it and standing again. The guide reads about 0.82.
    static var partialRange: SitToStandConfiguration {
        var configuration = standard
        configuration.seatedMaxRatio = 0.86
        configuration.minimumSitDuration = 0.25
        configuration.partial = true
        return configuration
    }
}

enum SitToStandExercise {
    static func definition(configuration: SitToStandConfiguration = .standard) -> ExerciseDefinition {
        let name = configuration.partial ? "Partial Sit-to-Stand" : "Sit-to-Stand"
        return ExerciseDefinition(
            id: .sitToStand,
            displayName: name,
            presentation: ExercisePresentation(
                shortName: name,
                muscles: ["Legs", "Glutes"],
                filterGroups: [.lower, .bodyweight],
                gradient: ExerciseGradient(token: .sitToStand, stops: ["#5b8def", "#9db8ff"], angle: 135),
                symbolName: "figure.seated.side",
                equipmentLine: "Bodyweight and a sturdy chair",
                cameraSetupLine: "Front, full body, chair behind you",
                watchesFor: [
                    WatchItem(cueID: .sitToStandTall, text: "Standing all the way up"),
                    WatchItem(cueID: .sitToStandControl, text: "Sitting down with control"),
                    WatchItem(cueID: .sitToStandKnees, text: "Knees apart as you rise")
                ]
            ),
            spokenName: configuration.partial ? "partial sit to stand" : "sit to stand",
            sets: 2,
            targetReps: 5...10,
            autoCompleteReps: 10,
            targetRangeAnnouncementReps: 5,
            restSeconds: 60,
            requiredJoints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle],
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
            setupLine: "Sit-to-stands, two sets of 5 to 10. Put a sturdy chair behind you, face the phone, and step back until your whole body is in view, head to feet.",
            voiceAliases: ["sit to stand", "sit-to-stand", "sit to stands", "chair stand", "chair stands",
                           "chair squat", "chair squats"],
            guide: guide(partial: configuration.partial),
            coachingCues: coachingCues,
            reminders: [
                .reminder(CoachingCueID(rawValue: "sitstand.reminder.feet"), "Feet flat on the floor."),
                .reminder(CoachingCueID(rawValue: "sitstand.reminder.lean"), "Lean forward to stand.")
            ],
            // From just above the head down to the feet, a little wider than the shoulders.
            motionEnvelope: MotionEnvelope(above: 0.4, below: 2.4, outward: 0.3),
            startsByHolding: false,
            equipment: .bodyweight,
            plantedJoints: [.leftAnkle, .rightAnkle],
            makeAnalyzer: { epoch in SitToStandAnalyzer(epoch: epoch, configuration: configuration) },
            diagnostics: ExerciseDiagnostics(configuration, definition: definition(configuration:)),
            reducedRange: configuration.partial ? nil : { definition(configuration: .partialRange) }
        )
    }

    private static var coachingCues: [CoachingCue] {
        let legs: Set<LandmarkType> = [.leftHip, .rightHip, .leftKnee, .rightKnee]
        return [
            .corrective(.sitToStandTall, "Stand all the way up.", trigger: .perRep, priority: 50, joints: legs),
            .corrective(.sitToStandControl, "Sit down slowly.", trigger: .perRep, priority: 40, joints: legs),
            .corrective(.sitToStandKnees, "Keep your knees apart.", trigger: .perRep, priority: 30,
                        joints: [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle])
        ]
    }

    /// The guide lowers the shoulders by 0.9 standing-thigh lengths for the full seat and 0.61 for the higher seat.
    /// With its 292-point standing shoulder-to-ankle span, those poses read about 0.74 and 0.82. The full Seat line
    /// at 0.80 leaves a 0.06 margin; the partial line at 0.86 leaves a 0.04 margin for the higher seat.
    private static func guide(partial: Bool) -> ExerciseGuide {
        let arms = ArmAngles(upperArmElevation: -85, forearmElevation: -85)
        let seated = LegPose(hipDrop: partial ? 0.61 : 0.9, kneeSpread: 0.1)
        let lastStep = partial ? "Lower a little" : "Sit down"
        let lastDetail = partial
            ? "Use a higher seat, or lower only until you touch it. Then stand again. That's one rep."
            : "Sit back down slowly, with control. That's one rep."
        return ExerciseGuide(
            summary: partial ? "2 sets × 5–10 reps · A sturdy chair · Whole body in view · Partial range"
                : "2 sets × 5–10 reps · A sturdy chair · Whole body in view",
            steps: [
                GuideStep(title: "Start", detail: "Put a sturdy chair behind you and face the phone. Sit near the front of the chair with your feet flat on the floor, about hip-width apart."),
                GuideStep(title: "Stand up", detail: "Lean forward slightly and stand up without using your hands, if you can."),
                GuideStep(title: "Stand tall", detail: "Stand all the way up."),
                GuideStep(title: lastStep, detail: lastDetail)
            ],
            tip: "Say \u{201C}start\u{201D} or tap Start when you're seated; sitting still won't start the set.",
            walkthrough: "This is the \(partial ? "partial " : "")sit to stand. Put a sturdy chair behind you and face the phone. "
                + "Sit near the front of the chair with your feet flat on the floor, about hip-width apart. "
                + "Lean forward slightly and stand up without using your hands, if you can. Stand all the way up. "
                + (partial
                    ? "Use a higher seat, or lower only until you touch it, then stand again. That's one rep."
                    : "Then sit back down slowly, with control. That's one rep."),
            startPositionInstruction: "Sit near the front of the chair",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0, legs: seated),
                ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0, stepIndex: 1),
                ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 0.4, stepIndex: 2),
                ArmKeyframe(angles: arms, moveDuration: 1.5, holdDuration: 0, stepIndex: 3, legs: seated)
            ], holdsDumbbells: false, chair: true)
        )
    }
}
