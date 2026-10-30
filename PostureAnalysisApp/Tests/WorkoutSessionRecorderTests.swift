import XCTest
@testable import PostureAnalysisApp

/// What a session recording writes, line by line.
@MainActor
final class WorkoutSessionRecorderTests: XCTestCase {
    private let id = UUID(uuidString: "3F2A0000-0000-4000-8000-000000000001")!
    private let app = WorkoutSessionLines.AppInfo(version: "1.0", build: "7", configuration: "Debug",
                                                  deviceModel: "iPhone16,1", systemVersion: "18.1.0")

    func testBeginWritesHeaderWithSchemaJointsAndConfigurations() throws {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 100)

        let header = try XCTUnwrap(writer(store).objects.first)
        XCTAssertEqual(header["k"] as? String, "header")
        XCTAssertEqual(header["schema"] as? String, "fmp.workout-session/1")
        XCTAssertEqual(header["id"] as? String, id.uuidString)
        XCTAssertEqual((header["jointOrder"] as? [String])?.count, LandmarkType.allCases.count)
        XCTAssertEqual(header["confidenceFloor"] as? Double, 0.3)
        XCTAssertEqual((header["camera"] as? [String: Any])?["analysisHz"] as? Int, 10)
        let exercises = try XCTUnwrap(header["exercises"] as? [String: Any])
        let press = try XCTUnwrap(exercises["shoulder_press"] as? [String: Any])
        let configuration = try XCTUnwrap(press["configuration"] as? [String: Any])
        XCTAssertEqual(configuration["topMinHeight"] as? Double, 0.8)
        XCTAssertEqual(configuration["topMinElbowAngle"] as? Double, 140)
        XCTAssertEqual(press["cameraView"] as? String, "front")
        XCTAssertNotNil((header["framing"] as? [String: Any])?["reliableAfter"])
        XCTAssertNotNil((header["cueScheduler"] as? [String: Any])?["cueCooldown"])

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(store.summaries[id]?.isComplete, false)
        XCTAssertEqual(store.prunedKeeping, [id])
    }

    func testFrameLinesKeepJointsExactAndListLowConfidenceJoints() throws {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 100)

        let x = 540.0926208496094
        var frame = PoseFrame(pose: BodyPose(landmarks: [
            .nose: landmark(.nose, x: x, y: 300.25, confidence: 0.9345703125)
        ], imageWidth: 1080, imageHeight: 1920), timestamp: 4521.123456)
        frame.sequence = 41
        frame.lowConfidenceLandmarks = [.rightWrist: landmark(.rightWrist, x: 612.04, y: 300.44, confidence: 0.1449)]
        recorder.recordFrame(frame, output: nil, pitchDegrees: 3.214, at: 101.25)

        let line = try XCTUnwrap(writer(store).objects(kind: "f").first)
        XCTAssertEqual(line["t"] as? Double, 1.25)
        XCTAssertEqual(line["ts"] as? Double, 4521.123456)
        XCTAssertEqual(line["seq"] as? Int, 41)
        XCTAssertEqual(line["p"] as? Bool, false)
        XCTAssertEqual(line["wh"] as? [Double], [1080, 1920])
        let joints = try XCTUnwrap(line["j"] as? [Any])
        XCTAssertEqual(joints.count, LandmarkType.allCases.count)
        XCTAssertEqual(joints[0] as? [Double], [x, 300.25, 0.9345703125])
        XCTAssertTrue(joints[1] is NSNull)
        let wristIndex = try XCTUnwrap(LandmarkType.allCases.firstIndex(of: .rightWrist))
        XCTAssertEqual(line["lo"] as? [[Double]], [[Double(wristIndex), 612, 300.4, 0.145]])
        XCTAssertEqual(line["pitch"] as? Double, 3.21)
    }

    func testImageSizeAndSequenceGapsAreTracked() throws {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 0)
        for sequence in [1, 2, 5] {
            var frame = PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920),
                                  timestamp: Double(sequence))
            frame.sequence = sequence
            // The frame after the gap arrived late, behind a stall.
            if sequence == 5 { frame.deliveryDelay = 0.2 }
            recorder.recordFrame(frame, output: nil, pitchDegrees: nil, at: Double(sequence))
        }
        recorder.end(.closed, workoutRecordID: nil, at: 6)

        let frames = writer(store).objects(kind: "f")
        XCTAssertNotNil(frames[0]["wh"])
        XCTAssertNil(frames[1]["wh"], "The image size is written only when it changes.")
        XCTAssertNil(frames[1]["delay"], "Frames without a measured delay omit it.")
        XCTAssertEqual(frames[2]["delay"] as? Double, 0.2)
        let end = try XCTUnwrap(writer(store).objects(kind: "end").first)
        XCTAssertEqual(end["frames"] as? Int, 3)
        XCTAssertEqual(end["seqGaps"] as? Int, 2)
    }

    func testStateIsWrittenOnlyWhenItChanges() {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 0)
        var snapshot = snapshotFixture()
        recorder.recordState(snapshot, at: 1)
        recorder.recordState(snapshot, at: 2)
        snapshot.repCount = 1
        recorder.recordState(snapshot, at: 3)

        let states = writer(store).objects(kind: "state")
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states.last?["reps"] as? Int, 1)
        XCTAssertEqual(states.last?["t"] as? Double, 3)
    }

    func testAudioDiagnosticsRecordRouteReasonsSessionOperationsAndInterruptions() throws {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 0)
        recorder.recordEvent(.audioRouteDiagnostic(reason: 6, outputs: ["BluetoothA2DP"], inputs: ["BuiltInMic"]),
                             at: 1)
        recorder.recordEvent(.audioSessionOperation(operation: "setActive", active: false,
                                                      category: "playAndRecord", mode: "default",
                                                      categoryOptions: ["mixWithOthers"],
                                                      activeOptions: ["notifyOthersOnDeactivation"],
                                                      isOtherAudioPlaying: true,
                                                      secondaryAudioShouldBeSilenced: false), at: 2)
        recorder.recordEvent(.audioInterruptionDiagnostic(type: "ended", reason: 2,
                                                           wasSuspended: false, shouldResume: true), at: 3)

        let route = try XCTUnwrap(writer(store).objects.last { $0["type"] as? String == "audio.route" })
        XCTAssertEqual(route["reason"] as? Int, 6, "The route reason distinguishes device changes from category changes.")
        XCTAssertEqual(route["outputs"] as? [String], ["BluetoothA2DP"])
        XCTAssertEqual(route["inputs"] as? [String], ["BuiltInMic"])

        let operation = try XCTUnwrap(writer(store).objects.last { $0["type"] as? String == "audio.session" })
        XCTAssertEqual(operation["active"] as? Bool, false)
        XCTAssertEqual(operation["activeOptions"] as? [String], ["notifyOthersOnDeactivation"])
        XCTAssertEqual(operation["isOtherAudioPlaying"] as? Bool, true)

        let interruption = try XCTUnwrap(writer(store).objects.last { $0["type"] as? String == "audio.interruption" })
        XCTAssertEqual(interruption["reason"] as? Int, 2)
        XCTAssertEqual(interruption["wasSuspended"] as? Bool, false)
        XCTAssertEqual(interruption["shouldResume"] as? Bool, true)
    }

    func testMarkerCarriesContextFlushesAndCountsInTheSummary() throws {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 10)
        recorder.recordState(snapshotFixture(), at: 11)
        recorder.recordEvent(.command(.start, source: .touch, phrase: nil), at: 12)

        let marker = try XCTUnwrap(recorder.recordMarker(
            WorkoutMarkerRequest(source: .voice, note: "that rep should have counted", heardAt: 125.5), at: 127))

        XCTAssertEqual(marker.time, 115.5, "A marker is stamped when its trigger was heard.")
        XCTAssertEqual(recorder.markers, [marker])
        let line = try XCTUnwrap(writer(store).objects(kind: "marker").first)
        XCTAssertEqual(line["t"] as? Double, 117)
        XCTAssertEqual(line["heardAt"] as? Double, 115.5)
        XCTAssertEqual(line["source"] as? String, "voice")
        XCTAssertEqual(line["text"] as? String, "that rep should have counted")
        let context = try XCTUnwrap(line["ctx"] as? [String: Any])
        XCTAssertEqual((context["state"] as? [String: Any])?["phase"] as? String, "exercising")
        XCTAssertEqual(((context["recent"] as? [[String: Any]])?.first)?["command"] as? String, "start")
        XCTAssertEqual(writer(store).flushCount, 1)
        XCTAssertEqual(store.summaries[id]?.markerCount, 1)
    }

    func testEndingWithoutFramesDeletesTheRecording() {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 0)
        recorder.end(.closed, workoutRecordID: nil, at: 5)

        XCTAssertEqual(store.deleted, [id])
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(writer(store).isClosed)
    }

    func testEndingWritesTheEndLineAndCompletesTheSummary() throws {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 0)
        recorder.recordFrame(PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: 1),
                             output: nil, pitchDegrees: nil, at: 1)
        recorder.end(.workoutEnded, workoutRecordID: id, at: 9)
        recorder.recordEvent(.cameraRunning, at: 10)

        let end = try XCTUnwrap(writer(store).objects(kind: "end").first)
        XCTAssertEqual(end["reason"] as? String, "workoutEnded")
        XCTAssertEqual(end["endedAt"] as? String, "2027-01-15T00:00:00.000-08:00", "Local time, like startedAt.")
        XCTAssertEqual(end["workoutRecordID"] as? String, id.uuidString)
        XCTAssertEqual(writer(store).kinds.last, "end", "Nothing is recorded after the end.")
        XCTAssertEqual(store.summaries[id]?.isComplete, true)
        XCTAssertEqual(store.summaries[id]?.frameCount, 1)
        XCTAssertTrue(store.deleted.isEmpty)
    }

    func testAFailedFinalWriteLeavesTheRecordingIncomplete() {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 0)
        recorder.recordFrame(PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: 1),
                             output: nil, pitchDegrees: nil, at: 1)
        writer(store).closeSucceeds = false

        recorder.end(.workoutEnded, workoutRecordID: nil, at: 2)

        XCTAssertEqual(store.summaries[id]?.isComplete, false)
        XCTAssertFalse(recorder.isRecording)
    }

    func testFlushWritesBeforeReturningAndDurationCountsFromBegin() {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        XCTAssertEqual(recorder.duration(at: 50), 0)
        recorder.begin(context(), at: 10)

        recorder.flush()

        XCTAssertEqual(writer(store).drainCount, 1)
        XCTAssertEqual(recorder.duration(at: 70), 60)
    }

    func testNothingIsRecordedWhenTheFileCannotBeCreated() {
        let store = MemoryWorkoutRecordingStore()
        store.failsToCreate = true
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 0)

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.recordMarker(WorkoutMarkerRequest(source: .tap), at: 1))
    }

    func testSingleExerciseRecordingsAreTitledByTheirExercises() {
        let store = MemoryWorkoutRecordingStore()
        let recorder = makeRecorder(store)
        recorder.begin(context(), at: 0)
        recorder.recordControl(.exercise(ShoulderPressExercise.definition(), analyzerEpoch: 0), at: 1)
        recorder.recordControl(.exercise(LateralRaiseExercise.definition(), analyzerEpoch: 1), at: 2)

        recorder.flush()
        XCTAssertEqual(store.summaries[id]?.title, "Dumbbell Shoulder Press, Lateral Raise")
        XCTAssertEqual(store.summaries[id]?.exerciseIDs, ["shoulder_press", "lateral_raise"])
        XCTAssertEqual(writer(store).objects(kind: "pipe").map { $0["exercise"] as? String },
                       ["shoulder_press", "lateral_raise"])
    }

    // MARK: - Helpers

    private func makeRecorder(_ store: MemoryWorkoutRecordingStore) -> WorkoutSessionRecorder {
        WorkoutSessionRecorder(id: id, store: store, app: app, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    private func writer(_ store: MemoryWorkoutRecordingStore) -> MemoryWorkoutSessionWriter {
        store.writers[id]!
    }

    private func context() -> WorkoutRecordingContext {
        WorkoutRecordingContext(startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                timeZone: TimeZone(identifier: "America/Los_Angeles")!,
                                exercises: ExerciseCatalog.all, plan: nil, settings: WorkoutSettings(),
                                tiltWarningsEnabled: true, isCoachMuted: false, isMicMuted: false)
    }

    private func landmark(_ type: LandmarkType, x: Double, y: Double, confidence: Double) -> Landmark {
        Landmark(type: type, normalizedLocation: CGPoint(x: x / 1080, y: 1 - y / 1920),
                 imageLocation: CGPoint(x: x, y: y), confidence: confidence)
    }

    private func snapshotFixture() -> WorkoutStateSnapshot {
        WorkoutStateSnapshot(phase: "exercising", exerciseID: "shoulder_press", planIndex: nil, setNumber: 1, side: nil,
                             repCount: 0, leftReps: 0, rightReps: 0, isCounting: true, analyzerEpoch: 1,
                             framingReliable: true, framingGuidance: nil, restEndsAt: nil, isPhoneTilted: false,
                             tipCueID: nil, isCoachSpeaking: false, micStatus: "listening", isCoachMuted: false,
                             isMicMuted: false, cameraStatus: "running")
    }
}
