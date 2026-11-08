import AdaptiveTraining
import Foundation
import Observation

/// The current rung of an active family, for the exercise that was just performed.
struct ActiveRung: Equatable {
    let family: MovementFamilyID
    let rungDose: RungDose
}

/// One plan item of Today's Session with the prescription item it carries. The plan item's id is the prescription
/// item's id, so evidence links to the exact item.
struct AdaptivePlanItem: Equatable {
    let itemID: UUID
    let role: PrescriptionItemRole
    let family: MovementFamilyID
    let rungDose: RungDose
    let exerciseID: ExerciseID
    let reducedRange: Bool
}

/// Today's Session after the engine issued it: the saved prescription, the plan the coach runs, and the adaptive
/// meaning of each plan item.
struct TodaySessionLaunch: Equatable {
    let prescription: Prescription
    let plan: WorkoutPlan
    let items: [AdaptivePlanItem]
}

/// The easier version the engine chose for an item that was too hard, resolved to something the coach can run. The
/// engine decided `target`; the app only found its exercise.
struct EasierSwapOption: Equatable {
    let target: RungDose
    let exerciseID: ExerciseID
    let reducedRange: Bool
}

/// An easier version the engine saved as a prescription, ready to run as a plan item of its own.
struct IssuedEasierSwap: Equatable {
    let prescriptionID: UUID
    let item: AdaptivePlanItem
}

/// What the workout model needs from adaptive training: which rung a manual exercise is, and a place to record
/// evidence. Nil in workouts that have no engine.
@MainActor
protocol AdaptiveEvidenceRecording: AnyObject {
    /// The family and rung when `exerciseID` (full or reduced range) is the current rung of an active family.
    func activeRung(for exerciseID: ExerciseID, reducedRange: Bool) -> ActiveRung?
    /// Saves evidence. A failure is logged and never reaches the workout.
    func record(_ evidence: AdaptiveEvidence)
    /// The easier version of a Today's Session main item that is under way, or nil when the engine has none or the
    /// coach can't run it. Read-only. The engine decides what is easier; callers never compare difficulty.
    func easierSwapOption(for item: PrescriptionItem, asOf now: Date) -> EasierSwapOption?
    /// Saves `option` as the prescription the user is now following in place of `item`, or nil when it couldn't be
    /// saved. A failure is logged and never reaches the workout.
    func issueEasierSwap(replacing item: PrescriptionItem, option: EasierSwapOption, at now: Date) -> IssuedEasierSwap?
}

extension AdaptiveEvidenceRecording {
    func easierSwapOption(for item: PrescriptionItem, asOf now: Date) -> EasierSwapOption? { nil }
    func issueEasierSwap(replacing item: PrescriptionItem, option: EasierSwapOption, at now: Date) -> IssuedEasierSwap? { nil }
}

/// What the Adaptive training debug page needs to start Today's Session.
@MainActor
protocol TodaySessionStarting: AnyObject {
    var lastStartProblem: String? { get }
    func start(asOf now: Date) -> TodaySessionLaunch?
}

/// What the coach reported about one calibration sample, once its evidence was recorded.
struct CalibrationProbeResult: Equatable {
    /// The probe this answers.
    let launchID: UUID
    /// The effort card's answer; nil when it was skipped or closed unrated.
    let effort: EffortFeedback?
    /// What the user stands behind; nil when nobody confirmed any work.
    let confirmed: WorkAmount?
}

/// Records the coach's evidence for one calibration sample as calibration evidence, and reports the first result.
///
/// The coach builds the same evidence it builds for any prescribed item. This turns it into a probe: source
/// `.calibration`, this attempt's id, and no prescription or bonus, so nothing about the sample can change a
/// recommendation until the calibration is committed. It offers no easier version and knows no active rung, so the
/// coach asks nothing else about a sample.
@MainActor
final class CalibrationProbeRecorder: AdaptiveEvidenceRecording {
    let launchID: UUID
    private let calibrationID: UUID
    private let store: @MainActor (AdaptiveEvidence) -> Void
    private let onResult: @MainActor (CalibrationProbeResult) -> Void
    private var hasReported = false

    init(launchID: UUID, calibrationID: UUID, store: @escaping @MainActor (AdaptiveEvidence) -> Void,
         onResult: @escaping @MainActor (CalibrationProbeResult) -> Void) {
        self.launchID = launchID
        self.calibrationID = calibrationID
        self.store = store
        self.onResult = onResult
    }

    func activeRung(for exerciseID: ExerciseID, reducedRange: Bool) -> ActiveRung? { nil }

