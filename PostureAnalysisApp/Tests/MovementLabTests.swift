import XCTest
@testable import PostureAnalysisApp

/// Runs Movement Lab plans through the real pipeline; the batch test runs only when a plan path is supplied.
@MainActor
final class MovementLabTests: XCTestCase {
    func testCanonicalPipelineCountsFiveReps() throws {
        let scenario = try canonicalScenario()
        let result = try XCTUnwrap(MovementLabRunner.run(plan: planWith([scenario]), mode: .pipeline).results.first)
        XCTAssertEqual(result.outcome, .passed)
        XCTAssertEqual(result.observed.reps, 5)
    }

    func testShallowPresetCountsZero() throws {
        var plan = MovementPresets.airSquat()
        let shallow = try XCTUnwrap(plan.scenarios.first { $0.id == "shallow-depth" })
        plan.scenarios = [shallow]
        let result = try XCTUnwrap(MovementLabRunner.run(plan: plan, mode: .pipeline).results.first)
        XCTAssertEqual(result.observed.reps, 0)
    }

    func testHalfDepthPresetReadsAbout059AndDoesNotCount() throws {
        let plan = MovementPresets.airSquat()
        let shallow = try XCTUnwrap(plan.scenarios.first { $0.id == "shallow-depth" })
        let materialization = MovementGenerator.materialize(plan: plan, scenario: shallow)
        XCTAssertTrue(materialization.isValid, materialization.invalidReasons.joined(separator: ", "))
        let exercise = try XCTUnwrap(ExerciseCatalog.all.first { $0.id == shallow.exercise })
        let motion = exercise.guide.motion
        let bottom = MovementGuideTimeline.maximumHipDropOutputTime(
            rep: 1, motion: motion, mutations: [], readyHold: MovementGenerator.readyHold
        )

        var pipeline = WorkoutFramePipeline()
        pipeline.collectsDiagnostics = true
        _ = pipeline.apply(.sessionPhase(.ready))
        _ = pipeline.apply(.exercise(exercise, analyzerEpoch: 1))
        _ = pipeline.apply(.sessionPhase(.exercising))
        _ = pipeline.apply(.counting(true))

        var bottomSignal: Double?
        var repCount = 0
        for sample in materialization.frames {
            let output = pipeline.process(frame: sample.frame, at: sample.elapsed)
            repCount += output.diagnostics?.analysis?.repEvents.count ?? 0
            if abs(sample.elapsed - bottom) < 1e-9 {
                bottomSignal = output.readings[.left]?.signal
                break
            }
        }
        guard let depth = bottomSignal else {
            return XCTFail("Expected the AirSquatAnalyzer to expose its left-side d reading at maximum hip drop.")
        }
        XCTAssertEqual(depth, 0.59, accuracy: 0.07)
        XCTAssertEqual(repCount, 0)
    }

    func testTooClosePresetClipsRequiredJointsAndNeverReachesReliableFraming() throws {
        var plan = MovementPresets.airSquat()
        let tooClose = try XCTUnwrap(plan.scenarios.first { $0.id == "too-close-framing" })
        plan.scenarios = [tooClose]
        let materialization = MovementGenerator.materialize(plan: plan, scenario: tooClose)
        XCTAssertTrue(materialization.isValid, materialization.invalidReasons.joined(separator: ", "))
        guard let first = materialization.frames.first else {
            return XCTFail("Expected a materialized frame for the framing scenario.")
        }
        XCTAssertNil(first.frame.pose[.leftAnkle], "An ankle beyond the image edge must be clipped from the frame.")
        XCTAssertNil(first.frame.pose[.rightAnkle], "An ankle beyond the image edge must be clipped from the frame.")

        let result = try XCTUnwrap(MovementLabRunner.run(plan: plan, mode: .pipeline).results.first)
        XCTAssertEqual(result.outcome, .passed)
        XCTAssertFalse(result.observed.framingChanges.contains("reliable"))
    }

    func testFramingAssertionsMatchExactStatesInPipelineAndCoachModes() throws {
        var plan = MovementPresets.airSquat()
        var scenario = try XCTUnwrap(plan.scenarios.first { $0.id == "too-close-framing" })
        scenario.assertions = [
            .framing(state: "reliable", reached: false),
            .framing(state: "stepBackFullBody", reached: true),
        ]
        plan.scenarios = [scenario]

        for mode in [MovementLabMode.pipeline, .coach] {
            let result = try XCTUnwrap(MovementLabRunner.run(plan: plan, mode: mode).results.first)
            XCTAssertEqual(result.outcome, .passed, "\(mode) framing observation: \(result.observed.framingChanges)")
            XCTAssertTrue(result.observed.framingChanges.contains("stepBackFullBody"))
            XCTAssertFalse(result.observed.framingChanges.contains("reliable"))
        }
    }

