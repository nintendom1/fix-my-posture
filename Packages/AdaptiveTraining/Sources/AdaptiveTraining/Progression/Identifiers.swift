import Foundation

/// A movement family's stable key, such as `push`. Persisted in evidence and exports; never rename one.
public struct MovementFamilyID: RawRepresentable, Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
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

    public static let push = MovementFamilyID(rawValue: "push")
    public static let squat = MovementFamilyID(rawValue: "squat")
    public static let row = MovementFamilyID(rawValue: "row")
    public static let overhead = MovementFamilyID(rawValue: "overhead")
    public static let hinge = MovementFamilyID(rawValue: "hinge")
    public static let glute = MovementFamilyID(rawValue: "glute")
    public static let lunge = MovementFamilyID(rawValue: "lunge")
    public static let neck = MovementFamilyID(rawValue: "neck")
    public static let core = MovementFamilyID(rawValue: "core")
}

/// One rung of a ladder: an exercise plus its prescription modifiers, such as `push.wall_push_up.shallow`.
/// Persisted in evidence and exports; never rename one.
public struct VariantID: RawRepresentable, Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
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
}
