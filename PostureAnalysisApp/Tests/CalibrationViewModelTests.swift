import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

/// The calibration screen's state: the quiz, the coach samples, the summary, and leaving. The flow's own rules are
/// tested in the package; these tests check that the app shows what the flow returns and records exactly its facts.
@MainActor
final class CalibrationViewModelTests: XCTestCase {
    /// A clock the tests move forward as the coach records evidence, so every fact has its own time.
    private final class TestClock {
        var value = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private let clock = TestClock()
    private var now: Date { clock.value }
    private let shallow = VariantID(rawValue: "push.wall_push_up.shallow")
    private let wall = VariantID(rawValue: "push.wall_push_up")
    private let incline = VariantID(rawValue: "push.incline_push_up")
    private let partialSit = VariantID(rawValue: "squat.sit_to_stand.partial")
    private let sit = VariantID(rawValue: "squat.sit_to_stand")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    // MARK: - Rig

    private final class Counter {
        var count = 0
    }

    @MainActor
    private struct Rig {
        let store: InMemoryAdaptiveTrainingStore
        let engine: AdaptiveTrainingEngine
        let coordinator: AdaptiveTrainingCoordinator
        let viewModel: CalibrationViewModel
        let finished: Counter

        var facts: AdaptiveFacts { store.facts }
    }

    private func makeRig(facts: AdaptiveFacts = .empty) -> Rig {
        let store = InMemoryAdaptiveTrainingStore(facts: facts)
        let bridge = ExerciseVariantBridge()
        let engine = AdaptiveTrainingEngine(store: store,
                                            builtExerciseIDs: bridge.availability(equipment: []).builtExerciseIDs,
                                            calendar: calendar)
        let coordinator = AdaptiveTrainingCoordinator(engine: engine, bridge: bridge)
        let finished = Counter()
        let clock = clock
        let viewModel = CalibrationViewModel(coordinator: coordinator, now: { clock.value },
                                             onFinish: { finished.count += 1 })
        return Rig(store: store, engine: engine, coordinator: coordinator, viewModel: viewModel, finished: finished)
    }

    /// What the coach does when a sample is rated: it records the evidence it builds for any prescribed item, to the
    /// recorder it was given.
    private func coachRecords(_ viewModel: CalibrationViewModel, effort: EffortFeedback?, confirmed: WorkAmount? = nil,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let launch = try XCTUnwrap(viewModel.probeLaunch, "No sample is running.", file: file, line: line)
        let item = try XCTUnwrap(launch.launch.items.first, file: file, line: line)
        let amount = confirmed ?? WorkAmount(launch.rungDose.dose)
        let confirmation: ConfirmationSource = effort == nil ? .none : .user
        clock.value = clock.value.addingTimeInterval(60)
        launch.recorder.record(AdaptiveEvidence(
            id: UUID(), recordedAt: now, source: .adaptive, family: launch.family, variant: launch.rungDose.variant,
            prescriptionID: launch.launch.prescription.id, prescriptionItemID: item.itemID, workoutID: UUID(),
            prescribed: launch.rungDose.dose, confirmed: amount, confirmation: confirmation, tracker: .notTracked,
            effort: effort, completion: .completed))
    }

    private func rateSample(_ viewModel: CalibrationViewModel, _ effort: EffortFeedback?, confirmed: WorkAmount? = nil,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        viewModel.startSample()
        try coachRecords(viewModel, effort: effort, confirmed: confirmed, file: file, line: line)
    }

    /// Through the quiz with push and squat, answering push "wall push-up" and squat "Not sure".
    private func finishQuiz(_ viewModel: CalibrationViewModel, families: Set<MovementFamilyID> = [.push, .squat]) {
        viewModel.begin()
        viewModel.continueFromEquipment()
        for family in [MovementFamilyID.push, .squat] where !families.contains(family) {
            viewModel.toggleFamily(family)
        }
        viewModel.continueFromAreas()
        for _ in 0..<4 {
            guard case .closeness(let family, _)? = viewModel.step else { break }
            viewModel.answerCloseness(family == .push ? wall : nil)
        }
    }

    private func summaryPoints(_ viewModel: CalibrationViewModel) -> [CalibrationStart] {
        guard case .summary(let points)? = viewModel.step else { return [] }
        return points
    }

    private func seededPush() -> AdaptiveFacts {
        AdaptiveFacts(calibrations: [
            CalibrationSessionRecord(id: UUID(), kind: .initial, startedAt: now.addingTimeInterval(-86_400 * 5),
                                     endedAt: now.addingTimeInterval(-86_400 * 5), status: .committed,
                                     families: [.push],
                                     startingPoints: [CalibrationStart(family: .push,
                                                                       start: RungDose(variant: wall, dose: .reps(3)))])
        ])
    }

    // MARK: - The whole flow

