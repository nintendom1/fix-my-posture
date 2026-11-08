import Foundation

/// How a rung is measured: repetitions or seconds held.
public enum DoseKind: String, Codable, CaseIterable, Sendable {
    case reps
    case seconds
}

/// An amount of one rung's work, such as 3 reps or 20 seconds. Amounts are always at least 1.
public struct Dose: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let kind: DoseKind
    public let amount: Int

    public init(kind: DoseKind, amount: Int) {
        self.kind = kind
        self.amount = max(1, amount)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case amount
    }

    /// Rejects amounts below 1 instead of trusting the JSON, so a decoded export can't hold a zero dose.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let amount = try container.decode(Int.self, forKey: .amount)
        guard amount >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container,
                                                   debugDescription: "A dose amount must be at least 1.")
        }
        self.init(kind: try container.decode(DoseKind.self, forKey: .kind), amount: amount)
    }

    public static func reps(_ amount: Int) -> Dose { Dose(kind: .reps, amount: amount) }
    public static func seconds(_ amount: Int) -> Dose { Dose(kind: .seconds, amount: amount) }

    /// Orders doses of the same kind by amount; reps sort before seconds so mixed lists stay stable.
    public static func < (lhs: Dose, rhs: Dose) -> Bool {
        lhs.kind == rhs.kind ? lhs.amount < rhs.amount : lhs.kind == .reps
    }

    /// "3 reps", "1 rep", or "20 s".
    public var description: String {
        switch kind {
        case .reps: return amount == 1 ? "1 rep" : "\(amount) reps"
        case .seconds: return "\(amount) s"
        }
    }
}

/// The doses a rung may prescribe: `lower...upper` in steps of `step` (1 rep, or 5 seconds for holds).
public struct DoseRange: Hashable, Codable, Sendable {
    public let kind: DoseKind
    public let lower: Int
    public let upper: Int
    public let step: Int

    public init(kind: DoseKind, lower: Int, upper: Int, step: Int? = nil) {
        precondition(lower >= 1 && upper >= lower, "A dose range needs 1 <= lower <= upper.")
        self.kind = kind
        self.lower = lower
        self.upper = upper
        self.step = max(1, step ?? (kind == .seconds ? 5 : 1))
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case lower
        case upper
        case step
    }

    /// Rejects `lower < 1`, `upper < lower`, and `step < 1` with a decoding error rather than the initializer's trap.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lower = try container.decode(Int.self, forKey: .lower)
        let upper = try container.decode(Int.self, forKey: .upper)
        let step = try container.decode(Int.self, forKey: .step)
        guard lower >= 1, upper >= lower, step >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .step, in: container,
                                                   debugDescription: "A dose range needs 1 <= lower <= upper and step >= 1.")
        }
        self.init(kind: try container.decode(DoseKind.self, forKey: .kind), lower: lower, upper: upper, step: step)
    }

    public static func reps(_ range: ClosedRange<Int>) -> DoseRange {
        DoseRange(kind: .reps, lower: range.lowerBound, upper: range.upperBound)
    }

    public static func seconds(_ range: ClosedRange<Int>, step: Int = 5) -> DoseRange {
        DoseRange(kind: .seconds, lower: range.lowerBound, upper: range.upperBound, step: step)
    }

    public var minimum: Dose { Dose(kind: kind, amount: lower) }
    public var maximum: Dose { Dose(kind: kind, amount: upper) }

    public func contains(_ dose: Dose) -> Bool {
        dose.kind == kind && (lower...upper).contains(dose.amount)
    }

    /// The nearest dose in range. A dose of the other kind clamps to the minimum.
    public func clamped(_ dose: Dose) -> Dose {
        guard dose.kind == kind else { return minimum }
        return Dose(kind: kind, amount: min(upper, max(lower, dose.amount)))
    }

    /// One step up, or nil at the top of the range.
    public func increased(_ dose: Dose) -> Dose? {
        let current = clamped(dose)
        guard current.amount < upper else { return nil }
        let remaining = upper - current.amount
        return Dose(kind: kind, amount: step >= remaining ? upper : current.amount + step)
    }
}
