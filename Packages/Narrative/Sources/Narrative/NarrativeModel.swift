import Foundation

public struct NarrativeFlag: Codable, Equatable, Sendable {
    public let id: FlagID
    public let scope: MemoryScope

    public init(id: FlagID, scope: MemoryScope) {
        self.id = id
        self.scope = scope
    }
}

public struct NarrativeExpressionAsset: Codable, Equatable, Sendable {
    public let expression: ExpressionID
    public let asset: AssetRef

    public init(expression: ExpressionID, asset: AssetRef) {
        self.expression = expression
        self.asset = asset
    }
}

public struct NarrativeCharacter: Codable, Equatable, Sendable {
    public let id: CharacterID
    public let allowedExpressions: [ExpressionID]
    public let defaultExpression: ExpressionID
    public let portrait: AssetRef?
    public let expressionAssets: [NarrativeExpressionAsset]

    public init(
        id: CharacterID,
        allowedExpressions: [ExpressionID],
        defaultExpression: ExpressionID,
        portrait: AssetRef? = nil,
        expressionAssets: [NarrativeExpressionAsset] = []
    ) {
        self.id = id
        self.allowedExpressions = allowedExpressions
        self.defaultExpression = defaultExpression
        self.portrait = portrait
        self.expressionAssets = expressionAssets
    }

    public func asset(for expression: ExpressionID) -> AssetRef? {
        expressionAssets.first(where: { $0.expression == expression })?.asset
    }
}

public struct NarrativeTarget: Codable, Equatable, Sendable {
    public let scene: SceneID
    public let node: NodeID

    public init(scene: SceneID, node: NodeID) {
        self.scene = scene
        self.node = node
    }
}

public struct NarrativeChoiceOption: Codable, Equatable, Sendable {
    public let id: ChoiceID
    public let text: String
    public let condition: NarrativeCondition?
    public let target: NodeID?

    public init(id: ChoiceID, text: String, condition: NarrativeCondition? = nil, target: NodeID?) {
        self.id = id
        self.text = text
        self.condition = condition
        self.target = target
    }
}

public struct NarrativeVisibleOption: Codable, Equatable, Sendable {
    public let id: ChoiceID
    public let text: String

    public init(id: ChoiceID, text: String) {
        self.id = id
        self.text = text
    }
}

public indirect enum NarrativeNode: Equatable, Sendable {
    case line(id: NodeID, speaker: CharacterID, expression: ExpressionID, text: String, audio: AudioRef?)
    case choice(id: NodeID, prompt: String, options: [NarrativeChoiceOption])
    case branch(id: NodeID, condition: NarrativeCondition, thenTarget: NodeID?, elseTarget: NodeID?)
    case setFlag(id: NodeID, flag: FlagID, value: Bool)
    case checkpoint(id: NodeID, checkpointID: CheckpointID)
    case jump(id: NodeID, target: NarrativeTarget?)
    case end(id: NodeID)

    public var id: NodeID {
        switch self {
        case let .line(id, _, _, _, _), let .choice(id, _, _), let .branch(id, _, _, _),
             let .setFlag(id, _, _), let .checkpoint(id, _), let .jump(id, _), let .end(id): id
        }
    }
}

extension NarrativeNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, speaker, expression, text, audio, prompt, options, condition, thenTarget,
             elseTarget, flag, value, checkpointID, target
    }

    private enum Kind: String, Codable { case line, choice, branch, setFlag, checkpoint, jump, end }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(NodeID.self, forKey: .id)
        switch try container.decode(Kind.self, forKey: .type) {
        case .line:
            self = .line(
                id: id,
                speaker: try container.decode(CharacterID.self, forKey: .speaker),
                expression: try container.decode(ExpressionID.self, forKey: .expression),
                text: try container.decode(String.self, forKey: .text),
                audio: try container.decodeIfPresent(AudioRef.self, forKey: .audio)
            )
        case .choice:
            self = .choice(id: id, prompt: try container.decode(String.self, forKey: .prompt), options: try container.decode([NarrativeChoiceOption].self, forKey: .options))
        case .branch:
            self = .branch(
                id: id,
                condition: try container.decode(NarrativeCondition.self, forKey: .condition),
                thenTarget: try container.decodeIfPresent(NodeID.self, forKey: .thenTarget),
                elseTarget: try container.decodeIfPresent(NodeID.self, forKey: .elseTarget)
            )
        case .setFlag:
            self = .setFlag(id: id, flag: try container.decode(FlagID.self, forKey: .flag), value: try container.decode(Bool.self, forKey: .value))
        case .checkpoint:
            self = .checkpoint(id: id, checkpointID: try container.decode(CheckpointID.self, forKey: .checkpointID))
        case .jump:
            self = .jump(id: id, target: try container.decodeIfPresent(NarrativeTarget.self, forKey: .target))
        case .end:
            self = .end(id: id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch self {
        case let .line(_, speaker, expression, text, audio):
            try container.encode(Kind.line, forKey: .type)
            try container.encode(speaker, forKey: .speaker)
            try container.encode(expression, forKey: .expression)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(audio, forKey: .audio)
        case let .choice(_, prompt, options):
            try container.encode(Kind.choice, forKey: .type)
            try container.encode(prompt, forKey: .prompt)
            try container.encode(options, forKey: .options)
        case let .branch(_, condition, thenTarget, elseTarget):
            try container.encode(Kind.branch, forKey: .type)
            try container.encode(condition, forKey: .condition)
            try container.encodeIfPresent(thenTarget, forKey: .thenTarget)
            try container.encodeIfPresent(elseTarget, forKey: .elseTarget)
        case let .setFlag(_, flag, value):
            try container.encode(Kind.setFlag, forKey: .type)
            try container.encode(flag, forKey: .flag)
            try container.encode(value, forKey: .value)
        case let .checkpoint(_, checkpointID):
            try container.encode(Kind.checkpoint, forKey: .type)
            try container.encode(checkpointID, forKey: .checkpointID)
        case let .jump(_, target):
            try container.encode(Kind.jump, forKey: .type)
            try container.encodeIfPresent(target, forKey: .target)
        case .end:
            try container.encode(Kind.end, forKey: .type)
        }
    }
}

