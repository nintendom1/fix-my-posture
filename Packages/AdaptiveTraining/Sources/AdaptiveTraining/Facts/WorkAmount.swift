import Foundation

/// An amount of work that was done or seen, which may be zero (unlike `Dose`, a prescription, which is always at
/// least 1). "The user confirmed zero reps" and "nobody confirmed anything" are different facts: the first is a
/// `WorkAmount` of zero, the second is nil.
public struct WorkAmount: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let kind: DoseKind
    public let amount: Int

    public init(kind: DoseKind, amount: Int) {
        self.kind = kind
        self.amount = max(0, amount)
    }

    public init(_ dose: Dose) {
        self.init(kind: dose.kind, amount: dose.amount)
    }

    public static func reps(_ amount: Int) -> WorkAmount { WorkAmount(kind: .reps, amount: amount) }
    public static func seconds(_ amount: Int) -> WorkAmount { WorkAmount(kind: .seconds, amount: amount) }

    private enum CodingKeys: String, CodingKey {
        case kind
        case amount
    }

    /// Rejects negative amounts instead of trusting the JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let amount = try container.decode(Int.self, forKey: .amount)
        guard amount >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container,
                                                   debugDescription: "A work amount can't be negative.")
        }
        self.init(kind: try container.decode(DoseKind.self, forKey: .kind), amount: amount)
    }

    /// The same work as a dose, or nil when nothing was done.
    public var dose: Dose? { amount >= 1 ? Dose(kind: kind, amount: amount) : nil }

    public var isZero: Bool { amount == 0 }

    /// Orders amounts of the same kind; reps sort before seconds so mixed lists stay stable.
    public static func < (lhs: WorkAmount, rhs: WorkAmount) -> Bool {
        lhs.kind == rhs.kind ? lhs.amount < rhs.amount : lhs.kind == .reps
    }

    public var description: String {
        switch kind {
        case .reps: return amount == 1 ? "1 rep" : "\(amount) reps"
        case .seconds: return "\(amount) s"
        }
    }
}
