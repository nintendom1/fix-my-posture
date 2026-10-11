import CoreGraphics
import Foundation

extension ExerciseID {
    static let shoulderPress = ExerciseID(rawValue: "shoulder_press")
}

/// Prototype thresholds for a standing dumbbell shoulder press filmed from the front.
/// These are heuristics to tune on device, not biomechanical standards.
///
/// - Height ratio `h` is the wrist's height above its shoulder divided by torso length
///   (shoulder midpoint to hip midpoint), measured in image pixels.
/// - The elbow angle is the 2D interior angle, so front-view foreshortening makes it approximate.
///   It is paired with `h` so that neither signal alone decides an end position.
/// - Raise `bottomMaxHeightRatio` if a user's start position (hands near ear height) never registers.
struct ShoulderPressConfiguration {
    /// Bottom: hands near shoulder height with elbows bent.
    var bottomMaxHeightRatio: Double = 0.25
    var bottomMaxElbowAngle: Double = 115
    /// Top: hands well above the head with arms nearly straight.
    var topMinHeightRatio: Double = 0.55
    var topMinElbowAngle: Double = 140
    /// Consecutive 10 Hz samples needed to confirm an end position.
    var confirmationSamples = 2
    /// Faster bottom-to-bottom cycles are treated as noise.
    var minimumRepDuration: TimeInterval = 0.8
    /// A longer gap between complete samples requires a fresh bottom. This tolerates one dropped
    /// sample at the 100–133 ms capture cadence; two dropped samples invalidate the rep.
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4

    static let standard = ShoulderPressConfiguration()
}

enum ShoulderPressExercise {
    static func definition(configuration: ShoulderPressConfiguration = .standard) -> ExerciseDefinition {
        ExerciseDefinition(
            id: .shoulderPress,
            displayName: "Shoulder Press",
            spokenName: "shoulder press",
            sets: 2,
            targetReps: 8...10,
            autoCompleteReps: 10,
            targetRangeAnnouncementReps: 8,
            restSeconds: 90,
            requiredJoints: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                             .leftWrist, .rightWrist, .leftHip, .rightHip],
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
            setupLine: "Shoulder press, two sets of 8 to 10. Face the phone with the dumbbells at your shoulders.",
            makeAnalyzer: { epoch in ShoulderPressAnalyzer(epoch: epoch, configuration: configuration) }
        )
    }
}
