import Foundation
import XCTest
@testable import Narrative

final class NarrativeRuntimeReviewTests: XCTestCase {
    func testFailedAdvanceAndChooseRestoreExactCallerStateAfterMutationsAndCheckpoint() throws {
        let flags = #"[{"id":"seen","scope":"player"}]"#
        let lineLoop = #"[{"type":"line","id":"entry","speaker":"mika","expression":"calm","text":"Waiting."},{"type":"setFlag","id":"set_seen","flag":"seen","value":true},{"type":"checkpoint","id":"mark","checkpointID":"loop_start"},{"type":"jump","id":"loop","target":{"scene":"scene","node":"loop"}},{"type":"end","id":"unreachable"}]"#
        let lineRuntime = NarrativeRuntime(script: try validated(nodes: lineLoop, flags: flags), automaticStepLimit: 4)
        let line = lineRuntime.start(scene: SceneID(rawValue: "scene"))
        let lineState = try XCTUnwrap(line.state)
        XCTAssertEqual(lineState.node, NodeID(rawValue: "entry"))
        let advance = lineRuntime.advance(from: lineState)
        XCTAssertEqual(advance.step.issueCode, .stepLimitExceeded)
        XCTAssertEqual(advance.step.issuePath, "runtime")
        XCTAssertEqual(advance.state, lineState)
        XCTAssertNil(advance.checkpoint, "A failed transition must not expose a checkpoint crossed by tentative execution.")

        let choiceLoop = #"[{"type":"choice","id":"entry","prompt":"Continue?","options":[{"id":"go","text":"Go","target":"set_seen"}]},{"type":"setFlag","id":"set_seen","flag":"seen","value":true},{"type":"checkpoint","id":"mark","checkpointID":"loop_start"},{"type":"jump","id":"loop","target":{"scene":"scene","node":"loop"}},{"type":"end","id":"unreachable"}]"#
        let choiceRuntime = NarrativeRuntime(script: try validated(nodes: choiceLoop, flags: flags), automaticStepLimit: 4)
        let choice = choiceRuntime.start(scene: SceneID(rawValue: "scene"))
        let choiceState = try XCTUnwrap(choice.state)
        XCTAssertEqual(choiceState.node, NodeID(rawValue: "entry"))
        let chosen = choiceRuntime.choose(ChoiceID(rawValue: "go"), from: choiceState)
        XCTAssertEqual(chosen.step.issueCode, .stepLimitExceeded)
        XCTAssertEqual(chosen.step.issuePath, "runtime")
        XCTAssertEqual(chosen.state, choiceState)
        XCTAssertNil(chosen.checkpoint)
    }

    func testAutomaticStepLimitAllowsFiniteChainAtLimitAndFailsOneStepBelow() throws {
        let nodes = #"[{"type":"setFlag","id":"entry","flag":"first","value":true},{"type":"setFlag","id":"second","flag":"second","value":true},{"type":"line","id":"last","speaker":"mika","expression":"calm","text":"Done."}]"#
        let flags = #"[{"id":"first","scope":"loop"},{"id":"second","scope":"loop"}]"#
        let script = try validated(nodes: nodes, flags: flags)
        let atLimit = NarrativeRuntime(script: script, automaticStepLimit: 2).start(scene: SceneID(rawValue: "scene"))
        guard case let .line(presentation, _) = atLimit.step else { return XCTFail("Two control nodes should fit a limit of two.") }
        XCTAssertEqual(presentation.text, "Done.")
        XCTAssertEqual(atLimit.state?.flags, [FlagID(rawValue: "first"): true, FlagID(rawValue: "second"): true])

        let belowLimitRuntime = NarrativeRuntime(script: script, automaticStepLimit: 1)
        let failed = belowLimitRuntime.start(scene: SceneID(rawValue: "scene"))
        XCTAssertEqual(failed.step.issueCode, .stepLimitExceeded)
        XCTAssertEqual(failed.step.issuePath, "runtime")
        XCTAssertEqual(failed.state, NarrativeState(scene: SceneID(rawValue: "scene"), node: NodeID(rawValue: "entry"), flags: [:]))
    }

