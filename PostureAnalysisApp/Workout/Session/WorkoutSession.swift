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
    /// After the last set, does the exercise (or the whole Saved Set) again from the start.
    case anotherRound
    /// In a Saved Set, skips the rest of this exercise and moves to the next one.
    case nextExercise
    /// Records the weight for this set and later sets of this exercise, until changed.
    case setWeight(WorkoutWeight)
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
    /// Form output from the analyzer, on every frame while counting.
    case formObserved(FormObservation)
    /// Corrective cues wait for the coach to finish speaking, so a tip and its spoken line match.
    case coachSpeakingChanged(Bool)
    /// A camera frame was analyzed, at its capture moment. A start hold counts only up to the latest one, so a
    /// stall can't complete it on stale pose evidence.
    case poseObserved
}

enum WorkoutEffect: Equatable {
    case speak(Utterance)
    case repeatLastInstruction
    /// Replace the analyzer; reps from older epochs are ignored.
    case resetAnalyzer(epoch: Int)
    case setCounting(Bool)
    case clearFeedback
    case stopCaptureAndVoice
    /// Show a coaching tip; corrective tips are also spoken through `.speak`.
    case showTip(CoachingTip)
}

struct ExerciseProgress: Equatable {
    /// Reps recorded for each finished set, in order, across every round.
    var setReps: [Int] = []
    /// The weight in use for each finished set, parallel to `setReps`.
    var setWeights: [WorkoutWeight?] = []
    /// Index in `setReps` where the current round began.
    var roundStart = 0
    /// One-based round number.
    var round = 1

    /// Reps for each finished set of the current round.
    var roundSetReps: [Int] { Array(setReps.dropFirst(roundStart)) }
    var roundSetWeights: [WorkoutWeight?] { Array(setWeights.dropFirst(roundStart)) }

    /// Records a finished set and the weight in use for it.
    mutating func record(reps: Int, weight: WorkoutWeight?) {
        // Older records may predate weights; keep the arrays aligned.
        while setWeights.count < setReps.count { setWeights.append(nil) }
        setReps.append(reps)
        setWeights.append(weight)
    }
}

/// A workout-scoped snapshot of settings that affect reducer decisions or voice parsing.
struct WorkoutSettings: Equatable {
    let restPolicy: RestPolicy
    let weightUnit: PreferredWeightUnit
    let startByHolding: Bool

    init(restPolicy: RestPolicy = .exerciseDefault,
         weightUnit: PreferredWeightUnit = .lb,
         startByHolding: Bool = true) {
        self.restPolicy = restPolicy
        self.weightUnit = weightUnit
        self.startByHolding = startByHolding
    }

    func restSeconds(for exercise: ExerciseDefinition) -> Int {
        switch restPolicy {
        case .exerciseDefault:
            return exercise.restSeconds
        case .fixed(let seconds):
            return min(max(seconds, 30), 120)
        }
    }
}

/// Pure workout state machine. Every input is an event with a time; every side effect is returned.
struct WorkoutSession {
    let exercises: [ExerciseDefinition]
    let settings: WorkoutSettings
    private(set) var phase: WorkoutPhase
    private(set) var exerciseID: ExerciseID?
    private(set) var progress: [ExerciseID: ExerciseProgress] = [:]
    private(set) var sideReps: [BodySide: Int] = [.left: 0, .right: 0]
    private(set) var framing = FramingStatus.lost
    private(set) var isCounting = false
    /// Time of the most recent rep that increased the displayed rep count.
    private(set) var lastRepAt: TimeInterval?
    /// Monotonic event key for visible rep-count changes, including when the count later resets.
    private(set) var repEventCount = 0
    private(set) var analyzerEpoch = 0
    private(set) var restEndsAt: TimeInterval?
    /// Full effective duration for the current rest, used by the HUD progress bar.
    private(set) var restDurationSeconds: Int?
    private(set) var voiceControlActive = false
    /// The workout was ended from the completion card, which already showed the results.
    private(set) var endedAfterCompletion = false
    /// The weight in use for each exercise; it carries to later sets until changed.
    private(set) var currentWeights: [ExerciseID: WorkoutWeight] = [:]
    /// Exercises run in order, such as a Saved Set; nil for a single exercise.
    let plan: WorkoutPlan?
    private(set) var planIndex = 0
    /// What happened to each plan occurrence, by item id.
    private(set) var planRecords: [UUID: PlanItemRecord] = [:]
    /// False once the user leaves the plan for another exercise.
    private(set) var isFollowingPlan = false
    /// Resting between plan exercises; the next exercise is already selected.
    private(set) var isRestingBeforeNextExercise = false
    /// When a timed hold in progress ends; nil while no hold is running.
    private(set) var holdEndsAt: TimeInterval?
    /// What was left of a timed hold when it was paused or the exercise menu opened.
    private var holdRemainingWhenStopped: TimeInterval?
    private var holdCountdownAnnounced = false

