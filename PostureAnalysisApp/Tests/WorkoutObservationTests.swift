import XCTest
import AdaptiveTraining
@testable import PostureAnalysisApp

@MainActor
enum WorkoutObservationTestContext {
    static var observer: (any WorkoutObserving)?
}

@MainActor
enum WorkoutObservationCall: Equatable {
    case handled(WorkoutEvent, [WorkoutEffect], TimeInterval)
    case said(Utterance, Bool)
    case repeated(Bool)
    case tip(CoachingTip?)
    case offered(WorkoutCoachOffer)
    case saved(WorkoutRecord)
    case adaptive([AdaptiveEvent])
}

@MainActor
final class WorkoutObservationRecorder: WorkoutObserving {
    private(set) var calls: [WorkoutObservationCall] = []
    private let doesHeavyWork: Bool
    private let attemptsReentrantSend: Bool
    private var didAttemptReentrantSend = false
    private var workResult = 0
    private let actionLog: WorkoutObservationActionLog?
    private var presentationSession: WorkoutSession?
    private(set) var presentationEvents: [WorkoutPresentationEvent] = []
    var onNotification: ((WorkoutObservationCall) -> Void)?
    private var reentrantSend: (() -> Void)?

    init(doesHeavyWork: Bool = false, attemptsReentrantSend: Bool = false,
         actionLog: WorkoutObservationActionLog? = nil) {
        self.doesHeavyWork = doesHeavyWork
        self.attemptsReentrantSend = attemptsReentrantSend
        self.actionLog = actionLog
    }

    func beginPresentationMapping(from session: WorkoutSession) {
        presentationSession = session
        presentationEvents = []
    }

    func attachReentrantSend(to model: WorkoutCoachModel) {
        guard attemptsReentrantSend else { return }
        reentrantSend = { [weak model] in model?.send(.endWorkout) }
    }

    func workoutDidHandle(_ event: WorkoutEvent, effects: [WorkoutEffect], at time: TimeInterval) {
        let input = WorkoutObservationInput.workoutDidHandle(event, effects: effects, at: time)
        if var after = presentationSession {
            let before = after
            _ = after.handle(event, at: time)
            presentationEvents += WorkoutPresentationMapper.map(
                input, before: WorkoutPresentationSnapshot(session: before),
                after: WorkoutPresentationSnapshot(session: after)
            )
            presentationSession = after
        }
        record(.handled(event, effects, time), input: input)
    }

    func coachDidSay(_ utterance: Utterance, muted: Bool) {
        record(.said(utterance, muted), input: .coachDidSay(utterance, muted: muted))
    }

    func coachDidRepeatLastInstruction(muted: Bool) {
        record(.repeated(muted), input: .coachDidRepeatLastInstruction(muted: muted))
    }

    func coachDidShowTip(_ tip: CoachingTip?) {
        record(.tip(tip), input: .coachDidShowTip(tip))
    }

    func coachDidOffer(_ offer: WorkoutCoachOffer) {
        record(.offered(offer), input: .coachDidOffer(offer))
    }

    func workoutDidSave(_ record: WorkoutRecord) {
        self.record(.saved(record), input: .workoutDidSave(record))
    }

    func adaptiveEventsDidOccur(_ events: [AdaptiveEvent]) {
        record(.adaptive(events), input: .adaptiveEventsDidOccur(events))
    }

    private func record(_ call: WorkoutObservationCall, input: WorkoutObservationInput) {
        calls.append(call)
        if case .workoutDidHandle = input {
            // Reducer transition mapping was performed from the recorded event and replay state above.
        } else {
            presentationEvents += WorkoutPresentationMapper.map(input)
        }
        actionLog?.append(Self.actionLabel(for: call))
        onNotification?(call)
        if doesHeavyWork {
            var result = workResult
            for value in 0..<8_192 { result = (result &* 31) &+ value }
            workResult = result
        }
        guard attemptsReentrantSend, !didAttemptReentrantSend, let reentrantSend else { return }
        didAttemptReentrantSend = true
        reentrantSend()
    }

