import CoreGraphics
import Foundation

extension ExerciseID {
    static let lateralRaise = ExerciseID(rawValue: "lateral_raise")
}

extension CoachingCueID {
    static let lateralHigher = CoachingCueID(rawValue: "lateral.higher")
    static let lateralEven = CoachingCueID(rawValue: "lateral.even")
    static let lateralShouldersDown = CoachingCueID(rawValue: "lateral.shoulders_down")
    static let lateralArmsLong = CoachingCueID(rawValue: "lateral.arms_long")
    static let lateralTorsoCentered = CoachingCueID(rawValue: "lateral.torso")
}

/// Prototype thresholds for a two-arm lateral raise filmed from the front.
/// Height and outward distance use each arm's own length as the ruler.
struct LateralRaiseConfiguration {
    /// Start is measured from the shoulder to the wrist; the hanging arm is about one arm length below it.
    var startMaximumHeight = -0.75
    /// The wrist must be at least this high and this far out to count as a lateral raise.
    var topMinimumHeight = -0.2
    var topMinimumOutward = 0.75
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 0.8
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence = 0.4
    var rulerWindow = 10
    var shoulderSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 6

    // Form coaching uses the same arm-length and pixel-space measurements as the rep rule.
    var attemptMinimumRise = 0.25
    var maximumTopTimingGap: TimeInterval = 0.3
    var maximumHeightGap = 0.25
    var minimumTopElbowAngle = 140.0
    var shoulderShrugTolerance = 0.12
    var torsoOffsetTolerance = 0.12
    var baselineSamples = 5

    static let standard = LateralRaiseConfiguration()
}

enum LateralRaiseExercise {
    static func definition(configuration: LateralRaiseConfiguration = .standard) -> ExerciseDefinition {
        let arms: Set<LandmarkType> = [.leftElbow, .rightElbow, .leftWrist, .rightWrist]
        return ExerciseDefinition(
            id: .lateralRaise,
            displayName: "Lateral Raise",
            presentation: ExercisePresentation(
                shortName: "Lateral Raise",
                muscles: ["Shoulders"],
                filterGroups: [.upper, .dumbbells],
                gradient: ExerciseGradient(token: .lateralRaise, stops: ["#4e78d2", "#62c7c8"], angle: 135),
                symbolName: "dumbbell.fill",
                equipmentLine: "Two dumbbells",
                cameraSetupLine: "Front, full arm span",
                watchesFor: [
                    WatchItem(cueID: .lateralHigher, text: "Both arms reach shoulder height"),
                    WatchItem(cueID: .lateralEven, text: "Both arms move evenly"),
                    WatchItem(cueID: .lateralShouldersDown, text: "Shoulders stay down"),
                    WatchItem(cueID: .lateralArmsLong, text: "Keep a slight elbow bend"),
                    WatchItem(cueID: .lateralTorsoCentered, text: "Torso stays centered")
                ]
            ),
            spokenName: "lateral raise",
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
            sideroomArmLengths: 1.1,
            countsArmsIndependently: false,
            setupLine: "Lateral Raise, two sets of 10. Face the phone and hold a dumbbell in each hand at your sides.",
            voiceAliases: [
                "lateral raise", "lateral raises", "side raise", "side raises", "side lateral raise", "dumbbell lateral raise"
            ],
            guide: guide,
            coachingCues: [
                .corrective(.lateralHigher, "Raise to shoulder height.", trigger: .perRep, priority: 50, joints: arms),
                .corrective(.lateralEven, "Raise both arms evenly.", trigger: .perRep, priority: 40, joints: arms),
                .corrective(.lateralShouldersDown, "Keep your shoulders down.", trigger: .continuous, priority: 30,
                            joints: [.nose, .leftShoulder, .rightShoulder]),
                .corrective(.lateralArmsLong, "Keep your arms long.", trigger: .perRep, priority: 20, joints: arms),
                .corrective(.lateralTorsoCentered, "Keep your torso centered.", trigger: .continuous, priority: 10,
                            joints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip])
            ],
            reminders: [
                .reminder(CoachingCueID(rawValue: "lateral.reminder.elbows"), "Lead with your elbows."),
                .reminder(CoachingCueID(rawValue: "lateral.reminder.lower"), "Lower slowly."),
                .reminder(CoachingCueID(rawValue: "lateral.reminder.brace"), "Brace your core.")
            ],
            motionEnvelope: MotionEnvelope(above: 0.3, below: 1.0, outward: 1.1),
            cameraView: .front,
            startsByHolding: true,
            equipment: .dumbbells,
            makeAnalyzer: { epoch in LateralRaiseAnalyzer(epoch: epoch, configuration: configuration) }
        )
    }

    private static var guide: ExerciseGuide {
        let start = ArmAngles(upperArmElevation: -85, forearmElevation: -85)
        let raised = ArmAngles(upperArmElevation: 0, forearmElevation: -8)
        return ExerciseGuide(
            summary: "2 sets × 10 reps · Two dumbbells · Front view",
            steps: [
                GuideStep(title: "Start", detail: "Stand tall with a dumbbell in each hand at your sides."),
                GuideStep(title: "Raise", detail: "Raise both arms out to the sides to about shoulder height, keeping a slight bend in your elbows."),
                GuideStep(title: "Lower", detail: "Pause with the dumbbells level, then lower them slowly to your sides. That's one rep.")
            ],
            tip: "Use a weight you can raise and lower with control.",
            walkthrough: "This is the lateral raise. Stand tall with the dumbbells at your sides. "
                + "Raise both arms out to the sides to about shoulder height with a slight bend in your elbows. "
                + "Pause with the dumbbells level, then lower slowly to your sides. That's one rep.",
            startPositionInstruction: "Stand tall, dumbbells at your sides",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: raised, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
                ArmKeyframe(angles: start, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
            ], forearmPlane: .frontal, holdsDumbbells: true)
        )
    }
}
