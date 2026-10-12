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
