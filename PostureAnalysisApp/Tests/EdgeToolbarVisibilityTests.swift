import XCTest
@testable import PostureAnalysisApp

@MainActor
final class EdgeToolbarVisibilityTests: XCTestCase {
    func testVisibleOnAppearAndHiddenAfterThreeSeconds() {
        let fixture = makeFixture()

        fixture.visibility.onAppear()
        XCTAssertTrue(fixture.visibility.isVisible)

        fixture.scheduler.advance(by: 2.99)
        XCTAssertTrue(fixture.visibility.isVisible)
        fixture.scheduler.advance(by: 0.01)
        XCTAssertFalse(fixture.visibility.isVisible)
    }

    func testInteractionShowsToolbarAndRestartsHideDeadline() {
        let fixture = makeFixture()
        fixture.visibility.onAppear()
        fixture.scheduler.advance(by: 2)
        fixture.visibility.interact()
        XCTAssertTrue(fixture.visibility.isVisible)

        fixture.scheduler.advance(by: 2.99)
        XCTAssertTrue(fixture.visibility.isVisible)
        fixture.scheduler.advance(by: 0.01)
        XCTAssertFalse(fixture.visibility.isVisible)
    }

    func testInteractionAfterAutoHideRevealsToolbarAndStartsNewWindow() {
        let fixture = makeFixture()
        fixture.visibility.onAppear()
        fixture.scheduler.advance(by: 3)
        XCTAssertFalse(fixture.visibility.isVisible)

        fixture.visibility.interact()
        XCTAssertTrue(fixture.visibility.isVisible)
        fixture.scheduler.advance(by: 2.99)
        XCTAssertTrue(fixture.visibility.isVisible)
        fixture.scheduler.advance(by: 0.01)
        XCTAssertFalse(fixture.visibility.isVisible)
    }

    func testVoiceOverKeepsToolbarVisibleUntilVoiceOverStops() {
        var voiceOverRunning = true
        let fixture = makeFixture(isVoiceOverRunning: { voiceOverRunning })
        fixture.visibility.onAppear()
        fixture.visibility.voiceOverStatusChanged()
        fixture.scheduler.advance(by: 30)
        XCTAssertTrue(fixture.visibility.isVisible)

        voiceOverRunning = false
        fixture.visibility.voiceOverStatusChanged()
        fixture.scheduler.advance(by: 3)
        XCTAssertFalse(fixture.visibility.isVisible)
    }

    func testDisappearCancelsPendingHide() {
        let fixture = makeFixture()
        fixture.visibility.onAppear()
        fixture.visibility.disappear()
        fixture.scheduler.advance(by: 10)

        XCTAssertTrue(fixture.visibility.isVisible)
    }

    private func makeFixture(isVoiceOverRunning: @escaping () -> Bool = { false }) -> Fixture {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let visibility = EdgeToolbarVisibilityController(scheduler: scheduler,
                                                         isVoiceOverRunning: isVoiceOverRunning)
        return Fixture(scheduler: scheduler, visibility: visibility)
    }

    private struct Fixture {
        let scheduler: ManualScheduler
        let visibility: EdgeToolbarVisibilityController
    }
}
