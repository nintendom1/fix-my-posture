import Foundation
@testable import PostureAnalysisApp

enum MovementLabMode: String, Codable {
    case pipeline
    case coach
}

enum MovementLabArtifactPaths {
    enum PathError: Error, LocalizedError {
        case invalidRunDirectory
        case invalidPresetManifest
        case symlink(String)
        case existingArtifact(String)

        var errorDescription: String? {
            switch self {
            case .invalidRunDirectory: return "Movement Lab output must be diagnostics/movement-lab/runs/<safe-run-id> inside the repository."
            case .invalidPresetManifest: return "Movement Lab preset output must be presets.json inside an allowed run directory."
            case .symlink(let path): return "Movement Lab output cannot pass through a symbolic link: \(path)"
            case .existingArtifact(let path): return "Movement Lab refuses to overwrite existing artifact \(path)."
            }
        }
    }

    static func runDirectory(environment: [String: String], workspaceRoot: URL) throws -> URL {
        guard let path = environmentValue("FMP_LAB_OUT", environment: environment) else {
            throw PathError.invalidRunDirectory
        }
        return try validateRunDirectory(URL(fileURLWithPath: path, isDirectory: true), workspaceRoot: workspaceRoot)
    }

    static func presetManifest(environment: [String: String], workspaceRoot: URL) throws -> URL {
        guard let path = environmentValue("FMP_LAB_PRESETS_OUT", environment: environment) else {
            throw PathError.invalidPresetManifest
        }
        let destination = URL(fileURLWithPath: path)
        guard destination.lastPathComponent == "presets.json" else { throw PathError.invalidPresetManifest }
        _ = try validateRunDirectory(destination.deletingLastPathComponent(), workspaceRoot: workspaceRoot)
        try rejectSymlinkComponents(from: workspaceRoot, to: destination)
        return destination.standardizedFileURL
    }

    static func validateRunDirectory(_ candidate: URL, workspaceRoot: URL) throws -> URL {
        let root = workspaceRoot.standardizedFileURL
        let runs = root.appendingPathComponent("diagnostics/movement-lab/runs", isDirectory: true).standardizedFileURL
        let output = candidate.standardizedFileURL
        let runID = output.lastPathComponent
        guard output.deletingLastPathComponent().path == runs.path,
              runID.range(of: #"^\d{8}-\d{6}-[A-Za-z0-9]{4,12}$"#, options: .regularExpression) != nil,
              output.path.hasPrefix(root.path + "/") else {
            throw PathError.invalidRunDirectory
        }
        try rejectSymlinkComponents(from: root, to: output)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedOutput = output.resolvingSymlinksInPath().standardizedFileURL
        let expectedResolved = resolvedRoot.appendingPathComponent("diagnostics/movement-lab/runs/\(runID)").standardizedFileURL
        guard resolvedOutput.path == expectedResolved.path else { throw PathError.invalidRunDirectory }
        if FileManager.default.fileExists(atPath: output.path) {
            let values = try output.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw PathError.invalidRunDirectory }
        }
        return output
    }

    static func rejectExistingArtifact(_ destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw PathError.existingArtifact(destination.path)
        }
    }

    static func rejectSymlinks(from root: URL, to destination: URL) throws {
        try rejectSymlinkComponents(from: root, to: destination)
    }

    static func environmentValue(_ name: String, environment: [String: String]) -> String? {
        environment[name] ?? environment["TEST_RUNNER_\(name)"]
    }

    private static func rejectSymlinkComponents(from root: URL, to destination: URL) throws {
        let root = root.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard destination.path.hasPrefix(root.path + "/") else { throw PathError.invalidRunDirectory }
        let suffix = destination.pathComponents.dropFirst(root.pathComponents.count)
        var current = root
        for component in suffix {
            current.appendPathComponent(component)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
                throw PathError.symlink(current.path)
            }
        }
    }
}

struct MovementLabCountingChange: Codable, Equatable {
    let time: TimeInterval
    let counting: Bool
}

struct MovementLabRun {
    let results: [MovementScenarioResult]
    let recordingLines: [String: [String]]
    let referenceRecordingLines: [String: [String]]
    let countingChanges: [String: [MovementLabCountingChange]]
    let elapsedSeconds: TimeInterval
}