    private static func actionLabel(for call: WorkoutObservationCall) -> String {
        switch call {
        case .handled(.coachSpeakingChanged(let speaking), _, _):
            return "observer.handle.coachSpeakingChanged:\(speaking)"
        case .handled(.command(.start), _, _): return "observer.handle.start"
        case .handled(.command(.repeatLast), _, _): return "observer.handle.repeatLast"
        case .handled: return "observer.handle.other"
        case .said(let utterance, _): return "observer.say:\(utterance.text)"
        case .repeated: return "observer.repeat"
        case .tip(let tip): return "observer.tip:\(tip?.cue.text ?? "cleared")"
        case .offered(let offer): return "observer.offer:\(offer)"
        case .saved: return "observer.saved"
        case .adaptive: return "observer.adaptive"
        }
    }
}

/// Observers see a workout without changing it.
@MainActor
final class WorkoutObservationTests: XCTestCase {
    func testObserverReceivesExactOrderedCallsAfterReducerEffects() throws {
        let order = WorkoutObservationActionLog()
        let observer = WorkoutObservationRecorder(actionLog: order)
        let exercise = Self.reportedExercise(sets: 1)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id, observer: observer, actionLog: order)
        var expectedSession = harness.model.session
        let expectedEffects = expectedSession.handle(.command(.start), at: harness.clock.now)
        let spoken = try XCTUnwrap(expectedEffects.compactMap { effect -> Utterance? in
            guard case .speak(let utterance) = effect else { return nil }
            return utterance
        }.first)
        let tip = try XCTUnwrap(expectedEffects.compactMap { effect -> CoachingTip? in
            guard case .showTip(let tip) = effect else { return nil }
            return tip
        }.first)

        harness.model.send(.start)

