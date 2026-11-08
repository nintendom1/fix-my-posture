import XCTest
import AVFoundation
@testable import PostureAnalysisApp

/// Deterministic traces of the production queue, ducking, and activity sequencing through an injected synthesizer.
@MainActor
final class SpeechCoachQueueTests: XCTestCase {
    func testQueueKeepsOnlyNewestTwoPendingLinesAndRestoresAfterDrain() {
        let harness = SpeechCoachTestHarness()

        harness.coach.speak(Utterance(text: "one", isInstruction: false))
        harness.coach.speak(Utterance(text: "two", isInstruction: false))
        harness.coach.speak(Utterance(text: "three", isInstruction: false))
        harness.coach.speak(Utterance(text: "four", isInstruction: false))
        harness.synthesizer.finishCurrent()
        harness.synthesizer.finishCurrent()
        harness.synthesizer.finishCurrent()

        XCTAssertEqual(harness.synthesizer.spokenTexts, ["one", "three", "four"])
        XCTAssertEqual(harness.log.entries, [
            "activity.true", "audio.beginDucking", "synth.speak:one",
            "synth.finish:one", "audio.beginDucking", "synth.speak:three",
            "synth.finish:three", "audio.beginDucking", "synth.speak:four",
            "synth.finish:four", "audio.endDucking", "activity.false"
        ])
        XCTAssertFalse(harness.coach.isSpeaking)
    }

    func testInterruptClearsQueuedLinesAndWaitsForCancellationBeforeStarting() {
        let harness = SpeechCoachTestHarness()

        harness.coach.speak(Utterance(text: "current", isInstruction: false))
        harness.coach.speak(Utterance(text: "discarded", isInstruction: false))
        harness.coach.speak(Utterance(text: "urgent", isInstruction: false, interrupts: true))
        harness.synthesizer.cancelCurrent()
        harness.synthesizer.finishCurrent()

        XCTAssertEqual(harness.synthesizer.spokenTexts, ["current", "urgent"])
        XCTAssertEqual(harness.log.entries, [
            "activity.true", "audio.beginDucking", "synth.speak:current",
            "synth.stop.immediate", "synth.cancel:current", "audio.beginDucking",
            "synth.speak:urgent", "synth.finish:urgent", "audio.endDucking", "activity.false"
        ])
    }

    func testRepeatSpeaksTheMostRecentInstructionAgain() {
        let harness = SpeechCoachTestHarness()

        harness.coach.speak(Utterance(text: "keep your back straight", isInstruction: true))
        harness.coach.speak(Utterance(text: "Marked.", isInstruction: false))
        harness.synthesizer.finishCurrent()
        harness.synthesizer.finishCurrent()
        harness.coach.repeatLastInstruction()
        harness.synthesizer.finishCurrent()

        XCTAssertEqual(harness.synthesizer.spokenTexts, ["keep your back straight", "Marked.", "keep your back straight"])
        XCTAssertEqual(harness.log.entries, [
            "activity.true", "audio.beginDucking", "synth.speak:keep your back straight",
            "synth.finish:keep your back straight", "audio.beginDucking", "synth.speak:Marked.",
            "synth.finish:Marked.", "audio.endDucking", "activity.false",
            "activity.true", "audio.beginDucking", "synth.speak:keep your back straight",
            "synth.finish:keep your back straight", "audio.endDucking", "activity.false"
        ])
    }

    func testRepeatUsesFallbackWhenNoInstructionHasBeenSpoken() {
        let harness = SpeechCoachTestHarness()

        harness.coach.repeatLastInstruction()
        harness.synthesizer.finishCurrent()

        XCTAssertEqual(harness.synthesizer.spokenTexts, ["Nothing to repeat yet."])
        XCTAssertEqual(harness.log.entries, [
            "activity.true", "audio.beginDucking", "synth.speak:Nothing to repeat yet.",
            "synth.finish:Nothing to repeat yet.", "audio.endDucking", "activity.false"
        ])
        XCTAssertNil(harness.coach.lastInstruction)
    }

    func testWatchdogUsesEstimatedDurationAndStopsStuckSpeech() throws {
        let harness = SpeechCoachTestHarness()

        harness.coach.speak(Utterance(text: "one two three four five six", isInstruction: false))
        let queuedTimer = try XCTUnwrap(harness.watchdog.scheduled.first?.timer)
        let queuedWatchdog = try XCTUnwrap(harness.watchdog.scheduled.first)
        XCTAssertEqual(queuedWatchdog.delay, 7.4, accuracy: 0.000_001)
        harness.synthesizer.emitDidStart()
        XCTAssertEqual(harness.watchdog.scheduled.count, 2)
        let playbackWatchdog = try XCTUnwrap(harness.watchdog.scheduled.last)
        XCTAssertEqual(playbackWatchdog.delay, 7.4, accuracy: 0.000_001)
        XCTAssertFalse(queuedTimer.isValid, "Playback start replaces the queue-time watchdog.")

        harness.watchdog.fireLatest()

        XCTAssertFalse(harness.coach.isSpeaking)
        XCTAssertFalse(playbackWatchdog.timer.isValid, "A watchdog timeout invalidates its timer.")
        XCTAssertEqual(harness.log.entries, [
            "activity.true", "audio.beginDucking", "synth.speak:one two three four five six",
            "synth.start:one two three four five six",
            "synth.stop.immediate", "audio.endDucking", "activity.false"
        ])
    }

