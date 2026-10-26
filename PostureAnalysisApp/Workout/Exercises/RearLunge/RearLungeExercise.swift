import CoreGraphics
import Foundation

extension ExerciseID {
    static let rearLunge = ExerciseID(rawValue: "rear_lunge")
}

extension CoachingCueID {
    static let lungeDeeper = CoachingCueID(rawValue: "lunge.deeper")
    static let lungeStepLonger = CoachingCueID(rawValue: "lunge.step_longer")
    static let lungeStandTall = CoachingCueID(rawValue: "lunge.stand_tall")
    static let lungeChestUp = CoachingCueID(rawValue: "lunge.chest_up")
}

/// Prototype pixel-space thresholds for a side-view rear lunge.
struct RearLungeConfiguration: Codable {
    var standMaxDrop = 0.08
    var lungeMinDrop = 0.30
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 1.0
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var sideSwitchMargin: Double = 0.2
    var rulerWindow: TimeInterval = 1.0
    var thresholdTolerance = 0.000_001

    var attemptMinimumDrop = 0.12
    var returnRise = 0.1
    var relowerMinimum = 0.04
    var minimumStepRatio = 0.6
    var chestCueMinimumDrop = 0.2
    var chestLeanDegrees = 20.0
    var thresholdHalfWidthLegRatio: CGFloat = 0.35

    static let standard = RearLungeConfiguration()
}

enum RearLungeExercise {
    static func definition(configuration: RearLungeConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .rearLunge,
            displayName: "Dumbbell Rear Lunge",
            presentation: ExercisePresentation(
                shortName: "Rear Lunge",
                muscles: ["Quadriceps", "Glutes"],
                filterGroups: [.lower, .dumbbells],
                gradient: ExerciseGradient(token: .rearLunge, stops: ["#5d78d8", "#9b76dc"], angle: 135),
                symbolName: "dumbbell.fill",
                equipmentLine: "Two dumbbells",
                cameraSetupLine: "Side-on, full body",
                watchesFor: [
                    WatchItem(cueID: .lungeDeeper, text: "Lunge depth"),
                    WatchItem(cueID: .lungeStepLonger, text: "Step length"),
                    WatchItem(cueID: .lungeStandTall, text: "Standing fully between reps"),
                    WatchItem(cueID: .lungeChestUp, text: "Torso stays upright")
                ]
            ),
            spokenName: "rear lunge",
            sets: 2,
            targetReps: 8...8,
            autoCompleteReps: 8,
            targetRangeAnnouncementReps: nil,
            restSeconds: 60,
            requiredJoints: [],
            focusSegments: [
                FocusSegment(from: .leftShoulder, to: .leftHip, style: .reference),
                FocusSegment(from: .rightShoulder, to: .rightHip, style: .reference),
                FocusSegment(from: .leftHip, to: .leftKnee, style: .limb),
                FocusSegment(from: .leftKnee, to: .leftAnkle, style: .limb),
                FocusSegment(from: .rightHip, to: .rightKnee, style: .limb),
                FocusSegment(from: .rightKnee, to: .rightAnkle, style: .limb)
            ],
            headroomArmLengths: nil,
            countsArmsIndependently: false,
            setupLine: "Dumbbell rear lunges, two sets of 8 each leg. Stand side-on to the phone with your whole body in view, holding the dumbbells at your sides.",
            voiceAliases: [
                "rear lunge", "rear lunges", "reverse lunge", "reverse lunges",
                "dumbbell lunge", "lunges", "lunge"
            ],
            guide: guide,
            coachingCues: coachingCues,
            reminders: [
                .reminder(CoachingCueID(rawValue: "lunge.reminder.front_foot"), "Front foot stays planted."),
                .reminder(CoachingCueID(rawValue: "lunge.reminder.brace"), "Brace your core."),
                .reminder(CoachingCueID(rawValue: "lunge.reminder.breathe"), "Breathe in on the way down.")
            ],
            motionEnvelope: MotionEnvelope(above: 0.4, below: 2.6, outward: 1.6),
            cameraView: .side,
            anyOfRequiredJoints: [
                [.leftShoulder, .leftHip, .leftKnee, .leftAnkle],
                [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
            ],
            startsByHolding: false,
            perSide: true,
            sideLimb: .leg,
            equipment: .dumbbells,
            makeAnalyzer: { epoch in RearLungeAnalyzer(epoch: epoch, configuration: configuration) },
            diagnostics: ExerciseDiagnostics(configuration, definition: definition(configuration:))
        )
    }

    private static var coachingCues: [CoachingCue] {
        let legs: Set<LandmarkType> = [
            .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
        ]
        return [
            .corrective(.lungeDeeper, "Lower a little deeper.", trigger: .perRep, priority: 50,
                        joints: legs),
            .corrective(.lungeStepLonger, "Step back a little farther.", trigger: .perRep, priority: 40,
                        joints: [.leftAnkle, .rightAnkle]),
            .corrective(.lungeStandTall, "Stand all the way up.", trigger: .perRep, priority: 30,
                        joints: legs),
            .corrective(.lungeChestUp, "Keep your chest up.", trigger: .continuous, priority: 20,
                        joints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip])
        ]
    }

    private static var guide: ExerciseGuide {
        let standingArms = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        let lunge = FigureShape(torsoPitch: 0, hipShift: 0.85, hipDrop: 0.38, stride: 0.85)
        return ExerciseGuide(
            summary: "2 sets × 8 reps each leg · Two dumbbells · Stand side-on, head to feet",
            steps: [
                GuideStep(title: "Start", detail: "Stand tall, side-on to the phone, with the dumbbells at your sides and your whole body in view."),
                GuideStep(title: "Step back", detail: "Step one foot back and lower until both knees bend and your back knee nears the floor. Keep your front foot planted and your torso upright."),
                GuideStep(title: "Stand", detail: "Push through your front foot to step back to standing. Switch legs after the set.")
            ],
            tip: "Step back with one leg. Keep the front foot planted and your torso upright.",
            walkthrough: "This is the dumbbell rear lunge. Stand tall, side-on to the phone, with the dumbbells at your sides and your whole body in view. "
                + "Step one foot back and lower until both knees bend and your back knee nears the floor. Keep your front foot planted and your torso upright. "
                + "Push through your front foot to step back to standing. Switch legs after the set.",
            startPositionInstruction: "Stand tall, dumbbells at your sides",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: standingArms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0,
                            shape: .neutral),
                ArmKeyframe(angles: standingArms, moveDuration: 1.5, holdDuration: 0.4, stepIndex: 1,
                            shape: lunge),
                ArmKeyframe(angles: standingArms, moveDuration: 1.5, holdDuration: 0, stepIndex: 2,
                            shape: .neutral)
            ], holdsDumbbells: true)
        )
    }
}