        XCTAssertEqual(observer.calls, [
            .said(spoken, false),
            .tip(tip),
            .handled(.command(.start), expectedEffects, harness.clock.now)
        ])
        XCTAssertEqual(harness.model.session.phase, expectedSession.phase)
    }

    func testNotificationsFollowSpeechRepeatAndTipProductionActions() throws {
        let order = WorkoutObservationActionLog()
        let observer = WorkoutObservationRecorder(actionLog: order)
        let exercise = Self.reportedExercise(sets: 1)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id, observer: observer, actionLog: order)
        observer.beginPresentationMapping(from: harness.model.session)
        let scheduledTip = "scheduler.schedule.end: \(WorkoutCoachModel.tipDuration)"
        observer.onNotification = { call in
            switch call {
            case .said(let utterance, false):
                XCTAssertEqual(harness.speech.utterances.last, utterance)
                XCTAssertEqual(order.entries.last, "observer.say:\(utterance.text)")
                XCTAssertTrue(order.entries.dropLast().contains("speech.speak.end: \(utterance.text)"))
            case .repeated:
                XCTAssertEqual(harness.speech.repeatCount, 1)
                XCTAssertEqual(Array(order.entries.suffix(2)), ["speech.repeat.end", "observer.repeat"])
            case .tip(let tip):
                XCTAssertEqual(harness.model.activeTip, tip)
                XCTAssertEqual(Array(order.entries.suffix(2)),
                               [scheduledTip, "observer.tip:\(tip?.cue.text ?? "cleared")"])
            default:
                break
            }
        }

        harness.model.send(.start)
        harness.voice.emit(.repeatLast)

        let spoken = try XCTUnwrap(harness.speech.utterances.first)
        let speechEnded = try XCTUnwrap(order.entries.firstIndex(of: "speech.speak.end: \(spoken.text)"))
        let speechNotified = try XCTUnwrap(order.entries.firstIndex(of: "observer.say:\(spoken.text)"))
        let tipScheduled = try XCTUnwrap(order.entries.firstIndex(of: scheduledTip))
        let tipNotified = try XCTUnwrap(order.entries.firstIndex(where: { $0.hasPrefix("observer.tip:") }))
        let repeatAction = try XCTUnwrap(order.entries.firstIndex(of: "speech.repeat.end"))
        let repeatNotified = try XCTUnwrap(order.entries.firstIndex(of: "observer.repeat"))
        XCTAssertLessThan(speechEnded, speechNotified)
        XCTAssertLessThan(tipScheduled, tipNotified)
        XCTAssertLessThan(repeatAction, repeatNotified)
    }

    func testSpeechActivityNestedDispatchFinishesBeforeOuterSpeechNotification() throws {
        let order = WorkoutObservationActionLog()
        let observer = WorkoutObservationRecorder(actionLog: order)
        let exercise = Self.reportedExercise(sets: 1)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id, observer: observer, actionLog: order)
        observer.beginPresentationMapping(from: harness.model.session)
        harness.speech.reportsActivity = true

        harness.model.send(.start)

        let nestedDispatch = try XCTUnwrap(order.entries.firstIndex(of: "observer.handle.coachSpeakingChanged:true"))
        let speechFinished = try XCTUnwrap(order.entries.firstIndex(where: { $0.hasPrefix("speech.speak.end:") }))
        let speechNotified = try XCTUnwrap(order.entries.firstIndex(where: { $0.hasPrefix("observer.say:") }))
        let outerDispatch = try XCTUnwrap(order.entries.firstIndex(of: "observer.handle.start"))
        XCTAssertLessThan(try XCTUnwrap(order.entries.firstIndex(where: { $0.hasPrefix("speech.speak.begin:") })),
                          nestedDispatch)
        XCTAssertLessThan(nestedDispatch, speechFinished)
        XCTAssertLessThan(speechFinished, speechNotified)
        XCTAssertLessThan(speechNotified, outerDispatch)
    }

    func testPresentationMapperUsesRealObservedModelTransitionsAcrossPerSideRounds() throws {
        var exercise = Self.reportedExercise(sets: 1)
        exercise.perSide = true
        let observer = WorkoutObservationRecorder()
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id, observer: observer)
        observer.beginPresentationMapping(from: harness.model.session)

        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.send(.anotherRound)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        let completed = observer.presentationEvents.compactMap { event -> WorkoutPresentationEvent? in
            guard case .setCompleted = event else { return nil }
            return event
        }
        XCTAssertEqual(completed, [
            .setCompleted(set: 1, reps: 1),
            .setCompleted(set: 1, reps: 1)
        ])
    }

    func testHistoryNotificationFollowsOnlySuccessfulCommit() throws {
        let order = WorkoutObservationActionLog()
        let observer = WorkoutObservationRecorder(actionLog: order)
        let exercise = Self.reportedExercise(sets: 1)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id, observer: observer, actionLog: order)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        let history = ObservationHistoryRepository(order: order)
        let reminders = ObservationReminderReconciliation(order: order)
        order.clear()
        let committed = WorkoutCoachHistory.save(
            session: harness.model.session, startedAt: Self.date(0), endedAt: Self.date(10),
            workoutID: harness.model.workoutID, savesHistory: true, history: history,
            preferences: InMemoryPreferences(), reminders: reminders, notifying: harness.model
        )

        let record = try XCTUnwrap(committed)
        XCTAssertEqual(order.entries, ["history.commit", "reminder.saved", "observer.saved"])
        XCTAssertEqual(observer.calls.filter { if case .saved = $0 { return true }; return false }, [.saved(record)])

        let beforeProbe = observer.calls.filter { if case .saved = $0 { return true }; return false }
        let probeHistory = ObservationHistoryRepository(order: WorkoutObservationActionLog())
        var didCaptureEndTime = false
        _ = WorkoutCoachHistory.save(
            session: harness.model.session, startedAt: Self.date(0), endedAt: {
                didCaptureEndTime = true
                return Self.date(10)
            },
            workoutID: harness.model.workoutID, savesHistory: false, history: probeHistory,
            preferences: InMemoryPreferences(), reminders: nil, notifying: harness.model
        )
        XCTAssertTrue(didCaptureEndTime)
        XCTAssertTrue(probeHistory.records.isEmpty)
        XCTAssertEqual(observer.calls.filter { if case .saved = $0 { return true }; return false }, beforeProbe)

        let failedOrder = WorkoutObservationActionLog()
        let failedHistory = ObservationHistoryRepository(order: failedOrder)
        failedHistory.shouldFail = true
        _ = WorkoutCoachHistory.save(
            session: harness.model.session, startedAt: Self.date(0), endedAt: Self.date(10),
            workoutID: harness.model.workoutID, savesHistory: true, history: failedHistory,
            preferences: InMemoryPreferences(), reminders: ObservationReminderReconciliation(order: failedOrder),
            notifying: harness.model
        )
        XCTAssertEqual(failedOrder.entries, ["history.commit"])
        XCTAssertEqual(observer.calls.filter { if case .saved = $0 { return true }; return false }, beforeProbe)
    }

    func testAdaptiveTodaySessionEventsReachObserverInEngineOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = Self.date(10)
        let calibration = CalibrationSessionRecord(
            id: Self.uuid(1), kind: .initial, startedAt: start, endedAt: start, status: .committed,
            families: [.push], equipment: [],
            startingPoints: [CalibrationStart(family: .push,
                                               start: RungDose(variant: VariantID(rawValue: "push.wall_push_up.shallow"),
                                                               dose: .reps(3)))]
        )
        let store = InMemoryAdaptiveTrainingStore(facts: AdaptiveFacts(calibrations: [calibration]))
        let bridge = ExerciseVariantBridge()
        let engine = AdaptiveTrainingEngine(store: store,
                                            builtExerciseIDs: bridge.availability(equipment: []).builtExerciseIDs,
                                            calendar: calendar)
        let observer = WorkoutObservationRecorder()
        var nextID = 2
        let coordinator = AdaptiveTrainingCoordinator(engine: engine, bridge: bridge, makeID: {
            defer { nextID += 1 }
            return Self.uuid(UInt8(truncatingIfNeeded: nextID))
        }, observer: observer)
        let now = Self.date(20)
        let launch = try XCTUnwrap(coordinator.start(asOf: now))
        let prescriptionItem = try XCTUnwrap(launch.prescription.items.first)
        let evidence = AdaptiveEvidence(
            id: Self.uuid(30), recordedAt: now, source: .adaptive, family: prescriptionItem.family,
            variant: prescriptionItem.target.variant, prescriptionID: launch.prescription.id,
            prescriptionItemID: prescriptionItem.id, workoutID: Self.uuid(31),
            prescribed: prescriptionItem.target.dose, confirmed: .reps(3), confirmation: .user,
            setAmounts: [.reps(3)], tracker: TrackerObservation(status: .tracked, observed: .reps(3)),
            effort: .easy, midSetTooHard: false,
            bonus: BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .easy),
            completion: .completed
        )

        coordinator.record(evidence)

        let calls = observer.calls.compactMap { call -> [AdaptiveEvent]? in
            guard case .adaptive(let events) = call else { return nil }
            return events
        }
        let expected = try AdaptiveReplay.events(facts: engine.facts(), profile: engine.profile())
            .filter { $0.factID == evidence.id }
        XCTAssertEqual(calls, [expected])
        XCTAssertGreaterThan(expected.count, 1)
        XCTAssertEqual(observer.presentationEvents.filter {
            if case .adaptive = $0 { return true }
            return false
        }, expected.map { .adaptive($0.kind) })
        let kinds = expected.map(\.kind)
        let sessionCompleted = try XCTUnwrap(kinds.firstIndex(of: .sessionCompleted))
        let effortEasy = try XCTUnwrap(kinds.firstIndex(of: .effortEasy))
        let bonusOffered = try XCTUnwrap(kinds.firstIndex(of: .bonusOffered))
        let bonusAccepted = try XCTUnwrap(kinds.firstIndex(of: .bonusAccepted))
        XCTAssertLessThan(sessionCompleted, effortEasy)
        XCTAssertLessThan(effortEasy, bonusOffered)
        XCTAssertLessThan(bonusOffered, bonusAccepted)
    }

    func testCloseWithAnOpenEffortCardFinalizesBeforeSaveAndUsesOneAcknowledgment() async throws {
        let rig = try makeCloseDeliveryRig()
        rig.harness.model.onAppear(isApplicationActive: true)
        rig.harness.model.send(.start)
        rig.harness.model.send(.nextSet)
        XCTAssertNotNil(rig.harness.model.effortCard)

        let scheduled = expectation(description: "single acknowledgment after close")
        rig.scheduler.onScheduleAcknowledgment = { scheduled.fulfill() }
        let record = try XCTUnwrap(saveAsViewDoesBeforeClosing(rig))
        rig.harness.model.send(.closeWorkout)
        await fulfillment(of: [scheduled], timeout: 2)

        XCTAssertEqual(rig.history.records.count, 1)
        XCTAssertEqual(rig.scheduler.acknowledgmentHistory.count, 1)
        XCTAssertEqual(rig.scheduler.acknowledgments.count, 1)
        XCTAssertTrue(rig.scheduler.immediatePersonaRequests.isEmpty)
        XCTAssertEqual(rig.scheduler.acknowledgments.first?.title, "Title adaptive.sessionCompleted")
        let traces = rig.traces.state.sent + rig.traces.state.suppressed
        let completion = try XCTUnwrap(traces.first { $0.observation.contentKey == "adaptive.sessionCompleted" })
        XCTAssertEqual(completion.delivery, .foldedReplace)
        XCTAssertEqual(record.endedAt, rig.endedAt)
    }

    func testCloseWithAPendingBonusFinalizesBeforeSaveAndUsesOneAcknowledgment() async throws {
        let rig = try makeCloseDeliveryRig()
        rig.harness.model.onAppear(isApplicationActive: true)
        rig.harness.model.send(.start)
        rig.harness.model.send(.nextSet)
        rig.harness.model.rateEffort(.easy)
        XCTAssertNotNil(rig.harness.model.bonusOffer)

        let scheduled = expectation(description: "single acknowledgment after close")
        rig.scheduler.onScheduleAcknowledgment = { scheduled.fulfill() }
        let record = try XCTUnwrap(saveAsViewDoesBeforeClosing(rig))
        rig.harness.model.send(.closeWorkout)
        await fulfillment(of: [scheduled], timeout: 2)

        XCTAssertEqual(rig.history.records.count, 1)
        XCTAssertEqual(rig.scheduler.acknowledgmentHistory.count, 1)
        XCTAssertEqual(rig.scheduler.acknowledgments.count, 1)
        XCTAssertTrue(rig.scheduler.immediatePersonaRequests.isEmpty)
        XCTAssertEqual(rig.scheduler.acknowledgments.first?.title, "Title adaptive.bonusDeclined")
        let traces = rig.traces.state.sent + rig.traces.state.suppressed
        let declined = try XCTUnwrap(traces.first { $0.observation.contentKey == "adaptive.bonusDeclined" })
        XCTAssertEqual(declined.delivery, .foldedReplace)
        XCTAssertTrue(traces.contains { $0.observation.contentKey == "adaptive.sessionCompleted" })
        XCTAssertEqual(record.endedAt, rig.endedAt)
    }

