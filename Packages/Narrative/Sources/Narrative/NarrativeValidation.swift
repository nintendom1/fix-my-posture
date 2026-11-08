import Foundation

public enum NarrativeIssueCode: String, Codable, Equatable, Sendable {
    case decoding
    case unsupportedVersion
    case invalidIDSyntax
    case duplicateID
    case unknownSpeaker
    case disallowedExpression
    case missingScene
    case missingNode
    case missingBranchTarget
    case choiceHasNoOptions
    case duplicateOptionID
    case optionMissingTarget
    case undeclaredFlag
    case unknownFact
    case unreachableNode
    case missingPortraitAsset
    case missingExpressionAsset
    case missingAudioAsset
    case blockingCallout
    case invalidDismissal
    case invalidChoice
    case invalidState
    case stepLimitExceeded
    case invalidCheckpoint
}

public enum NarrativeIssueSeverity: String, Codable, Equatable, Sendable { case error, warning }

public struct NarrativeIssue: Codable, Equatable, Sendable {
    public let code: NarrativeIssueCode
    public let path: String
    public let message: String
    public let severity: NarrativeIssueSeverity

    public init(code: NarrativeIssueCode, path: String, message: String, severity: NarrativeIssueSeverity = .error) {
        self.code = code
        self.path = path
        self.message = message
        self.severity = severity
    }
}

/// A script token created only after validation finds no errors. Warnings remain available on the result.
public struct NarrativeValidatedScript: Equatable, Sendable {
    public let script: NarrativeScript
    fileprivate init(script: NarrativeScript) { self.script = script }
}

public struct NarrativeValidationResult: Equatable, Sendable {
    public let validatedScript: NarrativeValidatedScript?
    public let issues: [NarrativeIssue]

    public var isValid: Bool { validatedScript != nil }
    public var errors: [NarrativeIssue] { issues.filter { $0.severity == .error } }
}

public struct NarrativeLoadResult: Equatable, Sendable {
    public let validatedScript: NarrativeValidatedScript?
    public let issues: [NarrativeIssue]

    public var isValid: Bool { validatedScript != nil }
}

public enum NarrativeScriptLoader {
    /// Decodes a JSON script, then returns every validation issue. Unknown host facts and missing manifest
    /// assets are warnings so the runtime can safely evaluate or fall back when they are encountered.
    public static func load(
        _ data: Data,
        assetManifest: NarrativeAssetManifest? = nil,
        knownFactIDs: Set<FactID> = NarrativeFacts.standardFactIDs
    ) -> NarrativeLoadResult {
        do {
            let script = try JSONDecoder().decode(NarrativeScript.self, from: data)
            let validation = NarrativeScriptValidator.validate(script, assetManifest: assetManifest, knownFactIDs: knownFactIDs)
            return NarrativeLoadResult(validatedScript: validation.validatedScript, issues: validation.issues)
        } catch {
            return NarrativeLoadResult(
                validatedScript: nil,
                issues: [NarrativeIssue(code: .decoding, path: "$", message: "The script JSON could not be decoded.")]
            )
        }
    }
}

public enum NarrativeScriptValidator {
    private struct Cursor: Hashable { let scene: SceneID; let node: NodeID }

