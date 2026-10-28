import AdaptiveTraining
import Foundation

/// One finished item of a workout, as the plain facts the app can see. The adapter turns it, with the effort card's
/// answer, into `AdaptiveEvidence`. It never decides anything about difficulty.
struct FinishedWorkoutItem: Equatable {
    enum Tracking: Equatable {
        /// The camera counted the reps.
        case camera
        /// The user said the set was done.
        case selfReported
        /// A hold measured in seconds; only the timer or Done ends it.
        case timedHold
    }

    enum Result: Equatable {
        /// Every set of the item finished.
        case completed
        /// The item was skipped, possibly after some work.
        case skipped
        /// The workout ended while the item was in progress.
        case endedWorkout
    }

    /// The plan occurrence; nil outside a plan.
    let planItemID: UUID?
    let exerciseID: ExerciseID
    let reducedRange: Bool
    /// Reps, or seconds for a hold.
    let unit: DoseKind
    let tracking: Tracking
    /// Every finished set of the item, in order, in `unit`.
    let setAmounts: [Int]
    /// What one set must reach to count as complete: the item's target, or the low end of its range.
    let target: Int
    let result: Result
    /// A camera-tracked item that finished while the camera had lost the body.
    let trackingLost: Bool
    /// Which round of a standalone exercise this is (Another Round starts a new one).
    var round = 1

    /// Names one occurrence, so the workout reports it once however many times it notices it.
    enum Key: Hashable {
        case plan(UUID)
        case exercise(ExerciseID, round: Int)
    }

    var key: Key { planItemID.map { .plan($0) } ?? .exercise(exerciseID, round: round) }

    /// The smallest set, so an item with several sets is never overstated.
    var counted: Int { setAmounts.min() ?? 0 }
    var didAnyWork: Bool { setAmounts.contains { $0 > 0 } }
}

/// Maps a finished item plus the effort card's answer to `AdaptiveEvidence`. Pure: ids and times come from the caller.
enum WorkoutOutcomeAdapter {
    /// Who the evidence is about.
    struct Identity: Equatable {
        enum Origin: Equatable {
            /// Today's Session: linked to the exact prescription item and what it asked for.
            case adaptive(prescriptionID: UUID, itemID: UUID, prescribed: Dose)
            /// A routine or Quick Start exercise that happens to be the current rung of an active family.
            case manual
        }

        let origin: Origin
        let family: MovementFamilyID
        let variant: VariantID
    }

    /// What the user said on the card.
    struct Answer: Equatable {
        /// Nil when the card was skipped or closed unrated.
        let effort: EffortFeedback?
        /// The amount on the card when it closed.
        let amount: Int
        /// The user changed the amount from the one the card showed first.
        let isAdjusted: Bool
    }

    /// `answer` is nil when no card was shown, for example when the workout ended during the item.
    static func evidence(id: UUID, recordedAt: Date, workoutID: UUID?, identity: Identity, item: FinishedWorkoutItem,
                         answer: Answer?) -> AdaptiveEvidence {
        let adjusted = answer.flatMap { $0.isAdjusted ? $0.amount : nil }
        let completion = completion(of: item, adjusted: adjusted)
        let confirmation = confirmation(of: item, completion: completion, adjusted: adjusted, rated: answer?.effort != nil)

        var source = EvidenceSource.manual
        var prescriptionID: UUID?
        var prescriptionItemID: UUID?
        var prescribed: Dose?
        if case .adaptive(let prescription, let itemID, let dose) = identity.origin {
            source = .adaptive
            prescriptionID = prescription
            prescriptionItemID = itemID
            prescribed = dose
        }

        return AdaptiveEvidence(
            id: id, recordedAt: recordedAt, source: source, family: identity.family, variant: identity.variant,
            prescriptionID: prescriptionID, prescriptionItemID: prescriptionItemID, workoutID: workoutID,
            prescribed: prescribed,
            confirmed: confirmation.source == .none ? nil : WorkAmount(kind: item.unit, amount: adjusted ?? item.counted),
            confirmation: confirmation.source,
            setAmounts: confirmation.setAmounts.map { WorkAmount(kind: item.unit, amount: $0) },
            tracker: tracker(of: item, completion: completion),
            effort: answer?.effort,
            // Mid-set Too Hard and the bonus are recorded by later PRs.
            midSetTooHard: false, bonus: nil,
            completion: completion)
    }

