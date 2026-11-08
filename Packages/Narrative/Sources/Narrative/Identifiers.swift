import Foundation

/// A stable string identifier used by authored narrative data.
public protocol NarrativeIdentifier: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible
where RawValue == String {
    init(rawValue: String)
}

public extension NarrativeIdentifier {
    /// Identifiers use lowercase ASCII letters, digits, periods, underscores, and hyphens.
    var isValid: Bool { Self.isValid(rawValue) }

    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 95 || byte == 45 || byte == 46
        }
    }

    var description: String { rawValue }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ScriptID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct SceneID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct NodeID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct CharacterID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ExpressionID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ChoiceID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct FlagID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct AudioRef: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct AssetRef: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct CheckpointID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct FactID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct CueID: NarrativeIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
