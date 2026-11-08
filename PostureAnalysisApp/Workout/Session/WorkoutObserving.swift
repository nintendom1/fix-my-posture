import Foundation
import AdaptiveTraining

enum WorkoutCoachOffer: Equatable, Sendable {
    case tooHard
    case effort
    case bonus
}

/// Read-only, downstream observation of completed workout actions. Production attaches no observer.
@MainActor
protocol WorkoutObserving: AnyObject {
    /// Called after the reducer effects and the model's follow-up bookkeeping have completed.
    func workoutDidHandle(_ event: WorkoutEvent, effects: [WorkoutEffect], at time: TimeInterval)
    /// Called after the line has been recorded and, unless muted, sent to speech.
    func coachDidSay(_ utterance: Utterance, muted: Bool)
    /// Called after the last instruction has been repeated, unless muted.
    func coachDidRepeatLastInstruction(muted: Bool)
    /// A value of nil means the visible tip was cleared.
    func coachDidShowTip(_ tip: CoachingTip?)
    /// Called after a feedback offer has been made available to the user.
    func coachDidOffer(_ offer: WorkoutCoachOffer)
    /// Called only after a history record was committed successfully.
    func workoutDidSave(_ record: WorkoutRecord)
    /// Called after a successful adaptive engine operation, in the engine's event order.
    func adaptiveEventsDidOccur(_ events: [AdaptiveEvent])
}

extension WorkoutObserving {
    func workoutDidHandle(_ event: WorkoutEvent, effects: [WorkoutEffect], at time: TimeInterval) { }
    func coachDidSay(_ utterance: Utterance, muted: Bool) { }
    func coachDidRepeatLastInstruction(muted: Bool) { }
    func coachDidShowTip(_ tip: CoachingTip?) { }
    func coachDidOffer(_ offer: WorkoutCoachOffer) { }
    func workoutDidSave(_ record: WorkoutRecord) { }
    func adaptiveEventsDidOccur(_ events: [AdaptiveEvent]) { }
}