    func testPipelineRecordingHasTopLevelViewerEventsAndStates() throws {
        let scenario = try canonicalScenario()
        let run = MovementLabRunner.run(plan: planWith([scenario]), mode: .pipeline)
        let records = try XCTUnwrap(run.recordingLines[scenario.id]).compactMap(jsonRecord)
        let repEvents = records.filter { $0["k"] as? String == "e" && $0["type"] as? String == "rep" }
        let states = records.filter { $0["k"] as? String == "state" }
        XCTAssertEqual(repEvents.count, 5)
        XCTAssertFalse(states.isEmpty)
        XCTAssertTrue(states.contains { $0["phase"] as? String == "exercising" })
    }

    func testPipelineRecordingKeepsClosingCountingControlAfterFrames() throws {
        let scenario = try canonicalScenario()
        let run = MovementLabRunner.run(plan: planWith([scenario]), mode: .pipeline)
        let records = try XCTUnwrap(run.recordingLines[scenario.id]).compactMap(jsonRecord)
        let isCountingStopRecord: ([String: Any]) -> Bool = { record in
            // Compare the counting field only: JSON numbers such as `"t": 0` also bridge to `false`.
            record["k"] as? String == "pipe" && record["control"] as? String == "counting"
                && (record["counting"] as? Bool) == false
        }
        guard let header = records.first,
              let firstFrameIndex = records.firstIndex(where: { $0["k"] as? String == "f" }),
              let lastFrameIndex = records.lastIndex(where: { $0["k"] as? String == "f" }),
              let stopIndex = records.firstIndex(where: isCountingStopRecord),
              let endIndex = records.firstIndex(where: { $0["k"] as? String == "end" }) else {
            return XCTFail("Expected a header, frames, closing counting(false) control, and end record.")
        }
        XCTAssertEqual(header["k"] as? String, "header")
        XCTAssertLessThan(firstFrameIndex, lastFrameIndex)
        XCTAssertLessThan(lastFrameIndex, stopIndex)
        XCTAssertLessThan(stopIndex, endIndex)
        XCTAssertTrue(records.enumerated().allSatisfy { entry in
            let record = entry.element
            return record["k"] as? String != "pipe" || isCountingStopRecord(record) || entry.offset < firstFrameIndex
        }, "Opening controls must stay before the first frame.")
        XCTAssertTrue(records.filter { $0["k"] as? String == "f" }.allSatisfy { $0["cnt"] as? Bool == true },
                      "Every frame should be recorded while counting is enabled.")
    }

    func testCoachCountsCompletedRepsAndContinuesIntoNextSet() throws {
        var firstSet = try canonicalScenario()
        firstSet.reps = 15
        firstSet.assertions = [.repCount(equals: 15, min: nil, max: nil)]
        let completed = try XCTUnwrap(MovementLabRunner.run(plan: planWith([firstSet]), mode: .coach).results.first)
        XCTAssertEqual(completed.outcome, .passed)
        XCTAssertEqual(completed.observed.reps, 15)

        var nextSet = firstSet
        nextSet.reps = 16
        nextSet.assertions = [.repCount(equals: 16, min: nil, max: nil)]
        let run = MovementLabRunner.run(plan: planWith([nextSet]), mode: .coach)
        let result = try XCTUnwrap(run.results.first)
        XCTAssertEqual(result.outcome, .passed)
        XCTAssertEqual(result.observed.reps, 16)
        let records = try XCTUnwrap(run.recordingLines[nextSet.id]).compactMap(jsonRecord)
        XCTAssertTrue(records.contains { $0["k"] as? String == "state" && $0["set"] as? Int == 2 })
    }

    func testPipelineMarksSpokenCueAssertionInconclusive() throws {
        var scenario = try canonicalScenario()
        scenario.assertions = [.spokenCue(textContains: "stand tall", present: true)]
        let result = try XCTUnwrap(MovementLabRunner.run(plan: planWith([scenario]), mode: .pipeline).results.first)
        XCTAssertEqual(result.outcome, .inconclusive)
        XCTAssertEqual(result.assertionResults.first?.passed, false)
        XCTAssertTrue(result.assertionResults.first?.detail.hasPrefix("Inconclusive:") == true)
    }

