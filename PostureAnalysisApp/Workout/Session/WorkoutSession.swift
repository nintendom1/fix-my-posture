import Foundation

enum PauseReason: Equatable {
    case user
    case background
    case interruption
}

enum WorkoutPhase: Equatable {
    case choosingExercise
    /// Waiting for reliable tracking and good framing.
    case framing
    /// Framed and waiting for start.
    case ready
    case exercising
    case paused(PauseReason)
    case resting
    /// Waiting for an exercise name; cancel returns to `previous`.
    indirect case changingExercise(previous: WorkoutPhase)
    case exerciseComplete
    case ended
}

/// Commands shared by touch controls and voice.
enum WorkoutCommand: Equatable {
    case start
    case pause
    case resume
    case restartSet
    case nextSet
    case changeExercise
    case selectExercise(ExerciseID)
    case cancel
    case repCount
    case whichSet
    case repeatLast
    /// Opens the Voice Commands help.
    case help
    /// Closes the Voice Commands help; the workout itself is unaffected.
    case closeHelp
    /// Silences the coach's spoken lines.
    case muteCoach
    case unmuteCoach
    /// Stops listening; turning it back on is touch-only, since a muted microphone can't hear.
    case muteMicrophone
    case endWorkout
}

struct Utterance: Equatable {
    let text: String
    /// Instructions are what "repeat that" repeats; status replies are not.
    var isInstruction = true
    /// Cancels current and queued speech.
    var interrupts = false
}

enum WorkoutEvent: Equatable {
    /// The screen is ready and the camera is running for the first time.
    case opened
    case command(WorkoutCommand)
    case framingChanged(FramingStatus)
    case repCompleted(RepEvent)
    /// Every arm is (or stops being) confirmed at the exercise's start position.
    case startPositionChanged(Bool)
    /// The phone has settled into (or out of) a forward/back lean that distorts heights.
    case phoneTiltChanged(Bool)
    /// Periodic clock for debounced guidance and the rest timer.
    case tick
    case appBackgrounded
    case appForegrounded
    case interruptionBegan
    case interruptionEnded
    /// Voice control availability changes how prompts are worded.
    case voiceControlChanged(Bool)
}

enum WorkoutEffect: Equatable {
    case speak(Utterance)
    case repeatLastInstruction
    /// Replace the analyzer; reps from older epochs are ignored.
    case resetAnalyzer(epoch: Int)
    case setCounting(Bool)
    case clearFeedback
    case stopCaptureAndVoice
}

struct ExerciseProgress: Equatable {
    /// Reps recorded for each finished set, in order.
    var setReps: [Int] = []
}

/// Pure workout state machine. Every input is an event with a time; every side effect is returned.
struct WorkoutSession {
    let exercises: [ExerciseDefinition]
    private(set) var phase: WorkoutPhase
    private(set) var exerciseID: ExerciseID?
    private(set) var progress: [ExerciseID: ExerciseProgress] = [:]
    private(set) var sideReps: [BodySide: Int] = [.left: 0, .right: 0]
    private(set) var framing = FramingStatus.lost
    private(set) var isCounting = false
    private(set) var analyzerEpoch = 0
    private(set) var restEndsAt: TimeInterval?
    private(set) var voiceControlActive = false

    private var guidanceChangedAt: TimeInterval?
    private var lastSpokenGuidance: FramingGuidance?
    private var lastGuidanceSpokenAt: TimeInterval?
    private var trackingLostAt: TimeInterval?
    private var trackingLossAnnounced = false
    private var restDoneAnnounced = false
    private var lastReadyAnnouncedAt: TimeInterval?
    private var startPositionSince: TimeInterval?
    private var readySince: TimeInterval?
    private var lastTiltWarningAt: TimeInterval?

    /// Guidance must hold this long before it is spoken.
    static let guidanceSettleTime: TimeInterval = 1.0
    /// The same guidance, or the ready prompt, is repeated no more often than this.
    static let guidanceRepeatInterval: TimeInterval = 20
    /// Tracking must stay lost this long mid-set before guidance is spoken.
    static let trackingLossGrace: TimeInterval = 0.5
    /// Holding the start position this long while ready (or after rest ends) begins the set.
    static let startHoldDuration: TimeInterval = 1.0
    /// The tilt warning is spoken at most this often.
    static let tiltWarningInterval: TimeInterval = 30

    init(exercises: [ExerciseDefinition], initialExercise: ExerciseID?) {
        self.exercises = exercises
        let initial = initialExercise.flatMap { id in exercises.contains { $0.id == id } ? id : nil }
        exerciseID = initial
        phase = initial == nil ? .choosingExercise : .framing
    }

