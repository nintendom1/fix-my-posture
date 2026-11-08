import Foundation

public struct NarrativeState: Codable, Equatable, Sendable {
    public let scene: SceneID
    public let node: NodeID
    public let flags: [FlagID: Bool]
    public let isEnded: Bool

    public init(scene: SceneID, node: NodeID, flags: [FlagID: Bool], isEnded: Bool = false) {
        self.scene = scene
        self.node = node
        self.flags = flags
        self.isEnded = isEnded
    }

    /// Drops loop-local companion memory while retaining all player/meta-history values.
    /// This helper changes only this in-memory state; it does not touch workout history, adaptive data, or notifications.
    public func resettingLoopMemory(in script: NarrativeScript) -> NarrativeState {
        let playerFlags = Set(script.flags.filter { $0.scope == .player }.map(\.id))
        let retained = flags.filter { playerFlags.contains($0.key) }
        return NarrativeState(scene: scene, node: node, flags: retained, isEnded: isEnded)
    }
}

public struct NarrativeCheckpoint: Codable, Equatable, Sendable {
    public let id: CheckpointID
    public let scene: SceneID
    public let node: NodeID
    public let flags: [FlagID: Bool]

    public init(id: CheckpointID, scene: SceneID, node: NodeID, flags: [FlagID: Bool]) {
        self.id = id
        self.scene = scene
        self.node = node
        self.flags = flags
    }
}

public enum NarrativeFallback: Codable, Equatable, Sendable {
    case expressionAssetMissing(requested: ExpressionID, used: ExpressionID, asset: AssetRef?)
    case audioAssetMissing(dropped: AudioRef)
}

public enum NarrativeStep: Codable, Equatable, Sendable {
    case line(presentation: CompanionPresentation, fallbacks: [NarrativeFallback])
    case choice(prompt: String, visibleOptions: [NarrativeVisibleOption])
    case end
    case failed(NarrativeIssue)
}

public struct NarrativeRuntimeResult: Codable, Equatable, Sendable {
    public let step: NarrativeStep
    public let state: NarrativeState?
    /// The most recent in-memory checkpoint crossed while resolving this step.
    public let checkpoint: NarrativeCheckpoint?

    public init(step: NarrativeStep, state: NarrativeState?, checkpoint: NarrativeCheckpoint? = nil) {
        self.step = step
        self.state = state
        self.checkpoint = checkpoint
    }
}

public struct NarrativeRestoreResult: Codable, Equatable, Sendable {
    public let state: NarrativeState?
    public let issues: [NarrativeIssue]
    public var isValid: Bool { state != nil }
}

/// A pure state machine: every operation takes an immutable state and returns a new one.
public struct NarrativeRuntime: Equatable, Sendable {
    private let validatedScript: NarrativeValidatedScript
    private let facts: NarrativeFacts
    private let assetManifest: NarrativeAssetManifest?
    private let stepLimit: Int

    public init(
        script: NarrativeValidatedScript,
        facts: NarrativeFacts = .empty,
        assetManifest: NarrativeAssetManifest? = nil,
        automaticStepLimit: Int = 128
    ) {
        validatedScript = script
        self.facts = facts
        self.assetManifest = assetManifest
        stepLimit = max(1, automaticStepLimit)
    }

    public func start(scene sceneID: SceneID) -> NarrativeRuntimeResult {
        guard let scene = validatedScript.script.scenes.first(where: { $0.id == sceneID }) else {
            return NarrativeRuntimeResult(step: .failed(NarrativeIssue(code: .missingScene, path: "scene", message: "Requested scene does not exist.")), state: nil)
        }
        return resolve(from: NarrativeState(scene: scene.id, node: scene.entryNode, flags: [:]))
    }

    public func advance(from state: NarrativeState) -> NarrativeRuntimeResult {
        guard isUsable(state) else { return failed(.invalidState, state: state, message: "State does not point into this script or contains undeclared flags.") }
        if state.isEnded { return NarrativeRuntimeResult(step: .end, state: state) }
        guard let node = node(scene: state.scene, id: state.node) else {
            return failed(.invalidState, state: state, message: "State node does not exist.")
        }
        switch node {
        case .line:
            guard let next = successor(of: state) else {
                return NarrativeRuntimeResult(step: .end, state: ending(state))
            }
            return preservingFailure(
                resolve(from: NarrativeState(scene: state.scene, node: next, flags: state.flags)),
                original: state
            )
        case .choice:
            return presentChoice(node, state: state)
        case .end:
            return NarrativeRuntimeResult(step: .end, state: ending(state))
        default:
            return resolve(from: state)
        }
    }

