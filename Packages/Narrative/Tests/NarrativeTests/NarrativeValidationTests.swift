import Foundation
import XCTest
@testable import Narrative

final class NarrativeValidationTests: XCTestCase {
    func testValidTwoSceneFixtureHasChoiceBranchCheckpointAndEnd() throws {
        let result = NarrativeFixtures.load(NarrativeFixtures.twoSceneScript)
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")
        let validated = try XCTUnwrap(result.validatedScript)
        XCTAssertEqual(validated.script.scenes.count, 2)
        XCTAssertTrue(validated.script.scenes.flatMap(\.nodes).contains { if case .choice = $0 { true } else { false } })
        XCTAssertTrue(validated.script.scenes.flatMap(\.nodes).contains { if case .branch = $0 { true } else { false } })
        XCTAssertTrue(validated.script.scenes.flatMap(\.nodes).contains { if case .checkpoint = $0 { true } else { false } })
        XCTAssertTrue(validated.script.scenes.flatMap(\.nodes).contains { if case .end = $0 { true } else { false } })
    }

    func testEveryValidationIssueCodeAndPath() {
        assertIssue(.decoding, "$", json: "{")

        let unsupported = NarrativeFixtures.twoSceneScript.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")
        assertIssue(.unsupportedVersion, "version", json: unsupported)

        let invalidID = NarrativeFixtures.twoSceneScript.replacingOccurrences(of: "\"id\": \"morning_story\"", with: "\"id\": \"\"", range: NarrativeFixtures.twoSceneScript.range(of: "\"id\": \"morning_story\""))
        assertIssue(.invalidIDSyntax, "id", json: invalidID)

        let duplicateExpression = NarrativeFixtures.twoSceneScript.replacingOccurrences(of: "\"allowedExpressions\": [\"calm\", \"happy\"]", with: "\"allowedExpressions\": [\"calm\", \"calm\"]")
        assertIssue(.duplicateID, "characters[0].allowedExpressions[1]", json: duplicateExpression)

        let unknownSpeaker = replacingFirst("\"speaker\": \"mika\"", with: "\"speaker\": \"nobody\"", in: NarrativeFixtures.twoSceneScript)
        assertIssue(.unknownSpeaker, "scenes[0].nodes[0].speaker", json: unknownSpeaker)

        let disallowedExpression = replacingFirst("\"id\": \"intro\", \"speaker\": \"mika\", \"expression\": \"calm\"", with: "\"id\": \"intro\", \"speaker\": \"mika\", \"expression\": \"angry\"", in: NarrativeFixtures.twoSceneScript)
        assertIssue(.disallowedExpression, "scenes[0].nodes[0].expression", json: disallowedExpression)

        let missingScene = replacingFirst("\"scene\": \"outro\"", with: "\"scene\": \"missing\"", in: NarrativeFixtures.twoSceneScript)
        assertIssue(.missingScene, "scenes[0].nodes[6].target.scene", json: missingScene)

        let missingNode = replacingFirst("\"target\": \"check\"", with: "\"target\": \"missing\"", in: NarrativeFixtures.twoSceneScript)
        assertIssue(.missingNode, "scenes[0].nodes[2].options[0].target", json: missingNode)

        let missingBranch = replacingFirst("\"thenTarget\": \"finish\"", with: "\"thenTarget\": \"missing\"", in: NarrativeFixtures.twoSceneScript)
        assertIssue(.missingBranchTarget, "scenes[0].nodes[3].thenTarget", json: missingBranch)

        let noOptions = NarrativeFixtures.script(nodes: "[{\"type\":\"choice\",\"id\":\"entry\",\"prompt\":\"Pick\",\"options\":[]},{\"type\":\"end\",\"id\":\"done\"}]")
        assertIssue(.choiceHasNoOptions, "scenes[0].nodes[0].options", json: noOptions)

        let duplicateOptions = NarrativeFixtures.script(nodes: "[{\"type\":\"choice\",\"id\":\"entry\",\"prompt\":\"Pick\",\"options\":[{\"id\":\"yes\",\"text\":\"Yes\",\"target\":\"done\"},{\"id\":\"yes\",\"text\":\"No\",\"target\":\"done\"}]},{\"type\":\"end\",\"id\":\"done\"}]")
        assertIssue(.duplicateOptionID, "scenes[0].nodes[0].options[1].id", json: duplicateOptions)

        let noTarget = NarrativeFixtures.script(nodes: "[{\"type\":\"choice\",\"id\":\"entry\",\"prompt\":\"Pick\",\"options\":[{\"id\":\"yes\",\"text\":\"Yes\"}]},{\"type\":\"end\",\"id\":\"done\"}]")
        assertIssue(.optionMissingTarget, "scenes[0].nodes[0].options[0].target", json: noTarget)

        let undeclaredFlag = NarrativeFixtures.script(nodes: "[{\"type\":\"setFlag\",\"id\":\"entry\",\"flag\":\"absent\",\"value\":true},{\"type\":\"end\",\"id\":\"done\"}]")
        assertIssue(.undeclaredFlag, "scenes[0].nodes[0].flag", json: undeclaredFlag)

        let unknownFact = replacingFirst("\"fact\": \"workouts_this_week\"", with: "\"fact\": \"unknown_fact\"", in: NarrativeFixtures.twoSceneScript)
        assertIssue(.unknownFact, "scenes[0].nodes[2].options[0].condition.fact", json: unknownFact, severity: .warning)

        let unreachable = NarrativeFixtures.script(nodes: "[{\"type\":\"end\",\"id\":\"entry\"},{\"type\":\"end\",\"id\":\"orphan\"}]")
        assertIssue(.unreachableNode, "scenes[0].nodes[1]", json: unreachable, severity: .warning)

        let emptyManifest = NarrativeAssetManifest(portraitsAndExpressions: [], audio: [])
        assertIssue(.missingPortraitAsset, "characters[0].portrait", json: NarrativeFixtures.twoSceneScript, manifest: emptyManifest, severity: .warning)
        assertIssue(.missingExpressionAsset, "characters[0].expressionAssets[0].asset", json: NarrativeFixtures.twoSceneScript, manifest: emptyManifest, severity: .warning)
        assertIssue(.missingAudioAsset, "scenes[0].nodes[0].audio", json: NarrativeFixtures.twoSceneScript, manifest: emptyManifest, severity: .warning)
    }

