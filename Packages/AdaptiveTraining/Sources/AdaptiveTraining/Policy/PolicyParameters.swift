import Foundation

/// Every V1 threshold in one place, like `PersonaPolicy`. Codable so `adaptive-replay` can try a candidate set
/// against an export before a new policy version ships.
public struct PolicyParameters: Codable, Hashable, Sendable {
    /// Easy ratings in a row, on different days, at the same rung and dose, before the dose goes up.
    public var easyStreakToIncrease: Int
    /// Too Hard with no lower comfortable dose cuts the dose by this fraction (at least one step).
    public var tooHardReduction: Double
    /// Facts older than this, relative to the fact being decided, don't count toward a streak or a comfortable dose.
    public var recencyWindowDays: Int
    /// At least this long since the family was last done means low confidence and a hold until one fresh rating.
    public var absenceDays: Int
    /// After a harder sample rated Too Hard, no sample for this long.
    public var harderSampleCooldownDays: Int

    public init(easyStreakToIncrease: Int, tooHardReduction: Double, recencyWindowDays: Int, absenceDays: Int,
                harderSampleCooldownDays: Int) {
        self.easyStreakToIncrease = easyStreakToIncrease
        self.tooHardReduction = tooHardReduction
        self.recencyWindowDays = recencyWindowDays
        self.absenceDays = absenceDays
        self.harderSampleCooldownDays = harderSampleCooldownDays
    }

    public static let standard = PolicyParameters(easyStreakToIncrease: 2, tooHardReduction: 0.25,
                                                  recencyWindowDays: 28, absenceDays: 14,
                                                  harderSampleCooldownDays: 7)
}
