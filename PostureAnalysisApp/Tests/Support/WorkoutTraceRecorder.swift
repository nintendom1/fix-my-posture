import AdaptiveTraining
import Foundation
@testable import PostureAnalysisApp

/// An ordered, human-readable trace of one workout: inputs, effects, speech, audio-session calls and listening
/// toggles, one line each. Golden tests compare it line by line, so any behaviour change shows up as a diff.
///
/// Lines starting with `>` are what the scenario did. Every other line is `t=<clock> <what happened>`, in the order it
/// happened: what the model recorded (reducer inputs, commands, pipeline controls, tips), what reached the fakes
/// (speech, audio session, voice controller), and a state line whenever the coach's state changed. Formatting is
/// fixed: two decimals, no UUIDs, no wall-clock dates.
///
/// It is also the model's session recorder. It never reports `isRecording`, so the model stays on its normal path
/// (no diagnostics, no recording chip) and only the calls every workout makes reach it.
@MainActor
final class WorkoutTraceRecorder: WorkoutSessionRecording {
    private(set) var lines: [String] = []
    /// The coach's clock; the harness sets it.
    var now: () -> TimeInterval = { 0 }
    /// The coach's state as ordered `(key, line)` pairs; a line is written whenever a key's line changes.
    var state: () -> [(key: String, line: String?)] = { [] }
    /// Known relationship ids use stable scenario names; unrecognized ids stay distinguishable as `other`.
    private var relationshipNames: [UUID: String] = [:]

    /// A line the model recorded that the fakes should receive next: unmuted speech and repeats are written once,
    /// when the speech coach gets them, so a line the coach never received still shows up.
    private enum Expected: Equatable {
        case speak(Utterance)
        case repeatLast
    }

    private var expected: Expected?
    private var lastState: [String: String] = [:]
    private var preservesExpectedSpeechDuringActivityCallback = false

    // MARK: - Scenario inputs

    /// Writes `> text` for something the scenario did.
    func input(_ text: String) {
        flushExpected()
        syncState()
        lines.append("> \(text)")
    }

    func nameRelationship(_ id: UUID, as symbol: String) {
        relationshipNames[id] = symbol
    }

    /// Reserves the place of an input whose description is known only after it ran, such as frames played until a
    /// condition. Pass the result to `insertInput`.
    func beginInput() -> Int {
        flushExpected()
        syncState()
        return lines.count
    }

    func insertInput(_ text: String, at index: Int) {
        lines.insert("> \(text)", at: min(max(index, 0), lines.count))
    }

    /// Writes `t=<now> text`.
    func record(_ text: String) {
        if !preservesExpectedSpeechDuringActivityCallback { flushExpected() }
        emit(text)
    }

    /// Holds a pending utterance expectation while the fake coach reports its synchronous start callback. The real
    /// `SpeechCoach` notifies listening before it hands the utterance to the synthesizer.
    func beginSpeechActivityCallback() {
        preservesExpectedSpeechDuringActivityCallback = true
    }

    func endSpeechActivityCallback() {
        preservesExpectedSpeechDuringActivityCallback = false
    }

    /// The final trace, with any pending state written.
    func finish() -> [String] {
        flushExpected()
        syncState()
        return lines
    }

    // MARK: - Fakes

    func speechSpoke(_ utterance: Utterance) {
        if expected == .speak(utterance) {
            expected = nil
            emit("speak \(Self.describe(utterance))")
        } else {
            record("speak unrecorded \(Self.describe(utterance))")
        }
    }

    /// The live coach speaks its last instruction again, or "Nothing to repeat yet." when there is none.
    func speechRepeated(lastInstruction: Utterance?) {
        let text = lastInstruction.map { Self.quoted($0.text) } ?? "nothing"
        if expected == .repeatLast {
            expected = nil
            emit("repeat last=\(text)")
        } else {
            record("repeat unrecorded last=\(text)")
        }
    }

    // MARK: - WorkoutSessionRecording

