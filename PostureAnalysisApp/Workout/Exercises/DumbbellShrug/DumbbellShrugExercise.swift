import CoreGraphics
import Foundation

extension ExerciseID {
    static let dumbbellShrug = ExerciseID(rawValue: "dumbbell_shrug")
}

extension CoachingCueID {
    static let shrugHigher = CoachingCueID(rawValue: "shrug.higher")
    static let shrugEven = CoachingCueID(rawValue: "shrug.even")
    static let shrugArmsStraight = CoachingCueID(rawValue: "shrug.arms_straight")
    static let shrugTorso = CoachingCueID(rawValue: "shrug.torso")
}

/// Prototype thresholds for a dumbbell shrug filmed from the front. These are heuristics to tune on device.
///
/// - Signal `lift` is how far the shoulder midpoint rose toward the nose, in shoulder widths:
///   (nose-to-shoulder gap at rest − gap now) / shoulder width. The nose is the fixed point, so moving the
///   whole body up and down, as when rising onto the toes, reads no lift.
/// - The rest gap and shoulder width are refreshed while the shoulders rest and locked during a rep.
struct DumbbellShrugConfiguration: Codable {
    /// Rest: the shoulders are back down, at most this far above the locked rest.
    var restMaximumLift = 0.04
    /// Top: the shoulders are at least this far above the locked rest.
    var topMinimumLift = 0.10
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 0.8
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence = 0.4
    /// Recent samples whose widest shoulder span is the live ruler.
    var rulerWindow = 10
    var gapSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 6
    /// While resting, the locked rest moves only toward a lower rest that is at least this much deeper,
    /// so a return that stops just inside the Rest line never moves it.
    var restRefreshDepth = 0.02
    /// Start position: both elbows are straight and each wrist hangs well below its shoulder.
    var minimumHangingElbowAngle = 150.0
    var minimumHangingArmDrop = 0.8

    // Form coaching uses the same shoulder-width units. The guide's own demonstration raises none of these.

    /// A rise this far above the locked rest is an attempt, counted or not.
    var attemptMinimumLift = 0.05
    /// "Lift both shoulders evenly": the two shoulders' rises differ by more than this at the attempt's peak.
    var maximumSideDifference = 0.05
    /// "Keep your arms straight": either elbow bends below this while the shoulders are lifted.
    var minimumElbowAngle = 150.0
    /// "Keep your torso still": the shoulder midpoint's sideways offset from the hip midpoint drifts more than
    /// this from the start of the set. Skipped while hips aren't visible.
    var torsoOffsetTolerance = 0.12
    /// Rest samples that set the torso baseline.
    var baselineSamples = 5

    static let standard = DumbbellShrugConfiguration()
}

