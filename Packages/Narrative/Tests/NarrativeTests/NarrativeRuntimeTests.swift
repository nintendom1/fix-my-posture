import Foundation
import XCTest
@testable import Narrative

final class NarrativeRuntimeTests: XCTestCase {
    func testRuntimeStepOrderAndCheckpointSnapshot() throws {
        let validated = try validatedFixture()
        let runtime = NarrativeRuntime(script: validated, facts: NarrativeFacts(values: [FactID(rawValue: "workouts_this_week"): 3]))

        let opening = runtime.start(scene: SceneID(rawValue: "opening"))
        guard case let .line(presentation, fallbacks) = opening.step else { return XCTFail("Expected opening line, got \(opening.step)") }
        XCTAssertEqual(presentation.character, CharacterID(rawValue: "mika"))
        XCTAssertEqual(presentation.expression, ExpressionID(rawValue: "calm"))
        XCTAssertEqual(presentation.expressionAsset, AssetRef(rawValue: "mika_calm"))
        XCTAssertEqual(presentation.text, "Welcome back.")
        XCTAssertEqual(presentation.audio, AudioRef(rawValue: "hello"))
        XCTAssertEqual(presentation.kind, .sceneLine)
        XCTAssertTrue(presentation.blocking)
        XCTAssertEqual(presentation.dismissal, .tap)
        XCTAssertNil(presentation.cueID)
        XCTAssertTrue(fallbacks.isEmpty)
        let openingState = try XCTUnwrap(opening.state)
        XCTAssertEqual(openingState.scene, SceneID(rawValue: "opening"))
        XCTAssertEqual(openingState.node, NodeID(rawValue: "intro"))
        XCTAssertFalse(openingState.isEnded)

        let choice = runtime.advance(from: openingState)
        guard case let .choice(prompt, options) = choice.step else { return XCTFail("Expected choice, got \(choice.step)") }
        XCTAssertEqual(prompt, "What next?")
        XCTAssertEqual(options.map(\.id), [ChoiceID(rawValue: "continue"), ChoiceID(rawValue: "skip")])
        let checkpoint = try XCTUnwrap(choice.checkpoint)
        XCTAssertEqual(checkpoint.id, CheckpointID(rawValue: "after_intro"))
        XCTAssertEqual(checkpoint.node, NodeID(rawValue: "mark"))
        XCTAssertEqual(checkpoint.flags, [:])

        let selected = runtime.choose(ChoiceID(rawValue: "continue"), from: try XCTUnwrap(choice.state))
        guard case let .line(finish, _) = selected.step else { return XCTFail("Expected finish line, got \(selected.step)") }
        XCTAssertEqual(finish.character, CharacterID(rawValue: "mika"))
        XCTAssertEqual(finish.expression, ExpressionID(rawValue: "happy"))
        XCTAssertEqual(finish.text, "Good work.")
        XCTAssertEqual(finish.kind, .sceneLine)
        XCTAssertTrue(finish.blocking)
        XCTAssertEqual(selected.state?.flags[FlagID(rawValue: "met_today")], true)
        XCTAssertEqual(selected.state?.node, NodeID(rawValue: "finish"))

        let outro = runtime.advance(from: try XCTUnwrap(selected.state))
        guard case let .line(outroPresentation, _) = outro.step else { return XCTFail("Expected outro line, got \(outro.step)") }
        XCTAssertEqual(outroPresentation.text, "See you soon.")
        XCTAssertEqual(outro.state?.scene, SceneID(rawValue: "outro"))
        XCTAssertEqual(outro.state?.node, NodeID(rawValue: "outro_line"))
        let ended = runtime.advance(from: try XCTUnwrap(outro.state))
        XCTAssertEqual(ended.step, .end)
        XCTAssertTrue(try XCTUnwrap(ended.state).isEnded)
        XCTAssertEqual(runtime.advance(from: try XCTUnwrap(ended.state)).step, .end)
    }

    func testChoiceVisibilityHiddenAndUnknownChoiceLeaveStateUnchanged() throws {
        let runtime = NarrativeRuntime(script: try validatedFixture(), facts: NarrativeFacts(values: [FactID(rawValue: "workouts_this_week"): 2]))
        let opening = runtime.start(scene: SceneID(rawValue: "opening"))
        let choice = runtime.advance(from: try XCTUnwrap(opening.state))
        guard case let .choice(_, options) = choice.step else { return XCTFail("Expected choice") }
        XCTAssertEqual(options.map(\.id), [ChoiceID(rawValue: "skip")])
        let state = try XCTUnwrap(choice.state)

        let hidden = runtime.choose(ChoiceID(rawValue: "continue"), from: state)
        XCTAssertEqual(hidden.step.issueCode, .invalidChoice)
        XCTAssertEqual(hidden.step.issuePath, "runtime")
        XCTAssertEqual(hidden.state, state)

        let unknown = runtime.choose(ChoiceID(rawValue: "not_declared"), from: state)
        XCTAssertEqual(unknown.step.issueCode, .invalidChoice)
        XCTAssertEqual(unknown.step.issuePath, "runtime")
        XCTAssertEqual(unknown.state, state)
    }

    func testUnknownFactsEvaluateFalse() throws {
        let json = NarrativeFixtures.twoSceneScript.replacingOccurrences(of: "\"fact\": \"workouts_this_week\"", with: "\"fact\": \"custom_unknown\"")
        let loaded = NarrativeFixtures.load(json)
        let validated = try XCTUnwrap(loaded.validatedScript)
        let runtime = NarrativeRuntime(script: validated, facts: NarrativeFacts(values: [:]))
        let opening = runtime.start(scene: SceneID(rawValue: "opening"))
        let choice = runtime.advance(from: try XCTUnwrap(opening.state))
        guard case let .choice(_, visible) = choice.step else { return XCTFail("Expected choice") }
        XCTAssertFalse(visible.contains { $0.id == ChoiceID(rawValue: "continue") })
    }

