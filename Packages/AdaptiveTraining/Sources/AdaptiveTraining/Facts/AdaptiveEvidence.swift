import Foundation

/// Where a piece of evidence came from.
public enum EvidenceSource: String, Codable, CaseIterable, Sendable {
    case calibration
    case adaptive
    case manual
    case recalibration
}

/// The user's answer to "How appropriate was what I just asked you to do?" It is about the dose, not about
/// whether the user was physically able to do it.
public enum EffortFeedback: String, Codable, CaseIterable, Sendable {
    case tooHard
    case okay
    case easy
}

/// Who vouched for `AdaptiveEvidence.confirmed`.
public enum ConfirmationSource: String, Codable, CaseIterable, Sendable {
    /// The user tapped Done, adjusted the count, or answered for themselves. Authoritative.
    case user
    /// The tracker counted it and the user rated the item without changing the count.
    case trackerAccepted
    /// Nobody confirmed anything: unrated manual work, or tracking alone. Never capacity evidence.
    case none
}

/// How the item ended.
public enum CompletionReason: String, Codable, CaseIterable, Sendable {
    /// The prescribed dose was done (a 1-rep prescription done is a complete session).
    case completed
    /// The user chose "Stop here, it counts" before the prescribed dose.
    case stoppedEarly
    /// The user took the offer of an easier version mid-item.
    case switchedToEasier
    /// The workout ended while this item was in progress.
    case endedWorkout
    /// The item was never started (skipped or the session closed first).
    case notAttempted
}

/// One optional bonus offered after an Easy rating. Declining is never negative evidence.
public struct BonusRecord: Codable, Hashable, Sendable {
    public let offered: Dose
    public let accepted: Bool
    /// What was done when accepted (zero when the user took it and did none); nil when declined or not reported.
    public let completed: WorkAmount?
    public let effort: EffortFeedback?

    public init(offered: Dose, accepted: Bool, completed: WorkAmount? = nil, effort: EffortFeedback? = nil) {
        self.offered = offered
        self.accepted = accepted
        self.completed = accepted ? completed : nil
        self.effort = accepted ? effort : nil
    }

    private enum CodingKeys: String, CodingKey {
        case offered
        case accepted
        case completed
        case effort
    }

    /// Decodes through the normalizing initializer, so a declined bonus can't carry work or a rating.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(offered: try container.decode(Dose.self, forKey: .offered),
                  accepted: try container.decode(Bool.self, forKey: .accepted),
                  completed: try container.decodeIfPresent(WorkAmount.self, forKey: .completed),
                  effort: try container.decodeIfPresent(EffortFeedback.self, forKey: .effort))
    }
}

/// A fact about what happened on one rung: what was asked, what the user confirmed, what the tracker saw, and how
/// it felt. Facts are append-only; the current interpretation is rebuilt from them, so a policy change can replay
/// history. Tracker observations are kept apart from user confirmation so a tracking failure can never be read as
/// a physical failure.
public struct AdaptiveEvidence: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let source: EvidenceSource
    public let family: MovementFamilyID
    public let variant: VariantID

    public let prescriptionID: UUID?
    public let prescriptionItemID: UUID?
    public let workoutID: UUID?
    public let calibrationID: UUID?

    /// What the app asked for; nil for manual work, which had a routine target instead.
    public let prescribed: Dose?
    /// What the user (or an accepted tracker count) says was done, which may be zero; nil when nobody confirmed
    /// anything.
    public let confirmed: WorkAmount?
    public let confirmation: ConfirmationSource
    /// Each set's confirmed amount for multi-set manual work; `[confirmed]` for a single adaptive item; empty when
    /// nothing was confirmed.
    public let setAmounts: [WorkAmount]

    public let tracker: TrackerObservation
    public let effort: EffortFeedback?
    /// The user said or tapped "Too hard?" during the item, whatever they chose next.
    public let midSetTooHard: Bool
    public let bonus: BonusRecord?
    public let completion: CompletionReason
    /// Context only, such as "15 lb"; V1 never reads it.
    public let weightNote: String?

    /// Normalizes confirmation: no confirmation source means no confirmed amount and no confirmed sets, and no
    /// confirmed amount means no confirmation source.
    public init(
        id: UUID, recordedAt: Date, source: EvidenceSource, family: MovementFamilyID, variant: VariantID,
        prescriptionID: UUID? = nil, prescriptionItemID: UUID? = nil, workoutID: UUID? = nil,
        calibrationID: UUID? = nil, prescribed: Dose? = nil, confirmed: WorkAmount?, confirmation: ConfirmationSource,
        setAmounts: [WorkAmount]? = nil, tracker: TrackerObservation, effort: EffortFeedback?,
        midSetTooHard: Bool = false, bonus: BonusRecord? = nil, completion: CompletionReason, weightNote: String? = nil
    ) {
        let normalizedConfirmed = confirmation == .none ? nil : confirmed
        self.id = id
        self.recordedAt = recordedAt
        self.source = source
        self.family = family
        self.variant = variant
        self.prescriptionID = prescriptionID
        self.prescriptionItemID = prescriptionItemID
        self.workoutID = workoutID
        self.calibrationID = calibrationID
        self.prescribed = prescribed
        self.confirmed = normalizedConfirmed
        self.confirmation = normalizedConfirmed == nil ? .none : confirmation
        self.setAmounts = normalizedConfirmed == nil ? [] : (setAmounts ?? [normalizedConfirmed].compactMap { $0 })
        self.tracker = tracker
        self.effort = effort
        self.midSetTooHard = midSetTooHard
        self.bonus = bonus
        self.completion = completion
        self.weightNote = weightNote
    }

    private enum CodingKeys: String, CodingKey {
        case id, recordedAt, source, family, variant, prescriptionID, prescriptionItemID, workoutID, calibrationID
        case prescribed, confirmed, confirmation, setAmounts, tracker, effort, midSetTooHard, bonus, completion
        case weightNote
    }

    /// Decodes through the normalizing initializer, so stored JSON can't hold a contradictory confirmation.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  recordedAt: try c.decode(Date.self, forKey: .recordedAt),
                  source: try c.decode(EvidenceSource.self, forKey: .source),
                  family: try c.decode(MovementFamilyID.self, forKey: .family),
                  variant: try c.decode(VariantID.self, forKey: .variant),
                  prescriptionID: try c.decodeIfPresent(UUID.self, forKey: .prescriptionID),
                  prescriptionItemID: try c.decodeIfPresent(UUID.self, forKey: .prescriptionItemID),
                  workoutID: try c.decodeIfPresent(UUID.self, forKey: .workoutID),
                  calibrationID: try c.decodeIfPresent(UUID.self, forKey: .calibrationID),
                  prescribed: try c.decodeIfPresent(Dose.self, forKey: .prescribed),
                  confirmed: try c.decodeIfPresent(WorkAmount.self, forKey: .confirmed),
                  confirmation: try c.decode(ConfirmationSource.self, forKey: .confirmation),
                  setAmounts: try c.decode([WorkAmount].self, forKey: .setAmounts),
                  tracker: try c.decode(TrackerObservation.self, forKey: .tracker),
                  effort: try c.decodeIfPresent(EffortFeedback.self, forKey: .effort),
                  midSetTooHard: try c.decode(Bool.self, forKey: .midSetTooHard),
                  bonus: try c.decodeIfPresent(BonusRecord.self, forKey: .bonus),
                  completion: try c.decode(CompletionReason.self, forKey: .completion),
                  weightNote: try c.decodeIfPresent(String.self, forKey: .weightNote))
    }
}
