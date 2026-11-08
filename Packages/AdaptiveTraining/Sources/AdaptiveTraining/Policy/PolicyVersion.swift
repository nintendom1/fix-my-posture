import Foundation

/// Names the recommendation rules that produced an interpretation. Stored on every prescription and cached profile,
/// so a policy change replays history instead of trusting decisions made under older rules.
public struct PolicyVersion: RawRepresentable, Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }

    public static let v1 = PolicyVersion(rawValue: "adaptive-policy-1")
}