    private var guidanceChangedAt: TimeInterval?
    private var lastSpokenGuidance: FramingGuidance?
    private var lastGuidanceSpokenAt: TimeInterval?
    private var trackingLostAt: TimeInterval?
    private var trackingLossAnnounced = false
    private var restDoneAnnounced = false
    private var lastReadyAnnouncedAt: TimeInterval?
    private var startPositionSince: TimeInterval?
    private var lastPoseObservedAt: TimeInterval?
    private var readySince: TimeInterval?
    private var lastTiltWarningAt: TimeInterval?
    private var restLeadsToNextExercise = false
    private var coaching: CoachingCueScheduler
    private var isCoachSpeaking = false
    private var lastTipID = 0

    /// Guidance must hold this long before it is spoken.
    static let guidanceSettleTime: TimeInterval = 1.0
    /// The same guidance, or the ready prompt, is repeated no more often than this.
    static let guidanceRepeatInterval: TimeInterval = 20
    /// Tracking must stay lost this long mid-set before guidance is spoken.
    static let trackingLossGrace: TimeInterval = 0.5
    /// Holding the start position this long while ready (or after rest ends) begins the set.
    static let startHoldDuration: TimeInterval = 1.0
    /// A timed hold says how long is left once, at this many seconds, when the hold is at least twice as long.
    static let holdCountdownSeconds: TimeInterval = 5
    /// The tilt warning is spoken at most this often.
    static let tiltWarningInterval: TimeInterval = 30

    init(exercises: [ExerciseDefinition], initialExercise: ExerciseID?, plan: WorkoutPlan? = nil,
         settings: WorkoutSettings = WorkoutSettings()) {
        self.exercises = exercises
        self.settings = settings
        // Occurrences whose exercise isn't available are skipped.
        let usable = plan.flatMap { plan in plan.items.firstIndex { item in exercises.contains { $0.id == item.exerciseID } } }
        self.plan = usable == nil ? nil : plan
        planIndex = usable ?? 0
        isFollowingPlan = usable != nil
        let requested = usable.flatMap { plan?.items[$0].exerciseID } ?? initialExercise
        let initial = requested.flatMap { id in exercises.contains { $0.id == id } ? id : nil }
        exerciseID = initial
        phase = initial == nil ? .choosingExercise : .framing
        coaching = CoachingCueScheduler(cues: [], reminders: [])
        coaching = Self.scheduler(for: exercise)
    }

    /// The selected exercise, with the plan occurrence's sets and reps when following a plan.
    var exercise: ExerciseDefinition? {
        guard let id = exerciseID, let base = exercises.first(where: { $0.id == id }) else { return nil }
        if let item = currentPlanItem, item.exerciseID == id { return base.withTarget(sets: item.sets, reps: item.targetReps) }
        return base
    }

    /// The exercise's hold-to-start choice combined with the workout-wide preference.
    var effectiveStartsByHolding: Bool {
        settings.startByHolding && (exercise?.startsByHolding ?? true) && !(exercise?.isSelfReported ?? false)
    }

    /// Camera-counted exercises wait for framing; self-reported ones go straight to Ready.
    private var needsFraming: Bool { !(exercise?.isSelfReported ?? false) }

    private var isTimed: Bool { exercise?.doseUnit == .seconds }

    /// Seconds left in the timed hold in progress or paused; nil when no hold is under way.
    func holdRemaining(at now: TimeInterval) -> TimeInterval? {
        switch phase {
        case .exercising:
            return holdEndsAt.map { max(0, $0 - now) }
        case .paused, .changingExercise:
            return holdRemainingWhenStopped
        default:
            return nil
        }
    }

    /// Effective rest for the selected exercise, before a rest has started.
    var effectiveRestSeconds: Int? {
        exercise.map { settings.restSeconds(for: $0) }
    }

    /// The plan occurrence in progress or up next.
    var currentPlanItem: WorkoutPlanItem? {
        guard isFollowingPlan, let plan, plan.items.indices.contains(planIndex) else { return nil }
        return plan.items[planIndex]
    }

    /// "Exercise 2 of 5" while following a plan.
    var planPositionLabel: String? {
        guard let plan, isFollowingPlan else { return nil }
        return "Exercise \(planIndex + 1) of \(plan.items.count)"
    }

    /// Reps both sides have completed in the current set.
    var repCount: Int { min(sideReps[.left] ?? 0, sideReps[.right] ?? 0) }

    /// Finished set entries in the current round (one per side for per-side exercises).
    func completedSets(for id: ExerciseID) -> Int { progress[id]?.roundSetReps.count ?? 0 }

    /// Whole sets finished in the current round; a per-side set counts once both sides are done.
    func setsDone(for exercise: ExerciseDefinition) -> Int {
        let entries = completedSets(for: exercise.id)
        return exercise.perSide ? entries / 2 : entries
    }