    func record(_ evidence: AdaptiveEvidence) {
        let probe = Self.probe(from: evidence, calibrationID: calibrationID)
        store(probe)
        guard !hasReported else { return }
        hasReported = true
        onResult(CalibrationProbeResult(launchID: launchID, effort: probe.effort, confirmed: probe.confirmed))
    }

    /// The same facts about what happened, as a probe of `calibrationID`.
    static func probe(from evidence: AdaptiveEvidence, calibrationID: UUID) -> AdaptiveEvidence {
        AdaptiveEvidence(
            id: evidence.id, recordedAt: evidence.recordedAt, source: .calibration, family: evidence.family,
            variant: evidence.variant, workoutID: evidence.workoutID, calibrationID: calibrationID,
            prescribed: evidence.prescribed, confirmed: evidence.confirmed, confirmation: evidence.confirmation,
            setAmounts: evidence.setAmounts, tracker: evidence.tracker, effort: evidence.effort,
            midSetTooHard: evidence.midSetTooHard, bonus: nil, completion: evidence.completion,
            weightNote: evidence.weightNote)
    }
}

/// One calibration sample ready to run in the coach: a one-item plan for the sample's rung, and the recorder that
/// turns the coach's evidence into the sample's result.
struct CalibrationProbeLaunch: Identifiable {
    var id: UUID { launch.prescription.id }
    let family: MovementFamilyID
    let rungDose: RungDose
    /// The unsaved prescription, plan, and plan item the coach reads. The prescription is never stored.
    let launch: TodaySessionLaunch
    let recorder: CalibrationProbeRecorder
}

/// What the calibration screen needs from adaptive training. The engine decides every step; this only starts,
/// saves, and runs what the flow returns.
@MainActor
protocol CalibrationCoordinating: AnyObject {
    /// Starts the first calibration and saves it as in progress, or nil when it couldn't be saved.
    func startCalibration(asOf now: Date) -> CalibrationFlow?
    /// Saves the quiz answers so far. A failure is logged and never stops the flow.
    func saveCalibrationProgress(_ flow: CalibrationFlow)
    /// Accepts the summary. False when it couldn't be saved.
    func commitCalibration(_ flow: CalibrationFlow, asOf now: Date) -> Bool
    /// Leaves without accepting anything. A failure is logged.
    func abandonCalibration(_ flow: CalibrationFlow, asOf now: Date)
    /// Prepares the sample the flow is showing to run in the coach, or nil when the coach can't run it. `onResult`
    /// fires once, when the coach records the sample's evidence.
    func prepareProbe(for flow: CalibrationFlow, asOf now: Date,
                      onResult: @escaping @MainActor (CalibrationProbeResult) -> Void) -> CalibrationProbeLaunch?
    /// A plain name for a rung, such as "Wall Push-Up".
    func displayName(of variant: VariantID) -> String
}

/// The one app object that calls the adaptive engine, besides the debug provider. It prepares Today's Session as a
/// tiny workout plan and records evidence. The engine decides what is easier, harder, or next; this type only maps
/// its answers to the coach and the coach's facts back.
@MainActor
@Observable
final class AdaptiveTrainingCoordinator: AdaptiveEvidenceRecording, TodaySessionStarting, CalibrationCoordinating {
    /// The plan id of every Today's Session workout. It matches no routine, so routine rotation and the Up Next
    /// override never see it.
    nonisolated static let todaySessionPlanID = UUID(uuid: (0x70, 0xDA, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                                                            0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))
    nonisolated static let todaySessionName = "Today's Session"
    /// The name of the one-item plan a calibration sample runs as. The plan has no id, so it matches no routine.
    nonisolated static let calibrationProbeName = "Finding your starting point"

    /// True for a saved workout that was a Today's Session.
    nonisolated static func isTodaySession(_ record: WorkoutRecord) -> Bool {
        record.planID == todaySessionPlanID
    }

    /// The session the last successful `start` prepared; the full-screen route reads it.
    private(set) var preparedLaunch: TodaySessionLaunch?
    /// Why the last `start` produced nothing, for the debug page only.
    private(set) var lastStartProblem: String?

    @ObservationIgnored private let engine: AdaptiveTrainingEngine
    @ObservationIgnored private let bridge: ExerciseVariantBridge
    @ObservationIgnored private let makeID: () -> UUID

    init(engine: AdaptiveTrainingEngine, bridge: ExerciseVariantBridge = ExerciseVariantBridge(),
         makeID: @escaping () -> UUID = UUID.init) {
        self.engine = engine
        self.bridge = bridge
        self.makeID = makeID
    }