    func testConditionComparisonsAndBoundaryValues() throws {
        let cases: [(String, [(Int, Bool)])] = [
            ("equal", [(2, false), (3, true), (4, false)]),
            ("notEqual", [(2, true), (3, false), (4, true)]),
            ("lessThan", [(2, true), (3, false), (4, false)]),
            ("lessThanOrEqual", [(2, true), (3, true), (4, false)]),
            ("greaterThan", [(2, false), (3, false), (4, true)]),
            ("greaterThanOrEqual", [(2, false), (3, true), (4, true)])
        ]

        for (comparison, values) in cases {
            let condition = #"{"type":"fact","fact":"workouts_this_week","comparison":"\#(comparison)","value":3}"#
            for (factValue, expected) in values {
                let visible = try visibleOptions(condition: condition, facts: NarrativeFacts(values: [FactID(rawValue: "workouts_this_week"): factValue]))
                XCTAssertEqual(visible.contains(ChoiceID(rawValue: "take")), expected, "\(comparison) at \(factValue)")
            }
        }
    }

    func testFlagConditionsNestedConditionsAndExplicitFalseWrites() throws {
        let isSet = #"{"type":"flagIsSet","flag":"enabled"}"#
        let isUnset = #"{"type":"flagIsUnset","flag":"enabled"}"#
        let equalsTrue = #"{"type":"flagEquals","flag":"enabled","value":true}"#
        let equalsFalse = #"{"type":"flagEquals","flag":"enabled","value":false}"#
        let enabled = FlagID(rawValue: "enabled")

        XCTAssertTrue(try visibleOptions(condition: isSet, flags: [enabled: true]).contains(ChoiceID(rawValue: "take")))
        XCTAssertFalse(try visibleOptions(condition: isSet, flags: [enabled: false]).contains(ChoiceID(rawValue: "take")))
        XCTAssertTrue(try visibleOptions(condition: isUnset, flags: [enabled: false]).contains(ChoiceID(rawValue: "take")))
        XCTAssertFalse(try visibleOptions(condition: isUnset, flags: [enabled: true]).contains(ChoiceID(rawValue: "take")))
        XCTAssertTrue(try visibleOptions(condition: equalsTrue, flags: [enabled: true]).contains(ChoiceID(rawValue: "take")))
        XCTAssertFalse(try visibleOptions(condition: equalsTrue, flags: [enabled: false]).contains(ChoiceID(rawValue: "take")))
        XCTAssertTrue(try visibleOptions(condition: equalsFalse, flags: [enabled: false]).contains(ChoiceID(rawValue: "take")))
        XCTAssertFalse(try visibleOptions(condition: equalsFalse, flags: [enabled: true]).contains(ChoiceID(rawValue: "take")))
        XCTAssertTrue(try visibleOptions(condition: #"{"type":"not","condition":{"type":"flagIsSet","flag":"enabled"}}"#, flags: [enabled: false]).contains(ChoiceID(rawValue: "take")))
        XCTAssertFalse(try visibleOptions(condition: #"{"type":"not","condition":{"type":"flagIsSet","flag":"enabled"}}"#, flags: [enabled: true]).contains(ChoiceID(rawValue: "take")))

        let workouts = FactID(rawValue: "workouts_this_week")
        let factCondition = #"{"type":"fact","fact":"workouts_this_week","comparison":"greaterThanOrEqual","value":3}"#
        let allCondition = #"{"type":"all","conditions":[{"type":"flagEquals","flag":"enabled","value":true},\#(factCondition)]}"#
        let anyCondition = #"{"type":"any","conditions":[{"type":"flagIsSet","flag":"enabled"},\#(factCondition)]}"#
        let facts = NarrativeFacts(values: [workouts: 3])
        XCTAssertTrue(try visibleOptions(condition: allCondition, flags: [enabled: true], facts: facts).contains(ChoiceID(rawValue: "take")))
        XCTAssertFalse(try visibleOptions(condition: allCondition, flags: [enabled: false], facts: facts).contains(ChoiceID(rawValue: "take")))
        XCTAssertTrue(try visibleOptions(condition: anyCondition, flags: [enabled: false], facts: facts).contains(ChoiceID(rawValue: "take")))
        XCTAssertFalse(try visibleOptions(condition: anyCondition, flags: [enabled: false], facts: NarrativeFacts(values: [workouts: 2])).contains(ChoiceID(rawValue: "take")))

        let branchNodes = #"[{"type":"setFlag","id":"entry","flag":"enabled","value":false},{"type":"branch","id":"branch","condition":{"type":"flagIsSet","flag":"enabled"},"thenTarget":"yes","elseTarget":"no"},{"type":"end","id":"yes"},{"type":"end","id":"no"}]"#
        let script = try validated(nodes: branchNodes, flags: #"[{"id":"enabled","scope":"player"}]"#)
        let initiallyTrue = NarrativeState(scene: SceneID(rawValue: "scene"), node: NodeID(rawValue: "entry"), flags: [enabled: true])
        let falseBranch = NarrativeRuntime(script: script).advance(from: initiallyTrue)
        XCTAssertEqual(falseBranch.step, .end)
        XCTAssertEqual(falseBranch.state?.node, NodeID(rawValue: "no"))
        XCTAssertEqual(falseBranch.state?.flags[enabled], false)

        let trueNodes = branchNodes.replacingOccurrences(of: "\"value\":false", with: "\"value\":true")
        let trueBranch = NarrativeRuntime(script: try validated(nodes: trueNodes, flags: #"[{"id":"enabled","scope":"player"}]"#)).advance(from: initiallyTrue)
        XCTAssertEqual(trueBranch.step, .end)
        XCTAssertEqual(trueBranch.state?.node, NodeID(rawValue: "yes"))
    }

    func testUnknownKnownAndKnownWithoutValueFactsEvaluateFalseOrTrue() throws {
        let condition = #"{"type":"fact","fact":"custom_fact","comparison":"greaterThanOrEqual","value":3}"#
        let result = NarrativeFixtures.load(NarrativeFixtures.script(nodes: choiceNodes(condition: condition)))
        XCTAssertTrue(result.issues.contains { $0.code == .unknownFact && $0.severity == .warning })
        let validated = try XCTUnwrap(result.validatedScript)
        let fact = FactID(rawValue: "custom_fact")

        let unknownButValued = NarrativeRuntime(script: validated, facts: NarrativeFacts(values: [fact: 3], knownFactIDs: [])).advance(from: choiceState())
        XCTAssertFalse(visibleOptions(from: unknownButValued).contains(ChoiceID(rawValue: "take")))

        let knownAndValued = NarrativeRuntime(script: validated, facts: NarrativeFacts(values: [fact: 3], knownFactIDs: [fact])).advance(from: choiceState())
        XCTAssertTrue(visibleOptions(from: knownAndValued).contains(ChoiceID(rawValue: "take")))

        let knownWithoutValue = NarrativeRuntime(script: validated, facts: NarrativeFacts(values: [:], knownFactIDs: [fact])).advance(from: choiceState())
        XCTAssertFalse(visibleOptions(from: knownWithoutValue).contains(ChoiceID(rawValue: "take")))
    }

    func testVisibleAlternateChoiceAndCompletePresentationAndTerminalState() throws {
        let runtime = NarrativeRuntime(script: try validatedFixture(), facts: NarrativeFacts(values: [FactID(rawValue: "workouts_this_week"): 2]))
        let choice = runtime.advance(from: try XCTUnwrap(runtime.start(scene: SceneID(rawValue: "opening")).state))
        guard case let .choice(prompt, options) = choice.step else { return XCTFail("Expected opening choice") }
        XCTAssertEqual(prompt, "What next?")
        XCTAssertEqual(options, [NarrativeVisibleOption(id: ChoiceID(rawValue: "skip"), text: "Skip ahead")])

        let skipped = runtime.choose(ChoiceID(rawValue: "skip"), from: try XCTUnwrap(choice.state))
        guard case let .line(presentation, fallbacks) = skipped.step else { return XCTFail("Expected skip line") }
        XCTAssertEqual(presentation.character, CharacterID(rawValue: "mika"))
        XCTAssertEqual(presentation.expression, ExpressionID(rawValue: "calm"))
        XCTAssertEqual(presentation.text, "We can pick this up later.")
        XCTAssertEqual(presentation.kind, .sceneLine)
        XCTAssertTrue(presentation.blocking)
        XCTAssertEqual(presentation.dismissal, .tap)
        XCTAssertNil(presentation.audio)
        XCTAssertTrue(fallbacks.isEmpty)
        XCTAssertEqual(skipped.state?.node, NodeID(rawValue: "skip_line"))

        let ended = runtime.advance(from: try XCTUnwrap(skipped.state))
        XCTAssertEqual(ended.step, .end)
        XCTAssertTrue(try XCTUnwrap(ended.state).isEnded)
        XCTAssertEqual(runtime.advance(from: try XCTUnwrap(ended.state)).state, ended.state)
    }

    func testChooseRejectsTerminalStateWithoutRestartingChoice() throws {
        let runtime = NarrativeRuntime(script: try validatedFixture())
        let terminalChoice = NarrativeState(scene: SceneID(rawValue: "opening"), node: NodeID(rawValue: "question"), flags: [:], isEnded: true)
        let rejected = runtime.choose(ChoiceID(rawValue: "skip"), from: terminalChoice)
        XCTAssertEqual(rejected.step.issueCode, .invalidChoice)
        XCTAssertEqual(rejected.step.issuePath, "runtime")
        XCTAssertEqual(rejected.state, terminalChoice)
    }

    func testUnknownSceneAndInvalidStateFailuresKeepTheirIssuePathsAndInput() throws {
        let runtime = NarrativeRuntime(script: try validatedFixture())
        let missingScene = runtime.start(scene: SceneID(rawValue: "not_declared"))
        XCTAssertEqual(missingScene.step.issueCode, .missingScene)
        XCTAssertEqual(missingScene.step.issuePath, "scene")
        XCTAssertNil(missingScene.state)

        let invalidCursor = NarrativeState(scene: SceneID(rawValue: "opening"), node: NodeID(rawValue: "missing"), flags: [:])
        let rejectedAdvance = runtime.advance(from: invalidCursor)
        XCTAssertEqual(rejectedAdvance.step.issueCode, .invalidState)
        XCTAssertEqual(rejectedAdvance.step.issuePath, "runtime")
        XCTAssertEqual(rejectedAdvance.state, invalidCursor)

        let undeclaredFlagState = NarrativeState(scene: SceneID(rawValue: "opening"), node: NodeID(rawValue: "question"), flags: [FlagID(rawValue: "unknown"): true])
        let rejectedChoice = runtime.choose(ChoiceID(rawValue: "skip"), from: undeclaredFlagState)
        XCTAssertEqual(rejectedChoice.step.issueCode, .invalidChoice)
        XCTAssertEqual(rejectedChoice.step.issuePath, "runtime")
        XCTAssertEqual(rejectedChoice.state, undeclaredFlagState)
    }

    func testCheckpointResumePreservesFlagsAndRejectsEveryInvalidLocation() throws {
        let flags = #"[{"id":"player_seen","scope":"player"},{"id":"loop_seen","scope":"loop"}]"#
        let nodes = #"[{"type":"setFlag","id":"entry","flag":"player_seen","value":true},{"type":"setFlag","id":"set_loop","flag":"loop_seen","value":true},{"type":"checkpoint","id":"mark","checkpointID":"resume_point"},{"type":"line","id":"after_mark","speaker":"mika","expression":"calm","text":"Resumed."},{"type":"end","id":"done"}]"#
        let script = try validated(nodes: nodes, flags: flags)
        let runtime = NarrativeRuntime(script: script)
        let next = runtime.start(scene: SceneID(rawValue: "scene"))
        guard case let .line(presentation, _) = next.step else { return XCTFail("Expected line after checkpoint") }
        XCTAssertEqual(presentation.text, "Resumed.")
        let checkpoint = try XCTUnwrap(next.checkpoint)
        XCTAssertEqual(checkpoint.flags, [FlagID(rawValue: "player_seen"): true, FlagID(rawValue: "loop_seen"): true])
        let roundTrip = try JSONDecoder().decode(NarrativeCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        XCTAssertEqual(roundTrip, checkpoint)

        let restored = runtime.restore(roundTrip)
        let restoredState = try XCTUnwrap(restored.state)
        XCTAssertEqual(restoredState.flags, checkpoint.flags)
        let resumed = runtime.advance(from: restoredState)
        guard case let .line(resumedPresentation, _) = resumed.step else { return XCTFail("Expected resumed line") }
        XCTAssertEqual(resumedPresentation.text, "Resumed.")
        XCTAssertEqual(resumed.state?.node, NodeID(rawValue: "after_mark"))
        XCTAssertEqual(resumed.state?.flags, checkpoint.flags)

        let invalidCases: [(NarrativeCheckpoint, String)] = [
            (NarrativeCheckpoint(id: checkpoint.id, scene: SceneID(rawValue: "missing"), node: checkpoint.node, flags: checkpoint.flags), "checkpoint.scene"),
            (NarrativeCheckpoint(id: checkpoint.id, scene: checkpoint.scene, node: NodeID(rawValue: "missing"), flags: checkpoint.flags), "checkpoint.node"),
            (NarrativeCheckpoint(id: checkpoint.id, scene: checkpoint.scene, node: NodeID(rawValue: "after_mark"), flags: checkpoint.flags), "checkpoint.node"),
            (NarrativeCheckpoint(id: CheckpointID(rawValue: "wrong_id"), scene: checkpoint.scene, node: checkpoint.node, flags: checkpoint.flags), "checkpoint.id"),
            (NarrativeCheckpoint(id: checkpoint.id, scene: checkpoint.scene, node: checkpoint.node, flags: [FlagID(rawValue: "undeclared"): true]), "checkpoint.flags")
        ]
        for (invalid, path) in invalidCases {
            let rejection = runtime.restore(invalid)
            XCTAssertNil(rejection.state, "\(path)")
            XCTAssertEqual(rejection.issues.map(\.code), [.invalidCheckpoint])
            XCTAssertEqual(rejection.issues.map(\.path), [path])
        }
    }

    func testLoopMemoryResetPreservesCompletePlayerStateIncludingFalseAndEnded() throws {
        let flags = #"[{"id":"player_yes","scope":"player"},{"id":"player_no","scope":"player"},{"id":"loop_yes","scope":"loop"},{"id":"loop_no","scope":"loop"}]"#
        let script = try validated(nodes: #"[{"type":"end","id":"entry"}]"#, flags: flags)
        let input = NarrativeState(
            scene: SceneID(rawValue: "scene"),
            node: NodeID(rawValue: "entry"),
            flags: [
                FlagID(rawValue: "player_yes"): true,
                FlagID(rawValue: "player_no"): false,
                FlagID(rawValue: "loop_yes"): true,
                FlagID(rawValue: "loop_no"): false
            ],
            isEnded: true
        )
        let reset = input.resettingLoopMemory(in: script.script)
        XCTAssertEqual(reset, NarrativeState(
            scene: input.scene,
            node: input.node,
            flags: [FlagID(rawValue: "player_yes"): true, FlagID(rawValue: "player_no"): false],
            isEnded: true
        ))
    }

    func testAvailableAssetsArePreservedAndFallbackCoversMissingMappingsAndDefault() throws {
        let happyLine = NarrativeFixtures.twoSceneScript.replacingOccurrences(
            of: "\"id\": \"intro\", \"speaker\": \"mika\", \"expression\": \"calm\"",
            with: "\"id\": \"intro\", \"speaker\": \"mika\", \"expression\": \"happy\""
        )
        let completeManifest = NarrativeAssetManifest(
            portraitsAndExpressions: [AssetRef(rawValue: "mika_portrait"), AssetRef(rawValue: "mika_calm"), AssetRef(rawValue: "mika_happy")],
            audio: [AudioRef(rawValue: "hello")]
        )
        let completeScript = try XCTUnwrap(NarrativeFixtures.load(happyLine, manifest: completeManifest).validatedScript)
        let complete = NarrativeRuntime(script: completeScript, assetManifest: completeManifest).start(scene: SceneID(rawValue: "opening"))
        guard case let .line(completePresentation, completeFallbacks) = complete.step else { return XCTFail("Expected line") }
        XCTAssertEqual(completePresentation.expression, ExpressionID(rawValue: "happy"))
        XCTAssertEqual(completePresentation.expressionAsset, AssetRef(rawValue: "mika_happy"))
        XCTAssertEqual(completePresentation.audio, AudioRef(rawValue: "hello"))
        XCTAssertTrue(completeFallbacks.isEmpty)

        let noHappyMapping = replacingExpressionAssets(in: happyLine, with: "[{\"expression\": \"calm\", \"asset\": \"mika_calm\"}]")
        let calmManifest = NarrativeAssetManifest(portraitsAndExpressions: [AssetRef(rawValue: "mika_calm")], audio: [])
        let mappingScript = try XCTUnwrap(NarrativeFixtures.load(noHappyMapping, manifest: calmManifest).validatedScript)
        let mappingResult = NarrativeRuntime(script: mappingScript, assetManifest: calmManifest).start(scene: SceneID(rawValue: "opening"))
        guard case let .line(mappingPresentation, mappingFallbacks) = mappingResult.step else { return XCTFail("Expected fallback line") }
        XCTAssertEqual(mappingPresentation.expression, ExpressionID(rawValue: "calm"))
        XCTAssertEqual(mappingPresentation.expressionAsset, AssetRef(rawValue: "mika_calm"))
        XCTAssertTrue(mappingFallbacks.contains(.expressionAssetMissing(requested: ExpressionID(rawValue: "happy"), used: ExpressionID(rawValue: "calm"), asset: nil)))

        let noDefaultAsset = NarrativeAssetManifest(portraitsAndExpressions: [], audio: [])
        let noDefaultScript = try XCTUnwrap(NarrativeFixtures.load(happyLine, manifest: noDefaultAsset).validatedScript)
        let noDefault = NarrativeRuntime(script: noDefaultScript, assetManifest: noDefaultAsset).start(scene: SceneID(rawValue: "opening"))
        guard case let .line(noDefaultPresentation, noDefaultFallbacks) = noDefault.step else { return XCTFail("Expected default semantic fallback") }
        XCTAssertEqual(noDefaultPresentation.expression, ExpressionID(rawValue: "calm"))
        XCTAssertNil(noDefaultPresentation.expressionAsset)
        XCTAssertTrue(noDefaultFallbacks.contains(.expressionAssetMissing(requested: ExpressionID(rawValue: "happy"), used: ExpressionID(rawValue: "calm"), asset: AssetRef(rawValue: "mika_happy"))))
    }

    func testDeterminismCoversTraceFailureFallbackRestoreAndReset() throws {
        let script = try validatedFixture()
        let facts = NarrativeFacts(values: [FactID(rawValue: "workouts_this_week"): 3])
        let first = NarrativeRuntime(script: script, facts: facts)
        let second = NarrativeRuntime(script: script, facts: facts)
        let firstStart = first.start(scene: SceneID(rawValue: "opening"))
        let secondStart = second.start(scene: SceneID(rawValue: "opening"))
        XCTAssertEqual(firstStart, secondStart)
        let firstChoice = first.advance(from: try XCTUnwrap(firstStart.state))
        let secondChoice = second.advance(from: try XCTUnwrap(secondStart.state))
        XCTAssertEqual(firstChoice, secondChoice)
        let choiceState1 = try XCTUnwrap(firstChoice.state)
        let choiceState2 = try XCTUnwrap(secondChoice.state)
        let firstFailure = first.choose(ChoiceID(rawValue: "missing"), from: choiceState1)
        let secondFailure = second.choose(ChoiceID(rawValue: "missing"), from: choiceState2)
        XCTAssertEqual(firstFailure, secondFailure)
        XCTAssertEqual(firstFailure.state, choiceState1)

        let firstLine = first.choose(ChoiceID(rawValue: "continue"), from: choiceState1)
        let secondLine = second.choose(ChoiceID(rawValue: "continue"), from: choiceState2)
        XCTAssertEqual(firstLine, secondLine)
        let firstOutro = first.advance(from: try XCTUnwrap(firstLine.state))
        let secondOutro = second.advance(from: try XCTUnwrap(secondLine.state))
        XCTAssertEqual(firstOutro, secondOutro)
        let firstEnd = first.advance(from: try XCTUnwrap(firstOutro.state))
        let secondEnd = second.advance(from: try XCTUnwrap(secondOutro.state))
        XCTAssertEqual(firstEnd, secondEnd)

        let manifest = NarrativeAssetManifest(portraitsAndExpressions: [], audio: [])
        let fallbackFirst = NarrativeRuntime(script: script, assetManifest: manifest).start(scene: SceneID(rawValue: "opening"))
        let fallbackSecond = NarrativeRuntime(script: script, assetManifest: manifest).start(scene: SceneID(rawValue: "opening"))
        XCTAssertEqual(fallbackFirst, fallbackSecond)

        let checkpoint = try XCTUnwrap(firstChoice.checkpoint)
        XCTAssertEqual(first.restore(checkpoint), second.restore(checkpoint))
        let resetInput = NarrativeState(scene: choiceState1.scene, node: choiceState1.node, flags: [FlagID(rawValue: "met_today"): true, FlagID(rawValue: "loop_seen"): true], isEnded: true)
        XCTAssertEqual(resetInput.resettingLoopMemory(in: script.script), resetInput.resettingLoopMemory(in: script.script))
    }

    private func validated(nodes: String, flags: String = "[]", characters: String = #"[{"id":"mika","allowedExpressions":["calm"],"defaultExpression":"calm","expressionAssets":[{"expression":"calm","asset":"calm_asset"}]}]"#) throws -> NarrativeValidatedScript {
        let json = NarrativeFixtures.script(nodes: nodes, characters: characters, flags: flags)
        let result = NarrativeFixtures.load(json)
        return try XCTUnwrap(result.validatedScript, "\(result.issues)")
    }

    private func choiceNodes(condition: String) -> String {
        "[{\"type\":\"choice\",\"id\":\"entry\",\"prompt\":\"Pick\",\"options\":[{\"id\":\"take\",\"text\":\"Take\",\"condition\":\(condition),\"target\":\"yes\"},{\"id\":\"otherwise\",\"text\":\"Otherwise\",\"target\":\"no\"}]},{\"type\":\"end\",\"id\":\"yes\"},{\"type\":\"end\",\"id\":\"no\"}]"
    }

    private func visibleOptions(condition: String, flags: [FlagID: Bool] = [:], facts: NarrativeFacts = .empty) throws -> [ChoiceID] {
        let flagsJSON = #"[{"id":"enabled","scope":"player"}]"#
        let script = try validated(nodes: choiceNodes(condition: condition), flags: flagsJSON, characters: "[]")
        let runtime = NarrativeRuntime(script: script, facts: facts)
        let state = NarrativeState(scene: SceneID(rawValue: "scene"), node: NodeID(rawValue: "entry"), flags: flags)
        let result = runtime.advance(from: state)
        guard case let .choice(_, options) = result.step else {
            XCTFail("Expected a valid choice node, got \(result.step)")
            return []
        }
        return options.map(\.id)
    }

    private func visibleOptions(from result: NarrativeRuntimeResult) -> [ChoiceID] {
        guard case let .choice(_, options) = result.step else { return [] }
        return options.map(\.id)
    }

    private func choiceState() -> NarrativeState {
        NarrativeState(scene: SceneID(rawValue: "scene"), node: NodeID(rawValue: "entry"), flags: [:])
    }

    private func replacingExpressionAssets(in json: String, with array: String) -> String {
        guard let opening = json.range(of: "\"expressionAssets\": ["),
              let closing = json[opening.upperBound...].firstIndex(of: "]") else {
            XCTFail("Fixture has no expression asset array.")
            return json
        }
        let range = opening.lowerBound..<json.index(after: closing)
        return json.replacingCharacters(in: range, with: "\"expressionAssets\": \(array)")
    }

    private func validatedFixture() throws -> NarrativeValidatedScript {
        try XCTUnwrap(NarrativeFixtures.load(NarrativeFixtures.twoSceneScript).validatedScript)
    }
}

private extension NarrativeStep {
    var issueCode: NarrativeIssueCode? {
        guard case let .failed(issue) = self else { return nil }
        return issue.code
    }

    var issuePath: String? {
        guard case let .failed(issue) = self else { return nil }
        return issue.path
    }
}
