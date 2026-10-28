import CoreGraphics
import Foundation

extension ExerciseID {
    static let wallPushUp = ExerciseID(rawValue: "wall_push_up")
}

extension CoachingCueID {
    static let wallPushUpDeeper = CoachingCueID(rawValue: "wallpush.deeper")
    static let wallPushUpBodyLine = CoachingCueID(rawValue: "wallpush.body_line")
    static let wallPushUpLockout = CoachingCueID(rawValue: "wallpush.lockout")
}

/// Prototype thresholds for a wall push-up. A shallow configuration is the push family's reduced-range floor.
struct WallPushUpConfiguration: Codable {
    var upMinElbowAngle: Double = 150
    var upMinHorizontalRatio: Double = 0.75
    var downMaxElbowAngle: Double = 115
    var downMaxHorizontalRatio: Double = 0.6
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 0.8
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var rulerWindow: TimeInterval = 1.0
    var referenceTimeout: TimeInterval = 6
    /// A reference only refreshes when the user returns close to the true straight-arm rest position.
    var referenceRefreshMinElbowAngle: Double = 160
    var referenceRefreshMinHorizontalRatio: Double = 0.9
    var bodyLineMaximumBend: Double = 20
    var shallow: Bool = false

    static let standard = WallPushUpConfiguration()

    static var reducedRange: WallPushUpConfiguration {
        var configuration = standard
        configuration.downMaxElbowAngle = 135
        configuration.downMaxHorizontalRatio = 0.72
        configuration.shallow = true
        return configuration
    }
}

enum WallPushUpExercise {
    static func definition(configuration: WallPushUpConfiguration = .standard) -> ExerciseDefinition {
        let shortName = configuration.shallow ? "Shallow Wall Push-Up" : "Wall Push-Up"
        return ExerciseDefinition(
            id: .wallPushUp,
            displayName: shortName,
            presentation: ExercisePresentation(
                shortName: shortName,
                muscles: ["Chest", "Triceps"],
                filterGroups: [.upper, .bodyweight],
                gradient: ExerciseGradient(token: .wallPushup, stops: ["#3b82c4", "#80c7e8"], angle: 135),
                symbolName: "figure.strengthtraining.functional",
                equipmentLine: "Bodyweight",
                cameraSetupLine: "Side camera beside a wall",
                watchesFor: [
                    WatchItem(cueID: .wallPushUpDeeper, text: "Elbow bend"),
                    WatchItem(cueID: .wallPushUpBodyLine, text: "Straight body line"),
                    WatchItem(cueID: .wallPushUpLockout, text: "Press back fully")
                ]
            ),
            spokenName: configuration.shallow ? "shallow wall push-up" : "wall push-up",
            sets: 2,
            targetReps: 6...10,
            autoCompleteReps: 10,
            targetRangeAnnouncementReps: 6,
            restSeconds: 45,
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
            setupLine: "Wall push-ups, two sets of 6 to 10. Stand an arm's length from a wall, side-on to the phone, and place your hands on the wall at shoulder height.",
            voiceAliases: ["wall push-up", "wall push-ups", "wall pushup", "wall pushups", "wall press"],
            guide: guide(shallow: configuration.shallow),
            coachingCues: [
                .corrective(.wallPushUpDeeper, "Bend your elbows a little more.", trigger: .perRep, priority: 50,
                            joints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist]),
                .corrective(.wallPushUpBodyLine, "Keep your body in a straight line.", trigger: .perRep, priority: 40,
                            joints: [.leftShoulder, .leftHip, .leftAnkle, .rightShoulder, .rightHip, .rightAnkle]),
                .corrective(.wallPushUpLockout, "Press all the way back.", trigger: .perRep, priority: 30,
                            joints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist])
            ],
            reminders: [
                .reminder(CoachingCueID(rawValue: "wallpush.reminder.hands"), "Hands at shoulder height."),
                .reminder(CoachingCueID(rawValue: "wallpush.reminder.breathe"), "Breathe out as you press.")
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
            makeAnalyzer: { epoch in WallPushUpAnalyzer(epoch: epoch, configuration: configuration) },
            diagnostics: ExerciseDiagnostics(configuration, definition: definition(configuration:)),
            reducedRange: configuration.shallow ? nil : { definition(configuration: .reducedRange) }
        )
    }

    private static func guide(shallow: Bool) -> ExerciseGuide {
        let start = ArmAngles(upperArmElevation: 0, forearmElevation: 0)
        // The planted hands stay at the wall. A 92° full-depth elbow and a 105° shallow elbow meet both
        // the angle and horizontal-distance checkpoints, including 15% segment-length variation.
        let down = ArmAngles(upperArmElevation: 0, forearmElevation: shallow ? -75 : -92)
        let bendCopy = shallow ? "Bend a little" : "Bend your elbows"
        let bendDetail = shallow
            ? "Bend a little to bring your chest toward the wall, keeping your body in one straight line."
            : "Bend your elbows to bring your chest toward the wall, keeping your body in one straight line."
        return ExerciseGuide(
            summary: shallow ? "2 sets × 6–10 reps · No equipment · Side camera at a wall · Shallow range"
                : "2 sets × 6–10 reps · No equipment · Side camera at a wall",
            steps: [
                GuideStep(title: "Start", detail: "Stand an arm's length from a wall, feet hip-width apart, and side-on to the phone. Place your hands on the wall at shoulder height, a little wider than your shoulders."),
                GuideStep(title: shallow ? "Bend a little" : "Bend", detail: bendDetail),
                GuideStep(title: "Press", detail: "Press back until your arms are straight. That's one rep.")
            ],
            tip: "Keep your body in one straight line from head to heels.",
            walkthrough: "This is the \(shallow ? "shallow " : "")wall push-up. Stand an arm's length from a wall with your feet hip-width apart, side-on to the phone. Place your hands on the wall at shoulder height, a little wider than your shoulders. \(bendCopy) to bring your chest toward the wall while keeping your body in one straight line. Press back until your arms are straight. That's one rep.",
            startPositionInstruction: "Hands on the wall, arms straight",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: down, moveDuration: 1.2, holdDuration: 0.3, stepIndex: 1),
                ArmKeyframe(angles: start, moveDuration: 1.2, holdDuration: 0, stepIndex: 2)
            ], holdsDumbbells: false, wallPushUp: true)
        )
    }
}
