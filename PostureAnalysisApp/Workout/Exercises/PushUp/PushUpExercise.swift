import CoreGraphics
import Foundation

extension ExerciseID {
    static let pushUp = ExerciseID(rawValue: "push_up")
}

extension CoachingCueID {
    static let pushUpLower = CoachingCueID(rawValue: "pushup.lower")
    static let pushUpFullExtension = CoachingCueID(rawValue: "pushup.full_extension")
    static let pushUpControlledLowering = CoachingCueID(rawValue: "pushup.controlled_lowering")
}

/// Prototype thresholds for push-ups filmed by a phone on the floor facing the head. Heuristics to tune
/// on device.
///
/// - Signal `h` is how far the shoulders sit above the planted hands, in arm lengths (upper arm + forearm),
///   averaged over both arms. The arms stand roughly upright in the image, so the longest recent arm length
///   (locked at the top) is a full ruler at any distance. Arms straight reads about 1; at the bottom the
///   shoulders sink toward the hands.
/// - The 2D elbow angle pairs with `h`, so leaning without bending the arms isn't counted.
struct PushUpConfiguration: Codable {
    /// Up (the start): arms nearly straight, shoulders well above the hands.
    var upMinRatio: Double = 0.8
    var upMinElbowAngle: Double = 150
    /// Down (the counted end): shoulders low, elbows bent.
    var downMaxRatio: Double = 0.5
    var downMaxElbowAngle: Double = 110
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 0.8
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var rulerWindow = 10
    var wristSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 6

    // Form coaching. The guide's own demonstration raises none of these.

    var attemptMinimumDrop: Double = 0.2
    /// "Push all the way up": after the bottom, rose this far and went down again without straightening.
    var returnRise: Double = 0.2
    /// "Lower with control": the shoulders took less than this from the Up line to the Down line. The demo's
    /// 1.5 s lowering reads 0.43 s; 0.2 s is a lowering faster than about 0.7 s.
    var minimumDescentTime: TimeInterval = 0.2

    static let standard = PushUpConfiguration()
}

enum PushUpExercise {
    static func definition(configuration: PushUpConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .pushUp,
            displayName: "Push-Up",
            presentation: ExercisePresentation(
                shortName: "Push-Up",
                muscles: ["Chest", "Triceps"],
                filterGroups: [.upper, .bodyweight],
                gradient: ExerciseGradient(token: .pushup, stops: ["#22c38e", "#7be0b4"], angle: 135),
                symbolName: "figure.strengthtraining.traditional",
                equipmentLine: "Bodyweight",
                cameraSetupLine: "Phone on the floor, facing you",
                watchesFor: [
                    WatchItem(cueID: .pushUpLower, text: "Lowering far enough"),
                    WatchItem(cueID: .pushUpFullExtension, text: "Pressing to straight arms")
                ]
            ),
            spokenName: "push-up",
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
                FocusSegment(from: .leftShoulder, to: .rightShoulder, style: .reference)
            ],
            headroomArmLengths: nil,
            // Recordings lost the whole body before the bottom of every rep at 34% or more, and kept it at 30%
            // or less: with the phone near the face, Vision stops seeing a body.
            maximumShoulderSpan: 0.32,
            countsArmsIndependently: false,
            setupLine: "Push-ups, two sets of 10. Lay the phone on the floor a long step in front of your hands, tilted up to see you, and get into a plank facing it.",
            voiceAliases: ["push ups", "pushups", "push up", "press ups"],
            guide: guide,
            coachingCues: [
                .corrective(.pushUpLower, "Go a little lower.", trigger: .perRep, priority: 50,
                            joints: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow]),
                .corrective(.pushUpFullExtension, "Push all the way up.", trigger: .perRep, priority: 40,
                            joints: [.leftElbow, .rightElbow, .leftWrist, .rightWrist]),
                .corrective(.pushUpControlledLowering, "Lower with control.", trigger: .perRep, priority: 30,
                            joints: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow])
            ],
            reminders: [
                .reminder(CoachingCueID(rawValue: "pushup.reminder.brace"), "Brace your core."),
                .reminder(CoachingCueID(rawValue: "pushup.reminder.hands"), "Hands under your shoulders."),
                .reminder(CoachingCueID(rawValue: "pushup.reminder.breathe"), "Breathe out as you push.")
            ],
            // Around the shoulders: the head above, the hands below, and the elbows flaring out.
            motionEnvelope: MotionEnvelope(above: 0.5, below: 1.1, outward: 0.6),
            cameraView: .floor,
            warnsAboutTilt: false,
            equipment: .bodyweight,
            plantedJoints: [.leftWrist, .rightWrist],
            makeAnalyzer: { epoch in PushUpAnalyzer(epoch: epoch, configuration: configuration) },
            diagnostics: ExerciseDiagnostics(configuration, definition: definition(configuration:))
        )
    }

    private static var guide: ExerciseGuide {
        // Seen from the floor: arms straight under the shoulders, then elbows bend out and the shoulders sink.
        let up = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        let down = ArmAngles(upperArmElevation: -25, forearmElevation: -155)
        return ExerciseGuide(
            summary: "2 sets × 10 reps · No equipment · Phone on the floor",
            steps: [
                GuideStep(title: "Start", detail: "Lay the phone on the floor a long step in front of your hands, tilted up to see you. Get into a plank facing it, hands under your shoulders and arms straight."),
                GuideStep(title: "Lower", detail: "Bend your elbows to lower your chest toward the floor, keeping your body in a straight line."),
                GuideStep(title: "Push", detail: "Push back up until your arms are straight. That's one rep.")
            ],
            tip: "Prop the phone against something so it leans back a little; the tilt warning stays off for push-ups.",
            walkthrough: "This is the push-up. Lay the phone on the floor a long step in front of your hands, tilted up to see you. "
                + "Get into a plank facing the phone, with your hands under your shoulders and your arms straight. "
                + "Bend your elbows to lower your chest toward the floor, keeping your body in a straight line. "
                + "Then push back up until your arms are straight. That's one rep.",
            startPositionInstruction: "Hold a plank with straight arms",
            motion: ArmMotion(keyframes: [
                ArmKeyframe(angles: up, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
                ArmKeyframe(angles: down, moveDuration: 1.5, holdDuration: 0.3, stepIndex: 1),
                ArmKeyframe(angles: up, moveDuration: 1.0, holdDuration: 0, stepIndex: 2)
            ], holdsDumbbells: false)
        )
    }
}