/// Runs synthetic scenarios against the same pipeline and coach used by a workout.
@MainActor
enum MovementLabRunner {
    private struct Observation {
        var reps = 0
        var rejections: [String] = []
        var signals: [String] = []
        var framingChanges: [String] = []
        var cues: [String] = []
        var countingChanges: [MovementLabCountingChange] = []
        var records: [String] = []
    }

    static func run(plan: MovementPlan, mode: MovementLabMode) -> MovementLabRun {
        let started = ProcessInfo.processInfo.systemUptime
        var results: [MovementScenarioResult] = []
        var recordings: [String: [String]] = [:]
        var references: [String: [String]] = [:]
        var counts: [String: [MovementLabCountingChange]] = [:]
        for scenario in plan.scenarios {
            let materialization = MovementGenerator.materialize(plan: plan, scenario: scenario)
            references[scenario.id] = referenceRecordingLines(plan: plan, scenario: scenario, materialization: materialization)
            guard materialization.isValid else {
                results.append(MovementScenarioResult(
                    scenarioID: scenario.id, revision: scenario.revision, outcome: .invalid,
                    observed: MovementObserved(), assertionResults: [], invalidReasons: materialization.invalidReasons
                ))
                recordings[scenario.id] = materialization.recordingLines
                counts[scenario.id] = []
                continue
            }

            var observation = mode == .pipeline
                ? runPipeline(scenario: scenario, materialization: materialization)
                : runCoach(plan: plan, scenario: scenario, materialization: materialization)
            let evaluated = evaluate(scenario.assertions, observation: observation, mode: mode)
            let outcome: MovementOutcome
            if evaluated.results.contains(where: { !$0.passed && !$0.detail.hasPrefix("Inconclusive:") }) {
                outcome = .failed
            } else if evaluated.hasInconclusive {
                outcome = .inconclusive
            } else {
                outcome = .passed
            }
            results.append(MovementScenarioResult(
                scenarioID: scenario.id, revision: scenario.revision, outcome: outcome,
                observed: MovementObserved(reps: observation.reps, rejections: observation.rejections,
                                           signals: observation.signals, framingChanges: observation.framingChanges,
                                           cues: observation.cues),
                assertionResults: evaluated.results, invalidReasons: []
            ))
            recordings[scenario.id] = observation.records
            counts[scenario.id] = observation.countingChanges
        }
        return MovementLabRun(results: results, recordingLines: recordings, referenceRecordingLines: references,
                              countingChanges: counts,
                              elapsedSeconds: ProcessInfo.processInfo.systemUptime - started)
    }

    private static func referenceRecordingLines(plan: MovementPlan, scenario: MovementScenario,
                                                 materialization: MovementMaterialization) -> [String] {
        guard let exercise = ExerciseCatalog.all.first(where: { $0.id == scenario.exercise }) else { return [] }
        var referenceMaterialization = materialization
        if !materialization.isValid {
            var referenceScenario = scenario
            referenceScenario.mutations = scenario.mutations.filter { mutation in
                switch mutation {
                case .tempo, .pause, .frameGap: return true
                default: return false
                }
            }
            referenceScenario.assertions = []
            referenceMaterialization = MovementGenerator.materialize(plan: plan, scenario: referenceScenario)
        }
        guard referenceMaterialization.isValid, !referenceMaterialization.frames.isEmpty else { return [] }
        let referenceFrames = referenceMaterialization.frames.map { sample in
            MovementMaterializedFrame(frame: sample.referenceFrame, referenceFrame: sample.referenceFrame,
                                      constraintReferenceFrame: sample.referenceFrame, elapsed: sample.elapsed)
        }
        return MovementMaterializer.recordingLines(plan: plan, scenario: scenario, exercise: exercise,
                                                   frames: referenceFrames)
    }