#if DEBUG
    func testReentrantObserverSendIsLoggedAndDropped() {
        let observer = WorkoutObservationRecorder(attemptsReentrantSend: true)
        let exercise = Self.reportedExercise(sets: 1)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id, observer: observer)
        observer.attachReentrantSend(to: harness.model)

        harness.model.send(.start)

        XCTAssertEqual(harness.model.droppedObserverReentrantSends, 1)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.send(.pause)

        XCTAssertEqual(harness.model.droppedObserverReentrantSends, 1)
        if case .paused = harness.model.session.phase { } else { XCTFail("An ordinary send after notification should run.") }
    }

    func testObservedModelDoesNotBlockAnUnobservedModel() {
        let observer = WorkoutObservationRecorder()
        let exercise = Self.reportedExercise(sets: 1)
        let observed = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                                initialExercise: exercise.id, observer: observer)
        let unobserved = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                                  initialExercise: exercise.id)
        var didSend = false
        observer.onNotification = { _ in
            guard !didSend else { return }
            didSend = true
            unobserved.model.send(.start)
        }

        observed.model.send(.start)

        XCTAssertTrue(didSend)
        XCTAssertEqual(unobserved.model.session.phase, .exercising)
        XCTAssertEqual(unobserved.model.droppedObserverReentrantSends, 0)
    }

    func testNestedObservedModelNotificationRestoresItsOwnGuard() {
        let firstObserver = WorkoutObservationRecorder()
        let secondObserver = WorkoutObservationRecorder()
        let exercise = Self.reportedExercise(sets: 1)
        let first = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                             initialExercise: exercise.id, observer: firstObserver)
        let second = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                              initialExercise: exercise.id, observer: secondObserver)
        var didSend = false
        firstObserver.onNotification = { _ in
            guard !didSend else { return }
            didSend = true
            second.model.send(.start)
            second.model.send(.pause)
        }

        first.model.send(.start)

        XCTAssertTrue(didSend)
        if case .paused = second.model.session.phase { } else { XCTFail("The later send should run after nested notification returns.") }
        XCTAssertEqual(second.model.droppedObserverReentrantSends, 0)
    }