    /// The engine's answer for Today's Session; an engine error reads as nothing offered.
    func status(asOf now: Date) -> TodaySessionStatus {
        do {
            return try engine.todaySession(asOf: now)
        } catch {
            PersistenceRepositoryLogging.failed("Read Today's Session", error: error)
            return .nothingOffered
        }
    }

    /// Issues the prescription and prepares the plan. Works only while the status is `.ready`.
    func start(asOf now: Date) -> TodaySessionLaunch? {
        preparedLaunch = nil
        lastStartProblem = nil
        guard case .ready(let session) = status(asOf: now) else {
            lastStartProblem = "Today's Session isn't ready."
            return nil
        }
        guard let main = resolve(session.main) else {
            lastStartProblem = "\(session.main.variant.rawValue) can't run here: no exercise matches it and its dose."
            return nil
        }
        // A sample the coach can't run is left out of the prescription too, so nothing is recorded that was never offered.
        let sample = session.harderSample.flatMap(resolve)
        let issued = sample == nil && session.harderSample != nil ? withoutSample(session) : session
        let prescriptionID = makeID()
        let mainItemID = makeID()
        let sampleItemID = sample == nil ? nil : makeID()

        let prescription: Prescription
        do {
            prescription = try engine.issue(issued, prescriptionID: prescriptionID, mainItemID: mainItemID,
                                            sampleItemID: sampleItemID, at: now)
        } catch {
            PersistenceRepositoryLogging.failed("Issue Today's Session", error: error)
            lastStartProblem = "Today's Session couldn't be saved: \(error.localizedDescription)"
            return nil
        }

        var items = [adaptiveItem(id: mainItemID, role: .main, family: session.family, resolved: main)]
        if let sample, let sampleItemID {
            items.append(adaptiveItem(id: sampleItemID, role: .harderSample, family: session.family, resolved: sample))
        }
        let plan = WorkoutPlan(id: Self.todaySessionPlanID, name: Self.todaySessionName,
                               items: items.map { item in
            let amount = item.rungDose.dose.amount
            return WorkoutPlanItem(id: item.itemID, exerciseID: item.exerciseID, sets: 1, targetReps: amount...amount,
                                   reducedRange: item.reducedRange, isOptional: item.role == .harderSample)
        })
        let launch = TodaySessionLaunch(prescription: prescription, plan: plan, items: items)
        preparedLaunch = launch
        return launch
    }

    func activeRung(for exerciseID: ExerciseID, reducedRange: Bool) -> ActiveRung? {
        let profile: AdaptiveProfile
        do {
            profile = try engine.profile()
        } catch {
            PersistenceRepositoryLogging.failed("Read adaptive profile", error: error)
            return nil
        }
        for family in profile.activeFamilies {
            guard let state = profile.state(family), let rung = engine.catalog.rung(state.current.variant),
                  rung.exerciseID == exerciseID.rawValue,
                  rung.modifiers.contains(.reducedRange) == reducedRange else { continue }
            return ActiveRung(family: family, rungDose: state.current)
        }
        return nil
    }

    func record(_ evidence: AdaptiveEvidence) {
        do {
            try engine.record(evidence)
        } catch {
            PersistenceRepositoryLogging.failed("Record adaptive evidence", error: error)
        }
    }

    func easierSwapOption(for item: PrescriptionItem, asOf now: Date) -> EasierSwapOption? {
        do {
            guard let target = try engine.easierSwap(for: item, asOf: now), let resolved = resolve(target) else {
                return nil
            }
            return EasierSwapOption(target: target, exerciseID: resolved.exercise.id,
                                    reducedRange: resolved.rung.modifiers.contains(.reducedRange))
        } catch {
            PersistenceRepositoryLogging.failed("Read the easier version", error: error)
            return nil
        }
    }

    func issueEasierSwap(replacing item: PrescriptionItem, option: EasierSwapOption,
                         at now: Date) -> IssuedEasierSwap? {
        let prescriptionID = makeID()
        let itemID = makeID()
        do {
            let prescription = try engine.issueEasierSwap(replacing: item, target: option.target,
                                                          prescriptionID: prescriptionID, itemID: itemID, at: now)
            return IssuedEasierSwap(
                prescriptionID: prescription.id,
                item: AdaptivePlanItem(itemID: itemID, role: .easierSwap, family: item.family, rungDose: option.target,
                                       exerciseID: option.exerciseID, reducedRange: option.reducedRange))
        } catch {
            PersistenceRepositoryLogging.failed("Issue the easier version", error: error)
            return nil
        }
    }