    func testKindReachesCoordinatorAndUsesItsOwnCopy() {
        let expected: [(CalibrationKind, String, String, String, String)] = [
            (.initial, CalibrationCopy.title, CalibrationCopy.intro,
             CalibrationCopy.areasTitle, CalibrationCopy.areasDetail),
            (.recalibration, CalibrationCopy.recalibrationTitle, CalibrationCopy.recalibrationIntro,
             CalibrationCopy.recalibrationAreasTitle, CalibrationCopy.recalibrationAreasDetail),
            (.addFamily, CalibrationCopy.addFamilyTitle, CalibrationCopy.addFamilyIntro,
             CalibrationCopy.addFamilyAreasTitle, CalibrationCopy.addFamilyAreasDetail)
        ]

        for (kind, title, intro, areasTitle, areasDetail) in expected {
            let rig = makeRig()
            let model = CalibrationViewModel(coordinator: rig.coordinator, kind: kind, now: { self.now })
            model.begin()

            XCTAssertEqual(model.flow?.kind, kind)
            XCTAssertEqual(model.title, title)
            XCTAssertEqual(model.intro, intro)
            XCTAssertEqual(model.areasTitle, areasTitle)
            XCTAssertEqual(model.areasDetail, areasDetail)
            XCTAssertEqual(model.summaryDetail, kind == .initial ? CalibrationCopy.summaryDetail : CalibrationCopy.continuedSummaryDetail)
        }
    }

    func testWordingScanIncludesEveryNewKindString() {
        let newStrings = [CalibrationCopy.recalibrationTitle, CalibrationCopy.recalibrationIntro,
                          CalibrationCopy.recalibrationAreasTitle, CalibrationCopy.recalibrationAreasDetail,
                          CalibrationCopy.addFamilyTitle, CalibrationCopy.addFamilyIntro,
                          CalibrationCopy.addFamilyAreasTitle, CalibrationCopy.addFamilyAreasDetail,
                          CalibrationCopy.continuedSummaryDetail]
        for value in newStrings {
            XCTAssertTrue(CalibrationCopy.all.contains(value), "Missing from wording scan: \(value)")
        }
    }

