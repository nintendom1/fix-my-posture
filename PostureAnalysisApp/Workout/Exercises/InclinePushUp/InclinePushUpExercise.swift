import CoreGraphics
import Foundation

extension ExerciseID {
    static let inclinePushUp = ExerciseID(rawValue: "incline_push_up")
}

extension CoachingCueID {
    static let inclinePushUpDeeper = CoachingCueID(rawValue: "incline.deeper")
    static let inclinePushUpBodyLine = CoachingCueID(rawValue: "incline.body_line")
    static let inclinePushUpLockout = CoachingCueID(rawValue: "incline.lockout")
}

/// A side-view push-up with the hands on a sturdy bench, table, or counter. It counts with the wall push-up's
/// analyzer and `PlantedPushUpConfiguration.incline`, which measures the straight-line shoulder-to-wrist distance.
enum InclinePushUpExercise {
    static func definition(configuration: PlantedPushUpConfiguration = .incline) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .inclinePushUp,
            displayName: "Incline Push-Up",
            presentation: ExercisePresentation(
                shortName: "Incline Push-Up",
                muscles: ["Chest", "Triceps"],
                filterGroups: [.upper, .bodyweight],
                gradient: ExerciseGradient(token: .inclinePushup, stops: ["#2f9e8f", "#7fd6c2"], angle: 135),
                symbolName: "figure.strengthtraining.functional",
                equipmentLine: "Bodyweight",
                cameraSetupLine: "Side camera beside a bench",
                watchesFor: [
                    WatchItem(cueID: .inclinePushUpDeeper, text: "Chest to the edge"),
                    WatchItem(cueID: .inclinePushUpBodyLine, text: "Hips in line"),
                    WatchItem(cueID: .inclinePushUpLockout, text: "Press to straight arms")
                ]
            ),
            spokenName: "incline push-up",
            sets: 2,
            targetReps: 6...10,
            autoCompleteReps: 10,
            targetRangeAnnouncementReps: 6,
            restSeconds: 60,
            requiredJoints: [],
            focusSegments: [
                FocusSegment(from: .leftShoulder, to: .leftElbow, style: .limb),
                FocusSegment(from: .leftElbow, to: .leftWrist, style: .limb),
                FocusSegment(from: .rightShoulder, to: .rightElbow, style: .limb),
                FocusSegment(from: .rightElbow, to: .rightWrist, style: .limb),
                FocusSegment(from: .leftShoulder, to: .leftHip, style: .reference),
                FocusSegment(from: .leftHip, to: .leftKnee, style: .reference),
                FocusSegment(from: .leftKnee, to: .leftAnkle, style: .reference),
                FocusSegment(from: .rightShoulder, to: .rightHip, style: .reference),
                FocusSegment(from: .rightHip, to: .rightKnee, style: .reference),
                FocusSegment(from: .rightKnee, to: .rightAnkle, style: .reference)
            ],
            headroomArmLengths: nil,
            countsArmsIndependently: false,
            setupLine: "Incline push-ups, two sets of 6 to 10. Put your hands on a sturdy bench, table, or counter, walk your feet back until your body is one straight line, and stand side-on to the phone.",
            voiceAliases: ["incline push-up", "incline push-ups", "incline pushup", "incline pushups",
                           "bench push-up", "bench push-ups"],
            guide: guide,
            coachingCues: [
                .corrective(.inclinePushUpDeeper, "Lower your chest a little more.", trigger: .perRep, priority: 50,
                            joints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist]),
                .corrective(.inclinePushUpBodyLine, "Keep your hips in line.", trigger: .perRep, priority: 40,
                            joints: [.leftShoulder, .leftHip, .leftAnkle, .rightShoulder, .rightHip, .rightAnkle]),
                .corrective(.inclinePushUpLockout, "Press all the way up.", trigger: .perRep, priority: 30,
                            joints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist])
            ],
            reminders: [
                .reminder(CoachingCueID(rawValue: "incline.reminder.hands"), "Hands under your shoulders."),
                .reminder(CoachingCueID(rawValue: "incline.reminder.breathe"), "Breathe out as you press.")
            ],
            motionEnvelope: MotionEnvelope(above: 0.3, below: 0.9, outward: 1.0),
            cameraView: .side,
            anyOfRequiredJoints: [
                [.leftShoulder, .leftElbow, .leftWrist, .leftHip],
                [.rightShoulder, .rightElbow, .rightWrist, .rightHip]
            ],
            startsByHolding: true,
            equipment: .bodyweight,
            plantedJoints: [.leftWrist, .rightWrist],
            makeAnalyzer: { epoch in InclinePushUpAnalyzer(epoch: epoch, configuration: configuration) },
            diagnostics: ExerciseDiagnostics(configuration, definition: definition(configuration:))
        )
    }

    private static var guide: ExerciseGuide {
        // Straight arms reach down and forward to the bench. At the bottom the upper arm points down and the
        // forearm rises to the planted hand, an 80° elbow that brings the chest to the bench's edge.
        let start = ArmAngles(upperArmElevation: -35, forearmElevation: -35)
        let down = ArmAngles(upperArmElevation: -65, forearmElevation: 35)
        return ExerciseGuide(
            summary: "2 sets × 6–10 reps · No equipment · Side camera beside a bench",
            steps: [
                GuideStep(title: "Hands", detail: "Place your hands on the edge of a sturdy bench, table, or counter, a little wider than your shoulders."),
                GuideStep(title: "Feet back", detail: "Walk your feet back until your body is one straight line from head to heels."),
                GuideStep(title: "Lower", detail: "Bend your elbows to lower your chest toward the edge."),
                GuideStep(title: "Press", detail: "Press back up until your arms are straight. That's one rep.")
            ],
            tip: "Higher surface = easier.",
            walkthrough: "This is the incline push-up. Place your hands on the edge of a sturdy bench, table, or counter, a little wider than your shoulders. Walk your feet back until your body is one straight line from head to heels, side-on to the phone. Bend your elbows to lower your chest toward the edge, then press back up until your arms are straight. That's one rep. A higher surface is easier.",
            startPositionInstruction: "Hands on the bench, arms straight",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 0.5, stepIndex: 0),
                ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 0.5, stepIndex: 1),
                ArmKeyframe(angles: down, moveDuration: 1.2, holdDuration: 0.3, stepIndex: 2),
                ArmKeyframe(angles: start, moveDuration: 1.2, holdDuration: 0, stepIndex: 3)
            ], holdsDumbbells: false, inclinePushUp: true)
        )
    }
}