    // MARK: - Calibration

    func startCalibration(asOf now: Date) -> CalibrationFlow? {
        do {
            return try engine.startCalibration(kind: .initial, id: makeID(), at: now)
        } catch {
            PersistenceRepositoryLogging.failed("Start calibration", error: error)
            return nil
        }
    }

    func saveCalibrationProgress(_ flow: CalibrationFlow) {
        do {
            try engine.saveProgress(flow)
        } catch {
            PersistenceRepositoryLogging.failed("Save calibration progress", error: error)
        }
    }

    func commitCalibration(_ flow: CalibrationFlow, asOf now: Date) -> Bool {
        do {
            try engine.commit(flow, at: now)
            return true
        } catch {
            PersistenceRepositoryLogging.failed("Commit calibration", error: error)
            return false
        }
    }

    func abandonCalibration(_ flow: CalibrationFlow, asOf now: Date) {
        do {
            try engine.abandon(flow, at: now)
        } catch {
            PersistenceRepositoryLogging.failed("Abandon calibration", error: error)
        }
    }

    func prepareProbe(for flow: CalibrationFlow, asOf now: Date,
                      onResult: @escaping @MainActor (CalibrationProbeResult) -> Void) -> CalibrationProbeLaunch? {
        guard case .probe(let family, let rungDose, _) = flow.step, let resolved = resolve(rungDose) else { return nil }
        let prescriptionID = makeID()
        let itemID = makeID()
        let item = adaptiveItem(id: itemID, role: .main, family: family, resolved: resolved)
        let amount = rungDose.dose.amount
        let plan = WorkoutPlan(id: nil, name: Self.calibrationProbeName, items: [
            WorkoutPlanItem(id: itemID, exerciseID: item.exerciseID, sets: 1, targetReps: amount...amount,
                            reducedRange: item.reducedRange)
        ])
        // Never saved: the coach reads it to know the sample's family and rung, and no bonus is ever offered.
        let prescription = Prescription(
            id: prescriptionID, issuedAt: now, kind: .calibrationProbe, policyVersion: engine.policyVersion,
            catalogVersion: engine.catalog.version,
            items: [PrescriptionItem(id: itemID, family: family, target: rungDose, role: .main, offersBonus: false)],
            rationale: "A tiny sample to find a comfortable starting point.")
        let recorder = CalibrationProbeRecorder(launchID: prescriptionID, calibrationID: flow.id,
                                                store: { [weak self] in self?.record($0) }, onResult: onResult)
        return CalibrationProbeLaunch(family: family, rungDose: rungDose,
                                      launch: TodaySessionLaunch(prescription: prescription, plan: plan, items: [item]),
                                      recorder: recorder)
    }

    func displayName(of variant: VariantID) -> String {
        guard let rung = engine.catalog.rung(variant), let exercise = bridge.exercise(for: rung) else {
            return variant.rawValue
        }
        return exercise.displayName
    }

    // MARK: - Mapping

    private struct Resolved {
        let rung: ProgressionRung
        let exercise: ExerciseDefinition
        let rungDose: RungDose
    }

    /// The coach's exercise for a rung and dose, or nil when the app can't run it or the exercise counts something
    /// other than the dose's unit.
    private func resolve(_ rungDose: RungDose) -> Resolved? {
        guard let rung = engine.catalog.rung(rungDose.variant), let exercise = bridge.exercise(for: rung),
              exercise.doseUnit == (rungDose.dose.kind == .seconds ? .seconds : .reps) else { return nil }
        return Resolved(rung: rung, exercise: exercise, rungDose: rungDose)
    }

    private func adaptiveItem(id: UUID, role: PrescriptionItemRole, family: MovementFamilyID,
                              resolved: Resolved) -> AdaptivePlanItem {
        AdaptivePlanItem(itemID: id, role: role, family: family, rungDose: resolved.rungDose,
                         exerciseID: resolved.exercise.id,
                         reducedRange: resolved.rung.modifiers.contains(.reducedRange))
    }

    private func withoutSample(_ session: TodaySession) -> TodaySession {
        TodaySession(family: session.family, main: session.main, harderSample: nil, offersBonus: session.offersBonus,
                     isTiny: session.isTiny, confidence: session.confidence,
                     estimatedSeconds: session.estimatedSeconds, rationale: session.rationale,
                     basedOnTransitionID: session.basedOnTransitionID)
    }
}