    /// How the item ended. A card amount the user changed counts, so correcting a miscount fixes the completion too.
    static func completion(of item: FinishedWorkoutItem, adjusted: Int?) -> CompletionReason {
        let amount = adjusted ?? item.counted
        switch item.result {
        case .endedWorkout:
            return .endedWorkout
        case .skipped:
            return item.didAnyWork || amount > 0 ? .stoppedEarly : .notAttempted
        case .completed:
            return amount >= item.target ? .completed : .stoppedEarly
        }
    }

    private static func confirmation(of item: FinishedWorkoutItem, completion: CompletionReason, adjusted: Int?,
                                     rated: Bool) -> (source: ConfirmationSource, setAmounts: [Int]) {
        // The user's own correction is authoritative, whatever the camera saw.
        if let adjusted {
            return (.user, Array(repeating: adjusted, count: max(1, item.setAmounts.count)))
        }
        if completion == .notAttempted { return (.none, []) }
        switch item.tracking {
        case .selfReported, .timedHold:
            // The user (or the hold timer they ran) reported the amount.
            return (.user, item.setAmounts.isEmpty ? [item.counted] : item.setAmounts)
        case .camera:
            // A tracker count stands in for the user's word only when they rated it, and never after tracking loss.
            guard rated, !item.trackingLost else { return (.none, []) }
            return (.trackerAccepted, item.setAmounts)
        }
    }

    private static func tracker(of item: FinishedWorkoutItem, completion: CompletionReason) -> TrackerObservation {
        switch item.tracking {
        case .selfReported, .timedHold:
            return .notTracked
        case .camera:
            if completion == .notAttempted { return .notTracked }
            let observed = WorkAmount(kind: item.unit, amount: item.counted)
            // Rejection reasons stay empty: the session doesn't keep the analyzer's rep rejections.
            return TrackerObservation(status: item.trackingLost ? .lost : .tracked, observed: observed)
        }
    }
}

/// Finds the items that finished in one reducer input by comparing the session before and after it, so the reducer's
/// transitions stay untouched.
enum FinishedItemDetector {
    /// `now` is the reducer time of the input, which a timed hold needs to say how long it had been held.
    static func finishedItems(before: WorkoutSession, after: WorkoutSession, at now: TimeInterval) -> [FinishedWorkoutItem] {
        var items: [FinishedWorkoutItem] = []

        // Plan occurrences get a record when they finish: completed, skipped, or (when the workout ends) no outcome.
        if let plan = after.plan {
            for planItem in plan.items {
                let earlier = before.planRecords[planItem.id]
                guard let record = after.planRecords[planItem.id], record != earlier, earlier?.outcome == nil,
                      let base = after.exercises.first(where: { $0.id == planItem.exerciseID }) else { continue }
                let definition = planItem.resolved(from: base).withTarget(sets: planItem.sets, reps: planItem.targetReps)
                let result: FinishedWorkoutItem.Result
                var amounts = record.setReps
                switch record.outcome {
                case .completed?:
                    result = .completed
                case .skipped?:
                    result = .skipped
                    // The record keeps only finished sets, so work in the set being skipped is read from before it.
                    if before.currentPlanItem?.id == planItem.id {
                        let partial = observedPartialAmount(in: before, at: now)
                        if partial > 0 { amounts.append(partial) }
                    }
                case nil:
                    result = .endedWorkout
                }
                items.append(item(planItem: planItem, definition: definition, amounts: amounts, result: result,
                                  trackingLost: !before.framing.isReliable, round: 1))
            }
        }

        // Outside a plan (or after leaving it), an exercise finishes with its last set, or when the workout ends
        // with sets done.
        if !after.isFollowingPlan, let id = after.exerciseID, id == before.exerciseID, let definition = after.exercise {
            let earlierSets = before.completedSets(for: id)
            let sets = after.completedSets(for: id)
            if sets > earlierSets {
                let result: FinishedWorkoutItem.Result?
                if after.phase == .ended {
                    result = .endedWorkout
                } else {
                    result = sets >= definition.setEntries ? .completed : nil
                }
                if let result {
                    items.append(item(planItem: nil, definition: definition,
                                      amounts: after.progress[id]?.roundSetReps ?? [], result: result,
                                      trackingLost: !before.framing.isReliable, round: after.progress[id]?.round ?? 1))
                }
            }
        }
        return items
    }

