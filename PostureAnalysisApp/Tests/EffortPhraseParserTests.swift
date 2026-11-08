import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

final class EffortPhraseParserTests: XCTestCase {
    func testEveryPhraseMapsToItsEffort() {
        let expected: [(String, EffortFeedback)] = [
            ("too hard", .tooHard), ("too difficult", .tooHard), ("that was too hard", .tooHard),
            ("this is too hard", .tooHard), ("it's too hard", .tooHard),
            ("okay", .okay), ("ok", .okay), ("fine", .okay), ("good", .okay), ("that was okay", .okay),
            ("easy", .easy), ("too easy", .easy), ("that was easy", .easy)
        ]
        XCTAssertEqual(expected.count, EffortPhraseParser.aliases.count, "Every alias is covered here.")
        for (phrase, effort) in expected {
            XCTAssertEqual(EffortPhraseParser.parse(phrase)?.effort, effort, phrase)
        }
    }

    func testOkayWinsOverTheFillerRule() {
        let commands = VoiceCommandParser(exercises: ExerciseCatalog.all)
        // "okay" is a filler word to the command parser, so it never matches there; the effort parser must see it first.
        XCTAssertNil(commands.parse("okay"))
        XCTAssertNil(commands.parse("ok"))
        XCTAssertEqual(EffortPhraseParser.parse("okay")?.effort, .okay)
        XCTAssertEqual(EffortPhraseParser.parse("OK!")?.effort, .okay)
        XCTAssertEqual(EffortPhraseParser.parse("okay that was easy")?.effort, .easy,
                       "A leading filler doesn't hide the answer.")
    }

    func testCaseAndPunctuationAreIgnored() {
        XCTAssertEqual(EffortPhraseParser.parse("Too hard!")?.effort, .tooHard)
        XCTAssertEqual(EffortPhraseParser.parse("That was OKAY.")?.effort, .okay)
        XCTAssertEqual(EffortPhraseParser.parse("  easy  ")?.effort, .easy)
        XCTAssertEqual(EffortPhraseParser.parse("too hard")?.phrase, "too hard")
    }

    func testTheLongestPhraseWins() {
        XCTAssertEqual(EffortPhraseParser.parse("too easy")?.phrase, "too easy")
        XCTAssertEqual(EffortPhraseParser.parse("that was too hard")?.phrase, "that was too hard")
        XCTAssertEqual(EffortPhraseParser.parse("okay too hard")?.effort, .tooHard)
    }

    func testCommandsAndSkipAreNotEffortPhrases() {
        for phrase in ["skip", "skip exercise", "start", "next set", "pause", "done", "stop", "resume", "end workout",
                       "how many reps", "hard", "difficult", ""] {
            XCTAssertNil(EffortPhraseParser.parse(phrase), "\"\(phrase)\" is not an effort phrase.")
        }
    }

    func testPartialPhrasesWaitForTheirWords() {
        XCTAssertNil(EffortPhraseParser.parse("too"))
        XCTAssertNil(EffortPhraseParser.parse("that was"))
        XCTAssertNil(EffortPhraseParser.parse("that was too"))
    }

    func testOnlyPoliteFillersMayAccompanyAnAnswer() {
        XCTAssertEqual(EffortPhraseParser.parse("so um okay")?.effort, .okay)
        XCTAssertEqual(EffortPhraseParser.parse("yeah it was really easy")?.effort, .easy)
        XCTAssertEqual(EffortPhraseParser.parse("please coach okay")?.effort, .okay)
        XCTAssertNil(EffortPhraseParser.parse("honestly I think it was too hard for me"))
        XCTAssertNil(EffortPhraseParser.parse("the weather is fine today in the city"))
        XCTAssertNil(EffortPhraseParser.parse("I guess that was okay"), "Any other word means it isn't an answer.")
        XCTAssertNil(EffortPhraseParser.parse("good job"))
    }

