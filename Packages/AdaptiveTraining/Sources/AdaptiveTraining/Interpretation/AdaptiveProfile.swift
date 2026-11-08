import Foundation

/// Everything the engine believes, rebuilt from facts by replay. The same facts, ladders, availability, parameters,
/// and calendar always give the same profile.
public struct AdaptiveProfile: Codable, Hashable, Sendable {
    public let policyVersion: PolicyVersion
    public let catalogVersion: String
    /// Every family that has ever been started, in catalog order.
    public let states: [MovementState]
    /// Families offered today: calibrated or added and not removed, with an available floor. Catalog order.
    public let activeFamilies: [MovementFamilyID]
    public let equipment: [TrainingEquipment]
    /// Every decision, oldest first.
    public let transitions: [Transition]

    public init(policyVersion: PolicyVersion, catalogVersion: String, states: [MovementState],
                activeFamilies: [MovementFamilyID], equipment: [TrainingEquipment], transitions: [Transition]) {
        self.policyVersion = policyVersion
        self.catalogVersion = catalogVersion
        self.states = states
        self.activeFamilies = activeFamilies
        self.equipment = equipment
        self.transitions = transitions
    }

    /// No family has a committed starting point yet: Today's Session should lead to calibration.
    /// A removed family keeps its state, so it doesn't count here; the planner reports `.nothingOffered` instead.
    public var needsCalibration: Bool { states.isEmpty }

    public func state(_ family: MovementFamilyID) -> MovementState? {
        states.first { $0.family == family }
    }

    /// Confidence as of `now`: low when the family hasn't been done for `absenceDays` or more. Time away never
    /// changes the prescription itself.
    public func confidence(of family: MovementFamilyID, asOf now: Date,
                           parameters: PolicyParameters = .standard) -> RecommendationConfidence? {
        guard let state = state(family) else { return nil }
        let since = state.lastPerformedAt ?? state.lastChangedAt
        let away = now.timeIntervalSince(since) >= TimeInterval(parameters.absenceDays) * 86_400
        return away ? .low : state.confidence
    }
}
