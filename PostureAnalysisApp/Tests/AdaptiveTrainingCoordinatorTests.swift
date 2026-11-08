import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AdaptiveTrainingCoordinatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? Date(timeIntervalSince1970: 0)
    }

    private let shallowWall = VariantID(rawValue: "push.wall_push_up.shallow")
    private let wall = VariantID(rawValue: "push.wall_push_up")
    private let partialSit = VariantID(rawValue: "squat.sit_to_stand.partial")

    // MARK: - Status

    func testStatusPassesThroughTheEngine() throws {
        let empty = makeRig()
        XCTAssertEqual(empty.coordinator.status(asOf: date(day: 20)), .needsCalibration)

        let rig = makeRig(facts: calibrated(.push, at: shallowWall, dose: .reps(3)))
        let expected = try rig.engine.todaySession(asOf: date(day: 20))
        XCTAssertEqual(rig.coordinator.status(asOf: date(day: 20)), expected)
        guard case .ready = expected else { return XCTFail("A calibrated family should be ready.") }
    }

    func testAnEngineErrorReadsAsNothingOffered() {
        let store = FailingStore(facts: calibrated(.push, at: shallowWall, dose: .reps(3)))
        store.failsReading = true
        let rig = makeRig(store: store)
        XCTAssertEqual(rig.coordinator.status(asOf: date(day: 20)), .nothingOffered)
        XCTAssertNil(rig.coordinator.start(asOf: date(day: 20)))
        XCTAssertNil(rig.coordinator.preparedLaunch)
    }

    // MARK: - Start

    func testStartWorksOnlyWhenReady() {
        let rig = makeRig()

        XCTAssertNil(rig.coordinator.start(asOf: date(day: 20)))
        XCTAssertNil(rig.coordinator.preparedLaunch)
        XCTAssertNotNil(rig.coordinator.lastStartProblem)
        XCTAssertTrue(rig.facts.prescriptions.isEmpty, "Nothing is issued when nothing is ready.")
    }

    func testStartIssuesThePrescriptionAndBuildsTheReducedRangeRepsPlan() throws {
        let rig = makeRig(facts: calibrated(.push, at: shallowWall, dose: .reps(3)))

        let launch = try XCTUnwrap(rig.coordinator.start(asOf: date(day: 20)))

        XCTAssertEqual(launch.prescription.id, rig.ids.uuid(1))
        XCTAssertEqual(launch.prescription.kind, .todaySession)
        XCTAssertEqual(launch.prescription.issuedAt, date(day: 20))
        XCTAssertEqual(launch.prescription.items.map(\.id), [rig.ids.uuid(2)])
        XCTAssertEqual(launch.prescription.items.map(\.role), [.main])
        XCTAssertEqual(rig.facts.prescriptions, [launch.prescription])
        XCTAssertEqual(rig.coordinator.preparedLaunch, launch)
        XCTAssertNil(rig.coordinator.lastStartProblem)

        XCTAssertEqual(launch.plan.id, AdaptiveTrainingCoordinator.todaySessionPlanID)
        XCTAssertEqual(launch.plan.name, "Today's Session")
        let planItem = try XCTUnwrap(launch.plan.items.first)
        XCTAssertEqual(launch.plan.items.count, 1)
        XCTAssertEqual(planItem.id, rig.ids.uuid(2), "The plan item's id is the prescription item's id.")
        XCTAssertEqual(planItem.exerciseID, .wallPushUp)
        XCTAssertEqual(planItem.sets, 1)
        XCTAssertEqual(planItem.targetReps, 3...3)
        XCTAssertTrue(planItem.reducedRange)
        XCTAssertFalse(planItem.isOptional)

        let item = try XCTUnwrap(launch.items.first)
        XCTAssertEqual(item, AdaptivePlanItem(itemID: rig.ids.uuid(2), role: .main, family: .push,
                                              rungDose: RungDose(variant: shallowWall, dose: .reps(3)),
                                              exerciseID: .wallPushUp, reducedRange: true))
    }

    func testAFullRangeRungIsNotReducedAndOffersAnOptionalSample() throws {
        // Okay twice is not enough; Easy twice on different days at the top of the range makes the next rung due.
        let rig = makeRig(facts: atTopOfRange(wall, top: 12))
        guard case .ready(let session) = rig.coordinator.status(asOf: date(day: 25)),
              let sample = session.harderSample else { return XCTFail("The harder sample should be due.") }
        XCTAssertEqual(sample.dose, .reps(1))

        let launch = try XCTUnwrap(rig.coordinator.start(asOf: date(day: 25)))

        XCTAssertEqual(launch.plan.items.count, 2)
        let main = try XCTUnwrap(launch.plan.items.first)
        let optional = try XCTUnwrap(launch.plan.items.dropFirst().first)
        XCTAssertEqual(main.targetReps, 12...12)
        XCTAssertFalse(main.reducedRange)
        XCTAssertFalse(main.isOptional)
        XCTAssertTrue(optional.isOptional)
        XCTAssertEqual(optional.sets, 1)
        XCTAssertEqual(optional.targetReps, 1...1)
        XCTAssertEqual(optional.id, rig.ids.uuid(3))
        XCTAssertEqual(launch.prescription.items.map(\.role), [.main, .harderSample])
        XCTAssertEqual(launch.prescription.items.map(\.id), [rig.ids.uuid(2), rig.ids.uuid(3)])
        XCTAssertEqual(launch.items.map(\.role), [.main, .harderSample])
        XCTAssertEqual(launch.items.last?.rungDose, sample)
        let exercise = try XCTUnwrap(LiveExerciseCatalog().exercise(optional.exerciseID))
        XCTAssertEqual(optional.label(for: exercise), "Optional: Incline Push-Up")
        XCTAssertEqual(main.label(for: try XCTUnwrap(LiveExerciseCatalog().exercise(main.exerciseID))), "Wall Push-Up")
    }

    func testAShallowAndFullRangeRungCanShareOneExerciseInOnePlan() throws {
        let plan = WorkoutPlan(id: nil, name: "Plan", items: [
            WorkoutPlanItem(id: UUID(), exerciseID: .wallPushUp, sets: 1, targetReps: 3...3, reducedRange: true),
            WorkoutPlanItem(id: UUID(), exerciseID: .wallPushUp, sets: 1, targetReps: 1...1)
        ])
        var session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp, plan: plan)
        XCTAssertEqual(session.exercise?.displayName, "Shallow Wall Push-Up")
        XCTAssertEqual(session.exercise?.targetReps, 3...3)

        _ = session.handle(.opened, at: 0)
        _ = session.handle(.command(.nextExercise), at: 1)
        XCTAssertEqual(session.exercise?.displayName, "Wall Push-Up", "The next occurrence runs the full range.")
        XCTAssertEqual(session.exercise?.targetReps, 1...1)
    }

    func testSecondsDosesBuildTimedPlanItems() throws {
        let hold = ProgressionCatalog(version: "test-1", families: [
            MovementFamily(id: .core, debugName: "Core", rungs: [
                ProgressionRung(id: VariantID(rawValue: "core.test_hold"), exerciseID: "shoulder_press",
                                doseRange: .seconds(5...45), isFloor: true)
            ])
        ])
        let rig = makeRig(facts: calibrated(.core, at: VariantID(rawValue: "core.test_hold"), dose: .seconds(20)),
                          ladders: hold, exercises: TimedCatalog())

        let launch = try XCTUnwrap(rig.coordinator.start(asOf: date(day: 20)))

        let planItem = try XCTUnwrap(launch.plan.items.first)
        XCTAssertEqual(planItem.targetReps, 20...20, "Seconds for a timed dose.")
        XCTAssertFalse(planItem.reducedRange)
        XCTAssertEqual(launch.items.first?.rungDose.dose, .seconds(20))
    }

    func testARungWhoseExerciseCountsTheOtherUnitIsNotStarted() {
        let hold = ProgressionCatalog(version: "test-1", families: [
            MovementFamily(id: .core, debugName: "Core", rungs: [
                ProgressionRung(id: VariantID(rawValue: "core.test_hold"), exerciseID: "shoulder_press",
                                doseRange: .seconds(5...45), isFloor: true)
            ])
        ])
        // The real shoulder press counts reps, so a dose in seconds can't run on it.
        let rig = makeRig(facts: calibrated(.core, at: VariantID(rawValue: "core.test_hold"), dose: .seconds(20)),
                          ladders: hold)

        XCTAssertNil(rig.coordinator.start(asOf: date(day: 20)))
        XCTAssertNotNil(rig.coordinator.lastStartProblem)
        XCTAssertTrue(rig.facts.prescriptions.isEmpty, "Nothing is issued for a session that can't run.")
    }

    func testAMainRungTheAppCannotResolveIsNotStarted() {
        let ghost = ProgressionCatalog(version: "test-1", families: [
            MovementFamily(id: .core, debugName: "Core", rungs: [
                ProgressionRung(id: VariantID(rawValue: "core.ghost"), exerciseID: "ghost_move",
                                doseRange: .reps(1...5), isFloor: true)
            ])
        ])
        // The engine believes the exercise exists; the coach's catalog has never heard of it.
        let rig = makeRig(facts: calibrated(.core, at: VariantID(rawValue: "core.ghost"), dose: .reps(2)),
                          ladders: ghost, builtExerciseIDs: ["ghost_move"])

        XCTAssertEqual(rig.coordinator.status(asOf: date(day: 20)).isReady, true)
        XCTAssertNil(rig.coordinator.start(asOf: date(day: 20)))
        XCTAssertNotNil(rig.coordinator.lastStartProblem)
        XCTAssertTrue(rig.facts.prescriptions.isEmpty)
    }

    func testASampleTheAppCannotRunIsLeftOutOfThePrescription() throws {
        // Incline push-ups are built for the engine but missing from the coach's catalog.
        let withoutIncline = FakeCatalog(all: ExerciseCatalog.all.filter { $0.id != .inclinePushUp })
        let rig = makeRig(facts: atTopOfRange(wall, top: 12), exercises: withoutIncline,
                          builtExerciseIDs: Set(ExerciseCatalog.all.map(\.id.rawValue)))
        guard case .ready(let session) = rig.coordinator.status(asOf: date(day: 25)), session.harderSample != nil else {
            return XCTFail("The engine should offer the sample.")
        }

        let launch = try XCTUnwrap(rig.coordinator.start(asOf: date(day: 25)))

        XCTAssertEqual(launch.plan.items.count, 1)
        XCTAssertEqual(launch.prescription.items.map(\.role), [.main], "Nothing is recorded that was never offered.")
    }

    // MARK: - Active rung

    func testActiveRungMatchesOnlyTheCurrentRungOfAnActiveFamily() throws {
        var facts = calibrated(.push, at: shallowWall, dose: .reps(3))
        facts = merging(facts, calibration: calibration(.squat, at: partialSit, dose: .reps(2), day: 11, kind: .addFamily))
        let rig = makeRig(facts: facts)

        let shallow = try XCTUnwrap(rig.coordinator.activeRung(for: .wallPushUp, reducedRange: true))
        XCTAssertEqual(shallow, ActiveRung(family: .push, rungDose: RungDose(variant: shallowWall, dose: .reps(3))))
        XCTAssertNil(rig.coordinator.activeRung(for: .wallPushUp, reducedRange: false),
                     "The full-range wall push-up is a different rung than the shallow floor.")
        XCTAssertNil(rig.coordinator.activeRung(for: .inclinePushUp, reducedRange: false), "Not the current rung.")
        XCTAssertEqual(rig.coordinator.activeRung(for: .sitToStand, reducedRange: true)?.family, .squat)
        XCTAssertNil(rig.coordinator.activeRung(for: .sitToStand, reducedRange: false))
        XCTAssertNil(rig.coordinator.activeRung(for: .shoulderPress, reducedRange: false), "No family uses it.")
    }

    func testAnInactiveFamilyHasNoActiveRung() throws {
        // Push is calibrated, then removed; squat was never started.
        var facts = calibrated(.push, at: shallowWall, dose: .reps(3))
        facts = AdaptiveFacts(prescriptions: facts.prescriptions, evidence: facts.evidence,
                              calibrations: facts.calibrations, engagement: facts.engagement,
                              settings: [SettingsFact(id: UUID(), recordedAt: date(day: 12), kind: .familyRemoved,
                                                      family: .push)])
        let rig = makeRig(facts: facts)

        XCTAssertNil(rig.coordinator.activeRung(for: .wallPushUp, reducedRange: true), "A removed family is inactive.")
        XCTAssertNil(rig.coordinator.activeRung(for: .sitToStand, reducedRange: true), "A family never started is inactive.")
    }

    // MARK: - Recording

    func testRecordSavesEvidenceThroughTheEngineAndASecondSaveOfTheSameIDIsHarmless() throws {
        let rig = makeRig(facts: calibrated(.push, at: shallowWall, dose: .reps(3)))
        let evidence = AdaptiveEvidence(id: rig.ids.uuid(9), recordedAt: date(day: 21), source: .manual, family: .push,
                                        variant: shallowWall, confirmed: .reps(3), confirmation: .user,
                                        tracker: .notTracked, effort: .okay, completion: .completed)

        rig.coordinator.record(evidence)
        rig.coordinator.record(evidence)

        XCTAssertEqual(rig.facts.evidence, [evidence])
    }

    func testAFailedSaveIsLoggedAndNeverThrown() {
        let store = FailingStore(facts: .empty)
        store.failsRecording = true
        let rig = makeRig(store: store)
        let evidence = AdaptiveEvidence(id: UUID(), recordedAt: date(day: 21), source: .manual, family: .push,
                                        variant: shallowWall, confirmed: nil, confirmation: .none,
                                        tracker: .notTracked, effort: nil, completion: .completed)

        rig.coordinator.record(evidence)

        XCTAssertTrue(rig.facts.evidence.isEmpty)
    }

    func testTheTodayPlanIDIsFixedAndMatchesNoRoutine() {
        XCTAssertEqual(AdaptiveTrainingCoordinator.todaySessionPlanID.uuidString, "70DA0000-0000-4000-8000-000000000001")
        XCTAssertFalse(BuiltInRoutines.all.contains { $0.id == AdaptiveTrainingCoordinator.todaySessionPlanID })
    }

    // MARK: - Calibration

    /// A flow that has finished the quiz for push alone, answering "Not sure", so its first sample is the floor.
    private func pushFlow(_ rig: Rig) throws -> CalibrationFlow {
        var flow = try XCTUnwrap(rig.coordinator.startCalibration(asOf: date(day: 20)))
        flow.setEquipment([])
        flow.setFamilies([.push])
        flow.answerCloseness(family: .push, variant: nil)
        return flow
    }

    func testStartingACalibrationSavesAnInProgressAttemptWithAFreshID() throws {
        let rig = makeRig()

        let flow = try XCTUnwrap(rig.coordinator.startCalibration(asOf: date(day: 20)))

        XCTAssertEqual(flow.id, rig.ids.uuid(1))
        XCTAssertEqual(flow.kind, .initial)
        XCTAssertEqual(flow.startedAt, date(day: 20))
        XCTAssertEqual(rig.facts.calibrations, [flow.inProgressRecord])
        XCTAssertEqual(rig.coordinator.status(asOf: date(day: 21)), .needsCalibration)
    }

    func testPreparingASampleBuildsAOneItemPlanForItsRungAndSavesNothing() throws {
        let rig = makeRig()
        let flow = try pushFlow(rig)

        let launch = try XCTUnwrap(rig.coordinator.prepareProbe(for: flow, asOf: date(day: 20), onResult: { _ in }))

        XCTAssertEqual(launch.family, .push)
        XCTAssertEqual(launch.rungDose, RungDose(variant: shallowWall, dose: .reps(2)))
        XCTAssertEqual(launch.id, launch.launch.prescription.id)
        XCTAssertEqual(launch.id, launch.recorder.launchID)
        XCTAssertEqual(launch.launch.plan.name, AdaptiveTrainingCoordinator.calibrationProbeName)
        XCTAssertNil(launch.launch.plan.id, "It matches no routine and is not Today's Session.")
        let planItem = try XCTUnwrap(launch.launch.plan.items.first)
        XCTAssertEqual(launch.launch.plan.items.count, 1)
        XCTAssertEqual(planItem.exerciseID, .wallPushUp)
        XCTAssertEqual(planItem.sets, 1)
        XCTAssertEqual(planItem.targetReps, 2...2)
        XCTAssertTrue(planItem.reducedRange, "The floor is the shallow variant.")
        XCTAssertFalse(planItem.isOptional)
        XCTAssertEqual(launch.launch.items, [AdaptivePlanItem(itemID: planItem.id, role: .main, family: .push,
                                                              rungDose: launch.rungDose, exerciseID: .wallPushUp,
                                                              reducedRange: true)])
        XCTAssertEqual(launch.launch.prescription.kind, .calibrationProbe)
        XCTAssertEqual(launch.launch.prescription.items.map(\.offersBonus), [false], "A sample never offers a bonus.")
        XCTAssertTrue(rig.facts.prescriptions.isEmpty, "The sample's prescription is never saved.")
    }

    func testThereIsNoSampleToPrepareOutsideASampleStep() throws {
        let rig = makeRig()
        let flow = try XCTUnwrap(rig.coordinator.startCalibration(asOf: date(day: 20)))

        XCTAssertEqual(flow.step, .equipment)
        XCTAssertNil(rig.coordinator.prepareProbe(for: flow, asOf: date(day: 20), onResult: { _ in }))
    }

    func testTheProbeRecorderTurnsCoachEvidenceIntoAProbeAndReportsOnlyTheFirstResult() throws {
        let rig = makeRig()
        let flow = try pushFlow(rig)
        var results: [CalibrationProbeResult] = []
        let launch = try XCTUnwrap(rig.coordinator.prepareProbe(for: flow, asOf: date(day: 20),
                                                                onResult: { results.append($0) }))
        let item = try XCTUnwrap(launch.launch.items.first)
        let workoutID = UUID()
        func coachEvidence(_ id: UUID, effort: EffortFeedback?) -> AdaptiveEvidence {
            AdaptiveEvidence(id: id, recordedAt: date(day: 20, hour: 11), source: .adaptive, family: .push,
                             variant: shallowWall, prescriptionID: launch.launch.prescription.id,
                             prescriptionItemID: item.itemID, workoutID: workoutID, prescribed: .reps(2),
                             confirmed: .reps(2), confirmation: .trackerAccepted,
                             tracker: TrackerObservation(status: .tracked, observed: .reps(2)), effort: effort,
                             midSetTooHard: true, bonus: BonusRecord(offered: .reps(1), accepted: false),
                             completion: .completed)
        }
        let first = coachEvidence(rig.ids.uuid(40), effort: .easy)

        launch.recorder.record(first)

        let stored = try XCTUnwrap(rig.facts.evidence.first)
        XCTAssertEqual(rig.facts.evidence.count, 1)
        XCTAssertEqual(stored.id, first.id)
        XCTAssertEqual(stored.source, .calibration)
        XCTAssertEqual(stored.calibrationID, flow.id)
        XCTAssertNil(stored.prescriptionID)
        XCTAssertNil(stored.prescriptionItemID)
        XCTAssertNil(stored.bonus)
        XCTAssertEqual(stored.workoutID, workoutID)
        XCTAssertEqual(stored.recordedAt, first.recordedAt)
        XCTAssertEqual(stored.family, .push)
        XCTAssertEqual(stored.variant, shallowWall)
        XCTAssertEqual(stored.prescribed, .reps(2))
        XCTAssertEqual(stored.confirmed, .reps(2))
        XCTAssertEqual(stored.confirmation, .trackerAccepted)
        XCTAssertEqual(stored.tracker, first.tracker)
        XCTAssertEqual(stored.effort, .easy)
        XCTAssertTrue(stored.midSetTooHard)
        XCTAssertEqual(stored.completion, .completed)
        XCTAssertEqual(results, [CalibrationProbeResult(launchID: launch.id, effort: .easy, confirmed: .reps(2))])

        launch.recorder.record(coachEvidence(rig.ids.uuid(41), effort: nil))

        XCTAssertEqual(rig.facts.evidence.count, 2, "Everything the coach records is kept.")
        XCTAssertEqual(results.count, 1, "Only the first result is reported.")
    }

    func testTheProbeRecorderKnowsNoActiveRungAndOffersNoEasierVersion() throws {
        let rig = makeRig()
        let flow = try pushFlow(rig)
        let launch = try XCTUnwrap(rig.coordinator.prepareProbe(for: flow, asOf: date(day: 20), onResult: { _ in }))
        let item = PrescriptionItem(id: rig.ids.uuid(50), family: .push,
                                    target: RungDose(variant: wall, dose: .reps(2)))

        XCTAssertNil(launch.recorder.activeRung(for: .wallPushUp, reducedRange: false))
        XCTAssertNil(launch.recorder.easierSwapOption(for: item, asOf: date(day: 20)))
    }

    func testDisplayNamesArePlainExerciseNames() {
        let rig = makeRig()

        XCTAssertEqual(rig.coordinator.displayName(of: wall), "Wall Push-Up")
        XCTAssertEqual(rig.coordinator.displayName(of: shallowWall), "Shallow Wall Push-Up")
        let unknown = VariantID(rawValue: "push.unknown")
        XCTAssertEqual(rig.coordinator.displayName(of: unknown), "push.unknown", "An unknown rung falls back to its ID.")
    }

    func testCommittingNeedsASummaryAndAbandoningNeverReachesACommittedAttempt() throws {
        let rig = makeRig()
        var flow = try pushFlow(rig)
        XCTAssertFalse(rig.coordinator.commitCalibration(flow, asOf: date(day: 20, hour: 12)),
                       "A sample is still waiting.")
        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.inProgress])

        flow.probeResult(family: .push, effort: .okay, confirmed: .reps(2))
        XCTAssertTrue(rig.coordinator.commitCalibration(flow, asOf: date(day: 20, hour: 12)))
        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.committed])
        XCTAssertEqual(try rig.engine.profile().states.map(\.family), [.push])

        rig.coordinator.abandonCalibration(flow, asOf: date(day: 20, hour: 13))
        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.committed], "A committed attempt never changes.")
    }

    func testAbandoningRecordsAnAbandonedAttemptThatChangesNothing() throws {
        let rig = makeRig()
        let flow = try pushFlow(rig)

        rig.coordinator.abandonCalibration(flow, asOf: date(day: 20, hour: 12))

        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.abandoned])
        XCTAssertEqual(rig.coordinator.status(asOf: date(day: 21)), .needsCalibration)
    }

    // MARK: - Rig

    @MainActor
    private struct Rig {
        let store: any AdaptiveTrainingStoring
        let engine: AdaptiveTrainingEngine
        let coordinator: AdaptiveTrainingCoordinator
        let ids: IDs

        /// Everything the store holds, read directly rather than through the coordinator.
        var facts: AdaptiveFacts { (try? store.loadFacts()) ?? .empty }
    }

    /// Hands out ids 1, 2, 3, ... so a test can name the id each fact received.
    private final class IDs {
        private var next = 0

        func make() -> UUID {
            next += 1
            return uuid(next)
        }

        func uuid(_ number: Int) -> UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: number)))
        }
    }

    private func makeRig(facts: AdaptiveFacts = .empty, store: (any AdaptiveTrainingStoring)? = nil,
                         ladders: ProgressionCatalog = .v1, exercises: any ExerciseCatalogProviding = LiveExerciseCatalog(),
                         builtExerciseIDs: Set<String>? = nil) -> Rig {
        let store: any AdaptiveTrainingStoring = store ?? InMemoryAdaptiveTrainingStore(facts: facts)
        let bridge = ExerciseVariantBridge(exercises: exercises, ladders: ladders)
        let built = builtExerciseIDs ?? bridge.availability(equipment: []).builtExerciseIDs
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: built, calendar: calendar, catalog: ladders)
        let ids = IDs()
        let coordinator = AdaptiveTrainingCoordinator(engine: engine, bridge: bridge, makeID: { ids.make() })
        return Rig(store: store, engine: engine, coordinator: coordinator, ids: ids)
    }

    // MARK: - Facts

    private func calibration(_ family: MovementFamilyID, at variant: VariantID, dose: Dose, day: Int = 10,
                             kind: CalibrationKind = .initial) -> CalibrationSessionRecord {
        CalibrationSessionRecord(id: UUID(uuid: (0xCA, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(day))),
                                 kind: kind, startedAt: date(day: day, hour: 9), endedAt: date(day: day, hour: 9),
                                 status: .committed, families: [family],
                                 startingPoints: [CalibrationStart(family: family, start: RungDose(variant: variant, dose: dose))])
    }

    private func calibrated(_ family: MovementFamilyID, at variant: VariantID, dose: Dose) -> AdaptiveFacts {
        AdaptiveFacts(calibrations: [calibration(family, at: variant, dose: dose)])
    }

    private func merging(_ facts: AdaptiveFacts, calibration: CalibrationSessionRecord) -> AdaptiveFacts {
        AdaptiveFacts(prescriptions: facts.prescriptions, evidence: facts.evidence,
                      calibrations: facts.calibrations + [calibration], engagement: facts.engagement,
                      settings: facts.settings)
    }

    /// A rung at the top of its range with Easy on two different days, so the next rung is offered as a sample.
    private func atTopOfRange(_ variant: VariantID, top: Int) -> AdaptiveFacts {
        let easy = { (day: Int) in
            AdaptiveEvidence(id: UUID(uuid: (0xE5, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(day))),
                             recordedAt: self.date(day: day), source: .manual, family: .push, variant: variant,
                             confirmed: .reps(top), confirmation: .user, tracker: .notTracked, effort: .easy,
                             completion: .completed)
        }
        return AdaptiveFacts(evidence: [easy(20), easy(21)],
                             calibrations: [calibration(.push, at: variant, dose: .reps(top))])
    }
}

