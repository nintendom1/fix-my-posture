import Foundation

/// How sure the engine is that a family's current prescription fits. Time away lowers it; it never changes the
/// prescription by itself.
public enum RecommendationConfidence: String, Codable, CaseIterable, Comparable, Sendable {
    case low
    case medium
    case high

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    var raised: Self { self == .low ? .medium : .high }
    var lowered: Self { self == .high ? .medium : .low }
}

/// The last dose on a rung that the user rated Okay or Easy.
public struct ComfortableDose: Codable, Hashable, Sendable {
    public let variant: VariantID
    public let dose: Dose
    public let ratedAt: Date

    public init(variant: VariantID, dose: Dose, ratedAt: Date) {
        self.variant = variant
        self.dose = dose
        self.ratedAt = ratedAt
    }
}

/// The engine's current interpretation of one movement family, rebuilt from facts by replay. Never edited directly.
public struct MovementState: Codable, Hashable, Sendable {
    public let family: MovementFamilyID
    /// What the next session prescribes for this family.
    public var current: RungDose
    public var confidence: RecommendationConfidence
    public var lastPerformedAt: Date?
    public var lastChangedAt: Date
    /// One entry per rung, sorted by variant id.
    public var comfortableDoses: [ComfortableDose]
    /// Consecutive Easy ratings at `current`, on different days.
    public var easyStreak: Int
    public var lastEasyAt: Date?
    /// The next session adds an optional one-rep sample of the next harder rung.
    public var harderSampleDue: Bool
    /// No harder sample is offered before this time (set after a sample rated Too Hard).
    public var harderSampleBlockedUntil: Date?

    public init(family: MovementFamilyID, current: RungDose, confidence: RecommendationConfidence,
                lastPerformedAt: Date? = nil, lastChangedAt: Date, comfortableDoses: [ComfortableDose] = [],
                easyStreak: Int = 0, lastEasyAt: Date? = nil, harderSampleDue: Bool = false,
                harderSampleBlockedUntil: Date? = nil) {
        self.family = family
        self.current = current
        self.confidence = confidence
        self.lastPerformedAt = lastPerformedAt
        self.lastChangedAt = lastChangedAt
        self.comfortableDoses = comfortableDoses.sorted { $0.variant < $1.variant }
        self.easyStreak = easyStreak
        self.lastEasyAt = lastEasyAt
        self.harderSampleDue = harderSampleDue
        self.harderSampleBlockedUntil = harderSampleBlockedUntil
    }

    public func comfortableDose(on variant: VariantID) -> ComfortableDose? {
        comfortableDoses.first { $0.variant == variant }
    }
}