    var exercise: ExerciseDefinition? {
        exerciseID.flatMap { id in exercises.first { $0.id == id } }
    }

    /// Reps both arms have completed in the current set.
    var repCount: Int { min(sideReps[.left] ?? 0, sideReps[.right] ?? 0) }

    func completedSets(for id: ExerciseID) -> Int { progress[id]?.setReps.count ?? 0 }

    /// One-based number of the set in progress or up next.
    var currentSetNumber: Int {
        guard let exercise else { return 1 }
        return min(completedSets(for: exercise.id) + 1, exercise.sets)
    }

    /// 0...1 while the start position is being held toward an automatic start; nil when no hold is
    /// being timed. Counts only from entering ready, or from the end of rest.
    func startHoldProgress(at now: TimeInterval) -> Double? {
        let phaseStart: TimeInterval
        switch phase {
        case .ready:
            guard let readySince else { return nil }
            phaseStart = readySince
        case .resting:
            guard let restEndsAt, now >= restEndsAt else { return nil }
            phaseStart = restEndsAt
        default:
            return nil
        }
        guard framing.isReliable, let held = startPositionSince else { return nil }
        return max(0, min(1, (now - max(held, phaseStart)) / Self.startHoldDuration))
    }

    func restRemaining(at now: TimeInterval) -> TimeInterval? {
        guard phase == .resting, let restEndsAt else { return nil }
        return max(0, restEndsAt - now)
    }

    mutating func handle(_ event: WorkoutEvent, at now: TimeInterval) -> [WorkoutEffect] {
        guard phase != .ended else { return [] }
        switch event {
        case .opened:
            return open()
        case .command(let command):
            return handle(command, at: now)
        case .framingChanged(let status):
            return framingChanged(status, at: now)
        case .repCompleted(let rep):
            return repCompleted(rep, at: now)
        case .startPositionChanged(let held):
            startPositionSince = held ? (startPositionSince ?? now) : nil
            return []
        case .phoneTiltChanged(let tilted):
            // Advisory only: counting continues, and the warning never blocks a set.
            guard tilted, lastTiltWarningAt.map({ now - $0 >= Self.tiltWarningInterval }) ?? true else { return [] }
            lastTiltWarningAt = now
            return [.speak(Utterance(text: "Your phone is tilted. Stand it upright so your reps are measured accurately."))]
        case .tick:
            return tick(at: now)
        case .appBackgrounded:
            return pauseForSystem(.background)
        case .interruptionBegan:
            return pauseForSystem(.interruption)
        case .appForegrounded, .interruptionEnded:
            if case .paused(let reason) = phase, reason != .user {
                return [.speak(Utterance(text: "Paused. \(prompt("resume")) when ready."))]
            }
            return []
        case .voiceControlChanged(let active):
            voiceControlActive = active
            return []
        }
    }

    // MARK: - Commands