    let id = UUID()
    let isRecording = false
    let markers: [WorkoutMarker] = []

    func begin(_ context: WorkoutRecordingContext, at uptime: TimeInterval) {}

    func recordControl(_ control: WorkoutFramePipeline.Control, at uptime: TimeInterval) {
        switch control {
        case .sessionPhase(let phase):
            record("control sessionPhase \(WorkoutStateSnapshot.label(phase))")
        case .exercise(let exercise, let epoch):
            record("control exercise \(exercise.map(Self.describe) ?? "none") epoch=\(epoch)")
        case .resetAnalyzer(let epoch):
            record("control resetAnalyzer epoch=\(epoch)")
        case .counting(let counting):
            record("control counting \(counting)")
        case .resetTracking:
            record("control resetTracking")
        }
    }

    func recordFrame(_ frame: PoseFrame, output: WorkoutFramePipeline.FrameOutput?, pitchDegrees: Double?,
                     at uptime: TimeInterval) {
        // Frames are summarized by the scenario's input line; a frame is still a moment to note state changes.
        flushExpected()
        syncState()
    }

    func recordState(_ snapshot: WorkoutStateSnapshot, at uptime: TimeInterval) {}

    func recordEvent(_ event: WorkoutRecordingEvent, at uptime: TimeInterval) {
        switch event {
        case .input(let input):
            record("input \(Self.describe(input))")
        case .command(let command, let source, let phrase):
            let heard = phrase.map { " \(Self.quoted($0))" } ?? ""
            record("command \(Self.describe(command)) (\(source.rawValue)\(heard))")
        case .speak(let utterance, let muted):
            if muted {
                record("speak muted \(Self.describe(utterance))")
            } else {
                flushExpected()
                expected = .speak(utterance)
            }
        case .repeatLastInstruction(let muted):
            if muted {
                record("repeat muted")
            } else {
                flushExpected()
                expected = .repeatLast
            }
        case .tipShown(let tip):
            let kind = tip.cue.kind == .corrective ? "corrective" : "reminder"
            record("tip show \(tip.cue.id.rawValue) \(Self.quoted(tip.cue.text)) (\(kind))")
        case .tipCleared:
            record("tip clear")
        case .clearFeedback:
            record("clearFeedback")
        case .guidePresented(let presented):
            record("guide \(presented ? "shown" : "hidden")")
        case .helpPresented(let presented):
            record("help \(presented ? "shown" : "hidden")")
        case .measurementsShown(let shown):
            record("measurements \(shown ? "shown" : "hidden")")
        case .cameraRunning, .cameraInterrupted, .cameraFailed, .audioInterruptionBegan, .audioInterruptionEnded,
             .audioInterruptionDiagnostic, .audioRouteDiagnostic, .audioSessionOperation, .audioWork:
            // Echoes of an input the scenario already wrote.
            break
        }
    }

    func recordMarker(_ request: WorkoutMarkerRequest, at uptime: TimeInterval) -> WorkoutMarker? { nil }

    func duration(at uptime: TimeInterval) -> TimeInterval { 0 }

    func flush() {
        record("recorder flush")
    }

    func end(_ reason: WorkoutRecordingEnd, workoutRecordID: UUID?, at uptime: TimeInterval) {}

    // MARK: - Writing

    private func emit(_ text: String) {
        syncState()
        lines.append("\(Self.time(now())) \(text)")
    }

    /// A recorded line the fakes never received is written as such before anything else.
    private func flushExpected() {
        guard let pending = expected else { return }
        expected = nil
        switch pending {
        case .speak(let utterance): emit("speak notDelivered \(Self.describe(utterance))")
        case .repeatLast: emit("repeat notDelivered")
        }
    }

    private func syncState() {
        for (key, line) in state() where lastState[key] != line {
            lastState[key] = line
            lines.append("\(Self.time(now())) \(line ?? "\(key) none")")
        }
    }

    // MARK: - Formatting