    public static func validate(
        _ script: NarrativeScript,
        assetManifest: NarrativeAssetManifest? = nil,
        knownFactIDs: Set<FactID> = NarrativeFacts.standardFactIDs
    ) -> NarrativeValidationResult {
        var issues: [NarrativeIssue] = []
        var characterIDs = Set<CharacterID>()
        var flagIDs = Set<FlagID>()
        var sceneIDs = Set<SceneID>()
        var globalNodeIDs = Set<NodeID>()
        var checkpointIDs = Set<CheckpointID>()
        var charactersByID: [CharacterID: NarrativeCharacter] = [:]
        var scenesByID: [SceneID: NarrativeScene] = [:]
        var nodesByScene: [SceneID: [NodeID: NarrativeNode]] = [:]

        if script.version != NarrativeScript.supportedVersion {
            issues.append(NarrativeIssue(code: .unsupportedVersion, path: "version", message: "Version \(script.version) is not supported."))
        }
        checkID(script.id, path: "id", into: &issues)

        for (index, character) in script.characters.enumerated() {
            let path = "characters[\(index)]"
            checkID(character.id, path: "\(path).id", into: &issues)
            if !characterIDs.insert(character.id).inserted {
                issues.append(NarrativeIssue(code: .duplicateID, path: "\(path).id", message: "Character id is duplicated."))
            } else {
                charactersByID[character.id] = character
            }
            var expressions = Set<ExpressionID>()
            for (expressionIndex, expression) in character.allowedExpressions.enumerated() {
                let expressionPath = "\(path).allowedExpressions[\(expressionIndex)]"
                checkID(expression, path: expressionPath, into: &issues)
                if !expressions.insert(expression).inserted {
                    issues.append(NarrativeIssue(code: .duplicateID, path: expressionPath, message: "Allowed expression id is duplicated."))
                }
            }
            checkID(character.defaultExpression, path: "\(path).defaultExpression", into: &issues)
            if !expressions.contains(character.defaultExpression) {
                issues.append(NarrativeIssue(code: .disallowedExpression, path: "\(path).defaultExpression", message: "Default expression is not allowed for this character."))
            }
            if let portrait = character.portrait {
                checkID(portrait, path: "\(path).portrait", into: &issues)
                if let assetManifest, !assetManifest.contains(portrait) {
                    issues.append(NarrativeIssue(code: .missingPortraitAsset, path: "\(path).portrait", message: "Portrait asset is missing from the manifest.", severity: .warning))
                }
            }
            var mappedExpressions = Set<ExpressionID>()
            for (assetIndex, entry) in character.expressionAssets.enumerated() {
                let assetPath = "\(path).expressionAssets[\(assetIndex)]"
                checkID(entry.expression, path: "\(assetPath).expression", into: &issues)
                checkID(entry.asset, path: "\(assetPath).asset", into: &issues)
                if !mappedExpressions.insert(entry.expression).inserted {
                    issues.append(NarrativeIssue(code: .duplicateID, path: "\(assetPath).expression", message: "Expression asset mapping is duplicated."))
                }
                if !expressions.contains(entry.expression) {
                    issues.append(NarrativeIssue(code: .disallowedExpression, path: "\(assetPath).expression", message: "Expression asset is declared for an expression not allowed by this character."))
                }
                if let assetManifest, !assetManifest.contains(entry.asset) {
                    issues.append(NarrativeIssue(code: .missingExpressionAsset, path: "\(assetPath).asset", message: "Expression asset is missing from the manifest.", severity: .warning))
                }
            }
        }

        for (index, flag) in script.flags.enumerated() {
            let path = "flags[\(index)].id"
            checkID(flag.id, path: path, into: &issues)
            if !flagIDs.insert(flag.id).inserted {
                issues.append(NarrativeIssue(code: .duplicateID, path: path, message: "Flag id is duplicated."))
            }
        }

        for (sceneIndex, scene) in script.scenes.enumerated() {
            let scenePath = "scenes[\(sceneIndex)]"
            checkID(scene.id, path: "\(scenePath).id", into: &issues)
            if !sceneIDs.insert(scene.id).inserted {
                issues.append(NarrativeIssue(code: .duplicateID, path: "\(scenePath).id", message: "Scene id is duplicated."))
            } else {
                scenesByID[scene.id] = scene
            }
            checkID(scene.entryNode, path: "\(scenePath).entryNode", into: &issues)
            var sceneNodes = [NodeID: NarrativeNode]()
            for (nodeIndex, node) in scene.nodes.enumerated() {
                let nodePath = "\(scenePath).nodes[\(nodeIndex)]"
                checkID(node.id, path: "\(nodePath).id", into: &issues)
                if !globalNodeIDs.insert(node.id).inserted {
                    issues.append(NarrativeIssue(code: .duplicateID, path: "\(nodePath).id", message: "Node id is duplicated in this script."))
                }
                if sceneNodes[node.id] == nil { sceneNodes[node.id] = node }
                switch node {
                case let .line(_, speaker, expression, _, audio):
                    checkID(speaker, path: "\(nodePath).speaker", into: &issues)
                    checkID(expression, path: "\(nodePath).expression", into: &issues)
                    if let character = charactersByID[speaker] {
                        if !character.allowedExpressions.contains(expression) {
                            issues.append(NarrativeIssue(code: .disallowedExpression, path: "\(nodePath).expression", message: "Expression is not allowed for this speaker."))
                        }
                    } else {
                        issues.append(NarrativeIssue(code: .unknownSpeaker, path: "\(nodePath).speaker", message: "Speaker is not declared."))
                    }
                    if let audio {
                        checkID(audio, path: "\(nodePath).audio", into: &issues)
                        if let assetManifest, !assetManifest.contains(audio) {
                            issues.append(NarrativeIssue(code: .missingAudioAsset, path: "\(nodePath).audio", message: "Audio asset is missing from the manifest.", severity: .warning))
                        }
                    }
                case let .choice(_, _, options):
                    if options.isEmpty {
                        issues.append(NarrativeIssue(code: .choiceHasNoOptions, path: "\(nodePath).options", message: "A choice must have at least one option."))
                    }
                    var optionIDs = Set<ChoiceID>()
                    for (optionIndex, option) in options.enumerated() {
                        let optionPath = "\(nodePath).options[\(optionIndex)]"
                        checkID(option.id, path: "\(optionPath).id", into: &issues)
                        if !optionIDs.insert(option.id).inserted {
                            issues.append(NarrativeIssue(code: .duplicateOptionID, path: "\(optionPath).id", message: "Choice option id is duplicated."))
                        }
                        if let condition = option.condition {
                            validate(condition, path: "\(optionPath).condition", declaredFlags: flagIDs, knownFacts: knownFactIDs, issues: &issues)
                        }
                        if let target = option.target {
                            checkID(target, path: "\(optionPath).target", into: &issues)
                        } else {
                            issues.append(NarrativeIssue(code: .optionMissingTarget, path: "\(optionPath).target", message: "Choice option has no target."))
                        }
                    }
                case let .branch(_, condition, thenTarget, elseTarget):
                    validate(condition, path: "\(nodePath).condition", declaredFlags: flagIDs, knownFacts: knownFactIDs, issues: &issues)
                    if let thenTarget { checkID(thenTarget, path: "\(nodePath).thenTarget", into: &issues) }
                    else { issues.append(NarrativeIssue(code: .missingBranchTarget, path: "\(nodePath).thenTarget", message: "Branch has no then target.")) }
                    if let elseTarget { checkID(elseTarget, path: "\(nodePath).elseTarget", into: &issues) }
                    else { issues.append(NarrativeIssue(code: .missingBranchTarget, path: "\(nodePath).elseTarget", message: "Branch has no else target.")) }
                case let .setFlag(_, flag, _):
                    checkID(flag, path: "\(nodePath).flag", into: &issues)
                    if !flagIDs.contains(flag) {
                        issues.append(NarrativeIssue(code: .undeclaredFlag, path: "\(nodePath).flag", message: "Flag is not declared."))
                    }
                case let .checkpoint(_, checkpointID):
                    checkID(checkpointID, path: "\(nodePath).checkpointID", into: &issues)
                    if !checkpointIDs.insert(checkpointID).inserted {
                        issues.append(NarrativeIssue(code: .duplicateID, path: "\(nodePath).checkpointID", message: "Checkpoint id is duplicated."))
                    }
                case let .jump(_, target):
                    if let target {
                        checkID(target.scene, path: "\(nodePath).target.scene", into: &issues)
                        checkID(target.node, path: "\(nodePath).target.node", into: &issues)
                    }
                case .end:
                    break
                }
            }
            nodesByScene[scene.id] = sceneNodes
            if sceneNodes[scene.entryNode] == nil {
                issues.append(NarrativeIssue(code: .missingNode, path: "\(scenePath).entryNode", message: "Scene entry node does not exist."))
            }
        }

        validateTargets(script.scenes, scenesByID: scenesByID, nodesByScene: nodesByScene, issues: &issues)
        validateReachability(script.scenes, nodesByScene: nodesByScene, issues: &issues)

        let validatedScript: NarrativeValidatedScript? = issues.contains(where: { $0.severity == .error }) ? nil : NarrativeValidatedScript(script: script)
        return NarrativeValidationResult(validatedScript: validatedScript, issues: issues)
    }