public struct NarrativeScene: Codable, Equatable, Sendable {
    public let id: SceneID
    public let entryNode: NodeID
    public let nodes: [NarrativeNode]

    public init(id: SceneID, entryNode: NodeID, nodes: [NarrativeNode]) {
        self.id = id
        self.entryNode = entryNode
        self.nodes = nodes
    }
}

public struct NarrativeScript: Codable, Equatable, Sendable {
    public static let supportedVersion = 1

    public let version: Int
    public let id: ScriptID
    public let characters: [NarrativeCharacter]
    public let flags: [NarrativeFlag]
    public let scenes: [NarrativeScene]

    public init(version: Int = NarrativeScript.supportedVersion, id: ScriptID, characters: [NarrativeCharacter], flags: [NarrativeFlag] = [], scenes: [NarrativeScene]) {
        self.version = version
        self.id = id
        self.characters = characters
        self.flags = flags
        self.scenes = scenes
    }
}

public struct NarrativeAssetManifest: Codable, Equatable, Sendable {
    public let portraitsAndExpressions: Set<AssetRef>
    public let audio: Set<AudioRef>

    public init(portraitsAndExpressions: Set<AssetRef>, audio: Set<AudioRef>) {
        self.portraitsAndExpressions = portraitsAndExpressions
        self.audio = audio
    }

    public func contains(_ asset: AssetRef) -> Bool { portraitsAndExpressions.contains(asset) }
    public func contains(_ ref: AudioRef) -> Bool { audio.contains(ref) }
}

public enum CompanionPresentationKind: String, Codable, Equatable, Sendable { case sceneLine, callout }

public enum NarrativeDismissal: Equatable, Sendable {
    case tap
    case auto(seconds: Double)
}

extension NarrativeDismissal: Codable {
    private enum CodingKeys: String, CodingKey { case type, seconds }
    private enum Kind: String, Codable { case tap, auto }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .tap: self = .tap
        case .auto: self = .auto(seconds: try container.decode(Double.self, forKey: .seconds))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tap: try container.encode(Kind.tap, forKey: .type)
        case let .auto(seconds):
            try container.encode(Kind.auto, forKey: .type)
            try container.encode(seconds, forKey: .seconds)
        }
    }
}

public struct CompanionPresentation: Codable, Equatable, Sendable {
    public let character: CharacterID
    public let expression: ExpressionID
    public let expressionAsset: AssetRef?
    public let text: String?
    public let audio: AudioRef?
    public let kind: CompanionPresentationKind
    public let blocking: Bool
    public let dismissal: NarrativeDismissal
    public let cueID: CueID?

    public init(character: CharacterID, expression: ExpressionID, expressionAsset: AssetRef? = nil, text: String?, audio: AudioRef? = nil, kind: CompanionPresentationKind, blocking: Bool, dismissal: NarrativeDismissal, cueID: CueID? = nil) {
        self.character = character
        self.expression = expression
        self.expressionAsset = expressionAsset
        self.text = text
        self.audio = audio
        self.kind = kind
        self.blocking = blocking
        self.dismissal = dismissal
        self.cueID = cueID
    }
}

public enum CompanionCallout {
    /// Builds a non-blocking future coaching presentation. It has no app or playback dependencies.
    public static func make(character: CharacterID, expression: ExpressionID, cueID: CueID, text: String, dismissal: NarrativeDismissal = .auto(seconds: 4)) -> CompanionPresentation {
        CompanionPresentation(character: character, expression: expression, text: text, kind: .callout, blocking: false, dismissal: dismissal, cueID: cueID)
    }
}
