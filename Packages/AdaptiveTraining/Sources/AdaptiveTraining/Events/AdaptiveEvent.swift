import Foundation

/// Semantic adaptive-training events for persona and notification copy. They flow one way: copy can react to an
/// event, but nothing a reaction says or does can change the engine's state.
public enum AdaptiveEventKind: String, Codable, CaseIterable, Sendable {
    case tinySessionPrescribed
    case sessionCompleted
    case effortTooHard
    case effortOkay
    case effortEasy
    case bonusOffered
    case bonusAccepted
    case bonusDeclined
    case progressed
    case regressed
    case calibrationCompleted
    case recalibrationCompleted
    case returnedAfterAbsence
}

public struct AdaptiveEvent: Codable, Hashable, Sendable {
    public let kind: AdaptiveEventKind
    public let family: MovementFamilyID?
    public let at: Date
    /// The fact that produced it.
    public let factID: UUID
    public let from: RungDose?
    public let to: RungDose?

    public init(kind: AdaptiveEventKind, family: MovementFamilyID?, at: Date, factID: UUID, from: RungDose? = nil,
                to: RungDose? = nil) {
        self.kind = kind
        self.family = family
        self.at = at
        self.factID = factID
        self.from = from
        self.to = to
    }
}