    /// Validates the shared presentation contract used by scene lines and future callouts.
    public static func validate(presentation: CompanionPresentation, path: String = "presentation") -> [NarrativeIssue] {
        var issues: [NarrativeIssue] = []
        checkID(presentation.character, path: "\(path).character", into: &issues)
        checkID(presentation.expression, path: "\(path).expression", into: &issues)
        if let asset = presentation.expressionAsset { checkID(asset, path: "\(path).expressionAsset", into: &issues) }
        if let audio = presentation.audio { checkID(audio, path: "\(path).audio", into: &issues) }
        if let cueID = presentation.cueID { checkID(cueID, path: "\(path).cueID", into: &issues) }
        if presentation.kind == .callout && presentation.blocking {
            issues.append(NarrativeIssue(code: .blockingCallout, path: "\(path).blocking", message: "Callouts must be non-blocking."))
        }
        if case let .auto(seconds) = presentation.dismissal, !seconds.isFinite || seconds <= 0 {
            issues.append(NarrativeIssue(code: .invalidDismissal, path: "\(path).dismissal.seconds", message: "Automatic dismissal must use a finite duration greater than zero."))
        }
        return issues
    }

    private static func validate(
        _ condition: NarrativeCondition,
        path: String,
        declaredFlags: Set<FlagID>,
        knownFacts: Set<FactID>,
        issues: inout [NarrativeIssue]
    ) {
        switch condition {
        case let .flagIsSet(flag), let .flagIsUnset(flag), let .flagEquals(flag, _):
            checkID(flag, path: "\(path).flag", into: &issues)
            if !declaredFlags.contains(flag) {
                issues.append(NarrativeIssue(code: .undeclaredFlag, path: "\(path).flag", message: "Flag is not declared."))
            }
        case let .fact(comparison):
            checkID(comparison.fact, path: "\(path).fact", into: &issues)
            if !knownFacts.contains(comparison.fact) {
                issues.append(NarrativeIssue(code: .unknownFact, path: "\(path).fact", message: "Fact is not known to the host.", severity: .warning))
            }
        case let .all(conditions), let .any(conditions):
            for (index, nested) in conditions.enumerated() {
                validate(nested, path: "\(path).conditions[\(index)]", declaredFlags: declaredFlags, knownFacts: knownFacts, issues: &issues)
            }
        case let .not(nested):
            validate(nested, path: "\(path).condition", declaredFlags: declaredFlags, knownFacts: knownFacts, issues: &issues)
        }
    }