    private mutating func handle(_ command: WorkoutCommand, at now: TimeInterval) -> [WorkoutEffect] {
        switch command {
        case .start:
            switch phase {
            case .framing, .ready, .resting: return beginSet(at: now)
            case .paused: return resumeSet(at: now)
            case .exercising: return hint("Already counting.")
            case .choosingExercise, .changingExercise: return hint(exerciseChoicePrompt)
            case .exerciseComplete: return hint(completePrompt)
            case .ended: return []
            }
        case .pause:
            switch phase {
            case .exercising:
                phase = .paused(.user)
                return setCounting(false) + [.speak(Utterance(text: "Paused. \(prompt("resume")) when ready.", interrupts: true))]
            case .paused: return hint("Already paused.")
            case .resting: return hint("You're resting. \(prompt("start")) for the next set.")
            case .framing, .ready: return hint("The set hasn't started. \(prompt("start")) to begin.")
            case .choosingExercise, .changingExercise: return hint(exerciseChoicePrompt)
            case .exerciseComplete: return hint(completePrompt)
            case .ended: return []
            }
        case .resume:
            switch phase {
            case .paused: return resumeSet(at: now)
            case .changingExercise(let previous): return returnFromChange(to: previous, at: now)
            case .exercising: return []
            case .framing, .ready, .resting: return hint("\(prompt("start")) to begin the set.")
            case .choosingExercise: return hint(exerciseChoicePrompt)
            case .exerciseComplete: return hint(completePrompt)
            case .ended: return []
            }
        case .restartSet:
            switch phase {
            case .exercising, .paused:
                sideReps = [.left: 0, .right: 0]
                return newAnalyzer() + [.clearFeedback, .speak(Utterance(text: "Set restarted. Counting from zero."))]
            default:
                return hint("No set is in progress.")
            }
        case .nextSet:
            switch phase {
            case .exercising, .paused: return completeSet(at: now)
            case .resting: return beginSet(at: now)
            case .framing, .ready: return hint("\(prompt("start")) to begin the set.")
            case .choosingExercise, .changingExercise: return hint(exerciseChoicePrompt)
            case .exerciseComplete: return hint(completePrompt)
            case .ended: return []
            }
        case .changeExercise:
            guard exercises.count > 1 else {
                return hint("\(exercise?.displayName ?? "This") is the only exercise for now.")
            }
            switch phase {
            case .choosingExercise, .changingExercise:
                return hint(exerciseChoicePrompt)
            case .ended:
                return []
            default:
                let wasCounting = isCounting
                phase = .changingExercise(previous: phase)
                return (wasCounting ? setCounting(false) : []) + [.speak(Utterance(text: exerciseChoicePrompt))]
            }
        case .selectExercise(let id):
            guard exercises.contains(where: { $0.id == id }) else { return hint(exerciseChoicePrompt) }
            if id == exerciseID {
                if case .changingExercise(let previous) = phase { return returnFromChange(to: previous, at: now) }
                return hint("You're already on \(exercise?.spokenName ?? "this exercise").")
            }
            return switchExercise(to: id)
        case .cancel:
            if case .changingExercise(let previous) = phase { return returnFromChange(to: previous, at: now) }
            return []
        case .repCount:
            return [.speak(Utterance(text: repCountReply, isInstruction: false))]
        case .whichSet:
            return [.speak(Utterance(text: setReply, isInstruction: false))]
        case .repeatLast:
            return [.repeatLastInstruction]
        case .help:
            return [.speak(Utterance(text: helpText, isInstruction: false))]
        case .closeHelp, .muteCoach:
            return []
        case .unmuteCoach:
            return [.speak(Utterance(text: "Coach voice on.", isInstruction: false))]
        case .muteMicrophone:
            return [.speak(Utterance(text: "Microphone off. Tap the microphone to turn it back on.", isInstruction: false))]
        case .endWorkout:
            return endWorkout()
        }
    }

    // MARK: - Transitions

    private mutating func open() -> [WorkoutEffect] {
        guard let exercise else {
            phase = .choosingExercise
            return [.speak(Utterance(text: "Workout coach ready. \(exerciseChoicePrompt)"))]
        }
        phase = .framing
        return newAnalyzer() + [.speak(Utterance(text: "Workout coach ready. \(exercise.setupLine)"))]
    }

    private mutating func beginSet(at now: TimeInterval) -> [WorkoutEffect] {
        guard let exercise else { return hint(exerciseChoicePrompt) }
        phase = .exercising
        restEndsAt = nil
        sideReps = [.left: 0, .right: 0]
        trackingLostAt = framing.isReliable ? nil : now
        trackingLossAnnounced = false
        let line = "Set \(currentSetNumber) of \(exercise.sets). Go."
        return newAnalyzer() + [.clearFeedback] + setCounting(framing.isReliable) + [.speak(Utterance(text: line))]
    }

    private mutating func resumeSet(at now: TimeInterval) -> [WorkoutEffect] {
        phase = .exercising
        trackingLostAt = framing.isReliable ? nil : now
        trackingLossAnnounced = false
        let reps = repCount
        let line = reps == 0 ? "Resuming." : "Resuming at \(reps)."
        return setCounting(framing.isReliable) + [.speak(Utterance(text: line, interrupts: true))]
    }

    private mutating func completeSet(at now: TimeInterval) -> [WorkoutEffect] {
        guard let exercise else { return [] }
        let reps = repCount
        progress[exercise.id, default: ExerciseProgress()].setReps.append(reps)
        sideReps = [.left: 0, .right: 0]
        let finished = completedSets(for: exercise.id)
        var effects = setCounting(false) + newAnalyzer() + [.clearFeedback]
        if finished >= exercise.sets {
            phase = .exerciseComplete
            restEndsAt = nil
            effects.append(.speak(Utterance(text: "Set \(finished) done, \(repPhrase(reps)). \(exercise.displayName) complete. \(completePrompt)")))
        } else {
            phase = .resting
            restEndsAt = now + TimeInterval(exercise.restSeconds)
            restDoneAnnounced = false
            effects.append(.speak(Utterance(text: "Set \(finished) done, \(repPhrase(reps)). Rest up. I'll tell you when it's time for set \(finished + 1).")))
        }
        return effects
    }

