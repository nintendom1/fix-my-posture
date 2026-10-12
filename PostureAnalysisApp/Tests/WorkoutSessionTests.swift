import XCTest
@testable import PostureAnalysisApp

final class WorkoutSessionTests: XCTestCase {
    private let press = ShoulderPressExercise.definition()

    func testHoldingStartPositionAutoStartsSet() {
        var session = readySession()
        _ = session.handle(.startPositionChanged(true), at: 2)
        _ = session.handle(.tick, at: 2.5)
        XCTAssertEqual(session.phase, .ready)

        let effects = session.handle(.tick, at: 3)
        XCTAssertEqual(session.phase, .exercising)
        XCTAssertTrue(effects.contains(.setCounting(true)))
        XCTAssertTrue(spoken(effects).contains("Set 1 of 2. Go."))
    }

    func testStartHoldProgressFillsOverOneSecond() {
        var session = readySession()
        XCTAssertNil(session.startHoldProgress(at: 2))
        _ = session.handle(.startPositionChanged(true), at: 2)
        XCTAssertEqual(session.startHoldProgress(at: 2.5) ?? -1, 0.5, accuracy: 0.001)
        _ = session.handle(.startPositionChanged(false), at: 2.6)
        XCTAssertNil(session.startHoldProgress(at: 2.7), "Letting go hides the ring.")
    }

    func testSuggestedCommandsFollowThePhase() {
        var session = readySession()
        XCTAssertTrue(session.suggestedCommands.contains(.start))
        _ = session.handle(.command(.start), at: 2)
        XCTAssertTrue(session.suggestedCommands.contains(.pause))
        XCTAssertFalse(session.suggestedCommands.contains(.start))
    }

    func testRestWaitsForTimerBeforeAutoStart() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 10)
        XCTAssertEqual(session.phase, .resting)

        // Rest is 90 s, so it ends at t = 100. Holding the start earlier must not skip it.
        _ = session.handle(.startPositionChanged(true), at: 20)
        _ = session.handle(.tick, at: 99)
        _ = session.handle(.tick, at: 100.5)
        XCTAssertEqual(session.phase, .resting)
        _ = session.handle(.tick, at: 101)
        XCTAssertEqual(session.phase, .exercising)
        XCTAssertEqual(session.currentSetNumber, 2)
    }

    func testStaleRepsAreIgnored() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        let epoch = session.analyzerEpoch
        _ = session.handle(.repCompleted(rep(epoch: epoch - 1)), at: 3)
        XCTAssertEqual(session.repCount, 0)
        _ = session.handle(.repCompleted(rep(epoch: epoch)), at: 4)
        XCTAssertEqual(session.repCount, 1)
    }

    func testTenRepsAnnounceTargetRangeAndCompleteSet() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        var lines: [String] = []
        for count in 1...10 {
            lines += spoken(session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 2 + Double(count)))
        }
        XCTAssertTrue(lines.contains("8. You're in the target range."))
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.progress[press.id]?.setReps, [10])
    }

    func testTiltWarningIsRateLimited() {
        var session = readySession()
        XCTAssertEqual(spoken(session.handle(.phoneTiltChanged(true), at: 5)).count, 1)
        _ = session.handle(.phoneTiltChanged(false), at: 6)
        XCTAssertTrue(spoken(session.handle(.phoneTiltChanged(true), at: 20)).isEmpty)
        XCTAssertEqual(spoken(session.handle(.phoneTiltChanged(true), at: 36)).count, 1)
    }

    /// Opened and reliably framed, waiting in ready at t = 1.
    private func readySession() -> WorkoutSession {
        var session = WorkoutSession(exercises: [press], initialExercise: press.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        XCTAssertEqual(session.phase, .ready)
        return session
    }

    private func rep(epoch: Int) -> RepEvent {
        RepEvent(epoch: epoch, timestamp: 0, sides: [.left, .right])
    }

    private func spoken(_ effects: [WorkoutEffect]) -> [String] {
        effects.compactMap { effect in
            if case .speak(let utterance) = effect { return utterance.text }
            return nil
        }
    }
}
