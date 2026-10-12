import XCTest
@testable import PostureAnalysisApp

final class CoachingCueSchedulerTests: XCTestCase {
    private let high = CoachingCue.corrective(CoachingCueID(rawValue: "test.high"), "High.", trigger: .perRep, priority: 50, joints: [])
    private let low = CoachingCue.corrective(CoachingCueID(rawValue: "test.low"), "Low.", trigger: .continuous, priority: 10, joints: [])
    private let lowest = CoachingCue.corrective(CoachingCueID(rawValue: "test.lowest"), "Lowest.", trigger: .continuous, priority: 5, joints: [])
    private let firstReminder = CoachingCue.reminder(CoachingCueID(rawValue: "test.reminder.a"), "A.")
    private let secondReminder = CoachingCue.reminder(CoachingCueID(rawValue: "test.reminder.b"), "B.")

    func testContinuousCueNeedsHalfSecondHold() {
        var scheduler = makeScheduler()
        XCTAssertNil(scheduler.update(signals([low]), speaking: false, at: 10))
        XCTAssertNil(scheduler.update(signals([low]), speaking: false, at: 10.4))
        // One frame without the signal restarts the hold.
        XCTAssertNil(scheduler.update(signals([]), speaking: false, at: 10.45))
        XCTAssertNil(scheduler.update(signals([low]), speaking: false, at: 10.5))
        XCTAssertNil(scheduler.update(signals([low]), speaking: false, at: 10.9))
        XCTAssertEqual(scheduler.update(signals([low]), speaking: false, at: 11)?.id, low.id)
    }

    func testPerRepCueNeedsTwoOfLastThreeAttempts() {
        var scheduler = makeScheduler()
        XCTAssertNil(scheduler.update(attempt([high]), speaking: false, at: 1))
        XCTAssertNil(scheduler.update(attempt([]), speaking: false, at: 2))
        XCTAssertEqual(scheduler.update(attempt([high]), speaking: false, at: 3)?.id, high.id)
    }

    func testCooldownAndGlobalGap() {
        var scheduler = makeScheduler()
        _ = scheduler.update(signals([low]), speaking: false, at: 0)
        XCTAssertEqual(scheduler.update(signals([low]), speaking: false, at: 0.5)?.id, low.id)
        // Still held, but the same cue waits 10 s.
        XCTAssertNil(scheduler.update(signals([low]), speaking: false, at: 6))
        XCTAssertEqual(scheduler.update(signals([low]), speaking: false, at: 10.5)?.id, low.id)
        // The tip is gone after 3 s, but another cue still waits until 4 s after the last one started.
        _ = scheduler.update(signals([lowest]), speaking: false, at: 13)
        XCTAssertNil(scheduler.update(signals([lowest]), speaking: false, at: 14.4))
        XCTAssertEqual(scheduler.update(signals([lowest]), speaking: false, at: 14.5)?.id, lowest.id)
    }

    func testHigherPriorityReplacesActiveCueButLowerWaits() {
        var scheduler = makeScheduler()
        _ = scheduler.update(signals([low]), speaking: false, at: 0)
        XCTAssertEqual(scheduler.update(signals([low]), speaking: false, at: 0.5)?.id, low.id)
        _ = scheduler.update(attempt([high]), speaking: false, at: 1)
        XCTAssertEqual(scheduler.update(attempt([high]), speaking: false, at: 1.5)?.id, high.id, "Replaces inside the 4 s gap.")
        XCTAssertEqual(scheduler.activeCue(at: 1.6)?.id, high.id)

        _ = scheduler.update(signals([lowest]), speaking: false, at: 1.6)
        XCTAssertNil(scheduler.update(signals([lowest]), speaking: false, at: 3), "A lower cue never replaces a higher one.")
        XCTAssertNil(scheduler.update(signals([lowest]), speaking: false, at: 5.4))
        XCTAssertEqual(scheduler.update(signals([lowest]), speaking: false, at: 5.5)?.id, lowest.id)
    }

    func testCorrectiveWaitsForCoachToFinishSpeaking() {
        var scheduler = makeScheduler()
        _ = scheduler.update(signals([low]), speaking: true, at: 0)
        XCTAssertNil(scheduler.update(signals([low]), speaking: true, at: 1))
        XCTAssertEqual(scheduler.update(signals([low]), speaking: false, at: 1.1)?.id, low.id)
    }

    func testRemindersAtSetStartThenAfterQuietInterval() {
        var scheduler = makeScheduler(reminders: [firstReminder, secondReminder])
        XCTAssertEqual(scheduler.beginSet(at: 0)?.id, firstReminder.id)
        XCTAssertNil(scheduler.tick(speaking: false, at: 24))
        XCTAssertEqual(scheduler.tick(speaking: false, at: 25)?.id, secondReminder.id)

        // A correction restarts the quiet interval.
        _ = scheduler.update(signals([low]), speaking: false, at: 30)
        XCTAssertEqual(scheduler.update(signals([low]), speaking: false, at: 30.5)?.id, low.id)
        _ = scheduler.update(signals([]), speaking: false, at: 31)
        XCTAssertNil(scheduler.tick(speaking: false, at: 50))
        XCTAssertEqual(scheduler.tick(speaking: false, at: 55.5)?.id, firstReminder.id)

        // The next set opens with the next reminder in the rotation.
        XCTAssertEqual(scheduler.beginSet(at: 100)?.id, secondReminder.id)
    }

    private func makeScheduler(reminders: [CoachingCue] = []) -> CoachingCueScheduler {
        CoachingCueScheduler(cues: [high, low, lowest], reminders: reminders)
    }

    private func signals(_ cues: [CoachingCue]) -> FormObservation {
        FormObservation(epoch: 1, signals: Set(cues.map(\.id)))
    }

    private func attempt(_ cues: [CoachingCue]) -> FormObservation {
        FormObservation(epoch: 1, repForms: [RepForm(timestamp: 0, flags: Set(cues.map(\.id)))])
    }
}
