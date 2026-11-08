import Foundation

/// What a decision did to a family's prescription.
public enum DecisionKind: String, Codable, CaseIterable, Sendable {
    /// A committed calibration set the starting point.
    case start
    case hold
    case increaseDose
    case decreaseDose
    case easierVariant
    case harderVariant
    /// The next session adds an optional sample of the harder rung.
    case offerHarderSample
    /// The fact was recorded but cannot change capacity (tracking only, unrated, declined, uncommitted, ...).
    case recordOnly
    /// The family stopped (removed) or resumed being offered.
    case deactivate
}

/// Why, as stable codes. The debug view and exports show both the codes and the readable summary.
public enum ReasonCode: String, Codable, CaseIterable, Sendable {
    case calibrationCommitted
    case calibrationProbe
    case calibrationNotCommitted
    case okayHold
    case easyOnceHold
    case easyStreakIncrease
    case topOfRangeSampleOffered
    case harderSampleAccepted
    case harderSampleTooHard
    case harderSampleDeclined
    case tooHardBackToComfortable
    case tooHardReducedDose
    case tooHardEasierRung
    case tooHardAtFloor
    case stoppedEarlyHold
    case manualHarderRungUp
    case manualSameRung
    case manualOtherRungRecorded
    case trackingOnly
    case unrated
    case notAttempted
    case unconfirmedRating
    /// Rated Okay or Easy with zero confirmed work: nothing to build on.
    case nothingCompleted
    case bonusRecordedOnly
    case easierSwapRecorded
    case returnedAfterAbsence
    case staleHistoryIgnored
    case familyInactive
    case familyRemoved
    case equipmentChanged
    case rungUnavailable
}

public struct Rationale: Codable, Hashable, Sendable {
    public let codes: [ReasonCode]
    /// The facts this decision rests on, oldest first.
    public let factIDs: [UUID]
    /// One readable line, such as "Push: wall push-up × 3. Easy twice on different days: add a rep."
    public let summary: String

    public init(codes: [ReasonCode], factIDs: [UUID], summary: String) {
        self.codes = codes
        self.factIDs = factIDs
        self.summary = summary
    }
}

/// One step of the replay: what a fact did to one family.
public struct Transition: Codable, Hashable, Identifiable, Sendable {
    /// The id of the fact that caused it (evidence, calibration, or settings fact).
    public let id: UUID
    public let at: Date
    public let family: MovementFamilyID
    public let kind: DecisionKind
    public let from: RungDose?
    public let to: RungDose?
    public let confidence: RecommendationConfidence?
    public let rationale: Rationale

    public init(id: UUID, at: Date, family: MovementFamilyID, kind: DecisionKind, from: RungDose?, to: RungDose?,
                confidence: RecommendationConfidence?, rationale: Rationale) {
        self.id = id
        self.at = at
        self.family = family
        self.kind = kind
        self.from = from
        self.to = to
        self.confidence = confidence
        self.rationale = rationale
    }
}