    public func choose(_ choiceID: ChoiceID, from state: NarrativeState) -> NarrativeRuntimeResult {
        guard !state.isEnded, isUsable(state), let node = node(scene: state.scene, id: state.node),
              case let .choice(_, _, options) = node else {
            return failed(.invalidChoice, state: state, message: "State is not waiting at a choice.")
        }
        guard let option = options.first(where: { $0.id == choiceID }),
              option.condition.map({ evaluate($0, flags: state.flags) }) ?? true,
              let target = option.target else {
            return failed(.invalidChoice, state: state, message: "Choice option is unknown or hidden.")
        }
        return preservingFailure(
            resolve(from: NarrativeState(scene: state.scene, node: target, flags: state.flags)),
            original: state
        )
    }

    /// Restores an in-memory checkpoint only if its scene, checkpoint node, id, and flags match this script.
    public func restore(_ checkpoint: NarrativeCheckpoint) -> NarrativeRestoreResult {
        guard validatedScript.script.scenes.contains(where: { $0.id == checkpoint.scene }) else {
            return invalidCheckpoint(path: "checkpoint.scene", message: "Checkpoint scene does not exist.")
        }
        guard let node = node(scene: checkpoint.scene, id: checkpoint.node) else {
            return invalidCheckpoint(path: "checkpoint.node", message: "Checkpoint node does not exist in the scene.")
        }
        guard case let .checkpoint(_, checkpointID) = node else {
            return invalidCheckpoint(path: "checkpoint.node", message: "Checkpoint node is not a checkpoint.")
        }
        guard checkpointID == checkpoint.id else {
            return invalidCheckpoint(path: "checkpoint.id", message: "Checkpoint id does not match its node.")
        }
        let declaredFlags = Set(validatedScript.script.flags.map(\.id))
        guard checkpoint.flags.keys.allSatisfy(declaredFlags.contains) else {
            return invalidCheckpoint(path: "checkpoint.flags", message: "Checkpoint contains an undeclared flag.")
        }
        return NarrativeRestoreResult(state: NarrativeState(scene: checkpoint.scene, node: checkpoint.node, flags: checkpoint.flags), issues: [])
    }

    private func resolve(from original: NarrativeState) -> NarrativeRuntimeResult {
        var state = original
        var steps = 0
        var crossedCheckpoint: NarrativeCheckpoint?

        while true {
            guard let node = node(scene: state.scene, id: state.node) else {
                return failed(.invalidState, state: original, message: "Execution reached a node that does not exist.")
            }
            switch node {
            case let .line(_, speakerID, expressionID, text, audio):
                guard let character = validatedScript.script.characters.first(where: { $0.id == speakerID }) else {
                    return failed(.unknownSpeaker, state: original, message: "Line speaker is not declared.")
                }
                var fallbacks: [NarrativeFallback] = []
                var selectedExpression = expressionID
                var selectedAsset = character.asset(for: expressionID)
                if !isAvailable(selectedAsset) {
                    selectedExpression = character.defaultExpression
                    selectedAsset = character.asset(for: character.defaultExpression)
                    if !isAvailable(selectedAsset) { selectedAsset = nil }
                    fallbacks.append(.expressionAssetMissing(requested: expressionID, used: character.defaultExpression, asset: character.asset(for: expressionID)))
                }
                var selectedAudio = audio
                if let audio, let assetManifest, !assetManifest.contains(audio) {
                    selectedAudio = nil
                    fallbacks.append(.audioAssetMissing(dropped: audio))
                }
                let presentation = CompanionPresentation(
                    character: speakerID,
                    expression: selectedExpression,
                    expressionAsset: selectedAsset,
                    text: text,
                    audio: selectedAudio,
                    kind: .sceneLine,
                    blocking: true,
                    dismissal: .tap
                )
                return NarrativeRuntimeResult(step: .line(presentation: presentation, fallbacks: fallbacks), state: state, checkpoint: crossedCheckpoint)
            case .choice:
                let result = presentChoice(node, state: state)
                return NarrativeRuntimeResult(step: result.step, state: result.state, checkpoint: crossedCheckpoint)
            case .end:
                return NarrativeRuntimeResult(step: .end, state: ending(state), checkpoint: crossedCheckpoint)
            case let .setFlag(_, flag, value):
                steps += 1
                guard steps <= stepLimit else { return stepLimitFailure(original) }
                var flags = state.flags
                flags[flag] = value
                guard let next = successor(of: state) else {
                    state = NarrativeState(scene: state.scene, node: state.node, flags: flags, isEnded: true)
                    return NarrativeRuntimeResult(step: .end, state: state, checkpoint: crossedCheckpoint)
                }
                state = NarrativeState(scene: state.scene, node: next, flags: flags)
            case let .checkpoint(_, checkpointID):
                steps += 1
                guard steps <= stepLimit else { return stepLimitFailure(original) }
                crossedCheckpoint = NarrativeCheckpoint(id: checkpointID, scene: state.scene, node: state.node, flags: state.flags)
                guard let next = successor(of: state) else {
                    state = ending(state)
                    return NarrativeRuntimeResult(step: .end, state: state, checkpoint: crossedCheckpoint)
                }
                state = NarrativeState(scene: state.scene, node: next, flags: state.flags)
            case let .branch(_, condition, thenTarget, elseTarget):
                steps += 1
                guard steps <= stepLimit else { return stepLimitFailure(original) }
                guard let target = (evaluate(condition, flags: state.flags) ? thenTarget : elseTarget) else {
                    return failed(.missingBranchTarget, state: original, message: "Branch target is missing.")
                }
                state = NarrativeState(scene: state.scene, node: target, flags: state.flags)
            case let .jump(_, target):
                steps += 1
                guard steps <= stepLimit else { return stepLimitFailure(original) }
                guard let target else { return failed(.missingNode, state: original, message: "Jump target is missing.") }
                state = NarrativeState(scene: target.scene, node: target.node, flags: state.flags)
            }
        }
    }

