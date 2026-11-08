import Foundation
import XCTest
@testable import Narrative

final class NarrativeValidationReviewTests: XCTestCase {
    func testSyntacticallyValidWrongTopLevelShapeIsADecodingIssue() {
        assertIssue(.decoding, "$", json: "[]")
    }

    func testIdentifierSyntaxRejectsUppercaseWhitespaceUnicodePunctuationAndInvalidReferences() {
        let cases: [(String, String, String)] = [
            ("\"id\": \"morning_story\"", "\"id\": \"Morning_story\"", "id"),
            ("\"id\": \"intro\"", "\"id\": \"bad node\"", "scenes[0].nodes[0].id"),
            ("\"id\": \"mika\"", "\"id\": \"mïka\"", "characters[0].id"),
            ("\"id\": \"outro\"", "\"id\": \"Outro\"", "scenes[1].id"),
            ("\"id\": \"intro\", \"speaker\": \"mika\", \"expression\": \"calm\"", "\"id\": \"intro\", \"speaker\": \"mika\", \"expression\": \"CALM\"", "scenes[0].nodes[0].expression"),
            ("\"portrait\": \"mika_portrait\"", "\"portrait\": \"mika/portrait\"", "characters[0].portrait"),
            ("\"audio\": \"hello\"", "\"audio\": \"hello!\"", "scenes[0].nodes[0].audio"),
            ("\"id\": \"continue\"", "\"id\": \"Continue\"", "scenes[0].nodes[2].options[0].id"),
            ("\"id\": \"met_today\"", "\"id\": \"Met_today\"", "flags[0].id")
        ]
        for (source, replacement, path) in cases {
            let json = replacingFirst(source, with: replacement, in: NarrativeFixtures.twoSceneScript)
            assertIssue(.invalidIDSyntax, path, json: json)
        }
    }

    func testValidIdentifierPunctuationAndDigitsAreAccepted() {
        let json = #"{"version":1,"id":"a0._-z","characters":[],"flags":[],"scenes":[{"id":"scene-1._0","entryNode":"node-9._a","nodes":[{"type":"end","id":"node-9._a"}]}]}"#
        let result = NarrativeFixtures.load(json)
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")
        XCTAssertNotNil(result.validatedScript)
    }

