import XCTest
@testable import PostureAnalysisApp

/// Replaying a recording through the pipeline reproduces what the phone counted, so a recording can test a fix.
@MainActor
final class WorkoutSessionReplayTests: XCTestCase {
    /// Every catalog exercise's demonstration, recorded through the coach, replays to the same reps.
    func testRecordedWorkoutsReplayToTheSameReps() throws {
        for exercise in ExerciseCatalog.all {
            let store = MemoryWorkoutRecordingStore()
            let recorder = WorkoutSessionRecorder(store: store)
            let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), initialExercise: exercise.id,
                                                   recorder: recorder)
            harness.model.onAppear(isApplicationActive: true)
            harness.camera.emit(.running)
            var time = 0.0
            for _ in 0..<10 { emit(exercise, at: &time, harness) }
            harness.model.send(.start)
            while time < exercise.guide.motion.duration * 2 + 1 { emit(exercise, at: &time, harness) }

            let text = "[\n" + store.writer(for: recorder.id).lines.joined(separator: ",\n") + "\n]\n"
            let frames = try WorkoutSessionReplayer.replay(WorkoutSessionFile(text: text))
            XCTAssertFalse(frames.flatMap(\.recorded.reps).isEmpty, "\(exercise.id.rawValue): the recording counted reps.")
            XCTAssertTrue(frames.contains { $0.recorded.counting == true }, "\(exercise.id.rawValue): the set was counting.")
            for frame in frames where frame.recorded != frame.replayed {
                XCTFail("\(exercise.id.rawValue) line \(frame.line): recorded \(frame.recorded), replayed \(frame.replayed)")
            }
        }
    }

    func testOnlyACutOffFinalRecordIsTolerated() throws {
        let start = """
        [
        {"k":"header","id":"x","jointOrder":["nose"],"exercises":{}},
        {"k":"pipe","t":0,"control":"exercise","exercise":"shoulder_press","epoch":1},
        {"k":"f","t":0.1,"ts":5,"p":true,"wh":[1080,1920],"j":[[540,300,0.9]]},
        """
        XCTAssertEqual(try WorkoutSessionReplayer.replay(WorkoutSessionFile(text: start + "\n{\"k\":\"f\",\"t\":0.2,\"p\":tr")).count, 1,
                       "A crash mid-write leaves a cut-off last record, which is skipped.")
        XCTAssertEqual(try WorkoutSessionReplayer.replay(WorkoutSessionFile(text: start)).count, 1, "An unclosed array reads.")
        XCTAssertThrowsError(try WorkoutSessionFile(text: start + "\n{\"k\":\"f\",broken},\n{\"k\":\"end\",\"t\":1}\n]"),
                             "A bad record before the end is corruption, not truncation.")
        XCTAssertThrowsError(try WorkoutSessionFile(text: start + "\n\"k\":\"f\"},\n{\"k\":\"end\",\"t\":1}\n]"),
                             "A record that lost its opening brace is corruption too.")
        XCTAssertThrowsError(try WorkoutSessionFile(text: start + "\n{\"k\":\"f\",broken}\n]"),
                             "A closed recording wasn't cut off, so a bad last record is corruption.")
    }

    func testRecordsTheReplayCannotReproduceAreErrors() {
        let header = #"{"k":"header","id":"x","jointOrder":["nose"],"exercises":{}}"#
        let press = #"{"k":"pipe","t":0,"control":"exercise","exercise":"shoulder_press","cameraView":"front","epoch":1}"#
        let frame = #"{"k":"f","t":0.1,"ts":5,"p":true,"wh":[1080,1920],"j":[[540,300,0.9]]}"#
        func replay(_ records: String...) throws {
            _ = try WorkoutSessionReplayer.replay(WorkoutSessionFile(text: "[\n" + records.joined(separator: ",\n") + "\n]"))
        }
        XCTAssertNoThrow(try replay(header, press, frame))
        XCTAssertThrowsError(try replay(header, frame), "A frame before any exercise")
        XCTAssertThrowsError(try replay(header, #"{"k":"pipe","t":0,"control":"exercise","exercise":"gone","epoch":1}"#),
                             "An exercise this build doesn't have")
        XCTAssertThrowsError(try replay(header, press.replacingOccurrences(of: "front", with: "side")), "A view the exercise doesn't use")
        XCTAssertThrowsError(try replay(header, #"{"k":"pipe","t":0,"control":"teleport"}"#), "An unknown control")
        XCTAssertThrowsError(try replay(header, #"{"k":"pipe","t":0,"control":"sessionPhase","phase":"dancing"}"#), "An unknown phase")
        XCTAssertThrowsError(try replay(header, press, frame.replacingOccurrences(of: #""wh":[1080,1920],"#, with: "")),
                             "A frame with no image size yet")
        XCTAssertThrowsError(try replay(#"{"k":"header","id":"x","exercises":{}}"#, press), "No joint order")
        XCTAssertThrowsError(try replay(header, press, frame.replacingOccurrences(of: #""p":true,"#, with: "")), "No processed flag")
        XCTAssertThrowsError(try replay(header, press, frame.replacingOccurrences(of: #""p":true"#, with: #""p":"true""#)),
                             "A processed flag that isn't a boolean")
        XCTAssertThrowsError(try replay(header, press, frame, frame.replacingOccurrences(of: "[1080,1920]", with: "[0,1920]")),
                             "An invalid image size after a valid one")
        let drifted = #"{"k":"header","id":"x","jointOrder":["nose"],"exercises":{"shoulder_press":{"required":["nose"]}}}"#
        XCTAssertThrowsError(try replay(drifted, press, frame), "Required joints that changed since the recording")
    }

    func testPhaseLabelsParseBack() {
        let phases: [WorkoutPhase] = [.choosingExercise, .framing, .ready, .exercising, .paused(.user), .paused(.background),
                                      .paused(.interruption), .resting, .changingExercise(previous: .exercising),
                                      .exerciseComplete, .ended]
        for phase in phases {
            XCTAssertEqual(WorkoutSessionReplayer.phase(WorkoutStateSnapshot.label(phase)), phase)
        }
    }

    /// Recordings pulled with `make diagnostics`, when `FMP_SESSION_DIR` (or `TEST_RUNNER_FMP_SESSION_DIR`) names their
    /// folder: each must replay to the reps the phone counted. The report lists every attempt the analyzers let go.
    /// Run with `make replay-sessions`; real recordings never enter the repository.
    func testLocalRecordingsReplayToWhatThePhoneCounted() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["FMP_SESSION_DIR"] ?? environment["TEST_RUNNER_FMP_SESSION_DIR"] else {
            throw XCTSkip("Set FMP_SESSION_DIR, or run make replay-sessions.")
        }
        let folder = URL(fileURLWithPath: path)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains(".summary.") && !$0.lastPathComponent.contains(".notes.") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var report = ""
        defer {
            // Written whatever happens, so a failed run never leaves an older report looking current.
            let attachment = XCTAttachment(string: report)
            attachment.name = "replay-report.txt"
            attachment.lifetime = .keepAlways
            add(attachment)
            if let out = environment["FMP_REPLAY_REPORT"] ?? environment["TEST_RUNNER_FMP_REPLAY_REPORT"] {
                do {
                    try report.write(toFile: out, atomically: true, encoding: .utf8)
                } catch {
                    XCTFail("Couldn't write the replay report to \(out): \(error)")
                }
            }
        }
        if files.isEmpty {
            report = "No recordings in \(path).\n"
            XCTFail("No recordings in \(path); pull some with make diagnostics.")
        }
        for url in files {
            let name = url.lastPathComponent
            let frames: [WorkoutSessionReplayer.Frame]
            do {
                frames = try WorkoutSessionReplayer.replay(WorkoutSessionFile(url: url))
            } catch {
                report += "\(name): CAN'T REPLAY: \(error)\n"
                XCTFail("\(name): \(error)")
                continue
            }
            let differing = frames.filter { $0.recorded != $0.replayed }
            report += "\(name): \(frames.count) analyzed frames, \(frames.flatMap(\.recorded.reps).count) reps on the phone, "
                + "\(frames.flatMap(\.replayed.reps).count) replayed, \(differing.isEmpty ? "identical" : "\(differing.count) frames DIFFER")\n"
            for frame in differing.prefix(5) {
                report += String(format: "  DIFFERS t %.1f (line %d)\n", frame.t, frame.line)
                    + "    phone:  \(frame.recorded)\n    replay: \(frame.replayed)\n"
            }
            if !differing.isEmpty { XCTFail("\(name): \(differing.count) frames differ; see the report.") }
            for frame in frames {
                for rejection in frame.rejections {
                    report += String(format: "  t %.1f  ", frame.t)
                        + "\(rejection.side.map { "\($0.rawValue): " } ?? "")\(Self.describe(rejection.reason))\n"
                }
            }
        }
    }

    /// The viewer's wording for why an attempt was let go.
    private static func describe(_ reason: RepRejectionReason) -> String {
        func stage(_ stage: RepAttemptStage) -> String {
            switch stage {
            case .atStart: return "at the start"
            case .moving: return "partway"
            case .reachedEnd: return "after reaching the counted end"
            }
        }
        switch reason {
        case .tooFast(let duration, let minimum):
            return String(format: "too fast: %.2f s, the minimum is %.2f s", duration, minimum)
        case .partialEnd(let reached):
            return "only \(reached.map(\.rawValue).sorted().joined(separator: "+")) reached the counted end"
        case .trackingGap(let seconds, let maximum, let at):
            return String(format: "tracking gap of %.2f s (over %.2f s) ", seconds, maximum) + stage(at)
        case .countingStopped(let at): return "counting stopped \(stage(at))"
        case .sideSwitched(let at): return "switched to the other side \(stage(at))"
        case .referenceExpired(let at): return "away from the start too long \(stage(at))"
        }
    }

    private func emit(_ exercise: ExerciseDefinition, at time: inout TimeInterval, _ harness: WorkoutCoachHarness) {
        harness.scheduler.advance(by: 0.1)
        time += 0.1
        harness.camera.emit(.frame(ReadyPoseFixtures.demoFrame(exercise, motionTime: time, at: time)))
    }
}