private extension TodaySessionStatus {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

private struct FakeCatalog: ExerciseCatalogProviding {
    var all: [ExerciseDefinition]

    func exercise(_ id: ExerciseID) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }
}

/// A catalog whose shoulder press is a self-reported hold measured in seconds.
private struct TimedCatalog: ExerciseCatalogProviding {
    var all: [ExerciseDefinition] {
        var hold = ShoulderPressExercise.definition()
        hold.tracking = .selfReported
        hold.doseUnit = .seconds
        hold.targetReps = 20...20
        hold.autoCompleteReps = 20
        return [hold]
    }

    func exercise(_ id: ExerciseID) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }
}

/// A store whose reads or writes fail on demand, around an in-memory one.
@MainActor
private final class FailingStore: AdaptiveTrainingStoring {
    var failsReading = false
    var failsRecording = false
    private let inner: InMemoryAdaptiveTrainingStore

    init(facts: AdaptiveFacts) {
        inner = InMemoryAdaptiveTrainingStore(facts: facts)
    }

    func loadFacts() throws -> AdaptiveFacts {
        if failsReading { throw CocoaError(.fileReadUnknown) }
        return try inner.loadFacts()
    }

    func record(_ prescription: Prescription) throws {
        if failsRecording { throw CocoaError(.fileWriteUnknown) }
        try inner.record(prescription)
    }

    func record(_ evidence: AdaptiveEvidence) throws {
        if failsRecording { throw CocoaError(.fileWriteUnknown) }
        try inner.record(evidence)
    }

    func save(_ calibration: CalibrationSessionRecord) throws { try inner.save(calibration) }
    func record(_ engagement: EngagementFact) throws { try inner.record(engagement) }
    func record(_ setting: SettingsFact) throws { try inner.record(setting) }
    func loadCachedProfile() -> CachedProfile? { inner.loadCachedProfile() }
    func saveCachedProfile(_ profile: CachedProfile) throws { try inner.saveCachedProfile(profile) }
}
