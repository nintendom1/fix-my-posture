import XCTest
@testable import PostureAnalysisApp

/// What the coach sends to a session recording, and in what order.
@MainActor
final class WorkoutCoachModelRecordingTests: XCTestCase {
    func testWorkoutSharesTheRecordingsIDAndShowsTheRECChipOnceRecording() {
        let recorder = WorkoutSessionRecorder(store: MemoryWorkoutRecordingStore())
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), recorder: recorder)
        XCTAssertEqual(harness.model.workoutID, recorder.id)
        XCTAssertNil(harness.model.hud.recording)

        harness.model.onAppear(isApplicationActive: true)

        XCTAssertEqual(harness.model.hud.recording, WorkoutRecordingHUD(markerCount: 0, confirmation: nil))
    }

    func testRECStaysHiddenWhenTheRecordingCannotStart() {
        let store = MemoryWorkoutRecordingStore()
        store.failsToCreate = true
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(),
                                               recorder: WorkoutSessionRecorder(store: store))
        harness.model.onAppear(isApplicationActive: true)

        XCTAssertNil(harness.model.hud.recording)
        harness.model.send(.dropMarker)
        XCTAssertTrue(harness.speech.utterances.isEmpty, "Nothing to confirm when nothing is recorded.")
    }

    func testWithoutARecorderThereIsNoRECChip() {
        let harness = WorkoutCoachHarness.make()
        XCTAssertNil(harness.model.hud.recording)
    }

    func testRecordingBeginsOnAppearWithTheHeaderAndState() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)

        XCTAssertEqual(writer.kinds.first, "header")
        let state = try XCTUnwrap(writer.objects(kind: "state").first)
        XCTAssertEqual(state["phase"] as? String, "framing")
        XCTAssertEqual(state["ex"] as? String, "shoulder_press")
    }

    func testEachFrameFollowsTheControlsBeforeItAndPrecedesTheControlsItsEventsCause() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        let ready = try XCTUnwrap(ReadyPoseFixtures.variants(for: ShoulderPressExercise.definition()).first)
        for index in 0...8 {
            harness.camera.emit(.frame(ReadyPoseFixtures.frame(ready, at: Double(index) / 10)))
        }
        XCTAssertEqual(harness.model.session.phase, .ready)

        harness.model.send(.start)
        harness.camera.emit(.frame(ReadyPoseFixtures.frame(ready, at: 0.9)))

        let kinds = writer.kinds
        let firstFrame = try XCTUnwrap(kinds.firstIndex(of: "f"))
        let pipes = writer.objects.enumerated().filter { $0.element["k"] as? String == "pipe" }
        // A fresh pipeline already starts in framing, so the first frame's only change is its exercise.
        let firstExercise = try XCTUnwrap(pipes.first { $0.element["control"] as? String == "exercise" })
        XCTAssertLessThan(firstExercise.offset, firstFrame, "A frame's own controls come first.")
        XCTAssertEqual(firstExercise.element["exercise"] as? String, "shoulder_press")
        XCTAssertEqual(pipes.first?.element["control"] as? String, "resetTracking", "Starting the camera resets tracking.")

        let start = try XCTUnwrap(writer.objects.firstIndex {
            $0["type"] as? String == "command" && $0["command"] as? String == "start"
        })
        XCTAssertEqual(writer.objects[start]["source"] as? String, "touch")
        let counting = try XCTUnwrap(pipes.first { $0.offset > start && $0.element["control"] as? String == "counting" })
        XCTAssertEqual(counting.element["counting"] as? Bool, true)
        let exercisingPhase = try XCTUnwrap(pipes.first {
            $0.element["control"] as? String == "sessionPhase" && $0.element["phase"] as? String == "exercising"
        })
        let lastFrame = try XCTUnwrap(kinds.lastIndex(of: "f"))
        XCTAssertGreaterThan(counting.offset, start)
        XCTAssertLessThan(exercisingPhase.offset, lastFrame)
        XCTAssertGreaterThan(exercisingPhase.offset, counting.offset)

        let frame = try XCTUnwrap(writer.objects(kind: "f").last)
        XCTAssertEqual(frame["p"] as? Bool, true)
        XCTAssertEqual(frame["cnt"] as? Bool, true)
        XCTAssertNotNil(frame["fr"], "Framing is written on every analyzed frame.")
        XCTAssertNotNil(frame["rd"])
        XCTAssertNotNil(frame["th"])
    }

    func testControlsCausedByAFramesEventsFollowThatFrame() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        let ready = try XCTUnwrap(ReadyPoseFixtures.variants(for: ShoulderPressExercise.definition()).first)
        var range: Range<Int>?
        // Holding the start position after Ready starts the set on the frame where the hold completes. Frames
        // land between the half-second ticks, so a frame (not a tick) completes the hold.
        harness.scheduler.advance(by: 0.05)
        for index in 0..<40 where harness.model.session.phase != .exercising {
            harness.scheduler.advance(by: 0.1)
            let before = writer.objects.count
            harness.camera.emit(.frame(ReadyPoseFixtures.frame(ready, at: Double(index) / 10)))
            range = before..<writer.objects.count
        }
        XCTAssertEqual(harness.model.session.phase, .exercising)

        let lines = Array(writer.objects[try XCTUnwrap(range)])
        let frame = try XCTUnwrap(lines.firstIndex { $0["k"] as? String == "f" })
        let caused = lines.indices.filter { lines[$0]["k"] as? String == "pipe" && $0 > frame }
        XCTAssertFalse(caused.isEmpty, "Starting the set changes the pipeline.")
        XCTAssertFalse(lines[..<frame].contains { $0["k"] as? String == "pipe" && $0["control"] as? String == "counting" },
                       "The set's controls must not come before the frame that started it.")
    }

    func testRepeatedControlsAreRecordedOnlyWhenTheyChangeThePipeline() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        let ready = try XCTUnwrap(ReadyPoseFixtures.variants(for: ShoulderPressExercise.definition()).first)
        for index in 0..<5 {
            harness.camera.emit(.frame(ReadyPoseFixtures.frame(ready, at: Double(index) / 10)))
        }

        let pipes = writer.objects(kind: "pipe").compactMap { $0["control"] as? String }
        XCTAssertEqual(pipes.filter { $0 == "exercise" }.count, 1)
        XCTAssertLessThanOrEqual(pipes.filter { $0 == "sessionPhase" }.count, 1)
        XCTAssertEqual(writer.objects(kind: "f").count, 5)
    }

    func testVoiceCommandsAreRecordedWithTheHeardPhrase() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.voice.emitHeard("let's go")
        harness.voice.emit(.start)

        let command = try XCTUnwrap(writer.events(type: "command").last)
        XCTAssertEqual(command["command"] as? String, "start")
        XCTAssertEqual(command["source"] as? String, "voice")
        XCTAssertEqual(command["phrase"] as? String, "let's go")
    }

    func testTapMarkerIsRecordedSpokenAndConfirmedOnTheChip() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.clock.advance(by: 116.4)

        harness.model.send(.dropMarker)

        let marker = try XCTUnwrap(writer.objects(kind: "marker").first)
        XCTAssertEqual(marker["source"] as? String, "tap")
        XCTAssertEqual(harness.speech.utterances.last?.text, "Marked.")
        XCTAssertEqual(harness.model.hud.recording, WorkoutRecordingHUD(markerCount: 1, confirmation: "Marked 1:56"))

        harness.scheduler.advance(by: WorkoutCoachModel.markerConfirmationDuration)
        XCTAssertEqual(harness.model.hud.recording, WorkoutRecordingHUD(markerCount: 1, confirmation: nil))
    }

    func testMarkerStaysSilentWhileTheCoachIsMuted() {
        let (harness, _) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.model.send(.setCoachMuted(true))

        harness.model.send(.dropMarker)

        XCTAssertFalse(harness.speech.utterances.contains { $0.text == "Marked." })
        XCTAssertEqual(harness.model.hud.recording?.markerCount, 1)
    }

    func testSpokenLinesAreRecordedEvenWhenMuted() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.model.send(.setCoachMuted(true))
        harness.camera.emit(.running)

        let speak = try XCTUnwrap(writer.events(type: "speak").first)
        XCTAssertEqual(speak["muted"] as? Bool, true)
        XCTAssertNotNil(speak["text"] as? String)
    }

    func testClosingEndsTheRecordingOnce() {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.camera.emit(.frame(PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920),
                                             timestamp: 0)))

        harness.model.onDisappear()
        harness.model.onDisappear()

        XCTAssertEqual(writer.objects(kind: "end").count, 1)
        XCTAssertEqual(writer.objects(kind: "end").first?["reason"] as? String, "closed")
        XCTAssertTrue(writer.isClosed)
    }

    func testBackgroundingFlushesTheRecording() {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)

        harness.model.setApplicationActive(false)

        XCTAssertEqual(writer.drainCount, 1, "Backgrounding writes everything before the app is suspended.")
        XCTAssertNotNil(writer.events(type: "app.background").first)
    }

    func testEveryLineTheCoachSpeaksIsRecorded() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.voice.status = .listening
        harness.model.send(.readGuideAloud)
        harness.model.send(.dropMarker)

        let spoken = Set(writer.events(type: "speak").compactMap { $0["text"] as? String })
        XCTAssertTrue(spoken.contains(WorkoutCoachModel.voiceTip))
        XCTAssertTrue(spoken.contains(ShoulderPressExercise.definition().guide.walkthrough))
        XCTAssertTrue(spoken.contains("Marked."))
        XCTAssertEqual(Set(harness.speech.utterances.map(\.text)), spoken,
                       "The recording lists exactly what was spoken.")
    }

    func testLosingFramingMidSetStopsCountingInsideTheFrameWithoutAControl() throws {
        let (harness, writer) = makeRecordingHarness()
        let ready = try startSet(harness)
        let start = writer.objects.count
        let empty = PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: 0)
        for index in 0..<6 {
            harness.camera.emit(.frame(PoseFrame(pose: empty.pose, timestamp: 1 + Double(index) / 10)))
        }
        for index in 0..<8 {
            harness.camera.emit(.frame(ReadyPoseFixtures.frame(ready, at: 1.6 + Double(index) / 10)))
        }

        let later = Array(writer.objects.dropFirst(start))
        let counting = later.filter { $0["k"] as? String == "pipe" && $0["control"] as? String == "counting" }
        XCTAssertTrue(counting.isEmpty, "The pipeline flips counting itself on framing changes; replay does too.")
        let flags = later.filter { $0["k"] as? String == "f" }.compactMap { $0["cnt"] as? Bool }
        XCTAssertTrue(flags.contains(false))
        XCTAssertEqual(flags.last, true, "Counting resumes once framing recovers.")
    }

    func testCameraInterruptionIsRecordedWithItsTrackingReset() throws {
        let (harness, writer) = makeRecordingHarness()
        _ = try startSet(harness)

        harness.camera.emit(.interrupted)

        let interrupted = try XCTUnwrap(writer.objects.lastIndex { $0["type"] as? String == "camera.interrupted" })
        let reset = try XCTUnwrap(writer.objects.lastIndex { $0["control"] as? String == "resetTracking" })
        XCTAssertGreaterThan(reset, interrupted)
        XCTAssertEqual(writer.objects(kind: "state").last?["phase"] as? String, "paused(interruption)")
    }

    func testEndingTheWorkoutEndsTheRecordingAndHidesREC() throws {
        let (harness, writer) = makeRecordingHarness()
        _ = try startSet(harness)

        harness.model.send(.endWorkout)

        let end = try XCTUnwrap(writer.objects(kind: "end").first)
        XCTAssertEqual(end["reason"] as? String, "workoutEnded")
        XCTAssertTrue(end["workoutRecordID"] is NSNull, "No set was finished, so no history entry is saved.")
        XCTAssertNil(harness.model.hud.recording)
    }

    func testAnotherRoundRecordsTheNewAnalyzer() throws {
        let (harness, writer) = makeRecordingHarness()
        _ = try startSet(harness)
        harness.model.send(.nextSet)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        let epoch = harness.model.session.analyzerEpoch
        let before = writer.objects.count

        harness.model.send(.anotherRound)

        let rebuilt = writer.objects.dropFirst(before).first {
            $0["k"] as? String == "pipe" && $0["control"] as? String == "exercise"
        }
        XCTAssertEqual(rebuilt?["epoch"] as? Int, harness.model.session.analyzerEpoch)
        XCTAssertGreaterThan(harness.model.session.analyzerEpoch, epoch)
    }

    func testRecordingStopsAfterSixtyMinutesWhileTheWorkoutCarriesOn() throws {
        let (harness, writer) = makeRecordingHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.camera.emit(.frame(PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920),
                                             timestamp: 0)))

        harness.scheduler.advance(by: WorkoutSessionRecorder.maximumDuration - 1)
        XCTAssertTrue(writer.objects(kind: "end").isEmpty)
        harness.scheduler.advance(by: 1)

        XCTAssertEqual(writer.objects(kind: "end").first?["reason"] as? String, "timeLimit")
        XCTAssertNil(harness.model.hud.recording)
        XCTAssertEqual(harness.model.session.phase, .framing)
        XCTAssertEqual(harness.camera.stops, 0, "The workout keeps its camera.")
    }

    /// Opens the coach, frames the press until Ready, and starts a set. Returns the Ready pose.
    private func startSet(_ harness: WorkoutCoachHarness) throws -> ReadyPoseVariant {
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        let ready = try XCTUnwrap(ReadyPoseFixtures.variants(for: ShoulderPressExercise.definition()).first)
        for index in 0...8 {
            harness.camera.emit(.frame(ReadyPoseFixtures.frame(ready, at: Double(index) / 10)))
        }
        harness.model.send(.start)
        harness.camera.emit(.frame(ReadyPoseFixtures.frame(ready, at: 0.9)))
        XCTAssertEqual(harness.model.session.phase, .exercising)
        return ready
    }

    // MARK: - Helpers

    func testBlockingAudioWorkIsRecordedWithItsDuration() throws {
        let store = MemoryWorkoutRecordingStore()
        let recorder = WorkoutSessionRecorder(store: store)
        let timing = AudioWorkTiming()
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), recorder: recorder, audioTiming: timing)
        harness.model.onAppear(isApplicationActive: true)

        timing.measure(.restoreOtherAudio) { Thread.sleep(forTimeInterval: 0.01) }

        let work = try XCTUnwrap(store.writer(for: recorder.id).events(type: "audio.work").last)
        XCTAssertEqual(work["step"] as? String, "restoreOtherAudio")
        XCTAssertGreaterThanOrEqual(work["ms"] as? Double ?? 0, 10)
    }

    func testWithoutARecordingAudioWorkIsNotTimed() {
        let timing = AudioWorkTiming()
        _ = WorkoutCoachHarness.make(audioTiming: timing)
        XCTAssertNil(timing.onMeasured)
    }

    private func makeRecordingHarness() -> (WorkoutCoachHarness, MemoryWorkoutSessionWriter) {
        let store = MemoryWorkoutRecordingStore()
        let recorder = WorkoutSessionRecorder(store: store)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), recorder: recorder)
        return (harness, store.writer(for: recorder.id))
    }
}