    private static func validateTargets(
        _ scenes: [NarrativeScene],
        scenesByID: [SceneID: NarrativeScene],
        nodesByScene: [SceneID: [NodeID: NarrativeNode]],
        issues: inout [NarrativeIssue]
    ) {
        for (sceneIndex, scene) in scenes.enumerated() {
            let scenePath = "scenes[\(sceneIndex)]"
            for (nodeIndex, node) in scene.nodes.enumerated() {
                let path = "\(scenePath).nodes[\(nodeIndex)]"
                switch node {
                case let .choice(_, _, options):
                    for (optionIndex, option) in options.enumerated() {
                        if let target = option.target, nodesByScene[scene.id]?[target] == nil {
                            issues.append(NarrativeIssue(code: .missingNode, path: "\(path).options[\(optionIndex)].target", message: "Choice target node does not exist in this scene."))
                        }
                    }
                case let .branch(_, _, thenTarget, elseTarget):
                    if let thenTarget, nodesByScene[scene.id]?[thenTarget] == nil {
                        issues.append(NarrativeIssue(code: .missingBranchTarget, path: "\(path).thenTarget", message: "Branch then target does not exist in this scene."))
                    }
                    if let elseTarget, nodesByScene[scene.id]?[elseTarget] == nil {
                        issues.append(NarrativeIssue(code: .missingBranchTarget, path: "\(path).elseTarget", message: "Branch else target does not exist in this scene."))
                    }
                case let .jump(_, target):
                    guard let target else {
                        issues.append(NarrativeIssue(code: .missingNode, path: "\(path).target", message: "Jump has no target."))
                        continue
                    }
                    guard scenesByID[target.scene] != nil else {
                        issues.append(NarrativeIssue(code: .missingScene, path: "\(path).target.scene", message: "Jump target scene does not exist."))
                        continue
                    }
                    if nodesByScene[target.scene]?[target.node] == nil {
                        issues.append(NarrativeIssue(code: .missingNode, path: "\(path).target.node", message: "Jump target node does not exist in the target scene."))
                    }
                default:
                    break
                }
            }
        }
    }