    private static func runPipeline(scenario: MovementScenario,
                                    materialization: MovementMaterialization) -> Observation {
        var observation = Observation()
        guard let exercise = ExerciseCatalog.all.first(where: { $0.id == scenario.exercise }) else { return observation }
        var pipeline = WorkoutFramePipeline()
        pipeline.collectsDiagnostics = true
        let controls: [WorkoutFramePipeline.Control] = [
            .sessionPhase(.ready), .exercise(exercise, analyzerEpoch: 1),
            .sessionPhase(.exercising), .counting(true)
        ]
        var lines: [String] = []
        var frameOutputIndex = 0
        var previousState: WorkoutStateSnapshot?
        var emittedControlStates = false
        for control in controls { _ = pipeline.apply(control) }

        // Replace each source frame in place. This preserves the recording's chronological
        // header, opening controls, frames, closing controls, and end marker.
        var samples = materialization.frames.makeIterator()
        for record in materialization.recordingLines {
            guard isFrameLine(record), let sample = samples.next() else {
                lines.append(record)
                continue
            }
            let output = pipeline.process(frame: sample.frame, at: sample.elapsed)
            collect(output, at: sample.elapsed, into: &observation)
            lines.append(WorkoutSessionLines.frame(sample.frame, output: output, pitchDegrees: nil,
                                                   imageSizeChanged: frameOutputIndex == 0,
                                                   t: sample.elapsed).serialized)
            frameOutputIndex += 1
            for event in output.events {
                guard let recordingEvent = WorkoutRecordingEvent(input: event) else { continue }
                lines.append(WorkoutSessionLines.event(recordingEvent, t: sample.elapsed).serialized)
            }
            if let diagnostics = output.diagnostics {
                let reps = observation.reps
                let framing = diagnostics.framing
                let state = pipelineSnapshot(exercise: exercise, reps: reps, counting: diagnostics.counting,
                                             framing: framing)
                if !emittedControlStates {
                    lines.append(WorkoutSessionLines.state(
                        pipelineSnapshot(exercise: exercise, reps: 0, counting: false, framing: nil,
                                         phase: "ready"), restEndsT: nil, t: sample.elapsed).serialized)
                    emittedControlStates = true
                }
                if previousState != state {
                    lines.append(WorkoutSessionLines.state(state, restEndsT: nil, t: sample.elapsed).serialized)
                    previousState = state
                }
            }
        }
        observation.records = lines
        return observation
    }

