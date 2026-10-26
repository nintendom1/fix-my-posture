import XCTest
@testable import PostureAnalysisApp

/// Markers by voice: dictated notes survive final results, task restarts, and coach speech, and never run commands.
@MainActor
final class WorkoutVoiceControllerTests: XCTestCase {
    private var clock = ManualClock(now: 100)
    private lazy var scheduler = ManualScheduler(clock: clock)
    private let recognizer = FakeSpeechRecognizer()
    private var commands: [WorkoutCommand] = []
    private var heard: [String] = []

    private func makeController(acceptsMarkers: Bool = true) -> WorkoutVoiceController {
        let controller = WorkoutVoiceController(recognizer: recognizer,
                                                parser: VoiceCommandParser(exercises: [ShoulderPressExercise.definition()]),
                                                permissions: GrantedVoicePermissions(), audio: nil,
                                                clock: { [clock] in clock.now }, scheduler: scheduler)
        controller.onCommand = { [weak self] in self?.commands.append($0) }
        controller.onHeard = { [weak self] in self?.heard.append($0) }
        controller.acceptsMarkers = acceptsMarkers
        controller.enable()
        return controller
    }

    func testAMarkerWaitsForQuietThenRecordsWhenItsTriggerWasHeard() {
        let controller = makeController()
        recognizer.hear("mark that")
        scheduler.advance(by: 1)
        XCTAssertTrue(commands.isEmpty, "A note may still follow.")
        recognizer.hear("mark that the rep")
        scheduler.advance(by: 1.6)

        XCTAssertEqual(commands.count, 1)
        guard case .mark(let note, let secondsAgo) = commands.first else { return XCTFail("\(commands)") }
        XCTAssertEqual(note, "the rep")
        XCTAssertEqual(secondsAgo, 2.6, accuracy: 0.11, "Placed when \"mark that\" was heard, not when the note ended.")
        XCTAssertEqual(heard, ["Mark: the rep"])
        withExtendedLifetime(controller) {}
    }

    func testANoteAcrossFinalResultsNeverRunsTheCommandsItMentions() {
        let controller = makeController()
        recognizer.hear("mark that", final: true)
        scheduler.advance(by: 0.5)
        recognizer.hear("pause didn't")
        recognizer.hear("pause didn't work", final: true)
        scheduler.advance(by: 0.5)
        recognizer.hear("wait 17")
        scheduler.advance(by: 1.6)

        XCTAssertEqual(commands.count, 1, "\(commands)")
        guard case .mark(let note, _) = commands.first else { return XCTFail("\(commands)") }
        XCTAssertEqual(note, "pause didn't work wait 17")
        withExtendedLifetime(controller) {}
    }

    func testCoachSpeechFinishesTheMarkerAfterListeningStops() {
        let controller = makeController()
        var stopsAtDelivery: [Int] = []
        controller.onCommand = { [weak self, recognizer] command in
            stopsAtDelivery.append(recognizer.stopCount)
            self?.commands.append(command)
        }
        recognizer.hear("note the rep should have")
        controller.setCoachSpeaking(true)
        XCTAssertTrue(commands.isEmpty, "Delivered on the next turn, so its \"Marked.\" can't start inside the coach's line.")
        scheduler.advance(by: 0)

        XCTAssertEqual(commands.map { command -> String? in if case .mark(let note, _) = command { return note } else { return "other" } }, ["the rep should have"])
        XCTAssertEqual(stopsAtDelivery, [1], "The microphone stopped before the marker went out.")
        controller.setCoachSpeaking(false)
        recognizer.hear("pause")
        XCTAssertEqual(commands.last, .pause, "After the marker, commands work again.")
    }

    func testMutingFinishesTheMarkerToo() {
        let controller = makeController()
        recognizer.hear("flag that")
        controller.setMuted(true)
        XCTAssertEqual(commands.count, 1)
    }

    func testWithoutARecordingMarkerPhrasesMeanNothing() {
        let controller = makeController(acceptsMarkers: false)
        recognizer.hear("note pause")
        XCTAssertEqual(commands, [.pause])
        XCTAssertFalse(recognizer.contextualStrings.contains("mark that"))
        controller.acceptsMarkers = true
        XCTAssertTrue(recognizer.contextualStrings.contains("mark that"))
    }

    func testARecordingEndingMidNoteDropsTheMarkerAndRetiresItsWords() {
        let controller = makeController()
        recognizer.hear("note end workout")
        let restarts = recognizer.restartCount
        controller.acceptsMarkers = false
        XCTAssertEqual(recognizer.restartCount, restarts + 1, "The note's task is replaced, so its words can't run as commands.")
        XCTAssertTrue(commands.isEmpty)
        recognizer.hear("pause")
        XCTAssertEqual(commands, [.pause], "Nothing is left to mark, and commands work again.")
    }

    func testANoteContinuesAcrossTaskRestartsWithoutAFinalResult() {
        let controller = makeController()
        recognizer.hear("mark that the rep")
        recognizer.rollOver()
        recognizer.hear("should have counted")
        scheduler.advance(by: 1.6)
        guard case .mark(let note, _) = commands.first else { return XCTFail("\(commands)") }
        XCTAssertEqual(note, "the rep should have counted")
        XCTAssertEqual(commands.count, 1)
        withExtendedLifetime(controller) {}
    }

    func testCommandsStillWorkWhileMarkersAreOn() {
        let controller = makeController()
        recognizer.hear("pause")
        XCTAssertEqual(commands, [.pause])
        withExtendedLifetime(controller) {}
    }
}
