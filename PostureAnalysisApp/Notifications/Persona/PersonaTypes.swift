import Foundation

// Shared vocabulary for the Extra Personable layer. Foundation only: no UIKit, SwiftUI, or UserNotifications.
// These types are the contract between the detectors, the planner, the content composer, the trace store,
// and the developer debug page. Change them only in the orchestrator's contract step.

/// The kind of thing she noticed. `occasion` (holidays, anniversaries) is reserved for a later version.
enum ObservationFamily: String, Codable, CaseIterable {
    case achievement
    case pattern
    case lapse
    case posture

    /// Tie-break when two candidates share a salience: achievement wins, posture is lowest.
    var priority: Int {
        switch self {
        case .achievement: 3
        case .lapse: 2
        case .pattern: 1
        case .posture: 0
        }
    }
}

/// How much an observation deserves to interrupt. There is deliberately no numeric score.
enum PersonaSalience: String, Codable, CaseIterable, Comparable {
    case low
    case medium
    case high

    var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    /// One step lower, stopping at low.
    var lowered: PersonaSalience {
        switch self {
        case .high: .medium
        case .medium, .low: .low
        }
    }
}

/// How well she knows the user, derived from workout days since the last persona reset.
enum PersonaFamiliarity: String, Codable, CaseIterable, Comparable {
    case new
    case familiar
    case established
    case longTerm

