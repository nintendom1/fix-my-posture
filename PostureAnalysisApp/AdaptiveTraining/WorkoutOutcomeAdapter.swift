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
    /// The extra set taken after an Easy rating, not an item the app prescribed.
    var isBonus = false
    /// The easier version taken when an item was too hard, run in its place.
    var isEasierSwap = false

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
        /// The prescription item may offer a bonus after an Easy rating (a main item whose prescription says so).
        var offersBonus = false
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

    /// What the user did about an item after tapping or saying "Too hard?" during it. Any of them flags the item's
    /// evidence (`midSetTooHard`); none of them touches the tracker's observation.
    enum TooHardChoice: Equatable {
        /// The offer was ignored (or closed) and the set ran its course.
        case flagged
        /// "Stop here, it counts": the item ended early with what was done.
        case stoppedHere
        /// "Easier version": the item ended with what was done and an easier rung or dose ran in its place.
        case switchedToEasier
    }

    /// `answer` is nil when no card was shown, for example when the workout ended during the item. `bonus` is the
    /// optional extra offered after an Easy rating, kept apart from the prescribed work. `tooHard` is set when the
    /// user flagged the item mid-set.
    static func evidence(id: UUID, recordedAt: Date, workoutID: UUID?, identity: Identity, item: FinishedWorkoutItem,
                         answer: Answer?, bonus: BonusRecord? = nil, tooHard: TooHardChoice? = nil) -> AdaptiveEvidence {
        let adjusted = answer.flatMap { $0.isAdjusted ? $0.amount : nil }
        // What the item itself did, whatever the user then chose; confirmation and the tracker read this.
        let outcome = completion(of: item, adjusted: adjusted)
        let confirmation = confirmation(of: item, completion: outcome, adjusted: adjusted, rated: answer?.effort != nil)
        let completion = completionAfter(outcome, choice: tooHard)

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
            tracker: tracker(of: item, completion: outcome),
            effort: answer?.effort,
            midSetTooHard: tooHard != nil, bonus: bonus,
            completion: completion)
    }

    /// How the item ended once the user's Too hard choice is counted. Stopping early is the user's choice, so even a
    /// self-reported item confirmed at its full amount reads as stopped early; taking the easier version is its own
    /// ending. A workout that ended, or an item never attempted, keeps its own reason.
    static func completionAfter(_ outcome: CompletionReason, choice: TooHardChoice?) -> CompletionReason {
        switch choice {
        case .switchedToEasier?:
            return .switchedToEasier
        case .stoppedHere?:
            return outcome == .completed ? .stoppedEarly : outcome
        case .flagged?, nil:
            return outcome
        }
    }

    // MARK: - Bonus

    /// A bonus is one more rep, or five more seconds of a hold.
    static let bonusReps = 1
    static let bonusSeconds = 5

    static func bonusDose(for unit: DoseKind) -> Dose {
        unit == .seconds ? .seconds(bonusSeconds) : .reps(bonusReps)
    }

    /// The bonus to offer once a prescribed item is rated, or nil. Only a main Today's Session item whose
    /// prescription offers one, rated Easy and done in full (counting a corrected amount), earns it. Manual work, a
    /// harder sample, Okay or Too Hard, a skipped item, an item stopped early, and a bonus itself never do.
    static func bonusOffer(identity: Identity, item: FinishedWorkoutItem, answer: Answer,
                           tooHard: TooHardChoice? = nil) -> Dose? {
        // Nobody who said it was too hard is asked to do more, whatever they rate it afterwards.
        guard identity.offersBonus, case .adaptive = identity.origin, !item.isBonus, !item.isEasierSwap,
              tooHard == nil, answer.effort == .easy,
              item.result == .completed,
              completion(of: item, adjusted: answer.isAdjusted ? answer.amount : nil) == .completed else { return nil }
        return bonusDose(for: item.unit)
    }

    /// What happened to an offered bonus. A declined one carries nothing else. An accepted one carries the amount only
    /// when somebody vouched for it, the same way the prescribed item does: the user's correction, a self-reported or
    /// timed amount, or a camera count the user rated without changing, and never after tracking was lost. A bonus
    /// that was accepted but ended before it was done (`item` nil) carries no amount. A lost tracker is never a
    /// failed bonus.
    static func bonusRecord(offered: Dose, accepted: Bool, item: FinishedWorkoutItem?,
                            answer: Answer?) -> BonusRecord {
        guard accepted, let item else { return BonusRecord(offered: offered, accepted: accepted) }
        let adjusted = answer.flatMap { $0.isAdjusted ? $0.amount : nil }
        let completion = completion(of: item, adjusted: adjusted)
        let confirmation = confirmation(of: item, completion: completion, adjusted: adjusted,
                                        rated: answer?.effort != nil)
        let completed = confirmation.source == .none
            ? nil : WorkAmount(kind: item.unit, amount: adjusted ?? item.counted)
        return BonusRecord(offered: offered, accepted: true, completed: completed, effort: answer?.effort)
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
                    // The record keeps only finished sets, so work in the set being skipped is read from before it. A
                    // bonus's or an easier version's record already carries that work, so it isn't added twice.
                    if before.currentPlanItem?.id == planItem.id, !planItem.isInserted {
                        let partial = before.observedSetAmount(at: now)
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
                    // The last set, or "Stop here" ending the exercise early: complete with the sets it has.
                    result = sets >= definition.setEntries || after.phase == .exerciseComplete ? .completed : nil
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

    /// The plan occurrence whose set is under way, as it stands when its screen closes: the sets it finished plus what
    /// the set under way has observed (counted reps, or seconds held; never invented reps for a self-reported set). It
    /// has the same shape as an item the workout ended on. Nil when nothing was done yet, so nothing is invented.
    static func itemInProgress(in session: WorkoutSession, at now: TimeInterval) -> FinishedWorkoutItem? {
        guard session.isFollowingPlan, let planItem = session.currentPlanItem, session.planRecords[planItem.id] == nil,
              let base = session.exercises.first(where: { $0.id == planItem.exerciseID }) else { return nil }
        var amounts = session.progress[planItem.exerciseID]?.roundSetReps ?? []
        let observed = session.observedSetAmount(at: now)
        if observed > 0 { amounts.append(observed) }
        guard !amounts.isEmpty else { return nil }
        let definition = planItem.resolved(from: base).withTarget(sets: planItem.sets, reps: planItem.targetReps)
        return item(planItem: planItem, definition: definition, amounts: amounts, result: .endedWorkout,
                    trackingLost: !session.framing.isReliable, round: 1)
    }

    private static func item(planItem: WorkoutPlanItem?, definition: ExerciseDefinition, amounts: [Int],
                             result: FinishedWorkoutItem.Result, trackingLost: Bool, round: Int) -> FinishedWorkoutItem {
        let isTimed = definition.doseUnit == .seconds
        let tracking: FinishedWorkoutItem.Tracking = isTimed ? .timedHold : (definition.isSelfReported ? .selfReported : .camera)
        return FinishedWorkoutItem(
            planItemID: planItem?.id, exerciseID: definition.id, reducedRange: planItem?.reducedRange ?? false,
            unit: isTimed ? .seconds : .reps, tracking: tracking, setAmounts: amounts,
            target: definition.targetReps.lowerBound, result: result,
            trackingLost: tracking == .camera && trackingLost, round: round, isBonus: planItem?.isBonus ?? false,
            isEasierSwap: planItem?.isEasierSwap ?? false)
    }

    /// Names the occurrence the session is on, the way `FinishedWorkoutItem.key` will once it finishes: the plan
    /// occurrence, or the standalone exercise and its round. Nil before an exercise is chosen.
    static func currentKey(in session: WorkoutSession) -> FinishedWorkoutItem.Key? {
        if session.isFollowingPlan, let planItem = session.currentPlanItem { return .plan(planItem.id) }
        guard let id = session.exerciseID else { return nil }
        return .exercise(id, round: session.progress[id]?.round ?? 1)
    }
}
