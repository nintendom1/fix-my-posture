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
enum ExerciseCameraView: String, Equatable {
    /// Facing the phone; both arms visible.
    case front
    /// Side-on to the phone; the arm nearer the phone is tracked.
    case side
    /// The phone lies on the floor facing the head, as for push-ups: hands planted near the bottom of the
    /// frame, shoulders rising and falling above them.
    case floor
    /// The phone stands upright at floor height, side-on to a person lying on their back.
    case lyingSide
}

/// The limb whose work is tracked one side at a time.
enum ExerciseSideLimb: String, Equatable {
    case arm
    case leg
}

/// Everything the coach needs to run one exercise. Register new exercises in `ExerciseCatalog.all`.
struct ExerciseDefinition: Identifiable {
    let id: ExerciseID
    /// Title case, for the HUD.
    let displayName: String
    /// Display metadata used by the redesigned exercise library and detail views.
    let presentation: ExercisePresentation
    /// Lower case, for spoken sentences.
    let spokenName: String
    var sets: Int
    var targetReps: ClosedRange<Int>
    /// The set completes automatically at this count.
    var autoCompleteReps: Int
    /// Announced once when reached, before auto-completion.
    var targetRangeAnnouncementReps: Int?
    let restSeconds: Int
    /// Joints that must be visible for reliable tracking.
    let requiredJoints: Set<LandmarkType>
    /// Segments the overlay draws; their endpoints are the only joints shown.
    let focusSegments: [FocusSegment]
    /// Overhead room needed above the shoulders, in arm lengths; nil skips the check.
    let headroomArmLengths: CGFloat?
    /// Horizontal room needed at each shoulder, in arm lengths; nil skips the check.
    var sideroomArmLengths: CGFloat? = nil
    /// Widest the shoulders may span in setup, as a fraction of image width; wider asks for the phone farther away.
    var maximumShoulderSpan: CGFloat? = nil
    /// Whether setup guidance asks the user to center their body in the frame.
    var centersInFrame: Bool = true
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
    /// Each set is done one limb at a time: left, then right, then rest. Each side's half is recorded as its
    /// own entry in the set history.
    var perSide = false
    /// Which limb the left/right set labels refer to when `perSide` is enabled.
    var sideLimb: ExerciseSideLimb = .arm
    /// False when the phone deliberately leans back, as on the floor for push-ups.
    var warnsAboutTilt = true
    /// Decides what kind of weight can be recorded for a set.
    var equipment: ExerciseEquipment = .dumbbells
    /// Joints resting on the floor during a rep, such as push-up hands. One that drops out at the frame edge
    /// is held where it was last seen instead of carried with its limb.
    var plantedJoints: Set<LandmarkType> = []
    /// Camera-counted, or self-reported when the camera can't follow the movement.
    var tracking: ExerciseTracking = .camera
    /// Reps, or seconds for a timed hold (then `targetReps` and `autoCompleteReps` are seconds).
    var doseUnit: ExerciseDoseUnit = .reps
    /// A same-exercise variant with a smaller range, when the adaptive ladder prescribes one.
    let reducedRange: (() -> ExerciseDefinition)?

    private let cameraAnalyzer: (_ epoch: Int) -> ExerciseAnalyzing

    /// The analyzer for this definition. Self-reported definitions use a no-op analyzer even when made by
    /// adapting a camera-tracked catalog definition.
    var makeAnalyzer: (_ epoch: Int) -> ExerciseAnalyzing {
        let usesCamera = tracking == .camera
        let cameraAnalyzer = self.cameraAnalyzer
        return { epoch in
            usesCamera ? cameraAnalyzer(epoch) : SelfReportedAnalyzer(epoch: epoch)
        }
    }