    static func time(_ value: TimeInterval) -> String {
        String(format: "t=%.2f", value)
    }

    static func quoted(_ text: String) -> String {
        "\"\(text)\""
    }

    /// `"text"`, then `(status)` for a line "repeat that" skips and `(interrupts)` for one that cuts in.
    static func describe(_ utterance: Utterance) -> String {
        var flags: [String] = []
        if !utterance.isInstruction { flags.append("status") }
        if utterance.interrupts { flags.append("interrupts") }
        return quoted(utterance.text) + (flags.isEmpty ? "" : " (\(flags.joined(separator: ", ")))")
    }

    static func describe(_ exercise: ExerciseDefinition) -> String {
        exercise.isReducedRangeVariant ? "\(exercise.id.rawValue)(reduced)" : exercise.id.rawValue
    }

    static func describe(_ command: WorkoutCommand) -> String {
        switch command {
        case .selectExercise(let id): return "selectExercise(\(id.rawValue))"
        case .setWeight(let weight): return "setWeight(\(weight))"
        default: return String(describing: command)
        }
    }

    static func describe(_ event: WorkoutEvent) -> String {
        switch event {
        case .opened: return "opened"
        case .command(let command): return "command \(describe(command))"
        case .framingChanged(let status): return "framing \(describe(status))"
        case .repCompleted(let rep):
            return "rep epoch=\(rep.epoch) sides=\(rep.sides.map(\.rawValue).sorted().joined(separator: ","))"
        case .startPositionChanged(let held): return "startPosition \(held)"
        case .phoneTiltChanged(let tilted): return "phoneTilt \(tilted)"
        case .tick: return "tick"
        case .appBackgrounded: return "appBackgrounded"
        case .appForegrounded: return "appForegrounded"
        case .interruptionBegan: return "interruptionBegan"
        case .interruptionEnded: return "interruptionEnded"
        case .voiceControlChanged(let usable): return "voiceControl \(usable)"
        case .formObserved: return "formObserved"
        case .coachSpeakingChanged(let speaking): return "coachSpeaking \(speaking)"
        case .poseObserved: return "poseObserved"
        case .startBonus(let request): return "startBonus amount=\(request.amount)"
        case .startEasierSwap(let request):
            return "startEasierSwap \(request.exerciseID.rawValue) reducedRange=\(request.reducedRange) amount=\(request.amount)"
        }
    }

    static func describe(_ status: FramingStatus) -> String {
        if status == .lost { return "lost" }
        let guidance = status.guidance.map { " guidance=\($0.rawValue)" } ?? ""
        return (status.isReliable ? "reliable" : "unreliable") + guidance
    }

    static func describe(_ status: VoiceStatus) -> String {
        switch status {
        case .unavailable(let reason): return "unavailable(\(quoted(reason)))"
        default: return String(describing: status)
        }
    }

    static func describe(_ event: AudioSessionEvent) -> String {
        switch event {
        case .interruptionBegan: return "interruptionBegan"
        case .interruptionEnded(let shouldResume): return "interruptionEnded shouldResume=\(shouldResume)"
        case .mediaServicesReset: return "mediaServicesReset"
        case .routeChanged: return "routeChanged"
        case .reactivated: return "reactivated"
        default: return String(describing: event)
        }
    }

    /// Every set: `3 reps`, `20 s`, then the side and weight when there are any.
    static func describe(_ sets: [RecordedSet]) -> String {
        "[" + sets.map { set in
            var parts = [set.amountLabel]
            if let side = set.side { parts.append(side) }
            if let weight = set.weight { parts.append("@\(weight)") }
            return parts.joined(separator: " ")
        }.joined(separator: ", ") + "]"
    }