    func testCommandBearingPhrasesAreNotAnswers() {
        for phrase in ["okay start", "okay end workout", "okay next set", "easy next exercise", "fine pause",
                       "okay lets go", "that was easy start over", "too hard end workout", "okay, done"] {
            XCTAssertNil(EffortPhraseParser.parse(phrase), "\"\(phrase)\" carries a command, so it isn't an answer.")
        }
    }

    func testNegatedAndMixedPhrasesAreNotAnswers() {
        for phrase in ["not easy", "not too hard", "that wasn't easy", "it isn't okay", "no that was easy",
                       "never easy", "not okay", "easy too hard", "too hard easy"] {
            XCTAssertNil(EffortPhraseParser.parse(phrase), "\"\(phrase)\" is negated or contradicts itself.")
        }
    }
}

/// The controller asks the effort parser first, and only while the card is open.
@MainActor
final class EffortVoiceRoutingTests: XCTestCase {
    func testAnEffortPhraseAnswersTheCardAndNeverRunsAsACommand() throws {
        let rig = makeRig()
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("okay")

        XCTAssertEqual(rig.efforts, [.okay])
        XCTAssertTrue(rig.commands.isEmpty, "A command parser that matches everything must not see an effort phrase.")
        XCTAssertEqual(rig.heard, ["okay"])
        XCTAssertEqual(rig.recognizer.restartCount, 1, "The utterance ends, so old words can't combine with new ones.")
    }

    func testEveryEffortAnswerReachesTheCard() {
        let rig = makeRig()
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("too hard")
        rig.recognizer.hear("that was easy")

        XCTAssertEqual(rig.efforts, [.tooHard, .easy])
        XCTAssertTrue(rig.commands.isEmpty)
    }

    func testWithoutAnOpenCardEffortPhrasesStayWithTheCommandParser() {
        let rig = makeRig()
        rig.controller.acceptsEffortFeedback = false

        rig.recognizer.hear("okay")

        XCTAssertTrue(rig.efforts.isEmpty)
        XCTAssertEqual(rig.commands, [.pause], "With no card open the transcript goes to the command parser as before.")
    }

    func testSkipAndOtherCommandsStillRunWhileTheCardIsOpen() {
        let rig = makeRig()
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("skip")

        XCTAssertTrue(rig.efforts.isEmpty)
        XCTAssertEqual(rig.commands, [.pause], "\"skip\" is not an effort phrase, so the command parser still decides.")
    }

    func testTheRealCommandParserNeverSeesOkayWhileTheCardIsOpen() {
        let rig = makeRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("okay")
        rig.recognizer.hear("start")

        XCTAssertEqual(rig.efforts, [.okay])
        XCTAssertEqual(rig.commands, [.start], "Commands that aren't effort phrases still work with the card open.")
    }

    func testAStreamingOkayThatBecomesACommandStartsTheSetAndNeverAnswersTheCard() {
        // Revert check: answering on the first partial "okay" closes the card before "okay start" arrives.
        let rig = makeRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("okay", final: false)
        XCTAssertTrue(rig.efforts.isEmpty, "A partial \"okay\" could still become a command, so it waits.")
        rig.advance(0.3)
        rig.recognizer.hear("okay start", final: false)
        rig.advance(0.8)

        XCTAssertTrue(rig.efforts.isEmpty, "\"okay start\" never rates the card.")
        XCTAssertEqual(rig.commands, [.start], "The real parser still starts the next set.")
    }

    func testACompleteOkayEndWorkoutRunsTheCommandAndLeavesTheCardOpen() {
        let rig = makeRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("okay end workout", final: true)

        XCTAssertTrue(rig.efforts.isEmpty)
        XCTAssertEqual(rig.commands, [.endWorkout])
    }

    func testAStandaloneStreamingOkayAnswersOnceItSettles() {
        let rig = makeRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("okay", final: false)
        rig.advance(0.3)
        XCTAssertTrue(rig.efforts.isEmpty, "Not settled yet.")
        rig.advance(0.5)

        XCTAssertEqual(rig.efforts, [.okay])
        XCTAssertTrue(rig.commands.isEmpty)
        XCTAssertEqual(rig.heard, ["okay"])
        rig.advance(2)
        XCTAssertEqual(rig.efforts, [.okay], "It answers once.")
    }

