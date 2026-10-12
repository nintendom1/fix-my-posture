import Foundation

/// Decides which coaching cue, if any, to show next. Pure and deterministic: time is passed in.
///
/// - A continuous signal must hold for `continuousHold` before its cue is eligible.
/// - A per-rep cue is eligible when the newest attempt raises it and 2 of the last 3 attempts did.
///   It stays pending until the next attempt, unless it was cooling down when that attempt arrived.
/// - Each cue cools down for `cueCooldown`; any two cues start at least `globalGap` apart.
/// - One cue is active at a time. A strictly higher-priority cue replaces the active one at once.
/// - A corrective cue doesn't start while the coach is speaking, so its tip and spoken line match.
/// - Reminders show one at set start, then one after `reminderInterval` without any cue.
struct CoachingCueScheduler {
    struct Configuration {
        var continuousHold: TimeInterval = 0.5
        var repWindow = 3
        var repsRequired = 2
        var cueCooldown: TimeInterval = 10
        var globalGap: TimeInterval = 4
        /// How long a tip stays on screen, and so how long a cue counts as active.
        var tipDuration: TimeInterval = 3
        var reminderInterval: TimeInterval = 25
    }

    let configuration: Configuration
    private let cues: [CoachingCueID: CoachingCue]
    private let reminders: [CoachingCue]

    private var heldSince: [CoachingCueID: TimeInterval] = [:]
    private var recentReps: [Set<CoachingCueID>] = []
    private var pending: Set<CoachingCueID> = []
    private var lastShown: [CoachingCueID: TimeInterval] = [:]
    private var lastCueStart: TimeInterval?
    private var active: (cue: CoachingCue, shownAt: TimeInterval)?
    private var lastCorrectiveAt: TimeInterval?
    private var lastReminderAt: TimeInterval?
    /// Survives `reset` and `beginSet`, so each set opens with the next reminder.
    private var reminderIndex = 0

    init(cues: [CoachingCue], reminders: [CoachingCue], configuration: Configuration = Configuration()) {
        self.cues = Dictionary(cues.filter { $0.kind == .corrective }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.reminders = reminders
        self.configuration = configuration
    }

    /// The cue on screen, if its tip hasn't expired.
    func activeCue(at now: TimeInterval) -> CoachingCue? {
        guard let active, now - active.shownAt < configuration.tipDuration else { return nil }
        return active.cue
    }

    /// Clears the previous set and returns the set-start reminder, if the exercise has any.
    mutating func beginSet(at now: TimeInterval) -> CoachingCue? {
        reset()
        return showReminder(at: now)
    }

    /// Feeds one analyzer frame and returns a cue to show now, if one is due.
    mutating func update(_ observation: FormObservation, speaking: Bool, at now: TimeInterval) -> CoachingCue? {
        for id in observation.signals where heldSince[id] == nil {
            heldSince[id] = now
        }
        heldSince = heldSince.filter { observation.signals.contains($0.key) }

        for rep in observation.repForms {
            recentReps.append(rep.flags)
            if recentReps.count > configuration.repWindow {
                recentReps.removeFirst(recentReps.count - configuration.repWindow)
            }
            // A newer attempt replaces whatever was pending from older ones.
            pending = rep.flags.filter { id in
                recentReps.filter { $0.contains(id) }.count >= configuration.repsRequired && !isCoolingDown(id, at: now)
            }
        }
        return nextCorrective(speaking: speaking, at: now)
    }

    /// Clock for cues that become due without a new frame, such as reminders.
    mutating func tick(speaking: Bool, at now: TimeInterval) -> CoachingCue? {
        if let cue = nextCorrective(speaking: speaking, at: now) { return cue }
        guard !reminders.isEmpty, activeCue(at: now) == nil, !isWithinGap(at: now) else { return nil }
        let quietSince = [lastCorrectiveAt, lastReminderAt].compactMap { $0 }.max()
        guard let quietSince, now - quietSince >= configuration.reminderInterval else { return nil }
        return showReminder(at: now)
    }

    /// Counting paused or tracking lost: holds and pending cues no longer describe the current movement.
    mutating func stopCounting() {
        heldSince = [:]
        pending = []
    }

    /// Clears everything except the reminder rotation.
    mutating func reset() {
        heldSince = [:]
        recentReps = []
        pending = []
        lastShown = [:]
        lastCueStart = nil
        active = nil
        lastCorrectiveAt = nil
        lastReminderAt = nil
    }

    // MARK: - Selection

    private mutating func nextCorrective(speaking: Bool, at now: TimeInterval) -> CoachingCue? {
        let eligible = cues.values.filter { cue in
            guard !isCoolingDown(cue.id, at: now) else { return false }
            switch cue.trigger {
            case .continuous:
                return heldSince[cue.id].map { now - $0 >= configuration.continuousHold } ?? false
            case .perRep:
                return pending.contains(cue.id)
            }
        }
        // Ties break on the id so the choice never depends on dictionary order.
        guard let best = eligible.max(by: { ($0.priority, $1.id.rawValue) < ($1.priority, $0.id.rawValue) }) else { return nil }
        if let current = activeCue(at: now) {
            guard best.priority > current.priority else { return nil }
        } else {
            guard !speaking, !isWithinGap(at: now) else { return nil }
        }
        show(best, at: now)
        lastCorrectiveAt = now
        pending.remove(best.id)
        return best
    }

    private mutating func showReminder(at now: TimeInterval) -> CoachingCue? {
        guard !reminders.isEmpty else { return nil }
        let reminder = reminders[reminderIndex % reminders.count]
        reminderIndex += 1
        show(reminder, at: now)
        lastReminderAt = now
        return reminder
    }

    private mutating func show(_ cue: CoachingCue, at now: TimeInterval) {
        lastShown[cue.id] = now
        lastCueStart = now
        active = (cue, now)
    }

    private func isCoolingDown(_ id: CoachingCueID, at now: TimeInterval) -> Bool {
        lastShown[id].map { now - $0 < configuration.cueCooldown } ?? false
    }

    private func isWithinGap(at now: TimeInterval) -> Bool {
        lastCueStart.map { now - $0 < configuration.globalGap } ?? false
    }
}