    private mutating func switchExercise(to id: ExerciseID) -> [WorkoutEffect] {
        guard let next = exercises.first(where: { $0.id == id }) else { return [] }
        // An in-progress set is discarded; finished sets stay with their exercise.
        sideReps = [.left: 0, .right: 0]
        exerciseID = id
        restEndsAt = nil
        framing = .lost
        guidanceChangedAt = nil
        lastSpokenGuidance = nil
        var effects = setCounting(false) + newAnalyzer() + [.clearFeedback]
        if completedSets(for: id) >= next.sets {
            phase = .exerciseComplete
            effects.append(.speak(Utterance(text: "\(next.displayName) is already done. \(completePrompt)")))
        } else {
            phase = .framing
            effects.append(.speak(Utterance(text: next.setupLine)))
        }
        return effects
    }

    private mutating func returnFromChange(to previous: WorkoutPhase, at now: TimeInterval) -> [WorkoutEffect] {
        phase = previous
        switch previous {
        case .exercising:
            trackingLostAt = framing.isReliable ? nil : now
            trackingLossAnnounced = false
            return setCounting(framing.isReliable) + [.speak(Utterance(text: "Back to \(exercise?.spokenName ?? "your set")."))]
        default:
            return [.speak(Utterance(text: "Okay, staying on \(exercise?.spokenName ?? "this exercise")."))]
        }
    }

    private mutating func pauseForSystem(_ reason: PauseReason) -> [WorkoutEffect] {
        switch phase {
        case .exercising:
            phase = .paused(reason)
            return setCounting(false)
        case .changingExercise(previous: .exercising):
            phase = .changingExercise(previous: .paused(reason))
            return setCounting(false)
        default:
            return []
        }
    }

    private mutating func endWorkout() -> [WorkoutEffect] {
        if let exercise, phase == .exercising || isPaused, repCount > 0 {
            progress[exercise.id, default: ExerciseProgress()].setReps.append(repCount)
        }
        sideReps = [.left: 0, .right: 0]
        phase = .ended
        restEndsAt = nil
        return setCounting(false) + [.clearFeedback,
            .speak(Utterance(text: "Workout ended. Nice work.", interrupts: true)),
            .stopCaptureAndVoice]
    }

    // MARK: - Tracking, reps, and time

    private mutating func framingChanged(_ status: FramingStatus, at now: TimeInterval) -> [WorkoutEffect] {
        let previous = framing
        framing = status
        if status.guidance != previous.guidance { guidanceChangedAt = now }
        switch phase {
        case .framing where status.isReliable && status.guidance == nil:
            phase = .ready
            readySince = now
            lastSpokenGuidance = nil
            // Framing near a threshold can flicker; announce readiness once per interval.
            if let last = lastReadyAnnouncedAt, now - last < Self.guidanceRepeatInterval { return [] }
            lastReadyAnnouncedAt = now
            return [.speak(Utterance(text: "Looks good. \(startPrompt) to start, or \(prompt("start").lowercased())."))]
        case .ready where !status.isReliable || status.guidance != nil:
            phase = .framing
            return []
        case .exercising where status.isReliable != previous.isReliable:
            if status.isReliable {
                trackingLostAt = nil
                trackingLossAnnounced = false
            } else {
                trackingLostAt = now
            }
            return setCounting(status.isReliable)
        default:
            return []
        }
    }

    private mutating func repCompleted(_ rep: RepEvent, at now: TimeInterval) -> [WorkoutEffect] {
        guard rep.epoch == analyzerEpoch, phase == .exercising, isCounting, let exercise else { return [] }
        let before = repCount
        for side in rep.sides { sideReps[side, default: 0] += 1 }
        let after = repCount
        guard after > before else { return [] }
        if after >= exercise.autoCompleteReps { return completeSet(at: now) }
        if let announce = exercise.targetRangeAnnouncementReps, before < announce, after >= announce {
            return [.speak(Utterance(text: "\(after). You're in the target range.", isInstruction: false))]
        }
        return []
    }

