import XCTest
@testable import PostureAnalysisApp

/// "Mark that" and "note, …" start a marker, with the words after the trigger as its note.
final class MarkerPhraseParserTests: XCTestCase {
    func testMarkThatAndFlagThatAnywhereStartAMarker() {
        XCTAssertEqual(MarkerPhraseParser.parse("Mark that"), .init(note: nil))
        XCTAssertEqual(MarkerPhraseParser.parse("okay flag that"), .init(note: nil))
        XCTAssertEqual(MarkerPhraseParser.parse("Mark that."), .init(note: nil))
        XCTAssertNil(MarkerPhraseParser.parse("pause"))
    }

    func testWordsAfterTheTriggerBecomeTheNoteAsHeard() {
        XCTAssertEqual(MarkerPhraseParser.parse("mark that, the rep should have counted")?.note, "the rep should have counted")
        XCTAssertEqual(MarkerPhraseParser.parse("Note: Left arm lagged.")?.note, "Left arm lagged")
        XCTAssertEqual(MarkerPhraseParser.parse("note wait 17")?.note, "wait 17")
        XCTAssertEqual(MarkerPhraseParser.parse("mark that mark that")?.note, "mark that", "The first trigger starts it.")
    }

    func testPunctuationWithoutSpacesStillSeparatesWords() {
        XCTAssertEqual(MarkerPhraseParser.parse("Note:pause didn't work")?.note, "pause didn't work")
        XCTAssertEqual(MarkerPhraseParser.parse("mark—that pause didn't work")?.note, "pause didn't work")
    }

    func testNoteCountsOnlyAsTheFirstWord() {
        XCTAssertNil(MarkerPhraseParser.parse("I should take note"))
        XCTAssertEqual(MarkerPhraseParser.parse("um, note"), .init(note: nil), "Fillers before it don't count.")
    }

    func testLongNotesAreCut() {
        let note = MarkerPhraseParser.parse("note " + String(repeating: "word ", count: 100))?.note
        XCTAssertEqual(note?.count, MarkerPhraseParser.maximumNoteLength)
    }

    func testTheVoiceCommandsListShowsMarkersOnlyWhileRecording() {
        let exercises = [ShoulderPressExercise.definition()]
        XCTAssertFalse(VoiceCommandHelp.sections(exercises: exercises).contains { $0.title == "Diagnostics" })
        let diagnostics = VoiceCommandHelp.sections(exercises: exercises, includesMarkers: true).first { $0.title == "Diagnostics" }
        XCTAssertEqual(diagnostics?.entries.map(\.title), ["Mark that"])
        for phrase in (diagnostics?.entries ?? []).flatMap({ [$0.title] + $0.alternates }) {
            XCTAssertNotNil(MarkerPhraseParser.parse(phrase), "\(phrase) doesn't mark")
        }
    }
}