    func testNothingIsSavedUntilTheScreenBegins() {
        let rig = makeRig()

        XCTAssertNil(rig.viewModel.step)
        XCTAssertTrue(rig.facts.calibrations.isEmpty)

        rig.viewModel.begin()

        XCTAssertEqual(rig.viewModel.step, .equipment)
        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.inProgress])
        rig.viewModel.begin()
        XCTAssertEqual(rig.facts.calibrations.count, 1, "Beginning again starts nothing new.")
    }

    func testTheQuizOffersWhatTheDeviceCanRunAndPreselectsPushAndSquat() {
        let rig = makeRig()
        rig.viewModel.begin()
        rig.viewModel.toggleEquipment(.dumbbells)
        rig.viewModel.continueFromEquipment()

        XCTAssertEqual(rig.viewModel.step, .families)
        XCTAssertTrue(rig.viewModel.offeredFamilies.contains(.push) && rig.viewModel.offeredFamilies.contains(.squat))
        XCTAssertEqual(rig.viewModel.offeredFamilies, rig.engine.catalog.offerableFamilies(
            availability: ExerciseVariantBridge().availability(equipment: [.dumbbells])),
                       "Only areas whose gentlest exercise is built are offered.")
        XCTAssertEqual(rig.viewModel.selectedFamilies, [.push, .squat])
        let record = rig.facts.calibrations.first
        XCTAssertEqual(record?.equipment, [.dumbbells], "The equipment answer is saved as the quiz goes.")
    }

    func testQuizSamplesRatingsAndCommitRecordExactlyTheFlowsFacts() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel)
        let flowID = try XCTUnwrap(rig.viewModel.flow?.id)

        // Push: Easy offers a harder sample, which is Okay.
        guard case .probe(.push, let first, false)? = rig.viewModel.step else {
            return XCTFail("Expected the push sample, got \(String(describing: rig.viewModel.step)).")
        }
        XCTAssertEqual(first, RungDose(variant: wall, dose: .reps(2)))
        XCTAssertEqual(rig.viewModel.sample?.exercise, "Wall Push-Up")
        XCTAssertEqual(rig.viewModel.sample?.amount, "2 reps")
        try rateSample(rig.viewModel, .easy)
        guard case .probe(.push, let harder, true)? = rig.viewModel.step else {
            return XCTFail("Expected a harder offer, got \(String(describing: rig.viewModel.step)).")
        }
        XCTAssertEqual(harder, RungDose(variant: incline, dose: .reps(1)))
        try rateSample(rig.viewModel, .okay)

        // Squat: Not sure starts at the floor, which is Okay.
        guard case .probe(.squat, let squat, false)? = rig.viewModel.step else {
            return XCTFail("Expected the squat sample, got \(String(describing: rig.viewModel.step)).")
        }
        XCTAssertEqual(squat, RungDose(variant: partialSit, dose: .reps(2)))
        try rateSample(rig.viewModel, .okay)

        let points = summaryPoints(rig.viewModel)
        XCTAssertEqual(points, [CalibrationStart(family: .push, start: RungDose(variant: incline, dose: .reps(1))),
                                CalibrationStart(family: .squat, start: RungDose(variant: partialSit, dose: .reps(2)))])
        XCTAssertEqual(rig.viewModel.summaryLines.first?.text, "Push: Incline Push-Up × 1")
        XCTAssertEqual(rig.viewModel.summaryLines.count, 2)
        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.inProgress], "Nothing counts before the summary is accepted.")
        XCTAssertTrue(try rig.engine.profile().needsCalibration)

        rig.viewModel.useThese()

        XCTAssertEqual(rig.viewModel.outcome, .committed)
        XCTAssertEqual(rig.finished.count, 0, "The screen stays up until Done.")
        let record = try XCTUnwrap(rig.facts.calibrations.first)
        XCTAssertEqual(rig.facts.calibrations.count, 1)
        XCTAssertEqual(record.id, flowID)
        XCTAssertEqual(record.kind, .initial)
        XCTAssertEqual(record.status, .committed)
        XCTAssertEqual(record.endedAt, now)
        XCTAssertEqual(record.families, [.push, .squat])
        XCTAssertEqual(record.equipment, [])
        XCTAssertEqual(record.startingPoints, points)

        XCTAssertEqual(rig.facts.evidence.count, 3)
        XCTAssertTrue(rig.facts.evidence.allSatisfy { $0.source == .calibration && $0.calibrationID == flowID })
        XCTAssertTrue(rig.facts.evidence.allSatisfy { $0.prescriptionID == nil && $0.prescriptionItemID == nil })
        XCTAssertEqual(rig.facts.evidence.map(\.variant), [wall, incline, partialSit])
        XCTAssertEqual(rig.facts.evidence.map(\.effort), [.easy, .okay, .okay])
        XCTAssertTrue(rig.facts.prescriptions.isEmpty, "A sample's prescription is never saved.")

        let profile = try rig.engine.profile()
        XCTAssertEqual(profile.activeFamilies, [.push, .squat])
        XCTAssertEqual(profile.state(.push)?.current, RungDose(variant: incline, dose: .reps(1)))
        XCTAssertEqual(profile.state(.squat)?.current, RungDose(variant: partialSit, dose: .reps(2)))

        rig.viewModel.finish()
        XCTAssertEqual(rig.finished.count, 1)
    }

    // MARK: - Samples

    func testADeclinedHarderOfferSettlesNeutrallyAtTheEasySample() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel, families: [.push])
        try rateSample(rig.viewModel, .easy)
        XCTAssertEqual(rig.viewModel.sample?.isHarderOffer, true)

        rig.viewModel.declineHarderSample()

        XCTAssertEqual(summaryPoints(rig.viewModel),
                       [CalibrationStart(family: .push, start: RungDose(variant: wall, dose: .reps(2)))],
                       "It settles at the Easy sample's own dose, which Easy alone never raises.")
        XCTAssertEqual(rig.facts.evidence.count, 1, "Declining leaves no evidence.")
        XCTAssertEqual(rig.facts.evidence.first?.effort, .easy)
    }

    func testTooHardStepsDownToTheEasierRungAtItsMinimum() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel, families: [.push])

        try rateSample(rig.viewModel, .tooHard)

        guard case .probe(.push, let easier, false)? = rig.viewModel.step else {
            return XCTFail("Expected an easier sample, got \(String(describing: rig.viewModel.step)).")
        }
        XCTAssertEqual(easier, RungDose(variant: shallow, dose: .reps(1)))
        try rateSample(rig.viewModel, .okay)
        XCTAssertEqual(summaryPoints(rig.viewModel),
                       [CalibrationStart(family: .push, start: RungDose(variant: shallow, dose: .reps(1)))])
        XCTAssertEqual(rig.facts.evidence.map(\.effort), [.tooHard, .okay])
    }

    func testASampleNobodyRatedChangesNothingAndIsStillRecorded() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel, families: [.push])
        let before = rig.viewModel.step

        try rateSample(rig.viewModel, nil)

        XCTAssertEqual(rig.viewModel.step, before, "The same sample is offered again.")
        XCTAssertNil(rig.viewModel.probeLaunch)
        XCTAssertEqual(rig.viewModel.notice, CalibrationCopy.noRating)
        XCTAssertEqual(rig.viewModel.flow?.probeCount, 0)
        XCTAssertEqual(rig.facts.evidence.count, 1)
        XCTAssertNil(rig.facts.evidence.first?.effort)
        XCTAssertEqual(rig.facts.evidence.first?.source, .calibration)
    }

    func testClosingTheCoachBeforeARatingDecidesNothing() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel, families: [.push])
        let before = rig.viewModel.step
        rig.viewModel.startSample()
        XCTAssertNotNil(rig.viewModel.probeLaunch)

        rig.viewModel.sampleClosed()

        XCTAssertNil(rig.viewModel.probeLaunch)
        XCTAssertEqual(rig.viewModel.step, before)
        XCTAssertTrue(rig.facts.evidence.isEmpty)
        XCTAssertTrue(rig.viewModel.hasDoneSamples, "The attempt has started a sample, so leaving asks first.")
    }

    func testAnAnswerFromAnotherSampleIsIgnored() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel, families: [.push])
        rig.viewModel.startSample()

        rig.viewModel.receive(CalibrationProbeResult(launchID: UUID(), effort: .easy, confirmed: .reps(2)))

        XCTAssertNotNil(rig.viewModel.probeLaunch, "Still waiting for the sample that is running.")
        XCTAssertEqual(rig.viewModel.flow?.probeCount, 0)
    }

    func testAnOkayWithNothingConfirmedOffersTheSameSampleAgain() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel, families: [.push])
        let before = rig.viewModel.step

        try rateSample(rig.viewModel, .okay, confirmed: .reps(0))

        XCTAssertEqual(rig.viewModel.step, before)
        XCTAssertEqual(rig.viewModel.flow?.probeCount, 1)
    }

    func testASampleTheCoachCannotRunShowsWhyAndCanBeSkipped() {
        let fake = FakeCoordinator()
        fake.canPrepare = false
        let viewModel = CalibrationViewModel(coordinator: fake, now: { self.now })
        viewModel.begin()
        viewModel.continueFromEquipment()
        viewModel.continueFromAreas()
        viewModel.answerCloseness(nil)
        viewModel.answerCloseness(nil)

        viewModel.startSample()

        XCTAssertEqual(viewModel.notice, CalibrationCopy.sampleUnavailable)
        XCTAssertNil(viewModel.probeLaunch)
        viewModel.skipArea()
        XCTAssertNil(viewModel.notice)
        XCTAssertEqual(viewModel.sample?.family, .squat, "Push is left out and squat is next.")
    }

    // MARK: - Skipping

    func testSkippingAnAreaLeavesItOutOfTheSummary() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel)
        rig.viewModel.skipArea()
        try rateSample(rig.viewModel, .okay)

        XCTAssertEqual(summaryPoints(rig.viewModel).map(\.family), [.squat])
        rig.viewModel.useThese()
        XCTAssertEqual(rig.facts.calibrations.first?.families, [.squat])
        XCTAssertEqual(rig.facts.calibrations.first?.startingPoints.map(\.family), [.squat])
    }

    func testSkippingEveryAreaLeavesNothingToUse() {
        let rig = makeRig()
        finishQuiz(rig.viewModel)
        rig.viewModel.skipArea()
        rig.viewModel.skipArea()

        XCTAssertEqual(summaryPoints(rig.viewModel), [])
        XCTAssertTrue(rig.viewModel.summaryLines.isEmpty)
        rig.viewModel.useThese()
        XCTAssertNil(rig.viewModel.outcome, "There is nothing to accept.")
        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.inProgress])

        rig.viewModel.leave()
        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.abandoned])
    }

    func testTheQuizNeedsAtLeastOneArea() {
        let rig = makeRig()
        rig.viewModel.begin()
        rig.viewModel.continueFromEquipment()
        rig.viewModel.toggleFamily(.push)
        rig.viewModel.toggleFamily(.squat)
        XCTAssertFalse(rig.viewModel.canContinueFromAreas)

        rig.viewModel.continueFromAreas()

        XCTAssertEqual(rig.viewModel.step, .families)
        let unknown = MovementFamilyID(rawValue: "swim")
        rig.viewModel.toggleFamily(unknown)
        XCTAssertFalse(rig.viewModel.selectedFamilies.contains(unknown), "Only areas the quiz offers can be chosen.")
    }

    // MARK: - Leaving (invariant 7: nothing changes)

    func testLeavingAtTheQuizRecordsAnAbandonedCalibrationAndChangesNothing() throws {
        let rig = makeRig(facts: seededPush())
        let before = try rig.engine.profile()
        rig.viewModel.begin()
        rig.viewModel.toggleEquipment(.dumbbells)

        rig.viewModel.requestExit()

        XCTAssertFalse(rig.viewModel.isConfirmingExit, "No sample was done, so it leaves without asking.")
        XCTAssertEqual(rig.viewModel.outcome, .left)
        XCTAssertEqual(rig.finished.count, 1)
        XCTAssertEqual(rig.facts.calibrations.filter { $0.status == .abandoned }.count, 1)
        XCTAssertEqual(rig.facts.calibrations.filter { $0.status == .abandoned }.first?.startingPoints, [])
        let after = try rig.engine.profile()
        XCTAssertEqual(after.states, before.states)
        XCTAssertEqual(after.activeFamilies, before.activeFamilies)
        XCTAssertEqual(after.equipment, before.equipment)
    }

    func testLeavingMidSampleAsksFirstThenRecordsAnAbandonedCalibrationAndChangesNothing() throws {
        let rig = makeRig(facts: seededPush())
        let before = try rig.engine.profile()
        finishQuiz(rig.viewModel)
        try rateSample(rig.viewModel, .easy)
        guard case .probe(.push, _, true)? = rig.viewModel.step else {
            return XCTFail("Expected to be mid-sample at a harder offer.")
        }

        rig.viewModel.requestExit()

        XCTAssertTrue(rig.viewModel.isConfirmingExit)
        XCTAssertNil(rig.viewModel.outcome)
        XCTAssertEqual(rig.facts.calibrations.filter { $0.status == .abandoned }.count, 0)
        rig.viewModel.keepGoing()
        XCTAssertFalse(rig.viewModel.isConfirmingExit)
        XCTAssertEqual(rig.finished.count, 0)

        rig.viewModel.requestExit()
        rig.viewModel.confirmLeave()

        XCTAssertEqual(rig.viewModel.outcome, .left)
        XCTAssertEqual(rig.finished.count, 1)
        XCTAssertEqual(rig.facts.calibrations.filter { $0.status == .abandoned }.count, 1)
        XCTAssertEqual(rig.facts.calibrations.filter { $0.status == .committed }.count, 1, "Only the earlier one.")
        let after = try rig.engine.profile()
        XCTAssertEqual(after.states, before.states, "An Easy sample on record changes no recommendation.")
        XCTAssertEqual(after.activeFamilies, before.activeFamilies)
    }

    func testLeavingFromTheSummaryRecordsAnAbandonedCalibrationAndChangesNothing() throws {
        let rig = makeRig(facts: seededPush())
        let before = try rig.engine.profile()
        let todayBefore = try rig.engine.todaySession(asOf: now)
        finishQuiz(rig.viewModel)
        try rateSample(rig.viewModel, .okay)
        try rateSample(rig.viewModel, .okay)
        XCTAssertFalse(summaryPoints(rig.viewModel).isEmpty)

        rig.viewModel.leave()

        XCTAssertEqual(rig.viewModel.outcome, .left)
        XCTAssertEqual(rig.finished.count, 1)
        let abandoned = try XCTUnwrap(rig.facts.calibrations.first { $0.status == .abandoned })
        XCTAssertEqual(abandoned.startingPoints, [], "Leaving accepts nothing, even from the summary.")
        let after = try rig.engine.profile()
        XCTAssertEqual(after.states, before.states)
        XCTAssertEqual(after.activeFamilies, before.activeFamilies)
        XCTAssertEqual(try rig.engine.todaySession(asOf: now), todayBefore)
    }

    func testLeavingWhileTheCoachIsUpClosesIt() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel, families: [.push])
        rig.viewModel.startSample()

        rig.viewModel.leave()

        XCTAssertNil(rig.viewModel.probeLaunch)
        XCTAssertEqual(rig.facts.calibrations.map(\.status), [.abandoned])
    }

    func testAScreenThatCouldNotStartLeavesWithoutRecordingAnything() {
        let fake = FakeCoordinator()
        fake.failsToStart = true
        var finished = 0
        let viewModel = CalibrationViewModel(coordinator: fake, now: { self.now }, onFinish: { finished += 1 })

        viewModel.begin()
        XCTAssertTrue(viewModel.couldNotStart)
        XCTAssertNil(viewModel.step)
        viewModel.requestExit()

        XCTAssertEqual(finished, 1)
        XCTAssertTrue(fake.abandoned.isEmpty)
        viewModel.begin()
        XCTAssertNil(viewModel.flow, "It doesn't try again on its own.")
    }

    func testACommitThatCouldNotBeSavedStaysAtTheSummaryWithAMessage() throws {
        let fake = FakeCoordinator()
        fake.commits = false
        let single = CalibrationViewModel(coordinator: fake, now: { self.now })
        // Push only, Okay: a summary with one starting point.
        single.begin()
        single.continueFromEquipment()
        single.toggleFamily(.squat)
        single.continueFromAreas()
        single.answerCloseness(nil)
        try rateSample(single, .okay)
        XCTAssertEqual(summaryPoints(single).count, 1)

        single.useThese()

        XCTAssertNil(single.outcome)
        XCTAssertEqual(single.notice, CalibrationCopy.saveFailed)
        XCTAssertEqual(summaryPoints(single).count, 1)
        fake.commits = true
        single.useThese()
        XCTAssertEqual(single.outcome, .committed)
        XCTAssertNil(single.notice)
    }

    // MARK: - A real coach

    func testARealCoachSampleRatesAndReportsBackAsAProbe() throws {
        let rig = makeRig()
        finishQuiz(rig.viewModel, families: [.push])
        rig.viewModel.startSample()
        let launch = try XCTUnwrap(rig.viewModel.probeLaunch)
        XCTAssertEqual(launch.launch.plan.name, AdaptiveTrainingCoordinator.calibrationProbeName)
        XCTAssertNil(launch.launch.plan.id, "It matches no routine, so no routine choice is consumed.")
        XCTAssertEqual(launch.launch.plan.items.count, 1)
        XCTAssertEqual(launch.launch.plan.items.first?.targetReps, 2...2)
        XCTAssertEqual(launch.launch.prescription.kind, .calibrationProbe)

        let harness = openCoach(launch)
        play(harness) { _ in false }
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        let card = try XCTUnwrap(harness.model.effortCard, "The coach asks how the sample was.")
        XCTAssertFalse(card.isBonus)
        XCTAssertNil(harness.model.bonusOffer)

        harness.model.rateEffort(.okay)

        XCTAssertNil(rig.viewModel.probeLaunch, "Rating the sample closes the coach.")
        XCTAssertEqual(summaryPoints(rig.viewModel),
                       [CalibrationStart(family: .push, start: RungDose(variant: wall, dose: .reps(2)))])
        let evidence = try XCTUnwrap(rig.facts.evidence.first)
        XCTAssertEqual(rig.facts.evidence.count, 1)
        XCTAssertEqual(evidence.source, .calibration)
        XCTAssertEqual(evidence.calibrationID, rig.viewModel.flow?.id)
        XCTAssertNil(evidence.prescriptionID)
        XCTAssertEqual(evidence.family, .push)
        XCTAssertEqual(evidence.variant, wall)
        XCTAssertEqual(evidence.prescribed, .reps(2))
        XCTAssertEqual(evidence.confirmed, .reps(2))
        XCTAssertEqual(evidence.effort, .okay)
        XCTAssertEqual(evidence.id, card.id)
        XCTAssertNil(evidence.bonus)
    }

    // MARK: - A sample is not a workout: no history, no reminders

    /// A coach for the sample on screen, built the way the factory builds one: the real model on the harness's fakes,
    /// with the sample's own recorder.
    private func openCoach(_ launch: CalibrationProbeLaunch) -> WorkoutCoachHarness {
        let harness = WorkoutCoachHarness.make(
            preferences: InMemoryPreferences(), initialExercise: launch.launch.plan.items.first?.exerciseID ?? .wallPushUp,
            plan: launch.launch.plan, adaptive: launch.recorder, todayLaunch: launch.launch)
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        return harness
    }

    /// Gets framed and starts the set, then plays the guide's demonstration at the camera's real cadence until `stop`
    /// says so, the set ends, or 600 frames pass.
    private func play(_ harness: WorkoutCoachHarness, until stop: (WorkoutCoachModel) -> Bool) {
        var time = 0.0
        func frame() {
            guard let exercise = harness.model.session.exercise else { return }
            harness.scheduler.advance(by: 0.1)
            time += 0.1
            harness.camera.emit(.frame(ReadyPoseFixtures.demoFrame(exercise, motionTime: time, at: time)))
        }
        for _ in 0..<10 { frame() }
        if harness.model.session.phase != .exercising { harness.model.send(.start) }
        var steps = 0
        while harness.model.session.phase == .exercising, !stop(harness.model), steps < 600 {
            frame()
            steps += 1
        }
    }

    /// What `WorkoutCoachView` does when its workout closes or ends: the one shared save.
    private func viewSaves(_ harness: WorkoutCoachHarness, savesHistory: Bool, history: RecordingHistory,
                           reminders: RecordingReminders) -> WorkoutRecord? {
        WorkoutCoachHistory.save(session: harness.model.session, startedAt: Date(timeIntervalSince1970: 100),
                                 endedAt: now, workoutID: harness.model.workoutID, savesHistory: savesHistory,
                                 history: history, preferences: InMemoryPreferences(), reminders: reminders)
    }

    private func startedSample(_ rig: Rig) throws -> CalibrationProbeLaunch {
        finishQuiz(rig.viewModel, families: [.push])
        rig.viewModel.startSample()
        return try XCTUnwrap(rig.viewModel.probeLaunch)
    }

    func testClosingAfterACompletedSampleSavesNoHistoryAndTellsNoReminder() throws {
        let rig = makeRig()
        let harness = openCoach(try startedSample(rig))
        play(harness) { _ in false }
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertNotNil(harness.model.effortCard, "The sample is finished and not yet rated.")
        let history = RecordingHistory()
        let reminders = RecordingReminders()

        // Close, as the coach view does it: save, close the workout, and leave the screen.
        let record = viewSaves(harness, savesHistory: false, history: history, reminders: reminders)
        harness.model.send(.closeWorkout)
        harness.model.onDisappear()

        let shown = try XCTUnwrap(record, "A finished sample makes a valid record, which is what must not be saved.")
        XCTAssertEqual(shown.entries.first?.sets.map(\.reps), [2])
        XCTAssertEqual(history.saved.count, 0)
        XCTAssertEqual(reminders.saved.count, 0)
        // The sample's evidence is still recorded, unrated, and the screen is told.
        XCTAssertEqual(rig.facts.evidence.count, 1)
        XCTAssertEqual(rig.facts.evidence.first?.source, .calibration)
        XCTAssertNil(rig.facts.evidence.first?.effort)
        XCTAssertEqual(rig.viewModel.notice, CalibrationCopy.noRating)
    }

    func testEndingTheWorkoutMidSampleSavesNoHistoryAndTellsNoReminder() throws {
        let rig = makeRig()
        let harness = openCoach(try startedSample(rig))
        play(harness) { $0.session.repCount >= 1 }
        XCTAssertEqual(harness.model.session.phase, .exercising)
        XCTAssertEqual(harness.model.session.repCount, 1)
        let history = RecordingHistory()
        let reminders = RecordingReminders()

        // End Workout, as the coach view does it: the session ends, then the view saves.
        harness.model.send(.endWorkout)
        XCTAssertEqual(harness.model.session.phase, .ended)
        let record = viewSaves(harness, savesHistory: false, history: history, reminders: reminders)

        let shown = try XCTUnwrap(record, "The rep that was counted makes a valid record, which must not be saved.")
        XCTAssertEqual(shown.entries.first?.sets.map(\.reps), [1])
        XCTAssertEqual(history.saved.count, 0)
        XCTAssertEqual(reminders.saved.count, 0)
        XCTAssertEqual(rig.facts.evidence.count, 1)
        XCTAssertEqual(rig.facts.evidence.first?.source, .calibration)
        XCTAssertEqual(rig.facts.evidence.first?.completion, .endedWorkout)
    }

    func testAbandoningAfterAClosedSampleLeavesHistoryAndRemindersUntouched() throws {
        let rig = makeRig(facts: seededPush())
        let before = try rig.engine.profile()
        let harness = openCoach(try startedSample(rig))
        play(harness) { _ in false }
        let history = RecordingHistory()
        let reminders = RecordingReminders()
        _ = viewSaves(harness, savesHistory: false, history: history, reminders: reminders)
        harness.model.send(.closeWorkout)
        harness.model.onDisappear()
        rig.viewModel.sampleClosed()

        rig.viewModel.requestExit()
        rig.viewModel.confirmLeave()

        XCTAssertEqual(rig.viewModel.outcome, .left)
        XCTAssertEqual(rig.facts.calibrations.filter { $0.status == .abandoned }.count, 1)
        XCTAssertEqual(history.saved.count, 0)
        XCTAssertEqual(reminders.saved.count, 0)
        let after = try rig.engine.profile()
        XCTAssertEqual(after.states, before.states)
        XCTAssertEqual(after.activeFamilies, before.activeFamilies)
    }

    func testAnOrdinaryWorkoutStillSavesHistoryAndTellsReminders() throws {
        let rig = makeRig()
        let harness = openCoach(try startedSample(rig))
        play(harness) { _ in false }
        let history = RecordingHistory()
        let reminders = RecordingReminders()

        let record = viewSaves(harness, savesHistory: true, history: history, reminders: reminders)

        XCTAssertEqual(history.saved.map(\.id), [harness.model.workoutID])
        XCTAssertEqual(reminders.saved.map(\.id), [harness.model.workoutID])
        XCTAssertEqual(record?.id, history.saved.first?.id)
    }

    func testOnlyTheCalibrationSampleOptsOutOfHistory() throws {
        let rig = makeRig()
        let harness = openCoach(try startedSample(rig))

        XCTAssertTrue(WorkoutCoachView(model: harness.model).savesHistory, "Every other workout saves by default.")
        XCTAssertFalse(CalibrationScreen.sampleCoach(model: harness.model).savesHistory)
    }

    // MARK: - Copy

    func testTheIntroIsTheWarmWordingTheBriefAsks() {
        XCTAssertEqual(CalibrationCopy.intro, "Let's find a comfortable starting point. A few tiny samples, no tests.")
    }

    func testNoCopyUsesAScoringOrMedicalWord() throws {
        var strings = CalibrationCopy.all + AdaptiveTrainingSettingsCopy.all
        let catalogFamilies = ProgressionCatalog.v1.families.map(\.id)
        strings += catalogFamilies.flatMap { [CalibrationCopy.areaName($0), CalibrationCopy.areaDetail($0)] }
        strings += catalogFamilies.map {
            CalibrationCopy.summaryLine(area: CalibrationCopy.areaName($0), exercise: "Wall Push-Up", dose: .reps(3))
        }
        strings.append(CalibrationCopy.summaryLine(area: "Glutes", exercise: "Glute Squeeze", dose: .seconds(10)))
        strings += TrainingEquipment.allCases.map(CalibrationCopy.equipmentName)
        strings += [CalibrationCopy.doseText(.reps(1)), CalibrationCopy.doseText(.seconds(5))]
        // Every exercise name a rung can show.
        strings += ProgressionCatalog.v1.families.flatMap(\.rungs).compactMap {
            ExerciseVariantBridge().exercise(for: $0)?.displayName
        }

        // The brief's own intro says "no tests"; the scan matches whole words, so that plural reads as the reassurance
        // it is and the singular "test" is still caught everywhere else.
        for string in strings {
            XCTAssertEqual(Self.forbiddenWords(in: string), [], "\"\(string)\"")
        }
        XCTAssertGreaterThan(strings.count, 60)

        // The words in the screen and view model sources are scanned too, so copy can't slip in inline.
        let sources = [
            ("Features/Calibration", "CalibrationScreen.swift"),
            ("Features/Calibration", "CalibrationViewModel.swift"),
            ("Features/Settings", "AdaptiveTrainingSettingsPage.swift"),
            ("Features/Settings", "AdaptiveTrainingSettingsViewModel.swift")
        ]
        for (directory, name) in sources {
            let literals = try Self.stringLiterals(inSource: name, directory: directory)
            XCTAssertFalse(literals.isEmpty, name)
            for literal in literals {
                XCTAssertEqual(Self.forbiddenWords(in: literal), [], "\(name): \"\(literal)\"")
            }
        }
    }

    func testTheScanCatchesTheWordsItIsMeantToCatch() {
        for bad in ["This is a test", "Your score", "Pick a level", "For a beginner", "Reduces pain", "A diagnosis",
                    "May cause injury", "Not medical advice", "Scoliosis check", "Therapy plan"] {
            XCTAssertFalse(Self.forbiddenWords(in: bad).isEmpty, bad)
        }
        XCTAssertEqual(Self.forbiddenWords(in: "A few tiny samples, no tests."), [])
        XCTAssertEqual(Self.forbiddenWords(in: "The latest version"), [])
    }

    private static let forbidden = [
        "test", "score", "scores", "level", "levels", "beginner", "beginners", "pain", "painful", "injury", "injuries",
        "injured", "diagnosis", "diagnose", "diagnostic", "medical", "doctor", "therapy", "therapist", "symptom",
        "symptoms", "condition", "disorder", "treat", "treatment", "scoliosis", "rehab", "rehabilitation"
    ]

    /// Whole words only, ignoring case, so "latest" and "tests" are not "test".
    private static func forbiddenWords(in string: String) -> [String] {
        let words = string.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.filter { forbidden.contains($0) }
    }

    /// The text of every string literal in a source file, ignoring comment lines.
    private static func stringLiterals(inSource name: String, directory: String,
                                       filePath: String = #filePath) throws -> [String] {
        let tests = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let url = tests.deletingLastPathComponent().appendingPathComponent(directory).appendingPathComponent(name)
        let source = try String(contentsOf: url, encoding: .utf8)
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let pattern = try NSRegularExpression(pattern: "\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
        let range = NSRange(code.startIndex..., in: code)
        return pattern.matches(in: code, range: range).compactMap { match in
            Range(match.range(at: 1), in: code).map { String(code[$0]) }
        }
    }

    // MARK: - Fakes

    /// Counts the workouts written to history.
    @MainActor
    private final class RecordingHistory: WorkoutHistoryRepository {
        private(set) var saved: [WorkoutRecord] = []

        func list() throws -> [WorkoutRecord] { saved }
        func save(_ record: WorkoutRecord) throws { saved.append(record) }
        func updateWeights(for record: WorkoutRecord) throws {}
        func delete(id: UUID) throws {}
    }

    /// Counts the workout-saved callbacks reminders receive.
    @MainActor
    private final class RecordingReminders: WorkoutReminderReconciliation {
        private(set) var saved: [WorkoutRecord] = []

        func reconcile() {}
        func workoutSaved(_ record: WorkoutRecord) { saved.append(record) }
    }

    /// A coordinator that never touches the engine, for the cases a real one can't produce.
    @MainActor
    private final class FakeCoordinator: CalibrationCoordinating {
        var failsToStart = false
        var commits = true
        var canPrepare = true
        private(set) var saved: [CalibrationFlow] = []
        private(set) var abandoned: [CalibrationFlow] = []
        private(set) var stored: [AdaptiveEvidence] = []

        private(set) var startedKinds: [CalibrationKind] = []

        func startCalibration(kind: CalibrationKind, asOf now: Date) -> CalibrationFlow? {
            startedKinds.append(kind)
            guard !failsToStart else { return nil }
            let built = Set(ProgressionCatalog.v1.families.flatMap { $0.rungs.map(\.exerciseID) })
            return CalibrationFlow(id: UUID(), kind: kind, startedAt: now, catalog: .v1,
                                   availability: Availability(builtExerciseIDs: built))
        }

        func saveCalibrationProgress(_ flow: CalibrationFlow) { saved.append(flow) }

        func commitCalibration(_ flow: CalibrationFlow, asOf now: Date) -> Bool { commits }

        func abandonCalibration(_ flow: CalibrationFlow, asOf now: Date) { abandoned.append(flow) }

        func prepareProbe(for flow: CalibrationFlow, asOf now: Date,
                          onResult: @escaping @MainActor (CalibrationProbeResult) -> Void) -> CalibrationProbeLaunch? {
            guard canPrepare, case .probe(let family, let rungDose, _) = flow.step else { return nil }
            let id = UUID()
            let item = AdaptivePlanItem(itemID: UUID(), role: .main, family: family, rungDose: rungDose,
                                        exerciseID: .wallPushUp, reducedRange: false)
            let prescription = Prescription(id: id, issuedAt: now, kind: .calibrationProbe, policyVersion: .v1,
                                            catalogVersion: "test", items: [], rationale: "Test")
            return CalibrationProbeLaunch(
                family: family, rungDose: rungDose,
                launch: TodaySessionLaunch(prescription: prescription, plan: WorkoutPlan(name: "Test", items: []),
                                           items: [item]),
                recorder: CalibrationProbeRecorder(launchID: id, calibrationID: flow.id,
                                                   store: { [weak self] in self?.stored.append($0) },
                                                   onResult: onResult))
        }

        func displayName(of variant: VariantID) -> String { variant.rawValue }
    }
}