    func testAPartialAnswerThatThenGoesFinalAnswersOnce() {
        let rig = makeRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("easy", final: false)
        rig.recognizer.hear("easy", final: true)
        rig.advance(2)

        XCTAssertEqual(rig.efforts, [.easy])
    }

    func testAnAnswerPendingWhenTheCardClosesIsDropped() {
        let rig = makeRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsEffortFeedback = true
        rig.recognizer.hear("okay", final: false)

        rig.controller.acceptsEffortFeedback = false
        rig.advance(2)

        XCTAssertTrue(rig.efforts.isEmpty)
        XCTAssertTrue(rig.commands.isEmpty)
    }

    func testNegatedRatingsNeverAnswerAndReachTheRealParserHarmlessly() {
        let rig = makeRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsEffortFeedback = true

        for phrase in ["not easy", "that wasn't easy", "not too hard", "it isn't okay"] {
            rig.recognizer.hear(phrase, final: true)
        }
        rig.recognizer.hear("not easy", final: false)
        rig.advance(2)

        XCTAssertTrue(rig.efforts.isEmpty, "A negated rating doesn't answer the card.")
        XCTAssertTrue(rig.commands.isEmpty, "And it isn't a command either.")
    }

    // MARK: - Rig

    @MainActor
    private struct Rig {
        let controller: WorkoutVoiceController
        let recognizer: ScriptedRecognizer
        let scheduler: ManualScheduler
        let box: Box

        var efforts: [EffortFeedback] { box.efforts }
        var commands: [WorkoutCommand] { box.commands }
        var heard: [String] { box.heard }

        /// Time passes, so a transcript can settle.
        func advance(_ seconds: TimeInterval) { scheduler.advance(by: seconds) }
    }

    private final class Box {
        var efforts: [EffortFeedback] = []
        var commands: [WorkoutCommand] = []
        var heard: [String] = []
    }

    private func makeRig(parser: any VoiceCommandParsing = EveryPhraseIsPause()) -> Rig {
        let recognizer = ScriptedRecognizer()
        let clock = ManualClock(now: 10)
        let scheduler = ManualScheduler(clock: clock)
        let controller = WorkoutVoiceController(recognizer: recognizer, parser: parser, permissions: GrantedPermissions(),
                                                audio: FakeAudioSession(), clock: { clock.now },
                                                scheduler: scheduler)
        let box = Box()
        controller.onEffort = { box.efforts.append($0) }
        controller.onCommand = { box.commands.append($0) }
        controller.onHeard = { box.heard.append($0) }
        controller.enable()
        return Rig(controller: controller, recognizer: recognizer, scheduler: scheduler, box: box)
    }
}

/// A command parser that turns every transcript into Pause, so any effort phrase that reaches it is visible.
private struct EveryPhraseIsPause: VoiceCommandParsing {
    var vocabulary: [String] { [] }

    func parse(_ transcript: String) -> VoiceCommandMatch? {
        VoiceCommandMatch(command: .pause, phrase: transcript, isPrefixOfLongerPhrase: false)
    }
}

private final class ScriptedRecognizer: SpeechRecognizing {
    var onTranscript: ((String, Bool) -> Void)?
    var onStateChanged: ((SpeechRecognizerState) -> Void)?
    private(set) var restartCount = 0

    func setContextualStrings(_ strings: [String]) {}
    func start() {}
    func stop() {}
    func restartTask() { restartCount += 1 }
    func reconfigureInput() {}
    func rebuild() {}

    /// A transcript the recognizer reports. A final one runs a match at once; a partial one is still streaming.
    func hear(_ text: String, final: Bool = true) {
        onTranscript?(text, final)
    }
}

@MainActor
private struct GrantedPermissions: VoicePermissionProviding {
    var microphone: VoicePermissionStatus { .granted }
    var speechRecognition: VoicePermissionStatus { .granted }
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
    func requestSpeechRecognition(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
}