    private mutating func tick(at now: TimeInterval) -> [WorkoutEffect] {
        switch phase {
        case .framing:
            guard let guidance = framing.guidance, let changedAt = guidanceChangedAt,
                  now - changedAt >= Self.guidanceSettleTime else { return [] }
            let repeatDue = lastGuidanceSpokenAt.map { now - $0 >= Self.guidanceRepeatInterval } ?? true
            guard guidance != lastSpokenGuidance || repeatDue else { return [] }
            lastSpokenGuidance = guidance
            lastGuidanceSpokenAt = now
            return [.speak(Utterance(text: guidance.spokenText))]
        case .ready:
            guard startHoldProgress(at: now) == 1 else { return [] }
            return beginSet(at: now)
        case .exercising:
            guard !framing.isReliable, !trackingLossAnnounced, let lostAt = trackingLostAt,
                  now - lostAt >= Self.trackingLossGrace else { return [] }
            trackingLossAnnounced = true
            let guidance = framing.guidance?.spokenText ?? FramingGuidance.stepIntoView.spokenText
            return [.speak(Utterance(text: "I can't see you. \(guidance)"))]
        case .resting:
            guard let restEndsAt, now >= restEndsAt else { return [] }
            if startHoldProgress(at: now) == 1 { return beginSet(at: now) }
            guard !restDoneAnnounced else { return [] }
            restDoneAnnounced = true
            return [.speak(Utterance(text: "Rest is up. \(startPrompt) or \(prompt("start").lowercased()) for set \(currentSetNumber)."))]
        default:
            return []
        }
    }

    // MARK: - Helpers

    private var startPrompt: String {
        exercise?.guide.startPositionInstruction ?? "Get into the start position"
    }

    private var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    private mutating func newAnalyzer() -> [WorkoutEffect] {
        analyzerEpoch += 1
        return [.resetAnalyzer(epoch: analyzerEpoch)]
    }

    private mutating func setCounting(_ counting: Bool) -> [WorkoutEffect] {
        guard counting != isCounting else { return [] }
        isCounting = counting
        return [.setCounting(counting)]
    }

    private func hint(_ text: String) -> [WorkoutEffect] {
        [.speak(Utterance(text: text, isInstruction: false))]
    }

    /// "Say start" with voice control, "Tap Start" without.
    func prompt(_ action: String) -> String {
        voiceControlActive ? "Say \(action)" : "Tap \(action.capitalized)"
    }

    private func repPhrase(_ reps: Int) -> String {
        reps == 1 ? "1 rep" : "\(reps) reps"
    }

    private var exerciseChoicePrompt: String {
        let names = exercises.map(\.spokenName)
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " or " + (names.last ?? "") : names.first ?? ""
        return voiceControlActive ? "Say \(list)." : "Choose \(list) from the exercise menu."
    }

    private var completePrompt: String {
        let remaining = exercises.filter { completedSets(for: $0.id) < $0.sets }
        guard !remaining.isEmpty else { return voiceControlActive ? "Say end workout to finish." : "Tap End to finish." }
        let names = remaining.map(\.spokenName).joined(separator: " or ")
        return voiceControlActive
            ? "Say \(names), or end workout."
            : "Choose \(names) from the exercise menu, or tap End."
    }

    private var repCountReply: String {
        guard let exercise else { return "No exercise selected yet." }
        switch phase {
        case .resting, .exerciseComplete:
            let last = progress[exercise.id]?.setReps.last ?? 0
            return "Your last set was \(repPhrase(last))."
        default:
            var reply = "\(repPhrase(repCount))."
            let left = sideReps[.left] ?? 0
            let right = sideReps[.right] ?? 0
            if exercise.countsArmsIndependently, left != right {
                reply += " Left \(left), right \(right)."
            }
            return reply
        }
    }

    private var setReply: String {
        guard let exercise else { return "No exercise selected yet." }
        let finished = completedSets(for: exercise.id)
        switch phase {
        case .resting:
            return "Set \(finished) of \(exercise.sets) done. Set \(finished + 1) is next."
        case .exerciseComplete:
            return "All \(exercise.sets) sets of \(exercise.spokenName) are done."
        default:
            return "Set \(currentSetNumber) of \(exercise.sets)."
        }
    }

    /// The full list is on screen, so the spoken version stays short.
    private var helpText: String {
        "Here's everything you can say. Try start, pause, or how many reps. Say close when you're done."
    }

    /// A few commands that make sense right now, for the top of the Voice Commands help.
    var suggestedCommands: [WorkoutCommand] {
        switch phase {
        case .choosingExercise, .changingExercise:
            return exercises.map { .selectExercise($0.id) } + (phase == .choosingExercise ? [] : [.cancel])
        case .framing, .ready: return [.start, .repeatLast]
        case .exercising: return [.pause, .repCount, .nextSet, .restartSet]
        case .paused: return [.resume, .restartSet, .nextSet]
        case .resting: return [.start, .whichSet]
        case .exerciseComplete: return exercises.count > 1 ? [.changeExercise, .endWorkout] : [.endWorkout]
        case .ended: return []
        }
    }
}