    private static func validateReachability(_ scenes: [NarrativeScene], nodesByScene: [SceneID: [NodeID: NarrativeNode]], issues: inout [NarrativeIssue]) {
        var reachable = Set<Cursor>()
        var pending = scenes.map { Cursor(scene: $0.id, node: $0.entryNode) }
        let scenesByID = Dictionary(scenes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        while let cursor = pending.popLast() {
            guard reachable.insert(cursor).inserted,
                  let scene = scenesByID[cursor.scene],
                  let node = nodesByScene[cursor.scene]?[cursor.node],
                  let index = scene.nodes.firstIndex(where: { $0.id == cursor.node }) else { continue }
            func add(_ sceneID: SceneID, _ nodeID: NodeID?) {
                if let nodeID { pending.append(Cursor(scene: sceneID, node: nodeID)) }
            }
            switch node {
            case .line, .setFlag, .checkpoint:
                add(cursor.scene, scene.nodes.dropFirst(index + 1).first?.id)
            case let .choice(_, _, options):
                for option in options { add(cursor.scene, option.target) }
            case let .branch(_, _, thenTarget, elseTarget):
                add(cursor.scene, thenTarget)
                add(cursor.scene, elseTarget)
            case let .jump(_, target):
                if let target { add(target.scene, target.node) }
            case .end:
                break
            }
        }
        for (sceneIndex, scene) in scenes.enumerated() {
            for (nodeIndex, node) in scene.nodes.enumerated() where !reachable.contains(Cursor(scene: scene.id, node: node.id)) {
                issues.append(NarrativeIssue(code: .unreachableNode, path: "scenes[\(sceneIndex)].nodes[\(nodeIndex)]", message: "Node cannot be reached from any scene entry.", severity: .warning))
            }
        }
    }

    private static func checkID<ID: NarrativeIdentifier>(_ id: ID, path: String, into issues: inout [NarrativeIssue]) {
        guard !id.isValid else { return }
        issues.append(NarrativeIssue(code: .invalidIDSyntax, path: path, message: "Identifier must be non-empty and use lowercase letters, digits, periods, underscores, or hyphens."))
    }
}
