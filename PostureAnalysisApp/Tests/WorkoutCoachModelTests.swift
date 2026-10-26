import XCTest
@testable import PostureAnalysisApp

@MainActor
final class WorkoutCoachModelTests: XCTestCase {
    func testConstructionDoesNotStartCameraVoiceAudioOrTiltServices() {
        let harness = WorkoutCoachHarness.make()

        XCTAssertEqual(harness.camera.starts, 0)
        XCTAssertEqual(harness.voice.enabledCount, 0)
        XCTAssertTrue(harness.audio.calls.isEmpty)
        XCTAssertEqual(harness.tilt.startCount, 0)
    }

    func testAuthorizedPermissionStartsCameraAndDeniedPermissionDoesNot() {
        let authorized = WorkoutCoachHarness.make(permissionStatus: .authorized)
        authorized.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(authorized.camera.starts, 1)

        let denied = WorkoutCoachHarness.make(permissionStatus: .denied)
        denied.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(denied.model.cameraStatus, .notAuthorized)
        XCTAssertEqual(denied.camera.starts, 0)
    }

    func testAudioInterruptionPausesActiveSession() {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.audio.emit(.interruptionBegan)

        XCTAssertEqual(harness.model.session.phase, .paused(.interruption))
    }

    func testSchedulerTickRefreshesNowEveryHalfSecond() {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(harness.model.now, 10)

        harness.scheduler.advance(by: 0.5)

        XCTAssertEqual(harness.model.now, 10.5, accuracy: 0.0001)
    }

    func testTipExpiresAfterExistingDurationThroughScheduler() {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertNotNil(harness.model.activeTip)

        harness.scheduler.advance(by: WorkoutCoachModel.tipDuration - 0.01)
        XCTAssertNotNil(harness.model.activeTip)
        harness.scheduler.advance(by: 0.01)

        XCTAssertNil(harness.model.activeTip)
    }

    func testHeardChipExpiresAfterOneAndAHalfSeconds() {
        let harness = WorkoutCoachHarness.make()
        harness.voice.emitHeard("pause")
        XCTAssertEqual(harness.model.heardPhrase, "pause")

        harness.scheduler.advance(by: 1.49)
        XCTAssertEqual(harness.model.heardPhrase, "pause")
        harness.scheduler.advance(by: 0.01)

        XCTAssertNil(harness.model.heardPhrase)
    }

    func testMutePreferencesPersistInInjectedDefaultsSuite() {
        let suiteName = "WorkoutCoachModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = WorkoutCoachHarness.make(preferences: UserDefaultsPreferences(defaults: defaults))
        first.model.setCoachMuted(true)
        first.model.setMicMuted(true)

        let second = WorkoutCoachHarness.make(preferences: UserDefaultsPreferences(defaults: defaults))
        XCTAssertTrue(second.model.isCoachMuted)
        XCTAssertTrue(second.model.isMicMuted)
        XCTAssertTrue(second.voice.mutedValues.isEmpty, "Construction doesn't operate the voice service.")
        second.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(second.voice.mutedValues, [true])
    }

    func testDisabledTiltWarningsNeverSurfaceTiltInWorkoutModel() {
        let preferences = InMemoryPreferences()
        preferences.tiltWarningsEnabled = false
        let harness = WorkoutCoachHarness.make(preferences: preferences)

        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.tilt.latestTilt = PhoneTilt(pitchDegrees: 20)
        harness.scheduler.advance(by: 2)

        XCTAssertFalse(harness.model.isPhoneTilted)
    }

    // MARK: - Frames delivered late, after a main-thread stall

    func testABacklogCannotCompleteTheStartHoldOnPoseItsLaterFramesContradict() throws {
        let (harness, held, released) = try makeReadyPressHarness()
        var capture = try reachReady(harness, holding: held)
        for _ in 0..<3 { capture = emit(harness, held, after: capture) }
        XCTAssertLessThan(harness.model.session.startHoldProgress(at: harness.clock.now) ?? 0, 0.5)

        // The coach finishes a line and restarting the microphone stalls main for 0.9 s (no ticks run) while the
        // user lets go. The speech change reaches the reducer first, then the camera delivers what it captured
        // all at once, and handling the first frame stalls main again.
        let stalledAt = harness.clock.now
        harness.clock.advance(by: 0.9)
        harness.speech.onActivityChanged?(false)
        let backlog = (1...9).map { index in
            LateFrame(frame: ReadyPoseFixtures.frame(index == 1 ? held : released, at: capture + Double(index) / 10),
                      capturedAt: stalledAt + Double(index) / 10)
        }
        deliver(backlog, to: harness, stallingAfterFirstBy: 0.5)

        XCTAssertEqual(harness.model.session.phase, .ready,
                       "The hold was 0.4 s when the user let go; delivery time must not complete it.")
    }