    private func presentChoice(_ node: NarrativeNode, state: NarrativeState) -> NarrativeRuntimeResult {
        guard case let .choice(_, prompt, options) = node else {
            return failed(.invalidState, state: state, message: "Expected a choice node.")
        }
        let visible = options.compactMap { option -> NarrativeVisibleOption? in
            guard option.condition.map({ evaluate($0, flags: state.flags) }) ?? true else { return nil }
            return NarrativeVisibleOption(id: option.id, text: option.text)
        }
        return NarrativeRuntimeResult(step: .choice(prompt: prompt, visibleOptions: visible), state: state)
    }

    private func evaluate(_ condition: NarrativeCondition, flags: [FlagID: Bool]) -> Bool {
        switch condition {
        case let .flagIsSet(flag): return flags[flag] == true
        case let .flagIsUnset(flag): return flags[flag] != true
        case let .flagEquals(flag, value): return (flags[flag] ?? false) == value
        case let .fact(comparison):
            guard facts.knownFactIDs.contains(comparison.fact), let value = facts.value(for: comparison.fact) else { return false }
            return comparison.comparison.evaluate(value, comparison.value)
        case let .all(conditions): return conditions.allSatisfy { evaluate($0, flags: flags) }
        case let .any(conditions): return conditions.contains { evaluate($0, flags: flags) }
        case let .not(nested): return !evaluate(nested, flags: flags)
        }
    }

    private func isAvailable(_ asset: AssetRef?) -> Bool {
        guard let asset else { return false }
        return assetManifest?.contains(asset) ?? true
    }

    private func successor(of state: NarrativeState) -> NodeID? {
        guard let scene = validatedScript.script.scenes.first(where: { $0.id == state.scene }),
              let index = scene.nodes.firstIndex(where: { $0.id == state.node }) else { return nil }
        return scene.nodes.dropFirst(index + 1).first?.id
    }

    private func node(scene sceneID: SceneID, id nodeID: NodeID) -> NarrativeNode? {
        validatedScript.script.scenes.first(where: { $0.id == sceneID })?.nodes.first(where: { $0.id == nodeID })
    }

    private func isUsable(_ state: NarrativeState) -> Bool {
        let declaredFlags = Set(validatedScript.script.flags.map(\.id))
        return node(scene: state.scene, id: state.node) != nil && state.flags.keys.allSatisfy(declaredFlags.contains)
    }

    private func ending(_ state: NarrativeState) -> NarrativeState {
        NarrativeState(scene: state.scene, node: state.node, flags: state.flags, isEnded: true)
    }

    private func failed(_ code: NarrativeIssueCode, state: NarrativeState, message: String) -> NarrativeRuntimeResult {
        NarrativeRuntimeResult(step: .failed(NarrativeIssue(code: code, path: "runtime", message: message)), state: state)
    }

    private func preservingFailure(_ result: NarrativeRuntimeResult, original: NarrativeState) -> NarrativeRuntimeResult {
        guard case .failed = result.step else { return result }
        return NarrativeRuntimeResult(step: result.step, state: original)
    }

    private func invalidCheckpoint(path: String, message: String) -> NarrativeRestoreResult {
        NarrativeRestoreResult(
            state: nil,
            issues: [NarrativeIssue(code: .invalidCheckpoint, path: path, message: message)]
        )
    }

    private func stepLimitFailure(_ original: NarrativeState) -> NarrativeRuntimeResult {
        failed(.stepLimitExceeded, state: original, message: "Automatic control flow exceeded the configured step limit.")
    }
}
