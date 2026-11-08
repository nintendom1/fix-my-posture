import Foundation

public enum MemoryScope: String, Codable, Equatable, Sendable {
    /// Durable player/meta-history. It is separate from workout and adaptive-training records.
    case player
    /// Future loop-local companion memory; a later weekly reset may clear these flags.
    case loop
}

public enum NarrativeComparisonOperator: String, Codable, Equatable, Sendable {
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual

    public func evaluate(_ lhs: Int, _ rhs: Int) -> Bool {
        switch self {
        case .equal: lhs == rhs
        case .notEqual: lhs != rhs
        case .lessThan: lhs < rhs
        case .lessThanOrEqual: lhs <= rhs
        case .greaterThan: lhs > rhs
        case .greaterThanOrEqual: lhs >= rhs
        }
    }
}

public struct NarrativeFactComparison: Codable, Equatable, Sendable {
    public let fact: FactID
    public let comparison: NarrativeComparisonOperator
    public let value: Int

    public init(fact: FactID, comparison: NarrativeComparisonOperator, value: Int) {
        self.fact = fact
        self.comparison = comparison
        self.value = value
    }
}

/// Conditions read host-supplied facts. Scripts can inspect fitness facts but cannot write them.
public indirect enum NarrativeCondition: Equatable, Sendable {
    case flagIsSet(FlagID)
    case flagIsUnset(FlagID)
    case flagEquals(FlagID, Bool)
    case fact(NarrativeFactComparison)
    case all([NarrativeCondition])
    case any([NarrativeCondition])
    case not(NarrativeCondition)
}

extension NarrativeCondition: Codable {
    private enum CodingKeys: String, CodingKey { case type, flag, value, comparison, fact, conditions, condition }

    private enum Kind: String, Codable { case flagIsSet, flagIsUnset, flagEquals, fact, all, any, not }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .flagIsSet:
            self = .flagIsSet(try container.decode(FlagID.self, forKey: .flag))
        case .flagIsUnset:
            self = .flagIsUnset(try container.decode(FlagID.self, forKey: .flag))
        case .flagEquals:
            self = .flagEquals(try container.decode(FlagID.self, forKey: .flag), try container.decode(Bool.self, forKey: .value))
        case .fact:
            self = .fact(NarrativeFactComparison(
                fact: try container.decode(FactID.self, forKey: .fact),
                comparison: try container.decode(NarrativeComparisonOperator.self, forKey: .comparison),
                value: try container.decode(Int.self, forKey: .value)
            ))
        case .all:
            self = .all(try container.decode([NarrativeCondition].self, forKey: .conditions))
        case .any:
            self = .any(try container.decode([NarrativeCondition].self, forKey: .conditions))
        case .not:
            self = .not(try container.decode(NarrativeCondition.self, forKey: .condition))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .flagIsSet(flag):
            try container.encode(Kind.flagIsSet, forKey: .type)
            try container.encode(flag, forKey: .flag)
        case let .flagIsUnset(flag):
            try container.encode(Kind.flagIsUnset, forKey: .type)
            try container.encode(flag, forKey: .flag)
        case let .flagEquals(flag, value):
            try container.encode(Kind.flagEquals, forKey: .type)
            try container.encode(flag, forKey: .flag)
            try container.encode(value, forKey: .value)
        case let .fact(fact):
            try container.encode(Kind.fact, forKey: .type)
            try container.encode(fact.fact, forKey: .fact)
            try container.encode(fact.comparison, forKey: .comparison)
            try container.encode(fact.value, forKey: .value)
        case let .all(conditions):
            try container.encode(Kind.all, forKey: .type)
            try container.encode(conditions, forKey: .conditions)
        case let .any(conditions):
            try container.encode(Kind.any, forKey: .type)
            try container.encode(conditions, forKey: .conditions)
        case let .not(condition):
            try container.encode(Kind.not, forKey: .type)
            try container.encode(condition, forKey: .condition)
        }
    }
}

/// Immutable host facts. Missing and unknown values both evaluate false; `knownFactIDs` lets the
/// validator distinguish an unknown name from a known fact whose value is currently unavailable.
public struct NarrativeFacts: Codable, Equatable, Sendable {
    public let values: [FactID: Int]
    public let knownFactIDs: Set<FactID>

    public init(values: [FactID: Int], knownFactIDs: Set<FactID>? = nil) {
        self.values = values
        self.knownFactIDs = knownFactIDs ?? Set(values.keys)
    }

    public static let empty = NarrativeFacts(values: [:])
    public static let standardFactIDs: Set<FactID> = [FactID(rawValue: "workouts_this_week")]

    public func value(for id: FactID) -> Int? { values[id] }
}