    func testWatchdogTimersAreInvalidatedOnFinishAndStop() throws {
        let finishedHarness = SpeechCoachTestHarness()
        finishedHarness.coach.speak(Utterance(text: "one two", isInstruction: false))
        let finishTimer = try XCTUnwrap(finishedHarness.watchdog.scheduled.first?.timer)
        finishedHarness.synthesizer.finishCurrent()
        XCTAssertFalse(finishTimer.isValid, "Normal completion invalidates the watchdog.")

        let stoppedHarness = SpeechCoachTestHarness()
        stoppedHarness.coach.speak(Utterance(text: "one two", isInstruction: false))
        let stopTimer = try XCTUnwrap(stoppedHarness.watchdog.scheduled.first?.timer)
        stoppedHarness.coach.stopAll()
        XCTAssertFalse(stopTimer.isValid, "stopAll invalidates the watchdog.")
    }

    func testStopAllReleasesAudioBeforeActivityEndsAndIgnoresLateCancel() {
        let harness = SpeechCoachTestHarness()

        harness.coach.speak(Utterance(text: "current", isInstruction: false))
        harness.coach.speak(Utterance(text: "queued", isInstruction: false))
        harness.coach.stopAll()
        harness.synthesizer.cancelCurrent()

        XCTAssertFalse(harness.coach.isSpeaking)
        XCTAssertEqual(harness.synthesizer.spokenTexts, ["current"])
        XCTAssertEqual(harness.log.entries, [
            "activity.true", "audio.beginDucking", "synth.speak:current",
            "synth.stop.immediate", "audio.endDucking", "activity.false", "synth.cancel:current"
        ])
    }

    func testSystemSynthesizerDeliversDelegateCallbacksAsynchronouslyInOrderOnMainQueue() async {
        let adapter = SystemSpeechSynthesizer()
        let delegate = RecordingSpeechSynthesizingDelegate()
        let synthesizer = AVSpeechSynthesizer()
        let started = AVSpeechUtterance(string: "started")
        let finished = AVSpeechUtterance(string: "finished")
        let cancelled = AVSpeechUtterance(string: "cancelled")
        adapter.delegate = delegate

        adapter.speechSynthesizer(synthesizer, didStart: started)
        adapter.speechSynthesizer(synthesizer, didFinish: finished)
        adapter.speechSynthesizer(synthesizer, didCancel: cancelled)
        XCTAssertTrue(delegate.events.isEmpty, "AV delegate entrypoints must not notify synchronously.")

        let callbacksDelivered = expectation(description: "main-queue speech callbacks delivered")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                XCTAssertEqual(delegate.events, [
                    .started(ObjectIdentifier(started)),
                    .finished(ObjectIdentifier(finished)),
                    .cancelled(ObjectIdentifier(cancelled))
                ])
                XCTAssertEqual(delegate.callbackWasOnMainThread, [true, true, true])
                callbacksDelivered.fulfill()
            }
        }
        await fulfillment(of: [callbacksDelivered], timeout: 2)
    }

    func testSystemSynthesizerDropsQueuedCallbackWhenAdapterIsReleased() async {
        let delegate = RecordingSpeechSynthesizingDelegate()
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "released")
        var adapter: SystemSpeechSynthesizer? = SystemSpeechSynthesizer()
        adapter?.delegate = delegate

        adapter?.speechSynthesizer(synthesizer, didStart: utterance)
        XCTAssertTrue(delegate.events.isEmpty)
        adapter = nil

        let mainQueueTurnEnded = expectation(description: "queued callback observes released adapter")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                XCTAssertTrue(delegate.events.isEmpty)
                mainQueueTurnEnded.fulfill()
            }
        }
        await fulfillment(of: [mainQueueTurnEnded], timeout: 2)
    }
}

@MainActor
private final class RecordingSpeechSynthesizingDelegate: SpeechSynthesizingDelegate {
    enum Event: Equatable {
        case started(ObjectIdentifier)
        case finished(ObjectIdentifier)
        case cancelled(ObjectIdentifier)
    }

    private(set) var events: [Event] = []
    private(set) var callbackWasOnMainThread: [Bool] = []