    /// One-based number of the set in progress or up next.
    var currentSetNumber: Int {
        guard let exercise else { return 1 }
        return min(setsDone(for: exercise) + 1, exercise.sets)
    }

    /// The side in progress or up next, for exercises done one side at a time.
    var currentSide: BodySide? {
        guard let exercise, exercise.perSide else { return nil }
        return completedSets(for: exercise.id) % 2 == 0 ? .left : .right
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
        guard effectiveStartsByHolding, framing.isReliable, let held = startPositionSince else { return nil }
        // Holding is only known up to the latest analyzed frame. Without frames (reducer tests), the clock decides.
        let observed = lastPoseObservedAt.map { min(now, $0) } ?? now
        return max(0, min(1, (observed - max(held, phaseStart)) / Self.startHoldDuration))
    }

    func restRemaining(at now: TimeInterval) -> TimeInterval? {
        guard phase == .resting, let restEndsAt else { return nil }
        return max(0, restEndsAt - now)
    }

    mutating func handle(_ event: WorkoutEvent, at now: TimeInterval) -> [WorkoutEffect] {
        guard phase != .ended else { return [] }
        switch event {
        case .opened:
            return open(at: now)
        case .command(let command):
            return handle(command, at: now)
        case .framingChanged(let status):
            return framingChanged(status, at: now)
        case .repCompleted(let rep):
            return repCompleted(rep, at: now)
        case .startPositionChanged(let held):
            startPositionSince = held && effectiveStartsByHolding ? (startPositionSince ?? now) : nil
            return []
        case .phoneTiltChanged(let tilted):
            // Advisory only: counting continues, and the warning never blocks a set.
            guard tilted, lastTiltWarningAt.map({ now - $0 >= Self.tiltWarningInterval }) ?? true else { return [] }
            lastTiltWarningAt = now
            return [.speak(Utterance(text: "Your phone is tilted. Stand it upright so your reps are measured accurately."))]
        case .tick:
            return tick(at: now)
        case .appBackgrounded:
            return pauseForSystem(.background, at: now)
        case .interruptionBegan:
            return pauseForSystem(.interruption, at: now)
        case .appForegrounded, .interruptionEnded:
            if case .paused(let reason) = phase, reason != .user {
                return [.speak(Utterance(text: "Paused. \(prompt("resume")) when ready."))]
            }
            return []
        case .voiceControlChanged(let active):
            voiceControlActive = active
            return []
        case .formObserved(let observation):
            guard observation.epoch == analyzerEpoch, phase == .exercising, isCounting else { return [] }
            return tipEffects(coaching.update(observation, speaking: isCoachSpeaking, at: now))
        case .coachSpeakingChanged(let speaking):
            isCoachSpeaking = speaking
            return []
        case .poseObserved:
            lastPoseObservedAt = max(lastPoseObservedAt ?? now, now)
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
            case .exercising: return hint(needsFraming ? "Already counting." : "Already going.")
            case .choosingExercise, .changingExercise: return hint(exerciseChoicePrompt)
            case .exerciseComplete: return hint(completePrompt)
            case .ended: return []
            }
        case .pause:
            switch phase {
            case .exercising:
                phase = .paused(.user)
                suspendHold(at: now)
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
                if isTimed, let seconds = exercise?.autoCompleteReps {
                    holdCountdownAnnounced = false
                    if phase == .exercising { holdEndsAt = now + TimeInterval(seconds) } else { holdRemainingWhenStopped = TimeInterval(seconds) }
                    return newAnalyzer() + clearFeedback() + [.speak(Utterance(text: "Hold restarted."))]
                }
                let line = needsFraming ? "Set restarted. Counting from zero." : "Set restarted."
                return newAnalyzer() + clearFeedback() + [.speak(Utterance(text: line))]
            default:
                return hint("No set is in progress.")
            }
        case .nextSet:
            switch phase {
            case .exercising, .paused: return completeSet(at: now, amount: currentSetAmount(at: now))
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
                if phase == .exercising { suspendHold(at: now) }
                phase = .changingExercise(previous: phase)
                return (wasCounting ? setCounting(false) : []) + [.speak(Utterance(text: exerciseChoicePrompt))]
            }
        case .selectExercise(let id):
            guard exercises.contains(where: { $0.id == id }) else { return hint(exerciseChoicePrompt) }
            if id == exerciseID {
                if case .changingExercise(let previous) = phase { return returnFromChange(to: previous, at: now) }
                return hint("You're already on \(exercise?.spokenName ?? "this exercise").")
            }
            if let plan, isFollowingPlan {
                // Leaving a Saved Set skips the rest of it, so it only happens from the chooser, which says so.
                guard case .changingExercise = phase else {
                    return hint("You're in \(plan.name). \(prompt("next exercise")) to skip ahead, or \(prompt("change exercise").lowercased()) to leave it.")
                }
                leavePlan()
            }
            return switchExercise(to: id, at: now)
        case .cancel:
            if case .changingExercise(let previous) = phase { return returnFromChange(to: previous, at: now) }
            return []
        case .anotherRound:
            guard phase == .exerciseComplete else { return hint("Another round is available after the last set.") }
            if plan != nil, isFollowingPlan { return restartPlan(at: now) }
            return startAnotherRound(at: now)
        case .nextExercise:
            return skipToNextExercise(at: now)
        case .setWeight(let weight):
            guard let exercise else { return hint("Choose an exercise first.") }
            guard exercise.equipment != .bodyweight else { return hint("\(exercise.displayName) doesn't use weights.") }
            currentWeights[exercise.id] = weight
            return [.speak(Utterance(text: "\(weight.spokenLabel).", isInstruction: false))]
        case .repCount:
            return [.speak(Utterance(text: repCountReply(at: now), isInstruction: false))]
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
            return endWorkout(at: now)
        }
    }

    // MARK: - Transitions

    private mutating func open(at now: TimeInterval) -> [WorkoutEffect] {
        guard let exercise else {
            phase = .choosingExercise
            return [.speak(Utterance(text: "Workout coach ready. \(exerciseChoicePrompt)"))]
        }
        enterSetup(at: now)
        let begin = needsFraming ? "" : " \(beginPrompt)."
        return newAnalyzer() + [.speak(Utterance(text: "Workout coach ready. \(exercise.setupLine)\(begin)"))]
    }

    /// Framing for camera-counted exercises (straight to Ready when framing is already good); Ready for
    /// self-reported ones, which never wait for the camera.
    private mutating func enterSetup(at now: TimeInterval) {
        if !needsFraming || (framing.isReliable && framing.guidance == nil) {
            phase = .ready
            readySince = now
        } else {
            phase = .framing
        }
    }

    /// What the set in progress has done: the tracked count, the prescribed reps for a self-reported set the user
    /// says is done, or the seconds held so far.
    private func currentSetAmount(at now: TimeInterval) -> Int {
        guard let exercise else { return repCount }
        if exercise.doseUnit == .seconds {
            let remaining = holdRemaining(at: now) ?? TimeInterval(exercise.autoCompleteReps)
            return max(0, exercise.autoCompleteReps - Int(remaining.rounded(.up)))
        }
        return exercise.isSelfReported ? exercise.autoCompleteReps : repCount
    }

    private mutating func suspendHold(at now: TimeInterval) {
        guard let holdEndsAt else { return }
        holdRemainingWhenStopped = max(0, holdEndsAt - now)
        self.holdEndsAt = nil
    }

    private mutating func resumeHold(at now: TimeInterval) {
        guard let remaining = holdRemainingWhenStopped else { return }
        holdEndsAt = now + remaining
        holdRemainingWhenStopped = nil
    }

    private mutating func clearHold() {
        holdEndsAt = nil
        holdRemainingWhenStopped = nil
        holdCountdownAnnounced = false
    }

    /// "Tap Done" or "Say next set": a self-reported set ends when the user says so.
    private var donePrompt: String {
        voiceControlActive ? "Say next set" : "Tap Done"
    }

    private mutating func beginSet(at now: TimeInterval) -> [WorkoutEffect] {
        guard let exercise else { return hint(exerciseChoicePrompt) }
        phase = .exercising
        restEndsAt = nil
        restDurationSeconds = nil
        sideReps = [.left: 0, .right: 0]
        trackingLostAt = framing.isReliable ? nil : now
        trackingLossAnnounced = false
        restLeadsToNextExercise = false
        isRestingBeforeNextExercise = false
        clearHold()
        let line: String
        if exercise.doseUnit == .seconds {
            holdEndsAt = now + TimeInterval(exercise.autoCompleteReps)
            line = "Set \(currentSetNumber) of \(exercise.sets). Hold for \(exercise.amountPhrase(exercise.autoCompleteReps)). Go."
        } else if exercise.isSelfReported {
            line = "Set \(currentSetNumber) of \(exercise.sets): \(exercise.amountPhrase(exercise.autoCompleteReps)). \(donePrompt) when you've finished."
        } else {
            line = "Set \(currentSetNumber) of \(exercise.sets). Go."
        }
        let effects = newAnalyzer() + clearFeedback() + setCounting(needsFraming && framing.isReliable)
            + [.speak(Utterance(text: line))]
        return effects + tipEffects(coaching.beginSet(at: now))
    }

    private mutating func resumeSet(at now: TimeInterval) -> [WorkoutEffect] {
        phase = .exercising
        trackingLostAt = framing.isReliable ? nil : now
        trackingLossAnnounced = false
        resumeHold(at: now)
        let line: String
        if let exercise, exercise.doseUnit == .seconds, let remaining = holdRemaining(at: now) {
            line = "Resuming. \(exercise.amountPhrase(Int(remaining.rounded(.up)))) left."
        } else {
            let reps = repCount
            line = reps == 0 || !needsFraming ? "Resuming." : "Resuming at \(reps)."
        }
        return setCounting(needsFraming && framing.isReliable) + [.speak(Utterance(text: line, interrupts: true))]
    }

    /// Records the set's `amount` (reps, or seconds for a timed hold) and moves on.
    private mutating func completeSet(at now: TimeInterval, amount: Int) -> [WorkoutEffect] {
        guard let exercise else { return [] }
        let reps = amount
        progress[exercise.id, default: ExerciseProgress()].record(reps: reps, weight: currentWeights[exercise.id])
        sideReps = [.left: 0, .right: 0]
        clearHold()
        let finished = completedSets(for: exercise.id)
        var effects = setCounting(false) + newAnalyzer() + clearFeedback()
        let completedSide: BodySide = finished % 2 == 1 ? .left : .right
        let done = exercise.perSide ? "\(exercise.sideLabel(completedSide)) done" : "Set \(finished) done"
        if finished >= exercise.setEntries, let item = currentPlanItem, let plan {
            planRecords[item.id] = PlanItemRecord(outcome: .completed, setReps: progress[exercise.id]?.roundSetReps ?? [],
                                                  setWeights: progress[exercise.id]?.roundSetWeights ?? [])
            let lead = "\(done), \(exercise.amountPhrase(reps)). \(exercise.displayName) complete."
            if let next = nextPlanIndex(after: planIndex) {
                return effects + advancePlan(to: next, at: now,
                                             restSeconds: settings.restSeconds(for: exercise), lead: lead)
            }
            phase = .exerciseComplete
            restEndsAt = nil
            restDurationSeconds = nil
            effects.append(.speak(Utterance(text: "\(lead) \(plan.name) complete. \(completePrompt)")))
        } else if finished >= exercise.setEntries {
            phase = .exerciseComplete
            restEndsAt = nil
            restDurationSeconds = nil
            effects.append(.speak(Utterance(text: "\(done), \(exercise.amountPhrase(reps)). \(exercise.displayName) complete. \(completePrompt)")))
        } else if exercise.perSide, finished % 2 == 1 {
            // Halfway through a per-side set: switch sides without resting.
            restEndsAt = nil
            restDurationSeconds = nil
            enterSetup(at: now)
            let switchPrompt = exercise.sideLimb == .leg
                ? "Switch: step back with your right leg."
                : "Switch to your right arm."
            effects.append(.speak(Utterance(text: "\(done), \(exercise.amountPhrase(reps)). \(switchPrompt) \(beginPrompt).")))
        } else if exercise.perSide {
            let set = finished / 2
            phase = .resting
            let restSeconds = settings.restSeconds(for: exercise)
            restDurationSeconds = restSeconds
            restEndsAt = now + TimeInterval(restSeconds)
            restDoneAnnounced = false
            effects.append(.speak(Utterance(text: "\(done), \(exercise.amountPhrase(reps)). Set \(set) done. Rest up. I'll tell you when it's time for set \(set + 1).")))
        } else {
            phase = .resting
            let restSeconds = settings.restSeconds(for: exercise)
            restDurationSeconds = restSeconds
            restEndsAt = now + TimeInterval(restSeconds)
            restDoneAnnounced = false
            effects.append(.speak(Utterance(text: "Set \(finished) done, \(exercise.amountPhrase(reps)). Rest up. I'll tell you when it's time for set \(finished + 1).")))
        }
        return effects
    }

    /// The same exercise again from set 1. Earlier rounds stay in the progress for the summary.
    private mutating func startAnotherRound(at now: TimeInterval) -> [WorkoutEffect] {
        guard let exercise else { return [] }
        var record = progress[exercise.id, default: ExerciseProgress()]
        record.roundStart = record.setReps.count
        record.round += 1
        progress[exercise.id] = record
        restEndsAt = nil
        restDurationSeconds = nil
        clearHold()
        // Framing doesn't change on its own here, so go straight to ready when it's already good.
        enterSetup(at: now)
        let line = "Round \(record.round) of \(exercise.spokenName). \(beginPrompt)."
        return newAnalyzer() + clearFeedback() + [.speak(Utterance(text: line))]
    }

    // MARK: - Plans

    /// The next occurrence whose exercise is available, after `index`.
    private func nextPlanIndex(after index: Int) -> Int? {
        guard let plan else { return nil }
        return plan.items.indices.first { candidate in
            candidate > index && exercises.contains { $0.id == plan.items[candidate].exerciseID }
        }
    }

    /// Selects the plan occurrence at `index`. With `restSeconds`, the rest timer runs first and the next
    /// exercise is announced; without, it goes straight to setup. Counting never starts on its own.
    private mutating func advancePlan(to index: Int, at now: TimeInterval, restSeconds: Int?, lead: String) -> [WorkoutEffect] {
        guard let plan, plan.items.indices.contains(index) else { return [] }
        let item = plan.items[index]
        planIndex = index
        exerciseID = item.exerciseID
        // This occurrence counts its own sets, even when the exercise appeared earlier.
        var record = progress[item.exerciseID, default: ExerciseProgress()]
        record.roundStart = record.setReps.count
        progress[item.exerciseID] = record
        sideReps = [.left: 0, .right: 0]
        clearHold()
        framing = .lost
        guidanceChangedAt = nil
        lastSpokenGuidance = nil
        coaching = Self.scheduler(for: exercise)
        guard let next = exercise else { return [] }
        if let restSeconds {
            phase = .resting
            restEndsAt = now + TimeInterval(restSeconds)
            restDurationSeconds = restSeconds
            restDoneAnnounced = false
            restLeadsToNextExercise = true
            isRestingBeforeNextExercise = true
            let target = "\(next.sets == 1 ? "1 set" : "\(next.sets) sets") of \(next.spokenTarget)"
            return [.speak(Utterance(text: "\(lead) Up next: \(next.spokenName), \(target). Rest up."))]
        }
        enterSetup(at: now)
        restEndsAt = nil
        restDurationSeconds = nil
        restLeadsToNextExercise = false
        isRestingBeforeNextExercise = false
        let begin = needsFraming ? "" : " \(beginPrompt)."
        return [.speak(Utterance(text: "\(lead) \(next.setupLine)\(begin)"))]
    }

    /// Skips the rest of the current occurrence, keeping any finished sets, and moves on.
    private mutating func skipToNextExercise(at now: TimeInterval) -> [WorkoutEffect] {
        guard let plan, isFollowingPlan, let item = currentPlanItem else {
            return hint("Next exercise works during a Saved Set.")
        }
        switch phase {
        case .exerciseComplete, .ended, .choosingExercise:
            return hint(completePrompt)
        default:
            break
        }
        if planRecords[item.id]?.outcome == nil {
            planRecords[item.id] = PlanItemRecord(outcome: .skipped, setReps: progress[item.exerciseID]?.roundSetReps ?? [],
                                                  setWeights: progress[item.exerciseID]?.roundSetWeights ?? [])
        }
        let effects = setCounting(false) + newAnalyzer() + clearFeedback()
        if let next = nextPlanIndex(after: planIndex) {
            let name = exercises.first { $0.id == plan.items[next].exerciseID }?.spokenName ?? "the next exercise"
            return effects + advancePlan(to: next, at: now, restSeconds: nil, lead: "Skipping to \(name).")
        }
        sideReps = [.left: 0, .right: 0]
        phase = .exerciseComplete
        restEndsAt = nil
        restDurationSeconds = nil
        isRestingBeforeNextExercise = false
        return effects + [.speak(Utterance(text: "\(plan.name) complete. \(completePrompt)"))]
    }

    /// The whole Saved Set again from its first exercise; earlier sets stay in the summary.
    private mutating func restartPlan(at now: TimeInterval) -> [WorkoutEffect] {
        guard let plan, let first = plan.items.indices.first(where: { index in exercises.contains { $0.id == plan.items[index].exerciseID } }) else { return [] }
        planRecords = [:]
        let effects = setCounting(false) + newAnalyzer() + clearFeedback()
        return effects + advancePlan(to: first, at: now, restSeconds: nil, lead: "Another round of \(plan.name).")
    }

    /// Choosing a different exercise ends the plan's order; what's left of it is skipped.
    private mutating func leavePlan() {
        guard let plan else { return }
        for item in plan.items[planIndex...] where planRecords[item.id]?.outcome == nil {
            let current = item.id == currentPlanItem?.id
            planRecords[item.id] = PlanItemRecord(outcome: .skipped,
                                                  setReps: current ? (progress[item.exerciseID]?.roundSetReps ?? []) : [],
                                                  setWeights: current ? (progress[item.exerciseID]?.roundSetWeights ?? []) : [])
        }
        isFollowingPlan = false
        isRestingBeforeNextExercise = false
        restLeadsToNextExercise = false
    }

    private mutating func switchExercise(to id: ExerciseID, at now: TimeInterval) -> [WorkoutEffect] {
        guard let next = exercises.first(where: { $0.id == id }) else { return [] }
        // An in-progress set is discarded; finished sets stay with their exercise.
        sideReps = [.left: 0, .right: 0]
        clearHold()
        exerciseID = id
        restEndsAt = nil
        restDurationSeconds = nil
        framing = .lost
        guidanceChangedAt = nil
        lastSpokenGuidance = nil
        var effects = setCounting(false) + newAnalyzer() + clearFeedback()
        coaching = Self.scheduler(for: next)
        if completedSets(for: id) >= next.setEntries {
            phase = .exerciseComplete
            effects.append(.speak(Utterance(text: "\(next.displayName) is already done. \(completePrompt)")))
        } else {
            enterSetup(at: now)
            let begin = needsFraming ? "" : " \(beginPrompt)."
            effects.append(.speak(Utterance(text: "\(next.setupLine)\(begin)")))
        }
        return effects
    }

    private mutating func returnFromChange(to previous: WorkoutPhase, at now: TimeInterval) -> [WorkoutEffect] {
        phase = previous
        switch previous {
        case .exercising:
            trackingLostAt = framing.isReliable ? nil : now
            trackingLossAnnounced = false
            resumeHold(at: now)
            return setCounting(needsFraming && framing.isReliable) + [.speak(Utterance(text: "Back to \(exercise?.spokenName ?? "your set")."))]
        default:
            return [.speak(Utterance(text: "Okay, staying on \(exercise?.spokenName ?? "this exercise")."))]
        }
    }

    private mutating func pauseForSystem(_ reason: PauseReason, at now: TimeInterval) -> [WorkoutEffect] {
        switch phase {
        case .exercising:
            phase = .paused(reason)
            suspendHold(at: now)
            return setCounting(false)
        case .changingExercise(previous: .exercising):
            phase = .changingExercise(previous: .paused(reason))
            return setCounting(false)
        default:
            return []
        }
    }

    private mutating func endWorkout(at now: TimeInterval) -> [WorkoutEffect] {
        endedAfterCompletion = phase == .exerciseComplete
        // A camera count or the seconds held so far is kept; a self-reported set the user never marked done isn't.
        if let exercise, phase == .exercising || isPaused, needsFraming || isTimed {
            let amount = currentSetAmount(at: now)
            if amount > 0 {
                progress[exercise.id, default: ExerciseProgress()].record(reps: amount, weight: currentWeights[exercise.id])
            }
        }
        clearHold()
        // The occurrence in progress keeps what was done, with no outcome yet.
        if let item = currentPlanItem, planRecords[item.id] == nil, let record = progress[item.exerciseID], !record.roundSetReps.isEmpty {
            planRecords[item.id] = PlanItemRecord(outcome: nil, setReps: record.roundSetReps, setWeights: record.roundSetWeights)
        }
        sideReps = [.left: 0, .right: 0]
        phase = .ended
        restEndsAt = nil
        restDurationSeconds = nil
        return setCounting(false) + clearFeedback() + [
            .speak(Utterance(text: "Workout ended. Nice work.", interrupts: true)),
            .stopCaptureAndVoice]
    }

    // MARK: - Tracking, reps, and time

    private mutating func framingChanged(_ status: FramingStatus, at now: TimeInterval) -> [WorkoutEffect] {
        let previous = framing
        framing = status
        if status.guidance != previous.guidance { guidanceChangedAt = now }
        // Self-reported exercises ignore framing: the camera can't follow them.
        guard needsFraming else { return [] }
        switch phase {
        case .framing where status.isReliable && status.guidance == nil:
            phase = .ready
            readySince = now
            lastSpokenGuidance = nil
            // Framing near a threshold can flicker; announce readiness once per interval.
            if let last = lastReadyAnnouncedAt, now - last < Self.guidanceRepeatInterval { return [] }
            lastReadyAnnouncedAt = now
            return [.speak(Utterance(text: "Looks good. \(beginPrompt)."))]
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
        lastRepAt = now
        repEventCount += 1
        // A timed hold's target is seconds, so only its timer (or Done) ends it.
        if exercise.doseUnit == .reps, after >= exercise.autoCompleteReps {
            return completeSet(at: now, amount: repCount)
        }
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
            if let exercise, exercise.doseUnit == .seconds, let holdEndsAt {
                if now >= holdEndsAt { return completeSet(at: now, amount: exercise.autoCompleteReps) }
                let remaining = holdEndsAt - now
                if !holdCountdownAnnounced, remaining <= Self.holdCountdownSeconds,
                   TimeInterval(exercise.autoCompleteReps) >= 2 * Self.holdCountdownSeconds {
                    holdCountdownAnnounced = true
                    return [.speak(Utterance(text: "\(Int(Self.holdCountdownSeconds)) seconds.", isInstruction: false))]
                }
            }
            if needsFraming, !framing.isReliable, !trackingLossAnnounced, let lostAt = trackingLostAt,
               now - lostAt >= Self.trackingLossGrace {
                trackingLossAnnounced = true
                let guidance = framing.guidance?.spokenText ?? FramingGuidance.stepIntoView.spokenText
                return [.speak(Utterance(text: "I can't see you. \(guidance)"))]
            }
            // Reminders come due on the clock rather than on a frame.
            return isCounting ? tipEffects(coaching.tick(speaking: isCoachSpeaking, at: now)) : []
        case .resting:
            guard let restEndsAt, now >= restEndsAt else { return [] }
            if restLeadsToNextExercise {
                // Rest before the next plan exercise ends in its normal setup; counting waits for a start.
                restLeadsToNextExercise = false
                isRestingBeforeNextExercise = false
                self.restEndsAt = nil
                restDurationSeconds = nil
                enterSetup(at: now)
                let begin = needsFraming ? "" : " \(beginPrompt)."
                return [.speak(Utterance(text: "Rest is up. \(exercise?.setupLine ?? "")\(begin)"))]
            }
            // Tracked but badly placed (say, the phone moved too close): set up again, as for Ready, before an
            // automatic start. Out of view, the usual prompt below applies.
            if needsFraming, framing.isReliable, let guidance = framing.guidance {
                self.restEndsAt = nil
                restDurationSeconds = nil
                phase = .framing
                lastSpokenGuidance = guidance
                lastGuidanceSpokenAt = now
                return [.speak(Utterance(text: "Rest is up. \(guidance.spokenText)"))]
            }
            if startHoldProgress(at: now) == 1 { return beginSet(at: now) }
            guard !restDoneAnnounced else { return [] }
            restDoneAnnounced = true
            let begin = effectiveStartsByHolding ? "\(startPrompt) or \(prompt("start").lowercased())" : prompt("start")
            return [.speak(Utterance(text: "Rest is up. \(begin) for set \(currentSetNumber)."))]
        default:
            return []
        }
    }

    // MARK: - Helpers

    /// How to begin a set: hold the start position or say start, or just say start.
    private var beginPrompt: String {
        guard effectiveStartsByHolding else { return "\(prompt("start")) when you're ready" }
        return "\(startPrompt) to start, or \(prompt("start").lowercased())"
    }

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
        if !counting { coaching.stopCounting() }
        return [.setCounting(counting)]
    }

    /// Clears end-position highlights and any tip, and forgets the set's coaching history.
    private mutating func clearFeedback() -> [WorkoutEffect] {
        coaching.reset()
        return [.clearFeedback]
    }

    /// A corrective cue is shown and spoken; a reminder is only shown.
    private mutating func tipEffects(_ cue: CoachingCue?) -> [WorkoutEffect] {
        guard let cue else { return [] }
        lastTipID += 1
        let tip = WorkoutEffect.showTip(CoachingTip(id: lastTipID, cue: cue))
        return cue.kind == .corrective ? [tip, .speak(Utterance(text: cue.text))] : [tip]
    }

    private static func scheduler(for exercise: ExerciseDefinition?) -> CoachingCueScheduler {
        CoachingCueScheduler(cues: exercise?.coachingCues ?? [], reminders: exercise?.reminders ?? [])
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

    /// Names the completion card's buttons, or their spoken equivalents.
    private var completePrompt: String {
        let others = exercises.count > 1
        if voiceControlActive {
            return others ? "Say another round, change exercise, or end workout." : "Say another round or end workout."
        }
        return others ? "Tap Another Round, Choose Exercise, or End Workout." : "Tap Another Round or End Workout."
    }

    private func repCountReply(at now: TimeInterval) -> String {
        guard let exercise else { return "No exercise selected yet." }
        switch phase {
        case .resting, .exerciseComplete:
            let last = progress[exercise.id]?.setReps.last ?? 0
            return "Your last set was \(exercise.amountPhrase(last))."
        case .exercising where exercise.doseUnit == .seconds, .paused where exercise.doseUnit == .seconds:
            let remaining = Int((holdRemaining(at: now) ?? 0).rounded(.up))
            return "\(exercise.amountPhrase(remaining)) left."
        case .exercising where exercise.isSelfReported, .paused where exercise.isSelfReported:
            return "This set is \(exercise.amountPhrase(exercise.autoCompleteReps)). \(donePrompt) when you've finished."
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
        let finished = setsDone(for: exercise)
        let side = currentSide.map { " \(exercise.sideLabel($0))." } ?? ""
        let position = planPositionLabel.map { "\($0). " } ?? ""
        switch phase {
        case .resting where isRestingBeforeNextExercise:
            return "\(position)Up next: \(exercise.spokenName), set 1 of \(exercise.sets)."
        case .resting:
            return "\(position)Set \(finished) of \(exercise.sets) done. Set \(finished + 1) is next."
        case .exerciseComplete:
            return "All \(exercise.sets) sets of \(exercise.spokenName) are done."
        default:
            return "\(position)Set \(currentSetNumber) of \(exercise.sets).\(side)"
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
        case .exercising where isFollowingPlan: return [.pause, .repCount, .nextSet, .nextExercise]
        case .resting where isFollowingPlan: return [.start, .whichSet, .nextExercise]
        case .exercising: return [.pause, .repCount, .nextSet, .restartSet]
        case .paused: return [.resume, .restartSet, .nextSet]
        case .resting: return [.start, .whichSet]
        case .exerciseComplete: return [.anotherRound] + (exercises.count > 1 ? [.changeExercise] : []) + [.endWorkout]
        case .ended: return []
        }
    }
}