    func testUnknownFactIsAWarningAndDoesNotPreventValidatedRuntime() throws {
        let json = replacingFirst("\"fact\": \"workouts_this_week\"", with: "\"fact\": \"unknown_fact\"", in: NarrativeFixtures.twoSceneScript)
        let result = NarrativeFixtures.load(json)
        XCTAssertNotNil(result.validatedScript)
        let issue = try XCTUnwrap(result.issues.first(where: { $0.code == .unknownFact }))
        XCTAssertEqual(issue.severity, .warning)
    }

    func testBlockingCalloutIsRejectedAndFactoryCreatesNonBlockingPresentation() throws {
        let callout = CompanionCallout.make(character: CharacterID(rawValue: "mika"), expression: ExpressionID(rawValue: "calm"), cueID: CueID(rawValue: "stand_tall"), text: "Lift your chest.")
        XCTAssertEqual(callout.character, CharacterID(rawValue: "mika"))
        XCTAssertEqual(callout.expression, ExpressionID(rawValue: "calm"))
        XCTAssertEqual(callout.text, "Lift your chest.")
        XCTAssertEqual(callout.cueID, CueID(rawValue: "stand_tall"))
        XCTAssertEqual(callout.kind, .callout)
        XCTAssertFalse(callout.blocking)
        XCTAssertEqual(callout.dismissal, .auto(seconds: 4))
        XCTAssertTrue(NarrativeScriptValidator.validate(presentation: callout).isEmpty)

        let blocked = CompanionPresentation(character: CharacterID(rawValue: "mika"), expression: ExpressionID(rawValue: "calm"), text: "Lift your chest.", kind: .callout, blocking: true, dismissal: .tap)
        let issue = try XCTUnwrap(NarrativeScriptValidator.validate(presentation: blocked).first)
        XCTAssertEqual(issue.code, .blockingCallout)
        XCTAssertEqual(issue.path, "presentation.blocking")
    }

    private func assertIssue(
        _ code: NarrativeIssueCode,
        _ path: String,
        json: String,
        manifest: NarrativeAssetManifest? = nil,
        severity: NarrativeIssueSeverity = .error
    ) {
        let result = NarrativeFixtures.load(json, manifest: manifest)
        let issue = result.issues.first { $0.code == code && $0.path == path }
        XCTAssertNotNil(issue, "Missing \(code.rawValue) at \(path): \(result.issues)")
        XCTAssertEqual(issue?.severity, severity)
        XCTAssertEqual(result.validatedScript == nil, severity == .error, "Unexpected validation token state for \(code.rawValue) at \(path).")
    }

    private func replacingFirst(_ target: String, with replacement: String, in source: String) -> String {
        guard let range = source.range(of: target) else {
            XCTFail("Fixture did not contain: \(target)")
            return source
        }
        return source.replacingCharacters(in: range, with: replacement)
    }
}