    func testInvalidFactAndCheckpointIdentifiersAreRejected() {
        let invalidFact = NarrativeFixtures.script(nodes: #"[{"type":"branch","id":"entry","condition":{"type":"fact","fact":"bad fact","comparison":"equal","value":1},"thenTarget":"done","elseTarget":"done"},{"type":"end","id":"done"}]"#)
        assertIssue(.invalidIDSyntax, "scenes[0].nodes[0].condition.fact", json: invalidFact)

        let invalidCheckpoint = NarrativeFixtures.script(nodes: #"[{"type":"checkpoint","id":"entry","checkpointID":"bad!"},{"type":"end","id":"done"}]"#)
        assertIssue(.invalidIDSyntax, "scenes[0].nodes[0].checkpointID", json: invalidCheckpoint)

        let invalidJumpScene = NarrativeFixtures.script(nodes: #"[{"type":"jump","id":"entry","target":{"scene":"bad scene","node":"done"}},{"type":"end","id":"done"}]"#)
        assertIssue(.invalidIDSyntax, "scenes[0].nodes[0].target.scene", json: invalidJumpScene)

        let invalidJumpNode = NarrativeFixtures.script(nodes: #"[{"type":"jump","id":"entry","target":{"scene":"scene","node":"Bad"}},{"type":"end","id":"done"}]"#)
        assertIssue(.invalidIDSyntax, "scenes[0].nodes[0].target.node", json: invalidJumpNode)
    }

    func testEveryDuplicateIDNamespaceHasAnExactPath() {
        let character = #"{"id":"mika","allowedExpressions":["calm"],"defaultExpression":"calm","expressionAssets":[]}"#
        let duplicateCharacters = NarrativeFixtures.script(nodes: #"[{"type":"end","id":"entry"}]"#, characters: "[\(character),\(character)]")
        assertIssue(.duplicateID, "characters[1].id", json: duplicateCharacters)

        let flag = #"{"id":"remembered","scope":"player"}"#
        let duplicateFlags = NarrativeFixtures.script(nodes: #"[{"type":"end","id":"entry"}]"#, flags: "[\(flag),\(flag)]")
        assertIssue(.duplicateID, "flags[1].id", json: duplicateFlags)

        let duplicateScenes = #"{"version":1,"id":"s","characters":[],"flags":[],"scenes":[{"id":"scene","entryNode":"first","nodes":[{"type":"end","id":"first"}]},{"id":"scene","entryNode":"second","nodes":[{"type":"end","id":"second"}]}]}"#
        assertIssue(.duplicateID, "scenes[1].id", json: duplicateScenes)

        let duplicateNodes = NarrativeFixtures.script(nodes: #"[{"type":"end","id":"entry"},{"type":"end","id":"entry"}]"#)
        assertIssue(.duplicateID, "scenes[0].nodes[1].id", json: duplicateNodes)

        let duplicateCheckpoints = NarrativeFixtures.script(nodes: #"[{"type":"checkpoint","id":"entry","checkpointID":"same"},{"type":"checkpoint","id":"second","checkpointID":"same"},{"type":"end","id":"done"}]"#)
        assertIssue(.duplicateID, "scenes[0].nodes[1].checkpointID", json: duplicateCheckpoints)

        let duplicateMapping = #"[{"id":"mika","allowedExpressions":["calm"],"defaultExpression":"calm","expressionAssets":[{"expression":"calm","asset":"one"},{"expression":"calm","asset":"two"}]}]"#
        let duplicateExpressionAssets = NarrativeFixtures.script(nodes: #"[{"type":"end","id":"entry"}]"#, characters: duplicateMapping)
        assertIssue(.duplicateID, "characters[0].expressionAssets[1].expression", json: duplicateExpressionAssets)
    }

    func testMissingSceneEntryJumpAndBranchTargetsHaveExactPaths() {
        let missingEntry = NarrativeFixtures.script(nodes: #"[{"type":"end","id":"entry"}]"#)
            .replacingOccurrences(of: "\"entryNode\":\"entry\"", with: "\"entryNode\":\"absent\"")
        assertIssue(.missingNode, "scenes[0].entryNode", json: missingEntry)

        let missingJumpNode = NarrativeFixtures.script(nodes: #"[{"type":"jump","id":"entry","target":{"scene":"scene","node":"absent"}},{"type":"end","id":"done"}]"#)
        assertIssue(.missingNode, "scenes[0].nodes[0].target.node", json: missingJumpNode)

        let missingBothBranchTargets = NarrativeFixtures.script(nodes: #"[{"type":"branch","id":"entry","condition":{"type":"fact","fact":"workouts_this_week","comparison":"equal","value":1},"thenTarget":null,"elseTarget":null},{"type":"end","id":"done"}]"#)
        assertIssue(.missingBranchTarget, "scenes[0].nodes[0].thenTarget", json: missingBothBranchTargets)
        assertIssue(.missingBranchTarget, "scenes[0].nodes[0].elseTarget", json: missingBothBranchTargets)

        let nonexistentElse = NarrativeFixtures.script(nodes: #"[{"type":"branch","id":"entry","condition":{"type":"fact","fact":"workouts_this_week","comparison":"equal","value":1},"thenTarget":"done","elseTarget":"absent"},{"type":"end","id":"done"}]"#)
        assertIssue(.missingBranchTarget, "scenes[0].nodes[0].elseTarget", json: nonexistentElse)
    }

    func testUndeclaredFlagsInDirectAndNestedConditionsAreReported() {
        let directCondition = NarrativeFixtures.script(nodes: #"[{"type":"choice","id":"entry","prompt":"Pick","options":[{"id":"yes","text":"Yes","condition":{"type":"flagIsUnset","flag":"missing"},"target":"done"},{"id":"no","text":"No","target":"done"}]},{"type":"end","id":"done"}]"#)
        assertIssue(.undeclaredFlag, "scenes[0].nodes[0].options[0].condition.flag", json: directCondition)

        let nestedCondition = NarrativeFixtures.script(nodes: #"[{"type":"choice","id":"entry","prompt":"Pick","options":[{"id":"yes","text":"Yes","condition":{"type":"all","conditions":[{"type":"not","condition":{"type":"flagEquals","flag":"missing","value":true}}]},"target":"done"},{"id":"no","text":"No","target":"done"}]},{"type":"end","id":"done"}]"#)
        assertIssue(.undeclaredFlag, "scenes[0].nodes[0].options[0].condition.conditions[0].condition.flag", json: nestedCondition)
    }

    func testIndependentErrorsAreAllReturnedInStableOrderAndPreventRuntimeToken() {
        let json = #"{"version":1,"id":"multi_error","characters":[{"id":"mika","allowedExpressions":["calm"],"defaultExpression":"happy","expressionAssets":[]}],"flags":[],"scenes":[{"id":"scene","entryNode":"missing_entry","nodes":[{"type":"line","id":"line","speaker":"ghost","expression":"calm","text":"Hello."},{"type":"end","id":"done"}]}]}"#
        let result = NarrativeFixtures.load(json)
        XCTAssertNil(result.validatedScript)
        let errors = result.issues.filter { $0.severity == .error }
        XCTAssertEqual(errors.map(\.code), [.disallowedExpression, .unknownSpeaker, .missingNode])
        XCTAssertEqual(errors.map(\.path), ["characters[0].defaultExpression", "scenes[0].nodes[0].speaker", "scenes[0].entryNode"])
    }

    func testCalloutFactoryContractAndAutomaticDismissalValidation() throws {
        let callout = CompanionCallout.make(
            character: CharacterID(rawValue: "mika"),
            expression: ExpressionID(rawValue: "calm"),
            cueID: CueID(rawValue: "stand_tall"),
            text: "Lift your chest."
        )
        XCTAssertEqual(callout.character, CharacterID(rawValue: "mika"))
        XCTAssertEqual(callout.expression, ExpressionID(rawValue: "calm"))
        XCTAssertEqual(callout.text, "Lift your chest.")
        XCTAssertEqual(callout.cueID, CueID(rawValue: "stand_tall"))
        XCTAssertEqual(callout.kind, .callout)
        XCTAssertFalse(callout.blocking)
        XCTAssertEqual(callout.dismissal, .auto(seconds: 4))

        let invalidDurations: [Double] = [0, -1, .nan, .infinity]
        for seconds in invalidDurations {
            let presentation = CompanionPresentation(character: callout.character, expression: callout.expression, text: callout.text, kind: .sceneLine, blocking: true, dismissal: .auto(seconds: seconds))
            let issue = try XCTUnwrap(NarrativeScriptValidator.validate(presentation: presentation).first)
            XCTAssertEqual(issue.code, .invalidDismissal)
            XCTAssertEqual(issue.path, "presentation.dismissal.seconds")
        }
        let valid = CompanionPresentation(character: callout.character, expression: callout.expression, text: callout.text, kind: .sceneLine, blocking: true, dismissal: .auto(seconds: 1.25))
        XCTAssertFalse(NarrativeScriptValidator.validate(presentation: valid).contains { $0.code == .invalidDismissal })
    }

    private func assertIssue(_ code: NarrativeIssueCode, _ path: String, json: String) {
        let result = NarrativeFixtures.load(json)
        let issue = result.issues.first { $0.code == code && $0.path == path }
        XCTAssertNotNil(issue, "Missing \(code.rawValue) at \(path): \(result.issues)")
        XCTAssertEqual(issue?.severity, .error)
        XCTAssertNil(result.validatedScript, "Error \(code.rawValue) at \(path) must prevent runtime construction.")
    }

    private func replacingFirst(_ target: String, with replacement: String, in source: String) -> String {
        guard let range = source.range(of: target) else {
            XCTFail("Fixture did not contain: \(target)")
            return source
        }
        return source.replacingCharacters(in: range, with: replacement)
    }
}
