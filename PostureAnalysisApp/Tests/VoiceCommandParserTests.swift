import XCTest
@testable import PostureAnalysisApp

final class VoiceCommandParserTests: XCTestCase {
    private let parser = VoiceCommandParser(exercises: [ShoulderPressExercise.definition()])

    func testCommonPhrasesWithFillers() {
        XCTAssertEqual(parser.parse("Okay coach, pause")?.command, .pause)
        XCTAssertEqual(parser.parse("Let's go!")?.command, .start)
        XCTAssertEqual(parser.parse("how many reps")?.command, .repCount)
        XCTAssertEqual(parser.parse("Stop workout")?.command, .pause, "Stopping pauses; ending needs \"end workout\".")
        XCTAssertEqual(parser.parse("never mind")?.command, .cancel)
        XCTAssertNil(parser.parse("nice weather today"))
    }

    func testLongestPhraseWins() {
        XCTAssertEqual(parser.parse("start over")?.command, .restartSet)
        XCTAssertEqual(parser.parse("end set")?.command, .nextSet)
        XCTAssertEqual(parser.parse("end the workout")?.command, .endWorkout)
    }

    func testDestructiveCommandsMustBeNearlyTheWholeUtterance() {
        XCTAssertEqual(parser.parse("please end the workout")?.command, .endWorkout)
        XCTAssertEqual(parser.parse("okay restart this set now")?.command, .restartSet)
        XCTAssertNil(parser.parse("I don't think I want to end workout yet"))
        XCTAssertNil(parser.parse("my friend said to restart the set every time"))
    }

    func testAmbiguousPrefixWaitsForMore() {
        XCTAssertEqual(parser.parse("start")?.isPrefixOfLongerPhrase, true, "Could become \"start over\".")
        XCTAssertEqual(parser.parse("start over")?.isPrefixOfLongerPhrase, false)
        XCTAssertEqual(parser.parse("pause")?.isPrefixOfLongerPhrase, false)
        XCTAssertEqual(parser.parse("restart")?.isPrefixOfLongerPhrase, false, "Longer forms mean the same thing.")
    }

    func testHelpOpensAndClosesByVoice() {
        XCTAssertEqual(parser.parse("What can I say?")?.command, .help)
        XCTAssertEqual(parser.parse("show voice commands")?.command, .help)
        XCTAssertEqual(parser.parse("okay, close")?.command, .closeHelp)
        XCTAssertEqual(parser.parse("What's my count")?.command, .repCount, "Display apostrophes still match.")
    }

    func testHelpListsEveryRecognizedPhraseOnce() {
        let exercises = [ShoulderPressExercise.definition()]
        let shown = VoiceCommandHelp.sections(exercises: exercises).flatMap(\.entries).flatMap { entry in
            [entry.title.lowercased()] + entry.alternates.map { $0.lowercased() }
        }
        for alias in VoiceCommandAlias.standard {
            XCTAssertEqual(shown.filter { $0 == alias.display.lowercased() }.count, 1, "\(alias.display) should appear once in help.")
        }
        for name in exercises.flatMap(\.voiceAliases) {
            XCTAssertTrue(shown.contains(name), "\(name) should appear in help.")
        }
    }

    func testSpokenWeights() {
        XCTAssertEqual(parser.parse("My weights are 17.5 pounds")?.command, .setWeight(.mass(17.5, .pounds)))
        XCTAssertEqual(parser.parse("my weights are seventeen point five pounds")?.command, .setWeight(.mass(17.5, .pounds)))
        XCTAssertEqual(parser.parse("add weight 8 kilograms")?.command, .setWeight(.mass(8, .kilograms)))
        XCTAssertEqual(parser.parse("my weights are twenty two and a half pounds")?.command, .setWeight(.mass(22.5, .pounds)))
        XCTAssertEqual(parser.parse("I'm using the red band")?.command, .setWeight(.band("Red band")))
        XCTAssertEqual(parser.parse("my weights are 17.5 pounds")?.isPrefixOfLongerPhrase, true, "Waits for the number to settle.")
        XCTAssertNil(parser.parse("I lost five pounds this month"), "Numbers outside a weight phrase never set one.")
        XCTAssertNil(parser.parse("my weights are seventeen"), "No unit yet.")
    }

    func testSoundCommands() {
        XCTAssertEqual(parser.parse("mute")?.command, .muteCoach)
        XCTAssertEqual(parser.parse("be quiet please")?.command, .muteCoach)
        XCTAssertEqual(parser.parse("unmute")?.command, .unmuteCoach)
        XCTAssertEqual(parser.parse("stop listening")?.command, .muteMicrophone)
        XCTAssertEqual(parser.parse("stop")?.command, .pause)
        XCTAssertEqual(parser.parse("stop")?.isPrefixOfLongerPhrase, true, "Could become \"stop listening\".")
        XCTAssertNil(parser.parse("I told him to be quiet about it"), "Muting must be said on its own.")
    }

    func testExerciseNamesSelectExercise() {
        XCTAssertEqual(parser.parse("switch to shoulder press")?.command, .selectExercise(.shoulderPress))
        XCTAssertEqual(parser.parse("let's do dumbbell press instead")?.command, .selectExercise(.shoulderPress))
        XCTAssertTrue(parser.vocabulary.contains("overhead press"))
    }
}