    /// Work that never finished its item, for when the workout ends or its screen closes: the plan occurrence in
    /// progress, or a standalone exercise, that has finished sets but not all of them. Each carries its finished sets
    /// only (the same ones history keeps) and ended with the workout.
    static func unfinishedItems(in session: WorkoutSession) -> [FinishedWorkoutItem] {
        var items: [FinishedWorkoutItem] = []
        let planExercises = Set(session.plan?.items.map(\.exerciseID) ?? [])
        if session.isFollowingPlan {
            if let planItem = session.currentPlanItem, session.planRecords[planItem.id] == nil,
               let sets = session.progress[planItem.exerciseID]?.roundSetReps, !sets.isEmpty,
               let base = session.exercises.first(where: { $0.id == planItem.exerciseID }) {
                let definition = planItem.resolved(from: base).withTarget(sets: planItem.sets, reps: planItem.targetReps)
                items.append(item(planItem: planItem, definition: definition, amounts: sets, result: .endedWorkout,
                                  trackingLost: !session.framing.isReliable, round: 1))
            }
            return items
        }
        for exercise in session.exercises where !planExercises.contains(exercise.id) {
            guard let progress = session.progress[exercise.id], !progress.roundSetReps.isEmpty,
                  progress.roundSetReps.count < exercise.setEntries else { continue }
            items.append(item(planItem: nil, definition: exercise, amounts: progress.roundSetReps, result: .endedWorkout,
                              trackingLost: !session.framing.isReliable, round: progress.round))
        }
        return items
    }

    /// What the set in progress had observed when it was discarded: counted reps for a camera exercise, seconds held
    /// for a timed hold, and nothing for a self-reported rep set, whose reps nobody has said were done.
    private static func observedPartialAmount(in session: WorkoutSession, at now: TimeInterval) -> Int {
        guard isSetInProgress(session.phase), let exercise = session.exercise else { return 0 }
        if exercise.doseUnit == .seconds {
            let remaining = session.holdRemaining(at: now) ?? TimeInterval(exercise.autoCompleteReps)
            return max(0, exercise.autoCompleteReps - Int(remaining.rounded(.up)))
        }
        return exercise.isSelfReported ? 0 : session.repCount
    }

    /// A set is under way while exercising or paused, including when the exercise chooser was opened over it.
    private static func isSetInProgress(_ phase: WorkoutPhase) -> Bool {
        switch phase {
        case .exercising, .paused: return true
        case .changingExercise(let previous): return isSetInProgress(previous)
        default: return false
        }
    }

    private static func item(planItem: WorkoutPlanItem?, definition: ExerciseDefinition, amounts: [Int],
                             result: FinishedWorkoutItem.Result, trackingLost: Bool, round: Int) -> FinishedWorkoutItem {
        let isTimed = definition.doseUnit == .seconds
        let tracking: FinishedWorkoutItem.Tracking = isTimed ? .timedHold : (definition.isSelfReported ? .selfReported : .camera)
        return FinishedWorkoutItem(
            planItemID: planItem?.id, exerciseID: definition.id, reducedRange: planItem?.reducedRange ?? false,
            unit: isTimed ? .seconds : .reps, tracking: tracking, setAmounts: amounts,
            target: definition.targetReps.lowerBound, result: result,
            trackingLost: tracking == .camera && trackingLost, round: round)
    }
}