#endif

    private static func reportedExercise(sets: Int) -> ExerciseDefinition {
        var exercise = ShoulderPressExercise.definition()
        exercise.tracking = .selfReported
        exercise.doseUnit = .reps
        exercise.startsByHolding = false
        exercise.sets = sets
        exercise.targetReps = 1...1
        exercise.autoCompleteReps = 1
        exercise.targetRangeAnnouncementReps = nil
        return exercise
    }

    private static func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400))
    }

    private static func uuid(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, value))
    }

    private func makeCloseDeliveryRig() throws -> CloseDeliveryRig {
        let exercise = Self.reportedExercise(sets: 1)
        let start = Date(timeIntervalSince1970: 900)
        let evidenceDate = Date(timeIntervalSince1970: 1_000)
        let endedAt = evidenceDate.addingTimeInterval(1)
        let history = CloseDeliveryHistory()
        let preferences = InMemoryPreferences()
        var settings = PersonaFixtures.reminderSettings
        settings.hour = 18
        preferences.workoutReminderSettings = settings
        preferences.extraPersonableEnabled = true

        let scheduler = MemoryWorkoutReminderScheduler()
        let traces = MemoryPersonaTraceStore()
        let personaCatalog = PersonaFixtures.catalog(
            keys: PersonaFixtures.contentKeys + AdaptiveEventDetector.contentKeys
        )
        let reminders = WorkoutReminderCoordinator(
            preferences: preferences, routines: nil, workoutHistory: history,
            exerciseCatalog: LiveExerciseCatalog(), router: AppRouter(), scheduler: scheduler,
            scenarioCatalog: try NotificationScenarioCatalog.bundled(), now: { endedAt },
            calendar: PersonaFixtures.calendar, personaCatalog: personaCatalog, personaTraces: traces,
            isAppActive: { true }
        )

        let variant = VariantID(rawValue: "push.close_integration_press")
        let ladders = ProgressionCatalog(version: "close-integration-1", families: [
            MovementFamily(id: .push, debugName: "Close integration", rungs: [
                ProgressionRung(id: variant, exerciseID: exercise.id.rawValue,
                                doseRange: .reps(1...5), isFloor: true),
            ]),
        ])
        let exerciseCatalog = CloseExerciseCatalog(exercises: [exercise])
        let bridge = ExerciseVariantBridge(exercises: exerciseCatalog, ladders: ladders)
        let calibrationDate = Date(timeIntervalSince1970: 500)
        let calibration = CalibrationSessionRecord(
            id: Self.uuid(1), kind: .initial, startedAt: calibrationDate, endedAt: calibrationDate,
            status: .committed, families: [.push], equipment: [],
            startingPoints: [CalibrationStart(family: .push, start: RungDose(variant: variant, dose: .reps(1)))]
        )
        let store = InMemoryAdaptiveTrainingStore(facts: AdaptiveFacts(calibrations: [calibration]))
        let engine = AdaptiveTrainingEngine(
            store: store, builtExerciseIDs: bridge.availability(equipment: []).builtExerciseIDs,
            calendar: PersonaFixtures.calendar, catalog: ladders
        )
        let adaptive = AdaptiveTrainingCoordinator(engine: engine, bridge: bridge, observer: reminders)
        let launch = try XCTUnwrap(adaptive.start(asOf: start))
        let harness = WorkoutCoachHarness.make(
            preferences: preferences, exercises: [exercise], initialExercise: exercise.id,
            plan: launch.plan, adaptive: adaptive, todayLaunch: launch
        )
        return CloseDeliveryRig(
            harness: harness, store: store, scheduler: scheduler, traces: traces, history: history,
            reminders: reminders, preferences: preferences, startedAt: start, endedAt: endedAt
        )
    }

    /// This is the lazy save path used by the view: evidence must exist before it captures `endedAt`.
    private func saveAsViewDoesBeforeClosing(_ rig: CloseDeliveryRig) -> WorkoutRecord? {
        WorkoutCoachHistory.save(
            session: rig.harness.model.session, startedAt: rig.startedAt,
            endedAt: {
                XCTAssertEqual(rig.store.facts.evidence.count, 1, "close evidence is finalized before end-time capture")
                return rig.endedAt
            },
            workoutID: rig.harness.model.workoutID, savesHistory: true, history: rig.history,
            preferences: rig.preferences, reminders: rig.reminders, notifying: rig.harness.model
        )
    }
}