    /// A saved workout: one line for the record, then one per entry.
    func describe(_ record: WorkoutRecord, workoutID: UUID) -> [String] {
        let planID = relationship(record.planID)
        let header = "record plan=\(record.planName.map(Self.quoted) ?? "none") planID=\(planID) "
            + "id=\(record.id == workoutID ? "workout" : "other") entries=\(record.entries.count)"
        return [header] + record.entries.map { entry in
            "entry \(entry.exerciseID.rawValue) \(Self.quoted(entry.name)) outcome=\(entry.outcome?.rawValue ?? "none") "
                + "sets=\(Self.describe(entry.sets))"
        }
    }

    func describe(_ evidence: AdaptiveEvidence, workoutID: UUID) -> String {
        let confirmed = evidence.confirmed.map { "\($0)" } ?? "none"
        let sets = "[" + evidence.setAmounts.map { "\($0)" }.joined(separator: ", ") + "]"
        let observed = evidence.tracker.observed.map { ":\($0)" } ?? ""
        let bonus: String
        if let record = evidence.bonus {
            bonus = "offered=\(record.offered) accepted=\(record.accepted) completed=\(record.completed.map { "\($0)" } ?? "none") "
                + "effort=\(record.effort?.rawValue ?? "none")"
        } else {
            bonus = "none"
        }
        let workout = evidence.workoutID == nil ? "none" : (evidence.workoutID == workoutID ? "this" : "other")
        return "evidence \(evidence.source.rawValue) \(evidence.family.rawValue)/\(evidence.variant.rawValue) "
            + "prescribed=\(evidence.prescribed.map { "\($0)" } ?? "none") confirmed=\(confirmed) "
            + "(\(evidence.confirmation.rawValue)) sets=\(sets) tracker=\(evidence.tracker.status.rawValue)\(observed) "
            + "effort=\(evidence.effort?.rawValue ?? "none") tooHard=\(evidence.midSetTooHard) bonus={\(bonus)} "
            + "completion=\(evidence.completion.rawValue) prescription=\(relationship(evidence.prescriptionID)) "
            + "calibration=\(relationship(evidence.calibrationID)) workout=\(workout)"
    }

    private func relationship(_ id: UUID?) -> String {
        guard let id else { return "none" }
        if id == AdaptiveTrainingCoordinator.todaySessionPlanID { return "todaySessionPlan" }
        return relationshipNames[id] ?? "other"
    }

    // MARK: - Coach state

    /// The state lines for `model`, in a fixed order: the session, the camera, the microphone, mutes, and anything
    /// open over the workout.
    static func state(of model: WorkoutCoachModel) -> [(key: String, line: String?)] {
        let session = model.session
        var parts = ["state \(WorkoutStateSnapshot.label(session.phase))"]
        parts.append(session.exerciseID?.rawValue ?? "none")
        if session.plan != nil { parts.append("item=\(session.planIndex + 1)") }
        parts.append("set=\(session.currentSetNumber)")
        parts.append("reps=\(session.repCount)")
        if let side = session.currentSide { parts.append("side=\(side.rawValue)") }
        parts.append("counting=\(session.isCounting)")
        let card = model.effortCard.map { card in
            "card \(card.isBonus ? "bonus" : "effort") amount=\(card.amountLabel) sets=\(card.setCount) "
                + "preselected=\(card.preselected?.rawValue ?? "none")"
        }
        let bonus = model.bonusOffer.map { "bonusOffer amount=\($0.amountLabel)" }
        let tooHard = model.tooHardOffer.map { offer in
            "tooHardOffer easier=" + (offer.easierVersion.map { "\(quoted($0.name)) \($0.amountLabel)" } ?? "none")
        }
        return [
            (key: "state", line: parts.joined(separator: " ")),
            (key: "camera", line: "camera \(WorkoutStateSnapshot.label(model.cameraStatus))"),
            (key: "mic", line: "mic \(describe(model.micStatus))"),
            (key: "mute", line: "mute coach=\(model.isCoachMuted) mic=\(model.isMicMuted)"),
            (key: "card", line: card),
            (key: "bonusOffer", line: bonus),
            (key: "tooHardOffer", line: tooHard)
        ]
    }
}