    func testTicksDuringAStallCannotCompleteANearlyFinishedHoldTheBacklogContradicts() throws {
        let (harness, held, released) = try makeReadyPressHarness()
        var capture = try reachReady(harness, holding: held)
        for _ in 0..<8 where (harness.model.session.startHoldProgress(at: harness.clock.now) ?? 0) < 0.75 {
            capture = emit(harness, held, after: capture)
        }
        XCTAssertGreaterThanOrEqual(harness.model.session.startHoldProgress(at: harness.clock.now) ?? 0, 0.75)
        XCTAssertEqual(harness.model.session.phase, .ready)

        // Half-second ticks fire before the camera's backlog arrives; the user let go right after the last frame.
        let stalledAt = harness.clock.now
        harness.scheduler.advance(by: 1.2)
        XCTAssertEqual(harness.model.session.phase, .ready, "No frame has shown the hold lasting a second.")
        deliver((1...12).map {
            LateFrame(frame: ReadyPoseFixtures.frame(released, at: capture + Double($0) / 10),
                      capturedAt: stalledAt + Double($0) / 10)
        }, to: harness)

        XCTAssertEqual(harness.model.session.phase, .ready)
    }

    func testFramesDeliveredLateBeforeAnInterruptionKeepTheirCaptureTimes() throws {
        let (harness, held, _) = try makeReadyPressHarness()
        var capture = try reachReady(harness, holding: held)
        for _ in 0..<3 { capture = emit(harness, held, after: capture) }

        // Two more held frames, then the camera is interrupted; main was stalled throughout, for longer than the
        // queue's 1.5 s, because nothing new arrives to push the old frames out.
        let stalledAt = harness.clock.now
        harness.clock.advance(by: 4)
        deliver((1...2).map {
            LateFrame(frame: ReadyPoseFixtures.frame(held, at: capture + Double($0) / 10),
                      capturedAt: stalledAt + Double($0) / 10)
        }, to: harness)
        harness.camera.emit(.interrupted)

        // A set started by the late frames would now be paused; setup instead returns to framing.
        XCTAssertEqual(harness.model.session.phase, .framing,
                       "The frames showed a 0.6 s hold; the set must not start before the interruption.")
    }

    func testABacklogStillStartsTheSetWhenTheHoldReallyCompleted() throws {
        let (harness, held, _) = try makeReadyPressHarness()
        var capture = try reachReady(harness, holding: held)
        for _ in 0..<3 { capture = emit(harness, held, after: capture) }

        let stalledAt = harness.clock.now
        harness.clock.advance(by: 0.9)
        harness.speech.onActivityChanged?(false)
        deliver((1...9).map {
            LateFrame(frame: ReadyPoseFixtures.frame(held, at: capture + Double($0) / 10),
                      capturedAt: stalledAt + Double($0) / 10)
        }, to: harness)

        XCTAssertEqual(harness.model.session.phase, .exercising)
    }

    func testARepInterruptedByAStallStillCounts() throws {
        let harness = try makeHarness()
        var capture = try startSet(harness)
        // Press up on time (the demo at double speed), then main stalls for 1 s through the top and the lowering.
        for step in 1...5 { capture = emit(harness, Self.pressDemo(at: 1 + 0.2 * Double(step)), after: capture) }
        let stalledAt = harness.clock.now
        harness.clock.advance(by: 1)
        deliver((1...10).map { step in
            LateFrame(frame: ReadyPoseFixtures.frame(Self.pressDemo(at: 2 + 0.2 * Double(step)), at: capture + Double(step) / 10),
                      capturedAt: stalledAt + Double(step) / 10)
        }, to: harness)
        capture += 1
        for _ in 0..<3 { capture = emit(harness, Self.pressDemo(at: 0), after: capture) }

        XCTAssertEqual(harness.model.session.repCount, 1, "The camera saw the whole rep.")
    }

    func testABacklogHandledAfterResumeCannotCountARepFromThePause() throws {
        let harness = try makeHarness()
        var capture = try startSet(harness)
        harness.model.send(.pause)

        // While paused, the user presses once during a 1.5 s stall; the Resume tap is handled before the backlog.
        let stalledAt = harness.clock.now
        harness.clock.advance(by: 1.5)
        harness.model.send(.resume)
        deliver((1...15).map { step in
            LateFrame(frame: ReadyPoseFixtures.frame(Self.pressDemo(at: 1 + 0.2 * Double(step)), at: capture + Double(step) / 10),
                      capturedAt: stalledAt + Double(step) / 10)
        }, to: harness)
        capture += 1.5
        XCTAssertEqual(harness.model.session.repCount, 0, "That rep happened while paused.")

        // A rep after resuming counts.
        for step in 1...20 { capture = emit(harness, Self.pressDemo(at: 0.2 * Double(step)), after: capture) }
        for _ in 0..<3 { capture = emit(harness, Self.pressDemo(at: 0), after: capture) }
        XCTAssertEqual(harness.model.session.repCount, 1)
    }

    private func makeHarness() throws -> WorkoutCoachHarness {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        return harness
    }