@MainActor
private struct CloseDeliveryRig {
    let harness: WorkoutCoachHarness
    let store: InMemoryAdaptiveTrainingStore
    let scheduler: MemoryWorkoutReminderScheduler
    let traces: MemoryPersonaTraceStore
    let history: CloseDeliveryHistory
    let reminders: WorkoutReminderCoordinator
    let preferences: InMemoryPreferences
    let startedAt: Date
    let endedAt: Date
}

@MainActor
private struct CloseExerciseCatalog: ExerciseCatalogProviding {
    let exercises: [ExerciseDefinition]
    var all: [ExerciseDefinition] { exercises }
    func exercise(_ id: ExerciseID) -> ExerciseDefinition? { exercises.first { $0.id == id } }
}

@MainActor
private final class CloseDeliveryHistory: WorkoutHistoryRepository {
    private(set) var records: [WorkoutRecord] = []

    func list() throws -> [WorkoutRecord] { records }
    func save(_ record: WorkoutRecord) throws { records.append(record) }
    func updateWeights(for record: WorkoutRecord) throws { }
    func delete(id: UUID) throws { records.removeAll { $0.id == id } }
}

@MainActor
private final class ObservationHistoryRepository: WorkoutHistoryRepository {
    enum Failure: Error { case rejected }

    private let order: WorkoutObservationActionLog
    var shouldFail = false
    private(set) var records: [WorkoutRecord] = []

    init(order: WorkoutObservationActionLog) {
        self.order = order
    }

    func list() throws -> [WorkoutRecord] { records }

    func save(_ record: WorkoutRecord) throws {
        order.append("history.commit")
        guard !shouldFail else { throw Failure.rejected }
        records.append(record)
    }

    func updateWeights(for record: WorkoutRecord) throws { }
    func delete(id: UUID) throws { }
}

@MainActor
private final class ObservationReminderReconciliation: WorkoutReminderReconciliation {
    private let order: WorkoutObservationActionLog

    init(order: WorkoutObservationActionLog) {
        self.order = order
    }

    func reconcile() { }
    func workoutSaved(_ record: WorkoutRecord) { order.append("reminder.saved") }
}