    private static func runCoach(plan: MovementPlan, scenario: MovementScenario,
                                 materialization: MovementMaterialization) -> Observation {
        var observation = Observation()
        guard ExerciseCatalog.all.contains(where: { $0.id == scenario.exercise }) else { return observation }
        let startedAt = MovementISO8601.date(from: plan.createdAt) ?? Date(timeIntervalSince1970: 0)
        let recorder = MovementLabRecorder(id: MovementMaterializer.recordingID(plan: plan, scenario: scenario),
                                           startedAt: startedAt)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), initialExercise: scenario.exercise,
                                               recorder: recorder)
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        let startTime = harness.clock.now
        let startCutoff = MovementGenerator.readyHold
        var previousElapsed: TimeInterval = 0
        for sample in materialization.frames where sample.elapsed <= startCutoff {
            advanceAndEmit(sample, from: previousElapsed, startTime: startTime, harness: harness)
            previousElapsed = sample.elapsed
        }
        harness.model.send(.start)
        for sample in materialization.frames where sample.elapsed > startCutoff {
            advanceAndEmit(sample, from: previousElapsed, startTime: startTime, harness: harness)
            previousElapsed = sample.elapsed
            if harness.model.session.phase == .resting {
                harness.model.send(.nextSet)
            }
        }
        harness.model.onDisappear()
        observation.reps = completedReps(harness.model.session, exerciseID: scenario.exercise)
        observation.cues = harness.speech.utterances.map(\.text)
        observation.records = recorder.lines
        for line in recorder.lines {
            guard let data = line.data(using: .utf8),
                  let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if record["k"] as? String == "f" {
                if let framing = record["fr"] as? [String: Any], let reliable = framing["ok"] as? Bool {
                    let label = framingState(reliable: reliable, guidance: framing["g"] as? String)
                    if observation.framingChanges.last != label { observation.framingChanges.append(label) }
                }
                if let values = record["sig"] as? [String] { observation.signals.append(contentsOf: values) }
                if let rejections = record["rej"] as? [[String: Any]] {
                    observation.rejections.append(contentsOf: rejections.compactMap { $0["reason"] as? String })
                }
                if let time = record["t"] as? Double, let counting = record["cnt"] as? Bool,
                   observation.countingChanges.last?.counting != counting {
                    observation.countingChanges.append(MovementLabCountingChange(time: time, counting: counting))
                }
            }
        }
        observation.reps = completedReps(harness.model.session, exerciseID: scenario.exercise)
        return observation
    }

    private static func completedReps(_ session: WorkoutSession, exerciseID: ExerciseID) -> Int {
        (session.progress[exerciseID]?.setReps.reduce(0, +) ?? 0) + session.repCount
    }

    private static func pipelineSnapshot(exercise: ExerciseDefinition, reps: Int, counting: Bool,
                                         framing: FramingStatus?, phase: String = "exercising") -> WorkoutStateSnapshot {
        WorkoutStateSnapshot(phase: phase, exerciseID: exercise.id.rawValue, planIndex: nil, setNumber: 1,
                             side: nil, repCount: reps, leftReps: 0, rightReps: 0, isCounting: counting,
                             analyzerEpoch: 1, framingReliable: framing?.isReliable ?? false,
                             framingGuidance: framing?.guidance?.rawValue, restEndsAt: nil,
                             isPhoneTilted: false, tipCueID: nil, isCoachSpeaking: false, micStatus: "off",
                             isCoachMuted: true, isMicMuted: true, cameraStatus: "running")
    }

    private static func framingState(reliable: Bool, guidance: String?) -> String {
        reliable ? "reliable" : (guidance ?? "unreliable")
    }

    private static func advanceAndEmit(_ sample: MovementMaterializedFrame, from previous: TimeInterval,
                                       startTime: TimeInterval, harness: WorkoutCoachHarness) {
        let delta = max(0, sample.elapsed - previous)
        harness.scheduler.advance(by: delta)
        let frame = PoseFrame(pose: sample.frame.pose, timestamp: startTime + sample.elapsed,
                              estimatedJoints: sample.frame.estimatedJoints,
                              sequence: sample.frame.sequence,
                              deliveryDelay: sample.frame.deliveryDelay,
                              lowConfidenceLandmarks: sample.frame.lowConfidenceLandmarks)
        harness.camera.emit(.frame(frame))
    }

    private static func collect(_ output: WorkoutFramePipeline.FrameOutput, at time: TimeInterval,
                                into observation: inout Observation) {
        guard let diagnostics = output.diagnostics else { return }
        observation.reps += diagnostics.analysis?.repEvents.count ?? 0
        observation.rejections += (diagnostics.analysis?.rejections ?? []).map(rejectionDescription)
        observation.signals += (diagnostics.analysis?.formSignals ?? []).map(\.rawValue).sorted()
        if let framing = diagnostics.framing {
            let label = framingState(reliable: framing.isReliable, guidance: framing.guidance?.rawValue)
            if observation.framingChanges.last != label { observation.framingChanges.append(label) }
        }
        if observation.countingChanges.last?.counting != diagnostics.counting {
            observation.countingChanges.append(MovementLabCountingChange(time: time, counting: diagnostics.counting))
        }
    }

    private static func rejectionDescription(_ rejection: RepRejection) -> String {
        let reason: String
        switch rejection.reason {
        case .tooFast(let duration, let minimum): reason = "tooFast(duration=\(duration),minimum=\(minimum))"
        case .partialEnd(let reached): reason = "partialEnd(reached=\(reached.map(\.rawValue).sorted().joined(separator: "+")))"
        case .trackingGap(let seconds, let maximum, let stage): reason = "trackingGap(seconds=\(seconds),maximum=\(maximum),stage=\(stage.rawValue))"
        case .countingStopped(let stage): reason = "countingStopped(stage=\(stage.rawValue))"
        case .sideSwitched(let stage): reason = "sideSwitched(stage=\(stage.rawValue))"
        case .referenceExpired(let stage): reason = "referenceExpired(stage=\(stage.rawValue))"
        }
        return "\(reason) at \(rejection.timestamp)"
    }

    private static func evaluate(_ assertions: [MovementAssertion], observation: Observation,
                                 mode: MovementLabMode) -> (results: [MovementAssertionResult], hasInconclusive: Bool) {
        var results: [MovementAssertionResult] = []
        var hasInconclusive = false
        for (index, assertion) in assertions.enumerated() {
            let passed: Bool
            let detail: String
            switch assertion {
            case .repCount(let equals, let min, let max):
                passed = equals.map { observation.reps == $0 }
                    ?? ((min.map { observation.reps >= $0 } ?? true) && (max.map { observation.reps <= $0 } ?? true))
                detail = "expected rep count \(expectation(equals: equals, min: min, max: max)); observed \(observation.reps)"
            case .rejection(let contains, let countMin):
                let count = observation.rejections.filter { $0.localizedCaseInsensitiveContains(contains) }.count
                passed = count >= countMin
                detail = "expected at least \(countMin) rejection(s) containing '\(contains)'; observed \(count)"
            case .formSignal(let id, let present):
                let found = observation.signals.contains(id)
                passed = found == present
                detail = "expected form signal \(id) present=\(present); observed \(found)"
            case .framing(let state, let reached):
                let found = observation.framingChanges.contains { $0 == state }
                passed = found == reached
                detail = "expected framing \(state) reached=\(reached); observed \(found)"
            case .spokenCue(let contains, let present):
                guard mode == .coach else {
                    hasInconclusive = true
                    results.append(MovementAssertionResult(assertionIndex: index, passed: false,
                                                           detail: "Inconclusive: spokenCue assertions require coach mode."))
                    continue
                }
                let found = observation.cues.contains { $0.localizedCaseInsensitiveContains(contains) }
                passed = found == present
                detail = "expected spoken cue containing '\(contains)' present=\(present); observed \(found)"
            }
            results.append(MovementAssertionResult(assertionIndex: index, passed: passed, detail: detail))
        }
        return (results, hasInconclusive)
    }

    private static func expectation(equals: Int?, min: Int?, max: Int?) -> String {
        if let equals { return "\(equals)" }
        return "\(min.map(String.init) ?? "0")…\(max.map(String.init) ?? "∞")"
    }

    private static func isFrameLine(_ line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return object["k"] as? String == "f"
    }

}