    func testBranchAndJumpCyclesStopAtLimitWithoutChangingInputState() throws {
        let loopJSON = NarrativeFixtures.script(nodes: "[{\"type\":\"branch\",\"id\":\"entry\",\"condition\":{\"type\":\"flagIsSet\",\"flag\":\"seen\"},\"thenTarget\":\"entry\",\"elseTarget\":\"entry\"},{\"type\":\"end\",\"id\":\"unreachable\"}]", flags: "[{\"id\":\"seen\",\"scope\":\"loop\"}]")
        let validated = try XCTUnwrap(NarrativeFixtures.load(loopJSON).validatedScript)
        let runtime = NarrativeRuntime(script: validated, automaticStepLimit: 5)
        let result = runtime.start(scene: SceneID(rawValue: "scene"))
        XCTAssertEqual(result.step.issueCode, .stepLimitExceeded)
        XCTAssertEqual(result.state, NarrativeState(scene: SceneID(rawValue: "scene"), node: NodeID(rawValue: "entry"), flags: [:]))

        let jumpJSON = NarrativeFixtures.script(nodes: "[{\"type\":\"jump\",\"id\":\"entry\",\"target\":{\"scene\":\"scene\",\"node\":\"entry\"}},{\"type\":\"end\",\"id\":\"unreachable\"}]")
        let jumpScript = try XCTUnwrap(NarrativeFixtures.load(jumpJSON).validatedScript)
        let jumpResult = NarrativeRuntime(script: jumpScript, automaticStepLimit: 3).start(scene: SceneID(rawValue: "scene"))
        XCTAssertEqual(jumpResult.step.issueCode, .stepLimitExceeded)
    }

    func testExpressionAndAudioFallbacksAreRecordedOnStep() throws {
        let target = "\"id\": \"intro\", \"speaker\": \"mika\", \"expression\": \"calm\""
        let replacement = "\"id\": \"intro\", \"speaker\": \"mika\", \"expression\": \"happy\""
        let json = NarrativeFixtures.twoSceneScript.replacingOccurrences(of: target, with: replacement, range: NarrativeFixtures.twoSceneScript.range(of: target))
        let manifest = NarrativeAssetManifest(portraitsAndExpressions: [AssetRef(rawValue: "mika_portrait"), AssetRef(rawValue: "mika_calm")], audio: [])
        let validated = try XCTUnwrap(NarrativeFixtures.load(json, manifest: manifest).validatedScript)
        let result = NarrativeRuntime(script: validated, assetManifest: manifest).start(scene: SceneID(rawValue: "opening"))
        guard case let .line(presentation, fallbacks) = result.step else { return XCTFail("Expected line") }
        XCTAssertEqual(presentation.expression, ExpressionID(rawValue: "calm"))
        XCTAssertEqual(presentation.expressionAsset, AssetRef(rawValue: "mika_calm"))
        XCTAssertNil(presentation.audio)
        XCTAssertTrue(fallbacks.contains(.expressionAssetMissing(requested: ExpressionID(rawValue: "happy"), used: ExpressionID(rawValue: "calm"), asset: AssetRef(rawValue: "mika_happy"))))
        XCTAssertTrue(fallbacks.contains(.audioAssetMissing(dropped: AudioRef(rawValue: "hello"))))
    }

    func testCheckpointRoundTripAndInvalidRestore() throws {
        let runtime = NarrativeRuntime(script: try validatedFixture())
        let opening = runtime.start(scene: SceneID(rawValue: "opening"))
        let choice = runtime.advance(from: try XCTUnwrap(opening.state))
        let checkpoint = try XCTUnwrap(choice.checkpoint)
        let encoded = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(NarrativeCheckpoint.self, from: encoded)
        XCTAssertEqual(decoded, checkpoint)
        let restored = runtime.restore(decoded)
        XCTAssertTrue(restored.isValid)
        XCTAssertEqual(restored.state?.scene, checkpoint.scene)
        XCTAssertEqual(restored.state?.node, checkpoint.node)
        XCTAssertEqual(restored.state?.flags, checkpoint.flags)

        let invalid = NarrativeCheckpoint(id: CheckpointID(rawValue: "unknown"), scene: checkpoint.scene, node: checkpoint.node, flags: checkpoint.flags)
        let rejected = runtime.restore(invalid)
        XCTAssertNil(rejected.state)
        XCTAssertEqual(rejected.issues.first?.code, .invalidCheckpoint)
    }

    func testLoopMemoryResetKeepsPlayerFlags() throws {
        let runtime = NarrativeRuntime(script: try validatedFixture())
        let state = NarrativeState(
            scene: SceneID(rawValue: "opening"),
            node: NodeID(rawValue: "intro"),
            flags: [FlagID(rawValue: "met_today"): true, FlagID(rawValue: "loop_seen"): true]
        )
        let reset = state.resettingLoopMemory(in: try validatedFixture().script)
        XCTAssertEqual(reset.flags[FlagID(rawValue: "met_today")], true)
        XCTAssertNil(reset.flags[FlagID(rawValue: "loop_seen")])
        XCTAssertEqual(runtime.advance(from: reset).state?.flags[FlagID(rawValue: "met_today")], true)
    }

    func testIdenticalInputsProduceIdenticalStepsAndStates() throws {
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
        let firstLine = first.choose(ChoiceID(rawValue: "continue"), from: try XCTUnwrap(firstChoice.state))
        let secondLine = second.choose(ChoiceID(rawValue: "continue"), from: try XCTUnwrap(secondChoice.state))
        XCTAssertEqual(firstLine, secondLine)
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