    var rank: Int {
        switch self {
        case .new: 0
        case .familiar: 1
        case .established: 2
        case .longTerm: 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// Recent direction of workout frequency.
enum PersonaTrajectory: String, Codable, CaseIterable {
    case improving
    case stable
    case declining
    case unknown
}

/// The emotional mode of one message. Humor follows the tone (see Design/NotificationCharacter/VOICE.md).
enum PersonaTone: String, Codable, CaseIterable {
    case proud
    case pleased
    case relieved
    case annoyed
    case disappointed
    case smug
    case competitive
    case concerned
    case warm

    /// Tones that read as negative toward the user; allowed only at established familiarity or later.
    var isNegative: Bool { self == .annoyed || self == .disappointed }
}

/// How a decision reached the user.
enum PersonaDelivery: String, Codable, CaseIterable {
    /// Standalone notification with the active interruption level (HIGH).
    case active
    /// Standalone notification with the passive interruption level (MEDIUM).
    case passive
    /// Replaced the workout acknowledgment's title, body, and art. Does not count toward the daily cap.
    case foldedReplace
    /// Added one line to the workout acknowledgment's body. Does not count toward the daily cap.
    case foldedAppend
    /// LOW salience with nothing to ride on: kept for the debug page only.
    case inAppOnly
    /// Suppressed before a delivery was chosen.
    case none

    /// Only standalone notifications count toward the daily cap.
    var isStandalone: Bool { self == .active || self == .passive }
}

/// Why a candidate did not become a notification.
enum PersonaSuppressionReason: String, Codable, CaseIterable {
    /// Extra Personable, reminders, or Character style is off.
    case disabled
    /// The same observation key was already sent.
    case recentlySent
    /// Too many recent messages of the same family and kind; salience was lowered below the delivery bar.
    case similarDowngrade
    /// Repeated low engagement made her quieter for a while.
    case cooling
    /// Two standalone persona notifications already fired or are planned for that day.
    case dailyCapReached
    /// It fell in quiet hours and could not be deferred within the day.
    case quietHours
    /// LOW salience with no acknowledgment to ride on.
    case lowSalience
    /// The content file has no usable copy for this key, tone, and familiarity.
    case noContent
    /// Another candidate in the same evaluation won.
    case lowerPriorityThanSelected
}

/// Engagement-based quieting. Affects frequency only, never warmth.
enum PersonaCoolingLevel: String, Codable, CaseIterable {
    case none
    case mild
    case strong

    var rank: Int {
        switch self {
        case .none: 0
        case .mild: 1
        case .strong: 2
        }
    }
}

/// A deterministic identity for an observation: `family.kind.subject.period`, such as
/// `pattern.weekday.7.2026-W44`. It is the dedup key, the notification identifier suffix, and the
/// continuity for running jokes: while a detector keeps producing the same `family.kind`, copy may refer back.
struct PersonaObservationKey: Codable, Equatable, Hashable {
    let family: ObservationFamily
    /// Dotted kind without the family, such as `pr.weight` or `weekday`.
    let kind: String
    /// What it is about, such as an exercise ID, a weekday number, or `workouts`. Use `-` when none.
    let subject: String
    /// When it applies, such as `2026-10-24`, `2026-W44`, or a count. Use `-` when none.
    let period: String

    /// `achievement.pr.weight`: used to count recent similar messages.
    var familyKind: String { "\(family.rawValue).\(kind)" }

    /// The full key string.
    var string: String { "\(familyKind).\(subject).\(period)" }
}

/// Why a detector believes an observation, in categorical terms the debug page can show.
struct PersonaEvidence: Codable, Equatable {
    /// 1 (tentative) to 5 (overwhelming). Negative observations need at least `PersonaPolicy.negativeMinimumStrength`.
    let strength: Int
    /// Short human-readable lines, such as "4 consecutive Sundays" or "Previous best 18 lb".
    let lines: [String]

    init(strength: Int, lines: [String]) {
        self.strength = min(max(strength, 1), 5)
        self.lines = lines
    }
}

/// A gentle next step attached to some lapse observations. Never a weight or rep prescription.
enum PersonaSuggestion: Codable, Equatable {
    case routine(id: UUID, name: String)
    case exercise(id: ExerciseID, name: String)

    var name: String {
        switch self {
        case .routine(_, let name), .exercise(_, let name): name
        }
    }
}

/// One thing a detector noticed. The planner picks at most one per notification.
struct PersonaObservation: Codable, Equatable {
    let key: PersonaObservationKey
    let salience: PersonaSalience
    let evidence: PersonaEvidence
    /// The entry in persona-content.json that voices it, such as `achievement.pr.weight`.
    let contentKey: String
    /// Token values for the copy, keyed by token name (`exercise`, `value`, `count`, ...).
    let values: [String: String]
    let relatedWorkoutID: UUID?
    let relatedExerciseID: ExerciseID?
    let suggestion: PersonaSuggestion?

    init(
        key: PersonaObservationKey,
        salience: PersonaSalience,
        evidence: PersonaEvidence,
        contentKey: String,
        values: [String: String] = [:],
        relatedWorkoutID: UUID? = nil,
        relatedExerciseID: ExerciseID? = nil,
        suggestion: PersonaSuggestion? = nil
    ) {
        self.key = key
        self.salience = salience
        self.evidence = evidence
        self.contentKey = contentKey
        self.values = values
        self.relatedWorkoutID = relatedWorkoutID
        self.relatedExerciseID = relatedExerciseID
        self.suggestion = suggestion
    }

    var family: ObservationFamily { key.family }

    /// Lapse observations other than a comeback read as criticism, so they need stronger evidence
    /// (`PersonaPolicy.negativeMinimumStrength`) and never exceed medium salience.
    var isNegative: Bool { key.family == .lapse && key.kind != "comeback" }
}

/// Everything the persona may read from the app's own history. New sources (for example HealthKit facts)
/// are added as fields here so detector signatures do not change.
struct PersonaHistory: Equatable {
    var records: [WorkoutRecord]
    var assessments: [PostureAssessment]
    var routineNames: [UUID: String]
    /// Estimated minutes per routine, used to suggest the shortest one.
    var routineMinutes: [UUID: Int]
    var exerciseNames: [ExerciseID: String]

    init(
        records: [WorkoutRecord] = [],
        assessments: [PostureAssessment] = [],
        routineNames: [UUID: String] = [:],
        routineMinutes: [UUID: Int] = [:],
        exerciseNames: [ExerciseID: String] = [:]
    ) {
        self.records = records
        self.assessments = assessments
        self.routineNames = routineNames
        self.routineMinutes = routineMinutes
        self.exerciseNames = exerciseNames
    }
}

/// What prompted an evaluation.
enum PersonaTrigger: Equatable {
    /// A workout was just saved; trigger-dependent kinds (PRs, comeback, milestones) are evaluated.
    case workoutSaved(WorkoutRecord)
    /// App launch, activation, or a settings or routine change.
    case reconcile

    var savedRecord: WorkoutRecord? {
        if case .workoutSaved(let record) = self { return record }
        return nil
    }
}

/// A notification tap or dismissal. Used only to adjust frequency.
struct PersonaEngagementEvent: Codable, Equatable {
    enum Kind: String, Codable {
        case tapped
        case dismissed
    }

    let traceID: UUID
    let observationKey: String
    let kind: Kind
    let date: Date
}