    /// A second of the press demo's start pose (reliably framed), then Start and a few more start frames; returns
    /// the last capture.
    private func startSet(_ harness: WorkoutCoachHarness) throws -> TimeInterval {
        var capture: TimeInterval = 0
        harness.camera.emit(.frame(ReadyPoseFixtures.frame(Self.pressDemo(at: 0), at: capture)))
        for _ in 0..<10 { capture = emit(harness, Self.pressDemo(at: 0), after: capture) }
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)
        for _ in 0..<3 { capture = emit(harness, Self.pressDemo(at: 0), after: capture) }
        return capture
    }

    /// The press guide's demonstration at `motionTime` (4 s a rep: hold, press up, hold, lower) in a 1080×1920 image.
    private static func pressDemo(at motionTime: TimeInterval) -> ReadyPoseVariant {
        let motion = ShoulderPressExercise.definition().guide.motion
        let sample = motion.sample(at: motionTime)
        let figure = ExerciseDemoFigureView.pose(for: sample.angles, legs: sample.legs, forearmPlane: motion.forearmPlane)
        let landmarks = Dictionary(uniqueKeysWithValues: figure.jointLocations.map { type, point in
            (type, Landmark(type: type,
                            normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: point, imageWidth: 1080,
                                                                                         imageHeight: 1920),
                            imageLocation: point, confidence: 0.9))
        })
        return ReadyPoseVariant(name: "press demo", isMinimal: false,
                                pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920))
    }

    private struct LateFrame {
        var frame: PoseFrame
        /// On the harness clock.
        var capturedAt: TimeInterval
    }

    /// Delivers frames as the camera does after a stall: in order, each stamped with its delay as it is handed over.
    private func deliver(_ frames: [LateFrame], to harness: WorkoutCoachHarness, stallingAfterFirstBy stall: TimeInterval = 0) {
        for (index, late) in frames.enumerated() {
            var frame = late.frame
            frame.deliveryDelay = max(0, harness.clock.now - late.capturedAt)
            harness.camera.emit(.frame(frame))
            if index == 0 { harness.clock.advance(by: stall) }
        }
    }

    private func makeReadyPressHarness() throws -> (WorkoutCoachHarness, ReadyPoseVariant, ReadyPoseVariant) {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        let held = try XCTUnwrap(ReadyPoseFixtures.variants(for: ShoulderPressExercise.definition()).first)
        return (harness, held, Self.armsOverhead(held))
    }

    /// Delivers held frames at 10 Hz until Ready; returns the last capture time.
    private func reachReady(_ harness: WorkoutCoachHarness, holding held: ReadyPoseVariant) throws -> TimeInterval {
        var capture: TimeInterval = 0
        harness.camera.emit(.frame(ReadyPoseFixtures.frame(held, at: capture)))
        for _ in 0..<30 where harness.model.session.phase != .ready {
            capture = emit(harness, held, after: capture)
        }
        XCTAssertEqual(harness.model.session.phase, .ready)
        return capture
    }

    /// One on-time frame 0.1 s later, with the ticks that fall due before it.
    private func emit(_ harness: WorkoutCoachHarness, _ variant: ReadyPoseVariant, after capture: TimeInterval) -> TimeInterval {
        harness.scheduler.advance(by: 0.1)
        harness.camera.emit(.frame(ReadyPoseFixtures.frame(variant, at: capture + 0.1)))
        return capture + 0.1
    }

    /// The same body with both arms straight overhead: framed, but out of the press's start position.
    private static func armsOverhead(_ variant: ReadyPoseVariant) -> ReadyPoseVariant {
        var landmarks = variant.pose.landmarks
        for (shoulder, elbow, wrist) in [(LandmarkType.leftShoulder, LandmarkType.leftElbow, LandmarkType.leftWrist),
                                         (.rightShoulder, .rightElbow, .rightWrist)] {
            guard let s = landmarks[shoulder], let e = landmarks[elbow], let w = landmarks[wrist] else { continue }
            let upper = hypot(e.imageLocation.x - s.imageLocation.x, e.imageLocation.y - s.imageLocation.y)
            let fore = hypot(w.imageLocation.x - e.imageLocation.x, w.imageLocation.y - e.imageLocation.y)
            var raisedElbow = e
            raisedElbow.imageLocation = CGPoint(x: s.imageLocation.x, y: s.imageLocation.y - upper)
            var raisedWrist = w
            raisedWrist.imageLocation = CGPoint(x: s.imageLocation.x, y: s.imageLocation.y - upper - fore)
            landmarks[elbow] = raisedElbow
            landmarks[wrist] = raisedWrist
        }
        return ReadyPoseVariant(name: "arms overhead", isMinimal: false,
                                pose: BodyPose(landmarks: landmarks, imageWidth: variant.pose.imageWidth,
                                               imageHeight: variant.pose.imageHeight))
    }

    func testVoiceCommandReachesReducer() {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.voice.emit(.pause)

        XCTAssertEqual(harness.model.session.phase, .paused(.user))
    }

}