@MainActor
private final class MovementLabRecorder: WorkoutSessionRecording {
    let id: UUID
    private(set) var isRecording = false
    private(set) var markers: [WorkoutMarker] = []
    private(set) var lines: [String] = []
    private var start: TimeInterval = 0
    private var context: WorkoutRecordingContext?
    private var frameCount = 0
    private let startedAt: Date

    init(id: UUID, startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
    }

    func begin(_ context: WorkoutRecordingContext, at uptime: TimeInterval) {
        let stableContext = WorkoutRecordingContext(
            startedAt: startedAt, timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
            exercises: context.exercises, plan: context.plan,
            settings: WorkoutSettings(restPolicy: .exerciseDefault, weightUnit: .lb, startByHolding: false),
            tiltWarningsEnabled: false, isCoachMuted: true, isMicMuted: true)
        self.context = stableContext
        start = uptime
        isRecording = true
        let app = WorkoutSessionLines.AppInfo(version: "1", build: "1", configuration: "MovementLab",
                                              deviceModel: "synthetic", systemVersion: "1")
        lines.append(WorkoutSessionLines.header(id: id, context: stableContext, app: app).serialized)
    }

    func recordControl(_ control: WorkoutFramePipeline.Control, at uptime: TimeInterval) {
        lines.append(WorkoutSessionLines.control(control, t: uptime - start).serialized)
    }

    func recordFrame(_ frame: PoseFrame, output: WorkoutFramePipeline.FrameOutput?, pitchDegrees: Double?, at uptime: TimeInterval) {
        lines.append(WorkoutSessionLines.frame(frame, output: output, pitchDegrees: pitchDegrees,
                                               imageSizeChanged: frameCount == 0, t: uptime - start).serialized)
        frameCount += 1
    }

    func recordState(_ snapshot: WorkoutStateSnapshot, at uptime: TimeInterval) {
        lines.append(WorkoutSessionLines.state(snapshot, restEndsT: nil, t: uptime - start).serialized)
    }

    func recordEvent(_ event: WorkoutRecordingEvent, at uptime: TimeInterval) {
        lines.append(WorkoutSessionLines.event(event, t: uptime - start).serialized)
    }

    func recordMarker(_ request: WorkoutMarkerRequest, at uptime: TimeInterval) -> WorkoutMarker? { nil }
    func duration(at uptime: TimeInterval) -> TimeInterval { max(0, uptime - start) }
    func flush() {}

    func end(_ reason: WorkoutRecordingEnd, workoutRecordID: UUID?, at uptime: TimeInterval) {
        guard let context else { isRecording = false; return }
        lines.append(WorkoutSessionLines.end(reason, endedAt: startedAt.addingTimeInterval(uptime - start),
                                             timeZone: TimeZone(secondsFromGMT: 0) ?? .current, frames: frameCount, sequenceGaps: 0,
                                             workoutRecordID: workoutRecordID, t: uptime - start).serialized)
        isRecording = false
    }
}
