import Foundation

/// Temporary context for one day. It may shrink today's session; it never changes the profile.
public struct SessionContext: Codable, Hashable, Sendable {
    /// "I only have a minute": the floor of the current rung's dose range, with no harder sample.
    public var tiny: Bool

    public init(tiny: Bool = false) {
        self.tiny = tiny
    }

    public static let normal = SessionContext()
}

/// Today's prescription: one family, one main item, and maybe an optional harder sample.
public struct TodaySession: Codable, Hashable, Sendable {
    public let family: MovementFamilyID
    public let main: RungDose
    /// An optional one-rep sample of the next harder rung; declining it is neutral.
    public let harderSample: RungDose?
    /// Whether an Easy rating on the main item may offer a bonus.
    public let offersBonus: Bool
    /// The session is a single rep or the shortest hold: render it as complete-able, never as "too small".
    public let isTiny: Bool
    public let confidence: RecommendationConfidence
    /// Rough seconds including setup, for the card.
    public let estimatedSeconds: Int
    /// One readable line of provenance, such as "Based on where you left off: Easy last time."
    public let rationale: String
    /// The transition the prescription rests on; nil for a fresh calibration start.
    public let basedOnTransitionID: UUID?

    public init(family: MovementFamilyID, main: RungDose, harderSample: RungDose?, offersBonus: Bool, isTiny: Bool,
                confidence: RecommendationConfidence, estimatedSeconds: Int, rationale: String,
                basedOnTransitionID: UUID?) {
        self.family = family
        self.main = main
        self.harderSample = harderSample
        self.offersBonus = offersBonus
        self.isTiny = isTiny
        self.confidence = confidence
        self.estimatedSeconds = estimatedSeconds
        self.rationale = rationale
        self.basedOnTransitionID = basedOnTransitionID
    }
}

/// What the Train hero should show.
public enum TodaySessionStatus: Codable, Hashable, Sendable {
    /// Nothing calibrated yet: route to calibration instead of inventing a workout.
    case needsCalibration
    /// Calibrated families exist but none can be offered on this device (for example their floors aren't built).
    case nothingOffered
    case ready(TodaySession)
    /// Today's main item is already done; `next` is what the rotation offers next time.
    case completedToday(family: MovementFamilyID, next: TodaySession?)
}
