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

/// What the workout model needs from adaptive training: which rung a manual exercise is, and a place to record
/// evidence. Nil in workouts that have no engine.
@MainActor
protocol AdaptiveEvidenceRecording: AnyObject {
    /// The family and rung when `exerciseID` (full or reduced range) is the current rung of an active family.
    func activeRung(for exerciseID: ExerciseID, reducedRange: Bool) -> ActiveRung?
    /// Saves evidence. A failure is logged and never reaches the workout.
    func record(_ evidence: AdaptiveEvidence)
}

/// What the Adaptive training debug page needs to start Today's Session.
@MainActor
protocol TodaySessionStarting: AnyObject {
    var lastStartProblem: String? { get }
    func start(asOf now: Date) -> TodaySessionLaunch?
}

/// The one app object that calls the adaptive engine, besides the debug provider. It prepares Today's Session as a
/// tiny workout plan and records evidence. The engine decides what is easier, harder, or next; this type only maps
/// its answers to the coach and the coach's facts back.
@MainActor
@Observable
final class AdaptiveTrainingCoordinator: AdaptiveEvidenceRecording, TodaySessionStarting {
    /// The plan id of every Today's Session workout. It matches no routine, so routine rotation and the Up Next
    /// override never see it.
    nonisolated static let todaySessionPlanID = UUID(uuid: (0x70, 0xDA, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                                                            0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))
    nonisolated static let todaySessionName = "Today's Session"

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