    func speechSynthesizingDidStart(_ utteranceID: ObjectIdentifier) {
        events.append(.started(utteranceID))
        callbackWasOnMainThread.append(Thread.isMainThread)
    }

    func speechSynthesizingDidFinish(_ utteranceID: ObjectIdentifier) {
        events.append(.finished(utteranceID))
        callbackWasOnMainThread.append(Thread.isMainThread)
    }

    func speechSynthesizingDidCancel(_ utteranceID: ObjectIdentifier) {
        events.append(.cancelled(utteranceID))
        callbackWasOnMainThread.append(Thread.isMainThread)
    }
}

@MainActor
private final class SpeechCoachTestLog {
    var entries: [String] = []
}

@MainActor
private final class RecordingSpeechSynthesizer: SpeechSynthesizing {
    weak var delegate: (any SpeechSynthesizingDelegate)?
    private(set) var spokenTexts: [String] = []
    private var current: AVSpeechUtterance?
    private let log: SpeechCoachTestLog

    var isSpeaking: Bool { current != nil }

    init(log: SpeechCoachTestLog) {
        self.log = log
    }

    func speak(_ utterance: AVSpeechUtterance) {
        current = utterance
        spokenTexts.append(utterance.speechString)
        log.entries.append("synth.speak:\(utterance.speechString)")
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        log.entries.append(boundary == .immediate ? "synth.stop.immediate" : "synth.stop.word")
        return true
    }

    func emitDidStart() {
        guard let current else { return }
        log.entries.append("synth.start:\(current.speechString)")
        delegate?.speechSynthesizingDidStart(ObjectIdentifier(current))
    }

    func finishCurrent() {
        guard let current else { return }
        self.current = nil
        log.entries.append("synth.finish:\(current.speechString)")
        delegate?.speechSynthesizingDidFinish(ObjectIdentifier(current))
    }

    func cancelCurrent() {
        guard let current else { return }
        self.current = nil
        log.entries.append("synth.cancel:\(current.speechString)")
        delegate?.speechSynthesizingDidCancel(ObjectIdentifier(current))
    }
}

@MainActor
private final class OrderedAudioSessionController: AudioSessionControlling {
    private let session: FakeAudioSession
    private let log: SpeechCoachTestLog

    var onEvent: ((AudioSessionEvent) -> Void)? {
        get { session.onEvent }
        set { session.onEvent = newValue }
    }

    init(session: FakeAudioSession, log: SpeechCoachTestLog) {
        self.session = session
        self.log = log
    }

    func configureBaseCategory() {
        session.configureBaseCategory()
        log.entries.append("audio.configureBaseCategory")
    }

    func setRecordingEnabled(_ enabled: Bool) {
        session.setRecordingEnabled(enabled)
        log.entries.append("audio.recordingEnabled:\(enabled)")
    }

    func activateForListening() -> Bool {
        let succeeded = session.activateForListening()
        log.entries.append("audio.activateForListening")
        return succeeded
    }

    func stopListening() {
        session.stopListening()
        log.entries.append("audio.stopListening")
    }

    func beginDucking() {
        session.beginDucking()
        log.entries.append("audio.beginDucking")
    }

    func endDucking() {
        session.endDucking()
        log.entries.append("audio.endDucking")
    }

    func deactivate() {
        session.deactivate()
        log.entries.append("audio.deactivate")
    }
}

@MainActor
private final class ManualSpeechWatchdog {
    struct ScheduledWatchdog {
        let delay: TimeInterval
        let timer: Timer
        let action: @MainActor () -> Void
    }

    private(set) var scheduled: [ScheduledWatchdog] = []

    func schedule(_ delay: TimeInterval, action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in }
        scheduled.append(ScheduledWatchdog(delay: delay, timer: timer, action: action))
        return timer
    }

    func fireLatest() {
        guard let scheduled = scheduled.last else { return }
        scheduled.action()
    }
}

@MainActor
private struct SpeechCoachTestHarness {
    let log: SpeechCoachTestLog
    let synthesizer: RecordingSpeechSynthesizer
    let watchdog: ManualSpeechWatchdog
    let coach: SpeechCoach

    init() {
        let log = SpeechCoachTestLog()
        let baseAudio = FakeAudioSession()
        let audio = OrderedAudioSessionController(session: baseAudio, log: log)
        let synthesizer = RecordingSpeechSynthesizer(log: log)
        let watchdog = ManualSpeechWatchdog()
        let coach = SpeechCoach(audio: audio, synthesizer: synthesizer, scheduleWatchdog: { delay, action in
            watchdog.schedule(delay, action: action)
        })
        coach.onActivityChanged = { log.entries.append("activity.\($0)") }
        self.log = log
        self.synthesizer = synthesizer
        self.watchdog = watchdog
        self.coach = coach
    }
}