    func testCoachModeUsesHarnessForSpokenCueAssertions() throws {
        var scenario = try canonicalScenario()
        scenario.assertions = [.spokenCue(textContains: "Set 1 of 2", present: true)]
        let result = try XCTUnwrap(MovementLabRunner.run(plan: planWith([scenario]), mode: .coach).results.first)
        XCTAssertEqual(result.outcome, .passed)
        XCTAssertEqual(result.observed.reps, 5)
        XCTAssertTrue(result.observed.cues.contains { $0.contains("Set 1 of 2") })
    }

    func testFailedRepAssertionProducesFailedOutcome() throws {
        var scenario = try canonicalScenario()
        scenario.assertions = [.repCount(equals: 4, min: nil, max: nil)]
        let result = try XCTUnwrap(MovementLabRunner.run(plan: planWith([scenario]), mode: .pipeline).results.first)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.assertionResults.first?.passed, false)
    }

    func testRejectionAssertionAndPositiveFormSignalAreCollected() throws {
        var plan = MovementPresets.airSquat()
        let exercise = AirSquatExercise.definition()
        let motion = exercise.guide.motion
        let gapTime = MovementGuideTimeline.maximumHipDropOutputTime(
            rep: 3, motion: motion, mutations: [], readyHold: MovementGenerator.readyHold)
        var gap = try canonicalScenario()
        gap.id = "tracking-gap"
        gap.mutations = [.frameGap(at: gapTime, duration: 0.5)]
        gap.assertions = [.rejection(reasonContains: "trackingGap", countMin: 1)]
        var knees = try canonicalScenario()
        knees.id = "knees-caving-signal"
        knees.mode = .raw
        var kneeMutations: [MovementMutation] = []
        for rep in 1...5 {
            let peak = MovementGuideTimeline.maximumHipDropOutputTime(
                rep: Int(rep), motion: motion, mutations: [], readyHold: MovementGenerator.readyHold)
            kneeMutations.append(contentsOf: [
                .jointOffset(joints: [LandmarkType.leftKnee.rawValue], dx: -0.12, dy: 0,
                             peak: peak, rise: 0.35, fall: 0.35, strength: 1),
                .jointOffset(joints: [LandmarkType.rightKnee.rawValue], dx: 0.12, dy: 0,
                             peak: peak, rise: 0.35, fall: 0.35, strength: 1),
            ])
        }
        knees.mutations = kneeMutations
        knees.assertions = [.formSignal(id: "squat.knees_out", present: true)]
        plan.scenarios = [gap, knees]

        let results = MovementLabRunner.run(plan: plan, mode: .pipeline).results
        let gapResult = try XCTUnwrap(results.first { $0.scenarioID == gap.id })
        let kneeResult = try XCTUnwrap(results.first { $0.scenarioID == knees.id })
        XCTAssertEqual(gapResult.outcome, .passed, gapResult.observed.rejections.joined(separator: "\n"))
        XCTAssertTrue(kneeResult.observed.signals.contains("squat.knees_out"))
    }

    func testCompositeDepthLimitReturnsInvalidBeforeConstrainedProjection() throws {
        var scenario = try canonicalScenario()
        scenario.mutations = Array(repeating: .depthScale(scale: 2, reps: nil), count: 5)
        let result = try XCTUnwrap(MovementLabRunner.run(plan: planWith([scenario]), mode: .pipeline).results.first)
        XCTAssertEqual(result.outcome, .invalid)
        XCTAssertTrue(result.invalidReasons.contains { $0.contains("Composite depth scale") })
    }

    func testEnvironmentOutputPathsAreContainedAndRefuseSymlinksAndOverwrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fmp-lab-paths-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        let runs = root.appendingPathComponent("diagnostics/movement-lab/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let run = runs.appendingPathComponent("20261108-123456-a1b2c3", isDirectory: true)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: false)

        let runEnvironment = ["TEST_RUNNER_FMP_LAB_OUT": run.path]
        XCTAssertEqual(try MovementLabArtifactPaths.runDirectory(environment: runEnvironment, workspaceRoot: root), run)
        let manifest = run.appendingPathComponent("presets.json")
        XCTAssertEqual(try MovementLabArtifactPaths.presetManifest(
            environment: ["FMP_LAB_PRESETS_OUT": manifest.path], workspaceRoot: root), manifest)
        XCTAssertThrowsError(try MovementLabArtifactPaths.runDirectory(
            environment: ["FMP_LAB_OUT": root.appendingPathComponent("outside").path], workspaceRoot: root))
        XCTAssertThrowsError(try MovementLabArtifactPaths.presetManifest(
            environment: ["FMP_LAB_PRESETS_OUT": root.appendingPathComponent("presets.json").path], workspaceRoot: root))

        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let symlink = runs.appendingPathComponent("20261108-123457-a1b2c3", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        XCTAssertThrowsError(try MovementLabArtifactPaths.runDirectory(
            environment: ["FMP_LAB_OUT": symlink.path], workspaceRoot: root))

        let existing = run.appendingPathComponent("results.json")
        try Data("existing".utf8).write(to: existing)
        XCTAssertThrowsError(try MovementLabArtifactPaths.rejectExistingArtifact(existing))
    }

    func testRepeatedRunsAreIdentical() throws {
        let plan = planWith([try canonicalScenario()])
        let first = MovementLabRunner.run(plan: plan, mode: .pipeline)
        let second = MovementLabRunner.run(plan: plan, mode: .pipeline)
        XCTAssertEqual(first.results, second.results)
        XCTAssertEqual(first.recordingLines, second.recordingLines)
        XCTAssertEqual(first.countingChanges, second.countingChanges)
    }

    func testRepeatedCoachRunsProduceIdenticalRecordings() throws {
        let plan = planWith([try canonicalScenario()])
        let first = MovementLabRunner.run(plan: plan, mode: .coach)
        let second = MovementLabRunner.run(plan: plan, mode: .coach)
        XCTAssertEqual(first.results, second.results)
        XCTAssertEqual(first.recordingLines, second.recordingLines)
    }

    func testBatchOfTwentyScenariosRunsTogether() throws {
        let source = try canonicalScenario()
        let scenarios = (1...20).map { number -> MovementScenario in
            var scenario = source
            scenario.id = "canonical-\(number)"
            return scenario
        }
        var plan = MovementPresets.airSquat()
        plan.scenarios = scenarios
        let run = MovementLabRunner.run(plan: plan, mode: .pipeline)
        XCTAssertEqual(run.results.count, 20)
        XCTAssertTrue(run.results.allSatisfy { $0.outcome == .passed && $0.observed.reps == 5 })
    }

    func testEnvironmentPlanWritesBatchArtifacts() throws {
        let environment = ProcessInfo.processInfo.environment
        let planPath = MovementLabArtifactPaths.environmentValue("FMP_LAB_PLAN", environment: environment)
        let preset = MovementLabArtifactPaths.environmentValue("FMP_LAB_PRESET", environment: environment)
        guard let planPathOrPreset = planPath ?? preset else {
            throw XCTSkip("Set FMP_LAB_PLAN and FMP_LAB_OUT to run an exploratory Movement Lab batch.")
        }
        let output = try MovementLabArtifactPaths.runDirectory(environment: environment, workspaceRoot: repositoryRoot)

        let planData: Data
        let plan: MovementPlan
        if let planPath {
            planData = try Data(contentsOf: URL(fileURLWithPath: planPath))
            plan = try JSONDecoder().decode(MovementPlan.self, from: planData)
        } else if planPathOrPreset == "air_squat" {
            plan = MovementPresets.airSquat()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            planData = try encoder.encode(plan)
        } else {
            XCTFail("Unknown Movement Lab preset '\(planPathOrPreset)'.")
            return
        }

        let modeName = MovementLabArtifactPaths.environmentValue("FMP_LAB_MODE", environment: environment) ?? "pipeline"
        guard let mode = MovementLabMode(rawValue: modeName) else {
            XCTFail("FMP_LAB_MODE must be pipeline or coach.")
            return
        }
        let run = MovementLabRunner.run(plan: plan, mode: mode)
        let scenariosDirectory = output.appendingPathComponent("scenarios", isDirectory: true)
        try MovementLabArtifactPaths.rejectSymlinks(from: output, to: scenariosDirectory)
        for file in ["plan.json", "results.json", "summary.json", "counting-changes.json"] {
            try MovementLabArtifactPaths.rejectExistingArtifact(output.appendingPathComponent(file))
        }
        if FileManager.default.fileExists(atPath: scenariosDirectory.path) {
            guard (try scenariosDirectory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
                throw MovementLabArtifactPaths.PathError.invalidRunDirectory
            }
            guard try FileManager.default.contentsOfDirectory(atPath: scenariosDirectory.path).isEmpty else {
                throw MovementLabArtifactPaths.PathError.existingArtifact(scenariosDirectory.path)
            }
        } else {
            try FileManager.default.createDirectory(at: scenariosDirectory, withIntermediateDirectories: false)
        }
        try writeAtomically(planData, to: output.appendingPathComponent("plan.json"))

        for scenario in plan.scenarios {
            guard let lines = run.recordingLines[scenario.id] else {
                XCTFail("Runner did not produce recording lines for scenario \(scenario.id).")
                continue
            }
            guard scenario.id.range(of: #"^[a-z0-9_-]{1,64}$"#, options: .regularExpression) != nil else {
                XCTFail("Scenario id is unsafe for an artifact path: \(scenario.id)")
                continue
            }
            let json = "[\n" + lines.map { "  \($0)" }.joined(separator: ",\n") + "\n]\n"
            try writeAtomically(Data(json.utf8), to: scenariosDirectory.appendingPathComponent("\(scenario.id).json"))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeAtomically(try encoder.encode(run.results), to: output.appendingPathComponent("results.json"))
        let counts = Dictionary(uniqueKeysWithValues: MovementOutcome.allCases.map { outcome in
            (outcome.rawValue, run.results.filter { $0.outcome == outcome }.count)
        })
        var guideRevisions: [String: String] = [:]
        for scenario in plan.scenarios {
            guard let exercise = ExerciseCatalog.all.first(where: { $0.id == scenario.exercise }) else { continue }
            guideRevisions[scenario.exercise.rawValue] = MovementCanonicalRevision.value(for: exercise)
        }
        let summary = MovementLabSummary(schemaVersion: MovementPlan.currentSchemaVersion,
                                         outcomes: counts, elapsedSeconds: run.elapsedSeconds,
                                         guideRevisions: guideRevisions,
                                         buildRevision: MovementLabArtifactPaths.environmentValue("FMP_LAB_BUILD_REVISION", environment: environment) ?? "unknown",
                                         executionRevision: MovementLabArtifactPaths.environmentValue("FMP_LAB_EXECUTION_REVISION", environment: environment) ?? "unknown")
        try writeAtomically(try encoder.encode(summary), to: output.appendingPathComponent("summary.json"))
        try writeAtomically(try encoder.encode(run.countingChanges),
                            to: output.appendingPathComponent("counting-changes.json"))
    }

    func testEmitBuiltInPresetsManifest() throws {
        let environment = ProcessInfo.processInfo.environment
        guard MovementLabArtifactPaths.environmentValue("FMP_LAB_PRESETS_OUT", environment: environment) != nil else {
            throw XCTSkip("Set FMP_LAB_PRESETS_OUT to emit the built-in preset manifest.")
        }
        let output = try MovementLabArtifactPaths.presetManifest(environment: environment, workspaceRoot: repositoryRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = MovementLabPresetManifest(presets: [
            MovementLabPresetEntry(id: "air_squat", plan: MovementPresets.airSquat())
        ])
        try writeAtomically(try encoder.encode(manifest), to: output)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
    }

    private func canonicalScenario() throws -> MovementScenario {
        try XCTUnwrap(MovementPresets.airSquat().scenarios.first { $0.id == "canonical" })
    }

    private func planWith(_ scenarios: [MovementScenario]) -> MovementPlan {
        var plan = MovementPresets.airSquat()
        plan.scenarios = scenarios
        return plan
    }

    private func jsonRecord(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeAtomically(_ data: Data, to destination: URL) throws {
        try MovementLabArtifactPaths.rejectExistingArtifact(destination)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: [])
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            if FileManager.default.fileExists(atPath: destination.path) {
                throw MovementLabArtifactPaths.PathError.existingArtifact(destination.path)
            }
            throw error
        }
    }
}

private struct MovementLabSummary: Codable {
    let schemaVersion: Int
    let outcomes: [String: Int]
    let elapsedSeconds: TimeInterval
    let guideRevisions: [String: String]
    let buildRevision: String
    let executionRevision: String
}

private struct MovementLabPresetManifest: Codable {
    let presets: [MovementLabPresetEntry]
}

private struct MovementLabPresetEntry: Codable {
    let id: String
    let plan: MovementPlan
}
