import Foundation

/// Stable cue key, separate from the wording (for example `press.full_extension`).
/// Each exercise declares its own constants in a `CoachingCueID` extension.
struct CoachingCueID: RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// One short coaching line. Corrective cues are spoken and shown as a tip; reminders are only shown.
/// Cues describe movement geometry relative to the user's own set, never injury or diagnosis.
struct CoachingCue: Equatable, Identifiable {
    enum Kind: Equatable {
        case corrective
        case reminder
    }

    enum Trigger: Equatable {
        /// Judged once per rep attempt; must show up in 2 of the last 3 attempts.
        case perRep
        /// Judged every frame; must hold for a moment before it counts.
        case continuous
    }

    let id: CoachingCueID
    let text: String
    let kind: Kind
    let trigger: Trigger
    /// A higher-priority cue replaces a lower one on screen.
    let priority: Int
    /// Joints drawn amber while the tip shows.
    let joints: Set<LandmarkType>

    static func corrective(_ id: CoachingCueID, _ text: String, trigger: Trigger, priority: Int,
                           joints: Set<LandmarkType>) -> CoachingCue {
        CoachingCue(id: id, text: text, kind: .corrective, trigger: trigger, priority: priority, joints: joints)
    }

    static func reminder(_ id: CoachingCueID, _ text: String) -> CoachingCue {
        CoachingCue(id: id, text: text, kind: .reminder, trigger: .continuous, priority: 0, joints: [])
    }
}

/// One rep attempt as judged for form. Attempts that didn't count are included, so the coach can say why.
struct RepForm: Equatable {
    let timestamp: TimeInterval
    /// Per-rep cues this attempt raised.
    let flags: Set<CoachingCueID>
}

/// Form output from one analyzer frame. The session drops observations whose epoch is stale.
struct FormObservation: Equatable {
    let epoch: Int
    var repForms: [RepForm] = []
    /// Continuous cues whose condition holds on this frame.
    var signals: Set<CoachingCueID> = []
}

/// A labeled value for the Show Measurements "Last rep" line, for tuning cue thresholds on device.
struct FormReading: Equatable {
    let label: String
    let value: String
}

/// A cue on screen. The id changes with every new tip, even when the same cue repeats.
struct CoachingTip: Equatable, Identifiable {
    let id: Int
    let cue: CoachingCue
}
