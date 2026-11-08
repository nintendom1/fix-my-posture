import Foundation
import AdaptiveTraining

/// Semantic workout events a future companion or sound layer could react to (#132 phase 1). Test-only consumers.
enum WorkoutPresentationEvent: Equatable, Sendable {
    case cueSpoken(text: String, muted: Bool)
    case instructionRepeated(muted: Bool)
    case tipShown(text: String)
    case tipCleared
    case repCounted(total: Int)
    case setCompleted(set: Int, reps: Int)
    case setStarted(set: Int)
    case restStarted(seconds: Int)
    case workoutPaused
    case workoutResumed
    case exerciseChanged(exerciseID: String)
    case exerciseCompleted
    case workoutCompleted
    case workoutSaved
    case tooHardOffered
    case effortRequested
    case bonusOffered
    case adaptive(AdaptiveEventKind)
}

/// Value-only input copied from one observer callback.
enum WorkoutObservationInput {
    case workoutDidHandle(WorkoutEvent, effects: [WorkoutEffect], at: TimeInterval)
    case coachDidSay(Utterance, muted: Bool)
    case coachDidRepeatLastInstruction(muted: Bool)
    case coachDidShowTip(CoachingTip?)
    case coachDidOffer(WorkoutCoachOffer)
    case workoutDidSave(WorkoutRecord)
    case adaptiveEventsDidOccur([AdaptiveEvent])
}

/// Read-only reducer and presentation state needed to derive transition events in tests.
struct WorkoutPresentationSnapshot {
    let session: WorkoutSession
}

/// Maps the existing workout and observer vocabulary to semantic events without owning workout decisions.
enum WorkoutPresentationMapper {
    static func map(_ input: WorkoutObservationInput) -> [WorkoutPresentationEvent] {
        switch input {
        case .workoutDidHandle:
            return []
        case .coachDidSay(let utterance, let muted):
            return [.cueSpoken(text: utterance.text, muted: muted)]
        case .coachDidRepeatLastInstruction(let muted):
            return [.instructionRepeated(muted: muted)]
        case .coachDidShowTip(let tip):
            return tip.map { [.tipShown(text: $0.cue.text)] } ?? [.tipCleared]
        case .coachDidOffer(let offer):
            switch offer {
            case .tooHard: return [.tooHardOffered]
            case .effort: return [.effortRequested]
            case .bonus: return [.bonusOffered]
            }
        case .workoutDidSave:
            return [.workoutSaved]
        case .adaptiveEventsDidOccur(let events):
            return events.map { .adaptive($0.kind) }
        }
    }

    /// State transitions are emitted in a stable order: exercise change, set/pause transition, reps and sets,
    /// then rest and completion.
    static func map(_ input: WorkoutObservationInput, before: WorkoutPresentationSnapshot,
                    after: WorkoutPresentationSnapshot) -> [WorkoutPresentationEvent] {
        guard case .workoutDidHandle = input else { return map(input) }

        let old = before.session
        let new = after.session
        var events: [WorkoutPresentationEvent] = []

        if old.exerciseID != new.exerciseID, let exerciseID = new.exerciseID {
            events.append(.exerciseChanged(exerciseID: exerciseID.rawValue))
        }
        if old.phase != new.phase {
            if new.phase == .exercising {
                if case .paused = old.phase { events.append(.workoutResumed) }
                else { events.append(.setStarted(set: new.currentSetNumber)) }
            } else if case .paused = new.phase, old.phase == .exercising {
                events.append(.workoutPaused)
            }
        }
        if new.repEventCount > old.repEventCount {
            let id = old.exerciseID
            let previousEntries = id.flatMap { old.progress[$0]?.setReps.count } ?? 0
            let progress = id.flatMap { new.progress[$0] }
            let total = (progress?.setReps.count ?? 0) > previousEntries
                ? progress?.setReps.last ?? new.repCount
                : new.repCount
            events.append(.repCounted(total: total))
        }
        events.append(contentsOf: completedSets(from: old, to: new))
        if old.phase != .resting, new.phase == .resting {
            events.append(.restStarted(seconds: new.restDurationSeconds ?? 0))
        }
        if old.phase != .exerciseComplete, new.phase == .exerciseComplete {
            events.append(.exerciseCompleted)
        }
        if old.phase != .ended, new.phase == .ended {
            events.append(.workoutCompleted)
        }
        return events
    }

    private static func completedSets(from before: WorkoutSession,
                                      to after: WorkoutSession) -> [WorkoutPresentationEvent] {
        guard let id = before.exerciseID,
              let exercise = before.exercises.first(where: { $0.id == id }) else { return [] }
        let oldProgress = before.progress[id]
        let newProgress = after.progress[id]
        let entriesPerSet = exercise.perSide ? 2 : 1
        let roundStart = oldProgress?.roundStart ?? 0
        let oldEntryCount = oldProgress?.setReps.count ?? 0
        let setReps = newProgress?.setReps ?? []
        let newEntryCount = setReps.count
        guard newEntryCount > oldEntryCount else { return [] }
        let completedBeforeEntries = max(0, oldEntryCount - roundStart)
        let completedAfterEntries = completedBeforeEntries + newEntryCount - oldEntryCount
        let completedBefore = completedBeforeEntries / entriesPerSet
        let completedAfter = completedAfterEntries / entriesPerSet
        guard completedAfter > completedBefore else { return [] }

        return (0..<(completedAfter - completedBefore)).compactMap { offset in
            let first = roundStart + (completedBefore + offset) * entriesPerSet
            guard setReps.indices.contains(first) else { return nil }
            let reps: Int
            if exercise.perSide {
                let second = first + 1
                guard setReps.indices.contains(second) else { return nil }
                reps = min(setReps[first], setReps[second])
            } else {
                reps = setReps[first]
            }
            return .setCompleted(set: completedBefore + offset + 1, reps: reps)
        }
    }
}
