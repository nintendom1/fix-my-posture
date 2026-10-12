import CoreGraphics
import Foundation

/// Stable exercise key, separate from user-facing names (for example `shoulder_press`).
/// Each exercise declares its own constant in an `ExerciseID` extension.
struct ExerciseID: RawRepresentable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A line the overlay draws between two joints.
struct FocusSegment: Hashable {
    enum Style: Hashable {
        /// The moving shoulder-elbow-wrist chain.
        case limb
        /// Thin torso lines that give the limbs context.
        case reference
    }

    let from: LandmarkType
    let to: LandmarkType
    let style: Style
}

/// Where the user faces relative to the phone.
enum ExerciseCameraView: Equatable {
    /// Facing the phone; both arms visible.
    case front
    /// Side-on to the phone; the arm nearer the phone is tracked.
    case side
    /// The phone lies on the floor facing the head, as for push-ups: hands planted near the bottom of the
    /// frame, shoulders rising and falling above them.
    case floor
}

/// Everything the coach needs to run one exercise. Register new exercises in `ExerciseCatalog.all`.
struct ExerciseDefinition: Identifiable {
    let id: ExerciseID
    /// Title case, for the HUD.
    let displayName: String
    /// Lower case, for spoken sentences.
    let spokenName: String
    let sets: Int
    let targetReps: ClosedRange<Int>
    /// The set completes automatically at this count.
    let autoCompleteReps: Int
    /// Announced once when reached, before auto-completion.
    let targetRangeAnnouncementReps: Int?
    let restSeconds: Int
    /// Joints that must be visible for reliable tracking.
    let requiredJoints: Set<LandmarkType>
    /// Segments the overlay draws; their endpoints are the only joints shown.
    let focusSegments: [FocusSegment]
    /// Overhead room needed above the shoulders, in arm lengths; nil skips the check.
    let headroomArmLengths: CGFloat?
    /// Each arm counts separately; displayed reps are the reps both arms completed.
    let countsArmsIndependently: Bool
    /// Spoken when the exercise is selected.
    let setupLine: String
    /// Lowercase names a user might say to select this exercise. They feed the voice parser and the
    /// recognizer's contextual hints.
    let voiceAliases: [String]
    let guide: ExerciseGuide
    /// Corrective cues, spoken and shown as tips. The analyzer raises them by `CoachingCueID`.
    let coachingCues: [CoachingCue]
    /// Visual-only reminders, one at set start and then between corrections.
    let reminders: [CoachingCue]
    /// Where the limbs travel during a rep; tips stay out of it.
    let motionEnvelope: MotionEnvelope
    var cameraView: ExerciseCameraView = .front
    /// When not empty, tracking also needs one of these sets fully visible, such as either arm from the side.
    var anyOfRequiredJoints: [Set<LandmarkType>] = []
    /// Holding the start position for a moment begins a set. Off when the start position is just standing,
    /// so a set never starts by accident; "start" and the Start button always work.
    var startsByHolding = true
    /// Each set is done one arm at a time: left, then right, then rest. Each arm's half is recorded as its
    /// own entry in the set history.
    var perSide = false
    /// False when the phone deliberately leans back, as on the floor for push-ups.
    var warnsAboutTilt = true

    /// Recorded entries that make up the full exercise.
    var setEntries: Int { perSide ? sets * 2 : sets }

    /// "Set 2" or, one arm at a time, "Set 2 L".
    func setLabel(entry index: Int) -> String {
        perSide ? "Set \(index / 2 + 1) \(index % 2 == 0 ? "L" : "R")" : "Set \(index + 1)"
    }
    let makeAnalyzer: (_ epoch: Int) -> ExerciseAnalyzing

    var focusJoints: Set<LandmarkType> {
        Set(focusSegments.flatMap { [$0.from, $0.to] })
    }

    var targetLabel: String {
        targetReps.lowerBound == targetReps.upperBound
            ? "\(targetReps.upperBound)"
            : "\(targetReps.lowerBound)–\(targetReps.upperBound)"
    }

    var spokenTarget: String {
        targetReps.lowerBound == targetReps.upperBound
            ? "\(targetReps.upperBound)"
            : "\(targetReps.lowerBound) to \(targetReps.upperBound)"
    }
}