    init(
        id: ExerciseID,
        displayName: String,
        presentation: ExercisePresentation,
        spokenName: String,
        sets: Int,
        targetReps: ClosedRange<Int>,
        autoCompleteReps: Int,
        targetRangeAnnouncementReps: Int?,
        restSeconds: Int,
        requiredJoints: Set<LandmarkType>,
        focusSegments: [FocusSegment],
        headroomArmLengths: CGFloat?,
        sideroomArmLengths: CGFloat? = nil,
        maximumShoulderSpan: CGFloat? = nil,
        centersInFrame: Bool = true,
        countsArmsIndependently: Bool,
        setupLine: String,
        voiceAliases: [String],
        guide: ExerciseGuide,
        coachingCues: [CoachingCue],
        reminders: [CoachingCue],
        motionEnvelope: MotionEnvelope,
        cameraView: ExerciseCameraView = .front,
        anyOfRequiredJoints: [Set<LandmarkType>] = [],
        startsByHolding: Bool = true,
        perSide: Bool = false,
        sideLimb: ExerciseSideLimb = .arm,
        warnsAboutTilt: Bool = true,
        equipment: ExerciseEquipment = .dumbbells,
        plantedJoints: Set<LandmarkType> = [],
        tracking: ExerciseTracking = .camera,
        doseUnit: ExerciseDoseUnit = .reps,
        makeAnalyzer: @escaping (_ epoch: Int) -> ExerciseAnalyzing,
        diagnostics: ExerciseDiagnostics? = nil,
        reducedRange: (() -> ExerciseDefinition)? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.presentation = presentation
        self.spokenName = spokenName
        self.sets = sets
        self.targetReps = targetReps
        self.autoCompleteReps = autoCompleteReps
        self.targetRangeAnnouncementReps = targetRangeAnnouncementReps
        self.restSeconds = restSeconds
        self.requiredJoints = requiredJoints
        self.focusSegments = focusSegments
        self.headroomArmLengths = headroomArmLengths
        self.sideroomArmLengths = sideroomArmLengths
        self.maximumShoulderSpan = maximumShoulderSpan
        self.centersInFrame = centersInFrame
        self.countsArmsIndependently = countsArmsIndependently
        self.setupLine = setupLine
        self.voiceAliases = voiceAliases
        self.guide = guide
        self.coachingCues = coachingCues
        self.reminders = reminders
        self.motionEnvelope = motionEnvelope
        self.cameraView = cameraView
        self.anyOfRequiredJoints = anyOfRequiredJoints
        self.startsByHolding = startsByHolding
        self.perSide = perSide
        self.sideLimb = sideLimb
        self.warnsAboutTilt = warnsAboutTilt
        self.equipment = equipment
        self.plantedJoints = plantedJoints
        self.tracking = tracking
        self.doseUnit = doseUnit
        self.reducedRange = reducedRange
        cameraAnalyzer = makeAnalyzer
        self.diagnostics = diagnostics
    }

    /// Recorded entries that make up the full exercise.
    var setEntries: Int { perSide ? sets * 2 : sets }

    /// Target suffixes used by Library, Train, routine, and reminder rows.
    var perSideTargetSuffix: String {
        guard perSide else { return "" }
        return sideLimb == .leg ? " each leg" : " / side"
    }

    /// Human-readable side label for the HUD and spoken set prompts.
    func sideLabel(_ side: BodySide) -> String {
        "\(side == .left ? "Left" : "Right") \(sideLimb.rawValue)"
    }

    /// "Set 2" or, one side at a time, "Set 2 L".
    func setLabel(entry index: Int) -> String {
        perSide ? "Set \(index / 2 + 1) \(index % 2 == 0 ? "L" : "R")" : "Set \(index + 1)"
    }
    /// The analyzer's tuning for session recordings, and a way to rebuild this exercise from a recorded tuning.
    var diagnostics: ExerciseDiagnostics? = nil

    var focusJoints: Set<LandmarkType> {
        Set(focusSegments.flatMap { [$0.from, $0.to] })
    }

    var targetLabel: String {
        targetReps.lowerBound == targetReps.upperBound
            ? "\(targetReps.upperBound)"
            : "\(targetReps.lowerBound)–\(targetReps.upperBound)"
    }

    /// "10 reps" or, for a timed hold, "20 s".
    var targetAmountLabel: String {
        doseUnit == .seconds ? "\(targetLabel) s" : "\(targetLabel) reps"
    }

    /// "10" for reps; "20 seconds" for a timed hold, since a bare number would read as reps.
    var spokenTarget: String {
        let range = targetReps.lowerBound == targetReps.upperBound
            ? "\(targetReps.upperBound)"
            : "\(targetReps.lowerBound) to \(targetReps.upperBound)"
        return doseUnit == .seconds ? "\(range) seconds" : range
    }

    /// A set's amount as spoken or shown: "1 rep", "3 reps", or "20 seconds".
    func amountPhrase(_ amount: Int) -> String {
        if doseUnit == .seconds { return amount == 1 ? "1 second" : "\(amount) seconds" }
        return amount == 1 ? "1 rep" : "\(amount) reps"
    }

    var isSelfReported: Bool { tracking == .selfReported }
}