enum DumbbellShrugExercise {
    static func definition(configuration: DumbbellShrugConfiguration = .standard) -> ExerciseDefinition {
        let shoulders: Set<LandmarkType> = [.leftShoulder, .rightShoulder]
        return ExerciseDefinition(
            id: .dumbbellShrug,
            displayName: "Dumbbell Shrug",
            presentation: ExercisePresentation(
                shortName: "Shrug",
                muscles: ["Upper back", "Traps"],
                filterGroups: [.upper, .dumbbells],
                gradient: ExerciseGradient(token: .shrug, stops: ["#5b6ee1", "#9b8cf2"], angle: 135),
                symbolName: "dumbbell.fill",
                equipmentLine: "Two dumbbells",
                cameraSetupLine: "Front, head and arms",
                watchesFor: [
                    WatchItem(cueID: .shrugHigher, text: "Shoulders lift toward your ears"),
                    WatchItem(cueID: .shrugEven, text: "Both shoulders lift evenly"),
                    WatchItem(cueID: .shrugArmsStraight, text: "Arms stay straight"),
                    WatchItem(cueID: .shrugTorso, text: "Torso stays still")
                ]
            ),
            spokenName: "dumbbell shrug",
            sets: 2,
            targetReps: 12...12,
            autoCompleteReps: 12,
            targetRangeAnnouncementReps: nil,
            restSeconds: 60,
            requiredJoints: [.nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist],
            focusSegments: [
                FocusSegment(from: .leftShoulder, to: .leftElbow, style: .limb),
                FocusSegment(from: .leftElbow, to: .leftWrist, style: .limb),
                FocusSegment(from: .rightShoulder, to: .rightElbow, style: .limb),
                FocusSegment(from: .rightElbow, to: .rightWrist, style: .limb),
                FocusSegment(from: .leftShoulder, to: .rightShoulder, style: .reference),
                FocusSegment(from: .leftHip, to: .rightHip, style: .reference)
            ],
            headroomArmLengths: nil,
            countsArmsIndependently: false,
            setupLine: "Dumbbell shrugs, two sets of 12. Face the phone with your head in view and hold a dumbbell in each hand at your sides.",
            voiceAliases: ["dumbbell shrug", "dumbbell shrugs", "shrug", "shrugs", "shoulder shrugs"],
            guide: guide,
            coachingCues: [
                .corrective(.shrugHigher, "Lift your shoulders higher.", trigger: .perRep, priority: 50,
                            joints: shoulders),
                .corrective(.shrugEven, "Lift both shoulders evenly.", trigger: .perRep, priority: 40,
                            joints: shoulders),
                .corrective(.shrugArmsStraight, "Keep your arms straight.", trigger: .continuous, priority: 30,
                            joints: [.leftElbow, .rightElbow, .leftWrist, .rightWrist]),
                .corrective(.shrugTorso, "Keep your torso still.", trigger: .continuous, priority: 20,
                            joints: shoulders.union([.leftHip, .rightHip]))
            ],
            reminders: [
                .reminder(CoachingCueID(rawValue: "shrug.reminder.pause"), "Pause at the top."),
                .reminder(CoachingCueID(rawValue: "shrug.reminder.lower"), "Lower all the way."),
                .reminder(CoachingCueID(rawValue: "shrug.reminder.chin"), "Keep your chin level.")
            ],
            // A tight band from just above the raised shoulders down past the hanging dumbbells.
            motionEnvelope: MotionEnvelope(above: 0.2, below: 1.1, outward: 0.3),
            cameraView: .front,
            startsByHolding: true,
            equipment: .dumbbells,
            makeAnalyzer: { epoch in DumbbellShrugAnalyzer(epoch: epoch, configuration: configuration) },
            diagnostics: ExerciseDiagnostics(configuration, definition: definition(configuration:))
        )
    }

    private static var guide: ExerciseGuide {
        // The arms hang straight throughout; only the shoulders move.
        let arms = ArmAngles(upperArmElevation: -88, forearmElevation: -88)
        return ExerciseGuide(
            summary: "2 sets × 12 reps · Two dumbbells · Front view",
            steps: [
                GuideStep(title: "Start", detail: "Stand tall facing the phone with the dumbbells at your sides, arms straight."),
                GuideStep(title: "Lift", detail: "Lift both shoulders straight up toward your ears, then pause."),
                GuideStep(title: "Lower", detail: "Lower your shoulders all the way. That's one rep.")
            ],
            tip: "Keep your arms straight; the shoulders do the work.",
            walkthrough: "This is the dumbbell shrug. Stand tall facing the phone with a dumbbell in each hand "
                + "at your sides and your arms straight. Lift both shoulders straight up toward your ears and pause. "
                + "Then lower them all the way. That's one rep.",
            startPositionInstruction: "Stand tall, dumbbells at your sides",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: arms, moveDuration: 0.8, holdDuration: 0.6, stepIndex: 1,
                            shape: FigureShape(shoulderLift: 0.22)),
                ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0, stepIndex: 2)
            ], forearmPlane: .frontal, holdsDumbbells: true)
        )
    }
}
