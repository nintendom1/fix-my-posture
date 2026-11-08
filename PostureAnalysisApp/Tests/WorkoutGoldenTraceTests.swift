import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

/// Pins what a workout says and does, in order, for representative flows.
///
/// Each scenario drives the real `WorkoutCoachModel` on the harness's fakes, runs twice and must produce the same trace
/// both times, then must match its golden in `WorkoutGoldenTraces` line for line. A mismatch reports the first
/// differing line with context. To re-record after a reviewed behaviour change, run with
/// `FMP_GOLDEN_PRINT=1` (or `TEST_RUNNER_FMP_GOLDEN_PRINT=1` through xcodebuild): each actual trace is printed and attached, and the test still
/// fails until the golden is updated.
@MainActor
final class WorkoutGoldenTraceTests: XCTestCase {
    // MARK: - Camera-tracked workouts

    func testAirSquatTwoFullSetsWithRest() {
        check(WorkoutGoldenTraces.airSquatTwoSets, "airSquatTwoSets") {
            let run = GoldenRun(initialExercise: .airSquat)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.send(.start)
            run.demo(until: Self.setEnded)
            // The 60 s rest announces its end and waits for Start.
            run.still(seconds: 61)
            run.send(.start)
            run.demo(until: Self.setEnded)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    func testPerSideDumbbellRowsFinishBothArmsRestAndStartNextSet() {
        check(WorkoutGoldenTraces.perSideRows, "perSideRows") {
            var row = DumbbellRowExercise.definition()
            row.sets = 2
            row.targetReps = 1...1
            row.autoCompleteReps = 1
            row.targetRangeAnnouncementReps = nil
            row.startsByHolding = false
            let run = GoldenRun(exercises: [row], initialExercise: .dumbbellRow)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.send(.start)

            run.demo(until: { $0.session.completedSets(for: .dumbbellRow) == 1 && $0.session.phase != .exercising })
            run.still(mirrored: true, seconds: 0.5)
            run.send(.start)
            run.demo(mirrored: true, until: Self.setEnded)

            run.still(seconds: 61)
            run.send(.start)
            run.demo(until: { $0.session.completedSets(for: .dumbbellRow) == 3 && $0.session.phase != .exercising })
            run.still(mirrored: true, seconds: 0.5)
            run.send(.start)
            run.demo(mirrored: true, until: Self.setEnded)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    func testRoutineOfTwoItemsRestsBetweenThemAndCompletes() {
        check(WorkoutGoldenTraces.routineTwoItems, "routineTwoItems") {
            let plan = WorkoutPlan(id: Self.uuid(0x21), name: "Golden Routine", items: [
                WorkoutPlanItem(id: Self.uuid(0x22), exerciseID: .airSquat, sets: 1, targetReps: 3...3),
                WorkoutPlanItem(id: Self.uuid(0x23), exerciseID: .wallPushUp, sets: 1, targetReps: 2...2)
            ])
            let run = GoldenRun(initialExercise: .airSquat, plan: plan)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.startIfNeeded()
            run.demo(until: Self.setEnded)
            // The user moves into the next item's position during the rest.
            run.still(until: Self.restEnded)
            run.still(seconds: 1)
            run.startIfNeeded()
            run.demo(until: Self.setEnded)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    func testPauseAndResumeMidSetAndDuringRest() {
        check(WorkoutGoldenTraces.pauseAndResume, "pauseAndResume") {
            let run = GoldenRun(exercises: [Self.airSquat(reps: 4, sets: 2)], initialExercise: .airSquat)
            run.open()
            run.still(seconds: 1)
            run.send(.start)
            run.demo(until: Self.reps(2))
            run.send(.pause)
            run.still(seconds: 2)
            run.send(.resume)
            run.demo(until: Self.setEnded)
            run.still(seconds: 5)
            run.send(.pause)
            run.still(seconds: 3)
            run.send(.resume)
            run.still(seconds: 53)
            run.send(.start)
            run.demo(until: Self.setEnded)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    func testMutedCoachRecordsEveryLineButSpeaksNone() {
        check(WorkoutGoldenTraces.coachMuted, "coachMuted") {
            let preferences = InMemoryPreferences()
            preferences.workoutCoachCoachMuted = true
            let run = GoldenRun(exercises: [Self.airSquat(reps: 3, sets: 1)], initialExercise: .airSquat,
                                preferences: preferences)
            run.open()
            run.voiceStatus(.listening)
            // An explicit tap, so the walkthrough plays even while muted.
            run.send(.readGuideAloud)
            run.still(seconds: 1)
            run.send(.start)
            run.demo(until: Self.setEnded)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    func testVoiceRepeatsTheLastInstruction() {
        check(WorkoutGoldenTraces.voiceRepeat, "voiceRepeat") {
            let run = GoldenRun(exercises: [Self.airSquat(reps: 3, sets: 1)], initialExercise: .airSquat)
            run.open()
            run.voiceStatus(.listening)
            run.say("repeat that", .repeatLast)
            run.still(seconds: 1)
            run.say("start", .start)
            run.demo(until: Self.reps(2))
            run.say("repeat that", .repeatLast)
            run.say("mute coach", .muteCoach)
            run.say("repeat that", .repeatLast)
            run.say("unmute coach", .unmuteCoach)
            run.say("repeat that", .repeatLast)
            run.demo(until: Self.setEnded)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    func testFramingLostAndRegainedMidSet() {
        check(WorkoutGoldenTraces.framingLost, "framingLost") {
            let run = GoldenRun(exercises: [Self.airSquat(reps: 4, sets: 1)], initialExercise: .airSquat)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.send(.start)
            run.demo(until: Self.reps(2))
            run.empty(seconds: 2)
            run.still(seconds: 2)
            run.resumeIfPaused()
            run.demo(until: Self.setEnded)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    /// Every squat drops twice before standing, so each rep asks to stand all the way up. The tip comes due on the
    /// second flagged rep while the coach is speaking, so it waits for the line to end; it stays quiet within its
    /// 10 s cooldown, then shows again.
    func testCorrectiveTipRepeatsOnlyAfterItsCooldown() {
        check(WorkoutGoldenTraces.correctiveTips, "correctiveTips") {
            let run = GoldenRun(initialExercise: .airSquat)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.send(.start)
            run.squats(Self.squatWithoutStanding, label: "squat-without-standing", seconds: 9.5)
            run.speechActivity(true)
            run.squats(Self.squatWithoutStanding, label: "squat-without-standing", seconds: 2, from: 9.5)
            run.speechActivity(false)
            run.squats(Self.squatWithoutStanding, label: "squat-without-standing", seconds: 20, from: 11.5)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    // MARK: - Self-reported

    func testSelfReportedTimedHoldCountsDown() {
        check(WorkoutGoldenTraces.timedHold, "timedHold") {
            let run = GoldenRun(exercises: [Self.hold(seconds: 15, sets: 2)], initialExercise: .shoulderPress)
            run.open()
            run.voiceStatus(.listening)
            run.send(.start)
            run.wait(until: Self.setEnded)
            // The press rests 90 s, then waits for Start.
            run.wait(seconds: 91)
            run.send(.start)
            run.wait(until: Self.setEnded)
            run.send(.endWorkout)
            return run.finish()
        }
    }

    // MARK: - Today's Session

    func testTodaySessionEasyEarnsABonusThatIsTaken() {
        check(WorkoutGoldenTraces.todayBonusTaken, "todayBonusTaken") {
            let wallPushUp = WallPushUpExercise.definition()
            let trace = WorkoutTraceRecorder()
            let launch = Self.todayLaunch(exercise: wallPushUp, dose: .reps(2), offersBonus: true)
            let run = GoldenRun(trace: trace, exercises: [wallPushUp], initialExercise: .wallPushUp, plan: launch.plan,
                                adaptive: TraceEvidence(trace: trace), todayLaunch: launch)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.startIfNeeded()
            run.demo(until: Self.setEnded)
            run.sayEffort(.easy)
            run.sayBonus(.accept)
            run.still(seconds: 1)
            run.startIfNeeded()
            run.demo(until: Self.setEnded)
            run.tap("rate okay") { $0.rateEffort(.okay) }
            run.send(.endWorkout)
            return run.finish()
        }
    }

    func testTodaySessionBonusDeclined() {
        check(WorkoutGoldenTraces.todayBonusDeclined, "todayBonusDeclined") {
            let wallPushUp = WallPushUpExercise.definition()
            let trace = WorkoutTraceRecorder()
            let launch = Self.todayLaunch(exercise: wallPushUp, dose: .reps(2), offersBonus: true)
            let run = GoldenRun(trace: trace, exercises: [wallPushUp], initialExercise: .wallPushUp, plan: launch.plan,
                                adaptive: TraceEvidence(trace: trace), todayLaunch: launch)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.startIfNeeded()
            run.demo(until: Self.setEnded)
            run.tap("rate easy") { $0.rateEffort(.easy) }
            run.tap("decline bonus") { $0.declineBonus() }
            run.send(.endWorkout)
            return run.finish()
        }
    }

    func testTodaySessionTooHardTakesTheEasierVersion() {
        check(WorkoutGoldenTraces.todayTooHard, "todayTooHard") {
            let wallPushUp = WallPushUpExercise.definition()
            let trace = WorkoutTraceRecorder()
            let option = EasierSwapOption(target: RungDose(variant: Self.shallow, dose: .reps(2)),
                                          exerciseID: .wallPushUp, reducedRange: true)
            let launch = Self.todayLaunch(exercise: wallPushUp, dose: .reps(5), offersBonus: true)
            let run = GoldenRun(trace: trace, exercises: [wallPushUp], initialExercise: .wallPushUp, plan: launch.plan,
                                adaptive: TraceEvidence(trace: trace, option: option), todayLaunch: launch)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.startIfNeeded()
            run.demo(until: Self.reps(1))
            run.send(.tooHard)
            run.tap("take easier version") { $0.takeEasierVersion() }
            run.still(seconds: 1)
            run.startIfNeeded()
            run.demo(until: Self.setEnded)
            run.tap("rate okay") { $0.rateEffort(.okay) }
            run.send(.endWorkout)
            return run.finish()
        }
    }

    // MARK: - Calibration

    /// A calibration sample runs through the coach as a one-item plan with the production probe recorder; closing it
    /// saves no history.
    func testCalibrationSampleReportsItsProbeAndSavesNoHistory() {
        check(WorkoutGoldenTraces.calibrationProbe, "calibrationProbe") {
            let trace = WorkoutTraceRecorder()
            let launch = Self.calibrationLaunch(trace: trace)
            let run = GoldenRun(trace: trace, exercises: [WallPushUpExercise.definition()], initialExercise: .wallPushUp,
                                plan: launch.launch.plan, adaptive: launch.recorder, todayLaunch: launch.launch,
                                savesHistory: false)
            run.open()
            run.voiceStatus(.listening)
            run.still(seconds: 1)
            run.startIfNeeded()
            run.demo(until: Self.setEnded)
            run.tap("rate okay") { $0.rateEffort(.okay) }
            return run.finish()
        }
    }

    // MARK: - Saving

    /// End Workout during the rest saves the one finished set; closing the summary afterwards saves nothing more.
    func testEndingDuringRestSavesTheFinishedSetOnce() {
        var saves: [[String]] = []
        check(WorkoutGoldenTraces.saveOnce, "saveOnce") {
            let run = GoldenRun(exercises: [Self.airSquat(reps: 3, sets: 2)], initialExercise: .airSquat)
            run.open()
            run.still(seconds: 1)
            run.send(.start)
            run.demo(until: Self.setEnded)
            run.still(seconds: 2)
            run.send(.endWorkout)
            run.close()
            let trace = run.finish()
            saves.append(trace.filter { $0.contains(" history save record ") || $0.contains(" reminders workoutSaved") })
            return trace
        }
        for lines in saves {
            XCTAssertEqual(lines.count, 2, "One record saved and one reminder told: \(lines)")
        }
    }

    // MARK: - Checking

    /// Runs `scenario` twice, requires identical traces, then compares the trace with `golden`.
    private func check(_ golden: String, _ name: String, file: StaticString = #filePath, line: UInt = #line,
                       _ scenario: () -> [String]) {
        let actual = scenario()
        let again = scenario()
        if let index = Self.firstDifference(actual, again) {
            XCTFail("\(name) is not deterministic: run 2 differs at line \(index + 1).\n"
                    + Self.comparison(expected: actual, actual: again, at: index), file: file, line: line)
        }
        let environment = ProcessInfo.processInfo.environment
        if environment["FMP_GOLDEN_PRINT"] == "1" || environment["TEST_RUNNER_FMP_GOLDEN_PRINT"] == "1" {
            let literal = Self.literal(name, actual)
            print(literal)
            let attachment = XCTAttachment(string: literal)
            attachment.name = "\(name).golden"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let expected = golden.isEmpty ? [] : golden.components(separatedBy: "\n")
        guard let index = Self.firstDifference(expected, actual) else { return }
        if expected.isEmpty {
            XCTFail("\(name) has no golden yet. Actual trace:\n\(Self.literal(name, actual))", file: file, line: line)
            return
        }
        XCTFail("\(name) differs from its golden at line \(index + 1) (expected \(expected.count) lines, got "
                + "\(actual.count)).\n" + Self.comparison(expected: expected, actual: actual, at: index)
                + "\nRe-record with FMP_GOLDEN_PRINT=1 (or TEST_RUNNER_FMP_GOLDEN_PRINT=1 through xcodebuild) only for a reviewed behaviour change.",
                file: file, line: line)
    }

    private static func firstDifference(_ expected: [String], _ actual: [String]) -> Int? {
        let shared = min(expected.count, actual.count)
        if let index = (0..<shared).first(where: { expected[$0] != actual[$0] }) { return index }
        return expected.count == actual.count ? nil : shared
    }

    private static func comparison(expected: [String], actual: [String], at index: Int) -> String {
        func line(_ lines: [String], _ index: Int) -> String {
            lines.indices.contains(index) ? lines[index] : "<end of trace>"
        }
        let context = (max(0, index - 3)...(index + 3)).compactMap { number -> String? in
            guard actual.indices.contains(number) else { return nil }
            return "\(number == index ? ">" : " ") \(number + 1): \(actual[number])"
        }
        return "expected: \(line(expected, index))\n"
            + "actual:   \(line(actual, index))\n"
            + "actual context:\n" + context.joined(separator: "\n")
    }

    /// The trace as a `WorkoutGoldenTraces` member, ready to paste.
    private static func literal(_ name: String, _ lines: [String]) -> String {
        "    static let \(name) = \"\"\"\n" + lines.map { "        \($0)" }.joined(separator: "\n") + "\n        \"\"\""
    }

    // MARK: - Fixtures

    private static let shallow = VariantID(rawValue: "push.wall_push_up.shallow")
    private static let wall = VariantID(rawValue: "push.wall_push_up")

    private static func setEnded(_ model: WorkoutCoachModel) -> Bool { model.session.phase != .exercising }
    private static func restEnded(_ model: WorkoutCoachModel) -> Bool { model.session.phase != .resting }
    private static func reps(_ count: Int) -> (WorkoutCoachModel) -> Bool {
        { $0.session.phase != .exercising || $0.session.repCount >= count }
    }

    private static func uuid(_ number: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: number)))
    }

    /// The catalog air squat with fewer reps and sets, so a scenario stays short.
    private static func airSquat(reps: Int, sets: Int) -> ExerciseDefinition {
        var copy = AirSquatExercise.definition()
        copy.targetReps = reps...reps
        copy.autoCompleteReps = reps
        copy.targetRangeAnnouncementReps = nil
        copy.sets = sets
        return copy
    }

    /// A self-reported timed hold, as the existing self-reported tests build one.
    private static func hold(seconds: Int, sets: Int) -> ExerciseDefinition {
        var copy = ShoulderPressExercise.definition()
        copy.tracking = .selfReported
        copy.doseUnit = .seconds
        copy.targetReps = seconds...seconds
        copy.autoCompleteReps = seconds
        copy.targetRangeAnnouncementReps = nil
        copy.sets = sets
        return copy
    }

    /// Stand, squat, rise partway, squat again, then stand: each loop is one rep that never stood up between drops.
    private static let squatWithoutStanding: ArmMotion = {
        let arms = AirSquatExercise.definition().guide.motion.startAngles
        var keyframes = [ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0)]
        for depth in [0.9, 0.4, 0.9] {
            keyframes.append(ArmKeyframe(angles: arms, moveDuration: 1.0, holdDuration: 0.3, stepIndex: 1,
                                         legs: LegPose(hipDrop: depth, kneeSpread: 0.3)))
        }
        keyframes.append(ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0, stepIndex: 2))
        return ArmMotion(keyframes: keyframes, holdsDumbbells: false)
    }()

    /// Today's Session with one main item, as the coordinator prepares it.
    private static func todayLaunch(exercise: ExerciseDefinition, dose: Dose, offersBonus: Bool) -> TodaySessionLaunch {
        let item = AdaptivePlanItem(itemID: uuid(0x32), role: .main, family: .push,
                                    rungDose: RungDose(variant: wall, dose: dose), exerciseID: exercise.id,
                                    reducedRange: false)
        let prescription = Prescription(
            id: uuid(0x31), issuedAt: Date(timeIntervalSince1970: 900), kind: .todaySession, policyVersion: .v1,
            catalogVersion: "test",
            items: [PrescriptionItem(id: item.itemID, family: item.family, target: item.rungDose, role: item.role,
                                     offersBonus: offersBonus)],
            rationale: "Test")
        let plan = WorkoutPlan(id: AdaptiveTrainingCoordinator.todaySessionPlanID,
                               name: AdaptiveTrainingCoordinator.todaySessionName,
                               items: [WorkoutPlanItem(id: item.itemID, exerciseID: item.exerciseID, sets: 1,
                                                       targetReps: dose.amount...dose.amount)])
        return TodaySessionLaunch(prescription: prescription, plan: plan, items: [item])
    }

    /// A two-rep wall push-up sample, built the way `AdaptiveTrainingCoordinator` builds one, with the production
    /// probe recorder writing what it stores and reports to the trace.
    private static func calibrationLaunch(trace: WorkoutTraceRecorder) -> CalibrationProbeLaunch {
        let rungDose = RungDose(variant: wall, dose: .reps(2))
        let item = AdaptivePlanItem(itemID: uuid(0x41), role: .main, family: .push, rungDose: rungDose,
                                    exerciseID: .wallPushUp, reducedRange: false)
        let plan = WorkoutPlan(id: nil, name: AdaptiveTrainingCoordinator.calibrationProbeName, items: [
            WorkoutPlanItem(id: item.itemID, exerciseID: item.exerciseID, sets: 1, targetReps: 2...2)
        ])
        let prescriptionID = uuid(0x40)
        let calibrationID = uuid(0x42)
        trace.nameRelationship(prescriptionID, as: "calibrationPrescription")
        trace.nameRelationship(calibrationID, as: "expectedCalibration")
        let prescription = Prescription(
            id: prescriptionID, issuedAt: Date(timeIntervalSince1970: 900), kind: .calibrationProbe, policyVersion: .v1,
            catalogVersion: "test",
            items: [PrescriptionItem(id: item.itemID, family: .push, target: rungDose, role: .main, offersBonus: false)],
            rationale: "A tiny sample to find a comfortable starting point.")
        let recorder = CalibrationProbeRecorder(
            launchID: prescription.id, calibrationID: calibrationID,
            store: { [weak trace] evidence in
                guard let trace else { return }
                trace.record("probe store " + trace.describe(evidence, workoutID: trace.id))
            },
            onResult: { [weak trace] result in
                trace?.record("probe result effort=\(result.effort?.rawValue ?? "none") "
                              + "confirmed=\(result.confirmed.map { "\($0)" } ?? "none")")
            })
        return CalibrationProbeLaunch(family: .push, rungDose: rungDose,
                                      launch: TodaySessionLaunch(prescription: prescription, plan: plan, items: [item]),
                                      recorder: recorder)
    }
}

// MARK: - Driving a scenario

/// One scenario: the coach on the harness's fakes, the trace, and what `WorkoutCoachView` does with history. Every
/// step writes its input line, then lets the view react, as `WorkoutCoachView` does when the phase changes.
@MainActor
private final class GoldenRun {
    let trace: WorkoutTraceRecorder
    let harness: WorkoutCoachHarness
    var model: WorkoutCoachModel { harness.model }

    private let preferences: InMemoryPreferences
    private let savesHistory: Bool
    private let history: TraceHistory
    private let reminders: TraceReminders
    private var historySaved = false
    private var closed = false
    /// Pose timestamps keep moving forward across every batch of frames.
    private var poseTime: TimeInterval = 0

    init(trace: WorkoutTraceRecorder? = nil, exercises: [ExerciseDefinition] = ExerciseCatalog.all,
         initialExercise: ExerciseID, plan: WorkoutPlan? = nil, preferences: InMemoryPreferences? = nil,
         adaptive: (any AdaptiveEvidenceRecording)? = nil, todayLaunch: TodaySessionLaunch? = nil,
         savesHistory: Bool = true) {
        let trace = trace ?? WorkoutTraceRecorder()
        let preferences = preferences ?? InMemoryPreferences()
        self.trace = trace
        self.preferences = preferences
        self.savesHistory = savesHistory
        if let planID = plan?.id {
            let symbol = planID == AdaptiveTrainingCoordinator.todaySessionPlanID ? "todaySessionPlan" : "expectedRoutine"
            trace.nameRelationship(planID, as: symbol)
        }
        if let todayLaunch {
            let symbol = todayLaunch.prescription.kind == .calibrationProbe
                ? "calibrationPrescription" : "originalPrescription"
            trace.nameRelationship(todayLaunch.prescription.id, as: symbol)
        }
        history = TraceHistory(trace: trace)
        reminders = TraceReminders(trace: trace)
        harness = WorkoutCoachHarness.make(preferences: preferences, exercises: exercises, initialExercise: initialExercise,
                                           plan: plan, adaptive: adaptive, todayLaunch: todayLaunch, trace: trace)
    }

    // MARK: Inputs

    func open() {
        trace.input("appear (app active)")
        model.onAppear(isApplicationActive: true)
        trace.input("camera running")
        harness.camera.emit(.running)
        viewReacts()
    }

    func voiceStatus(_ status: VoiceStatus) {
        trace.input("voice status \(WorkoutTraceRecorder.describe(status))")
        harness.voice.status = status
        viewReacts()
    }

    func send(_ intent: WorkoutIntent) {
        trace.input("send .\(intent)")
        model.send(intent)
        viewReacts()
    }

    func startIfNeeded() {
        guard model.session.phase != .exercising else { return }
        send(.start)
    }

    func resumeIfPaused() {
        guard case .paused = model.session.phase else { return }
        send(.resume)
    }

    /// A voice command, heard as `phrase`.
    func say(_ phrase: String, _ command: WorkoutCommand) {
        trace.input("voice heard \(WorkoutTraceRecorder.quoted(phrase)) -> \(WorkoutTraceRecorder.describe(command))")
        harness.voice.emitHeard(phrase)
        harness.voice.emit(command)
        viewReacts()
    }

    func sayEffort(_ effort: EffortFeedback) {
        trace.input("voice effort \(effort.rawValue)")
        harness.voice.emitEffort(effort)
        viewReacts()
    }

    func sayBonus(_ answer: BonusAnswer) {
        trace.input("voice bonus \(answer)")
        harness.voice.emitBonus(answer)
        viewReacts()
    }

    /// A button on a card or offer, which calls the model directly.
    func tap(_ label: String, _ action: (WorkoutCoachModel) -> Void) {
        trace.input("tap \(label)")
        action(model)
        viewReacts()
    }

    /// The live speech coach starting or finishing a line.
    func speechActivity(_ speaking: Bool) {
        trace.input("speech activity \(speaking)")
        harness.speech.onActivityChanged?(speaking)
        viewReacts()
    }

    // MARK: Frames and time

    /// The current exercise's guide demonstration from its start, a frame every 0.1 s.
    func demo(mirrored: Bool = false, until stop: (WorkoutCoachModel) -> Bool, limit: Int = 900) {
        guard let exercise = model.session.exercise else { return }
        frames("frames demo \(WorkoutTraceRecorder.describe(exercise))", limit: limit, until: stop) { motion, time in
            ReadyPoseFixtures.demoFrame(exercise, motionTime: motion, at: time, mirrored: mirrored)
        }
    }

    /// The current exercise's start position, held still.
    func still(mirrored: Bool = false, seconds: TimeInterval) {
        still(until: { _ in false }, limit: Int((seconds * 10).rounded()), mirrored: mirrored)
    }

    func still(until stop: (WorkoutCoachModel) -> Bool, limit: Int = 900, mirrored: Bool = false) {
        guard let exercise = model.session.exercise else { return }
        frames("frames still \(WorkoutTraceRecorder.describe(exercise))", limit: limit, until: stop) { _, time in
            ReadyPoseFixtures.demoFrame(exercise, motionTime: 0, at: time, mirrored: mirrored)
        }
    }

    /// Frames with nobody in them.
    func empty(seconds: TimeInterval) {
        frames("frames empty", limit: Int((seconds * 10).rounded()), until: { _ in false }) { _, time in
            PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: time)
        }
    }

    /// Squats following `motion` from `motionStart` on the guide's figure, placed like `ReadyPoseFixtures` places it.
    func squats(_ motion: ArmMotion, label: String, seconds: TimeInterval, from motionStart: TimeInterval = 0) {
        let label = "frames \(label) motion from \(String(format: "%.1fs", motionStart))"
        frames(label, limit: Int((seconds * 10).rounded()), until: { _ in false }) { motionTime, time in
            Self.figureFrame(motion, motionTime: motionStart + motionTime, at: time)
        }
    }

    func wait(seconds: TimeInterval) {
        wait(until: { _ in false }, limit: Int((seconds * 10).rounded()))
    }

    /// Time passing with no frames, 0.1 s at a time.
    func wait(until stop: (WorkoutCoachModel) -> Bool, limit: Int = 900) {
        let index = trace.beginInput()
        var count = 0
        while count < limit, !stop(model) {
            count += 1
            harness.scheduler.advance(by: 0.1)
        }
        trace.insertInput("wait \(Self.seconds(count))", at: index)
        viewReacts()
    }

    private func frames(_ label: String, limit: Int, until stop: (WorkoutCoachModel) -> Bool,
                        _ make: (_ motionTime: TimeInterval, _ poseTime: TimeInterval) -> PoseFrame) {
        let index = trace.beginInput()
        var count = 0
        while count < limit, !stop(model) {
            count += 1
            harness.scheduler.advance(by: 0.1)
            poseTime += 0.1
            harness.camera.emit(.frame(make(Double(count) / 10, poseTime)))
        }
        trace.insertInput("\(label) \(count) frames @0.1 (\(Self.seconds(count)))", at: index)
        viewReacts()
    }

    private static func seconds(_ count: Int) -> String {
        String(format: "%.1fs", Double(count) / 10)
    }

    private static func figureFrame(_ motion: ArmMotion, motionTime: TimeInterval, at time: TimeInterval) -> PoseFrame {
        let joints = ExerciseDemoFigureView.pose(for: motion.sample(at: motionTime), forearmPlane: motion.forearmPlane,
                                                 cameraView: .front).jointLocations
        let anchors: [LandmarkType] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
        let centered = anchors.compactMap { joints[$0] }
        let centerX = centered.isEmpty ? 0 : centered.reduce(0) { $0 + $1.x } / CGFloat(centered.count)
        let scale: CGFloat = 3
        let size = ReadyPoseFixtures.imageSize
        let xOffset = size.width / 2 - centerX * scale
        let yOffset = (size.height - ExerciseDemoFigureView.canvasSize.height * scale) / 2
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            let pixel = CGPoint(x: point.x * scale + xOffset, y: point.y * scale + yOffset)
            return (type, Landmark(type: type,
                                   normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                    pixel: pixel, imageWidth: size.width, imageHeight: size.height),
                                   imageLocation: pixel, confidence: ReadyPoseFixtures.confidence))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: size.width, imageHeight: size.height),
                         timestamp: time)
    }

    // MARK: The view

    /// What `WorkoutCoachView` does when the phase becomes `.ended`: save history once, and close when the workout
    /// ended after its completion screen.
    private func viewReacts() {
        guard model.session.phase == .ended, !historySaved else { return }
        trace.input("view saves history (phase ended)")
        saveHistory()
        if model.session.endedAfterCompletion { close() }
    }

    /// Close, as `WorkoutCoachView` does it: save history once, then close the workout.
    func close() {
        guard !closed else { return }
        closed = true
        trace.input("view close")
        saveHistory()
        model.send(.closeWorkout)
    }

    /// The final trace, after the screen closes.
    func finish() -> [String] {
        close()
        return trace.finish()
    }

    private func saveHistory() {
        guard !historySaved else { return }
        historySaved = true
        let record = WorkoutCoachHistory.save(session: model.session, startedAt: Date(timeIntervalSince1970: 0),
                                              endedAt: Date(timeIntervalSince1970: 600), workoutID: model.workoutID,
                                              savesHistory: savesHistory, history: history, preferences: preferences,
                                              reminders: reminders)
        guard let record else {
            trace.record("history nothing to save")
            return
        }
        guard !savesHistory else { return }
        for line in trace.describe(record, workoutID: model.workoutID) {
            trace.record("history not saved " + line)
        }
    }
}

// MARK: - Tracing fakes

/// Workout history that writes each call to the trace.
@MainActor
private final class TraceHistory: WorkoutHistoryRepository {
    private let trace: WorkoutTraceRecorder

    init(trace: WorkoutTraceRecorder) {
        self.trace = trace
    }

    func list() throws -> [WorkoutRecord] {
        trace.record("history list")
        return []
    }

    func save(_ record: WorkoutRecord) throws {
        for line in trace.describe(record, workoutID: trace.id) {
            trace.record("history save " + line)
        }
    }

    func updateWeights(for record: WorkoutRecord) throws {
        trace.record("history updateWeights")
    }

    func delete(id: UUID) throws {
        trace.record("history delete")
    }
}

@MainActor
private final class TraceReminders: WorkoutReminderReconciliation {
    private let trace: WorkoutTraceRecorder

    init(trace: WorkoutTraceRecorder) {
        self.trace = trace
    }

    func reconcile() {
        trace.record("reminders reconcile")
    }

    func workoutSaved(_ record: WorkoutRecord) {
        trace.record("reminders workoutSaved")
    }
}

/// Adaptive training that writes every call to the trace, knows no active rung, and offers `option` as the easier
/// version, issuing it under fixed ids.
@MainActor
private final class TraceEvidence: AdaptiveEvidenceRecording {
    private let trace: WorkoutTraceRecorder
    private let option: EasierSwapOption?

    init(trace: WorkoutTraceRecorder, option: EasierSwapOption? = nil) {
        self.trace = trace
        self.option = option
    }

    func activeRung(for exerciseID: ExerciseID, reducedRange: Bool) -> ActiveRung? { nil }

    func record(_ evidence: AdaptiveEvidence) {
        trace.record(trace.describe(evidence, workoutID: trace.id))
    }

    func easierSwapOption(for item: PrescriptionItem, asOf now: Date) -> EasierSwapOption? {
        trace.record("adaptive easierSwapOption -> " + (option.map(Self.describe) ?? "none"))
        return option
    }

    func issueEasierSwap(replacing item: PrescriptionItem, option: EasierSwapOption, at now: Date) -> IssuedEasierSwap? {
        trace.record("adaptive issueEasierSwap " + Self.describe(option))
        let id = { (number: UInt8) in UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, number)) }
        let prescriptionID = id(0xA0)
        trace.nameRelationship(prescriptionID, as: "easierPrescription")
        return IssuedEasierSwap(prescriptionID: prescriptionID,
                                item: AdaptivePlanItem(itemID: id(0xB0), role: .easierSwap, family: item.family,
                                                       rungDose: option.target, exerciseID: option.exerciseID,
                                                       reducedRange: option.reducedRange))
    }

    private static func describe(_ option: EasierSwapOption) -> String {
        "\(option.exerciseID.rawValue) reducedRange=\(option.reducedRange) "
            + "target=\(option.target.variant.rawValue) \(option.target.dose)"
    }
}
