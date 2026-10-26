import Foundation

/// Hands-free control: listens while the coach is quiet and turns phrases into workout commands.
///
/// - Half-duplex: recognition stops (partial transcript discarded) before the coach speaks and
///   resumes once the speech queue drains, so the coach never hears itself.
/// - Unambiguous matches run immediately. A match that could still grow into a different command
///   ("start" → "start over") runs on a final result or once the transcript settles for 0.6 s.
/// - A transcript that stays unchanged for 1.2 s ends the utterance, so later commands aren't buried
///   in earlier chatter.
/// - While recording, "mark that" or "note, …" starts a marker. Everything heard until 1.5 s of quiet becomes its
///   note, across final results and task restarts, and none of it runs as a command. Coach speech or stopping
///   listening finishes the marker with the note so far, instead of losing it.
@MainActor
final class WorkoutVoiceController: VoiceControlling {
    typealias Status = VoiceStatus

    static let ambiguousSettleTime: TimeInterval = 0.6
    static let utteranceEndTime: TimeInterval = 1.2
    static let checkInterval: TimeInterval = 0.1

    var onStatusChanged: ((Status) -> Void)?
    var onCommand: ((WorkoutCommand) -> Void)?
    /// The phrase that triggered a command, for the "Heard" chip.
    var onHeard: ((String) -> Void)?

    private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatusChanged?(status) } }
    }

    private let recognizer: SpeechRecognizing
    private let parser: VoiceCommandParsing
    private let permissions: VoicePermissionProviding
    private let audio: AudioSessionControlling?
    private let clock: () -> TimeInterval
    private let scheduler: Scheduling
    private var wantsListening = false
    private var isCoachSpeaking = false
    private var isRecognizing = false
    private var transcript = ""
    private var transcriptChangedAt: TimeInterval = 0
    private var pending: VoiceCommandMatch?
    private var checkTimer: Cancellable?
    private var dictation: MarkerDictation?

    var acceptsMarkers = false {
        didSet {
            guard acceptsMarkers != oldValue else { return }
            if !acceptsMarkers, dictation != nil {
                // The recording ended mid-note: there's nothing left to mark, and the note's words must not run as
                // commands, so its transcript and recognition task go too.
                dictation = nil
                resetTranscript()
                if isRecognizing { recognizer.restartTask() }
            }
            recognizer.setContextualStrings(vocabulary)
        }
    }

    private var vocabulary: [String] { parser.vocabulary + (acceptsMarkers ? MarkerPhraseParser.vocabulary : []) }

    /// A marker being dictated: when its trigger was heard, and its note so far.
    private struct MarkerDictation {
        let startedAt: TimeInterval
        /// Note text from recognition tasks that already ended.
        var committed: [String] = []
        /// This task's part: the words after the trigger, or a later task's whole transcript.
        var current: String?
        /// Whether this task's transcript holds the trigger.
        var isTriggerTask = true

        var note: String? {
            MarkerPhraseParser.trimmedNote((committed + [current].compactMap { $0 }).joined(separator: " "))
        }

        mutating func update(with text: String) {
            current = isTriggerTask ? MarkerPhraseParser.parse(text)?.note ?? current : MarkerPhraseParser.trimmedNote(text)
        }

        /// A final result ends this task; the next one continues the note.
        mutating func commit() {
            if let current { committed.append(current) }
            current = nil
            isTriggerTask = false
        }
    }

    init(recognizer: SpeechRecognizing, parser: VoiceCommandParsing, permissions: VoicePermissionProviding,
         audio: AudioSessionControlling?, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         scheduler: Scheduling? = nil) {
        self.recognizer = recognizer
        self.parser = parser
        self.permissions = permissions
        self.audio = audio
        self.clock = clock
        self.scheduler = scheduler ?? MainScheduler()
        recognizer.setContextualStrings(parser.vocabulary)
        recognizer.onTranscript = { [weak self] text, isFinal in
            MainActor.assumeIsolated { self?.handleTranscript(text, isFinal: isFinal) }
        }
        recognizer.onStateChanged = { [weak self] state in
            MainActor.assumeIsolated { self?.handleRecognizerState(state) }
        }
        recognizer.onTaskStarted = { [weak self] in
            MainActor.assumeIsolated { self?.taskStarted() }
        }
    }

    // MARK: - Lifecycle

    /// Starts listening, asking for microphone and then speech permission the first time.
    func enable() {
        wantsListening = true
        switch permissions.microphone {
        case .denied:
            status = .needsPermission
            return
        case .notDetermined:
            status = .requestingPermission
            permissions.requestMicrophone { [weak self] _ in self?.enableIfWanted() }
            return
        case .granted:
            break
        }
        switch permissions.speechRecognition {
        case .denied:
            status = .needsPermission
        case .notDetermined:
            status = .requestingPermission
            permissions.requestSpeechRecognition { [weak self] _ in self?.enableIfWanted() }
        case .granted:
            audio?.setRecordingEnabled(true)
            startRecognizing()
        }
    }

    /// Stops listening and releases the microphone, for backgrounding, closing, or interruptions.
    func disable(status newStatus: Status = .off) {
        let interrupted = takeDictation()
        wantsListening = false
        stopRecognizing()
        if let interrupted { deliver(interrupted) }
        audio?.stopListening()
        if status.isUsable || status == .requestingPermission { status = newStatus }
    }

    /// The user muted or unmuted the microphone. Unmuting only clears the state; call `enable()` when
    /// capture is running.
    func setMuted(_ muted: Bool) {
        if muted {
            let interrupted = takeDictation()
            wantsListening = false
            stopRecognizing()
            if let interrupted { deliver(interrupted) }
            audio?.stopListening()
            status = .muted
        } else if status == .muted {
            status = .off
        }
    }

    /// Tries again after a failure or a pause the system didn't resume.
    func retry() {
        if case .unavailable = status { status = .off }
        enable()
    }

    func setCoachSpeaking(_ speaking: Bool) {
        // The coach is about to talk over a note: keep what was said rather than lose the marker.
        let interrupted = speaking ? takeDictation() : nil
        isCoachSpeaking = speaking
        if speaking {
            // Synchronous, before the audio session is reconfigured for ducking.
            stopRecognizing()
            if status == .listening { status = .coachSpeaking }
            // Delivered on the next turn: its "Marked." mustn't start while the coach is starting this line.
            if let interrupted {
                _ = scheduler.schedule(after: 0) { [weak self] in self?.deliver(interrupted) }
            }
        } else if wantsListening, status == .coachSpeaking || status == .listening {
            startRecognizing()
        }
    }

    /// The audio route or session changed underneath a running engine.
    func handleAudioEvent(_ event: AudioSessionEvent) {
        switch event {
        case .routeChanged:
            if isRecognizing { recognizer.reconfigureInput() }
        case .mediaServicesReset:
            stopRecognizing()
            recognizer.rebuild()
            if wantsListening, !isCoachSpeaking { startRecognizing() }
        case .reactivated:
            // A late restore deactivated the session under a running engine.
            if isRecognizing {
                recognizer.reconfigureInput()
            } else if wantsListening, !isCoachSpeaking {
                startRecognizing()
            }
        case .interruptionBegan, .interruptionEnded:
            break
        }
    }

    private func enableIfWanted() {
        guard wantsListening else { return }
        enable()
    }

    // MARK: - Recognition

    private func startRecognizing() {
        guard wantsListening, !isRecognizing else { return }
        guard !isCoachSpeaking else {
            status = .coachSpeaking
            return
        }
        guard audio?.activateForListening() ?? true else {
            status = .unavailable("The microphone couldn't start. Tap to try again.")
            return
        }
        resetTranscript()
        isRecognizing = true
        recognizer.start()
        checkTimer?.cancel()
        checkTimer = scheduler.repeating(every: Self.checkInterval) { [weak self] in self?.checkTranscript() }
    }

    private func stopRecognizing() {
        checkTimer?.cancel()
        checkTimer = nil
        resetTranscript()
        guard isRecognizing else { return }
        isRecognizing = false
        recognizer.stop()
    }

    private func handleRecognizerState(_ state: SpeechRecognizerState) {
        switch state {
        case .listening:
            if wantsListening, !isCoachSpeaking { status = .listening }
        case .unavailable(let reason):
            isRecognizing = false
            checkTimer?.cancel()
            checkTimer = nil
            audio?.stopListening()
            status = .unavailable(reason)
        case .idle:
            break
        }
    }

    private func handleTranscript(_ text: String, isFinal: Bool) {
        guard isRecognizing, !isCoachSpeaking else { return }
        if text != transcript {
            transcript = text
            transcriptChangedAt = clock()
        }
        if acceptsMarkers, dictateMarker(text, isFinal: isFinal) { return }
        guard let match = parser.parse(text) else {
            pending = nil
            if isFinal { resetTranscript() }
            return
        }
        if isFinal || !match.isPrefixOfLongerPhrase {
            execute(match)
        } else {
            pending = match
        }
    }

    private func checkTranscript() {
        guard isRecognizing else { return }
        if dictation != nil {
            if clock() - transcriptChangedAt >= MarkerPhraseParser.settleTime, let finished = takeDictation() {
                recognizer.restartTask()
                deliver(finished)
            }
            return
        }
        guard !transcript.isEmpty else { return }
        let settled = clock() - transcriptChangedAt
        if let pending, settled >= pending.settleTime ?? Self.ambiguousSettleTime {
            execute(pending)
        } else if pending == nil, settled >= Self.utteranceEndTime {
            // End of utterance without a command: start fresh so old words can't combine with new ones.
            resetTranscript()
            recognizer.restartTask()
        }
    }

    private func execute(_ match: VoiceCommandMatch) {
        resetTranscript()
        recognizer.restartTask()
        onHeard?(match.phrase)
        onCommand?(match.command)
    }

    private func resetTranscript() {
        transcript = ""
        pending = nil
    }

    // MARK: - Markers

    /// Starts or continues a marker; returns true when the transcript belongs to one, so no command runs from it.
    private func dictateMarker(_ text: String, isFinal: Bool) -> Bool {
        if dictation == nil {
            guard MarkerPhraseParser.parse(text) != nil else { return false }
            pending = nil
            dictation = MarkerDictation(startedAt: clock())
        }
        dictation?.update(with: text)
        if isFinal {
            // The recognizer starts a new task after a final result; the note carries on in it.
            dictation?.commit()
            transcript = ""
        }
        return true
    }

    /// Ends the marker being dictated, if any, returning its note and when its trigger was heard.
    private func takeDictation() -> (note: String?, heardAt: TimeInterval)? {
        guard let dictation else { return nil }
        self.dictation = nil
        resetTranscript()
        return (dictation.note, dictation.startedAt)
    }

    private func deliver(_ marker: (note: String?, heardAt: TimeInterval)) {
        onHeard?(marker.note.map { "Mark: \($0)" } ?? "Mark")
        onCommand?(.mark(note: marker.note, heardSecondsAgo: clock() - marker.heardAt))
    }

    /// Any new recognition task, final result or not, ends this part of a note; the next transcript continues it.
    private func taskStarted() {
        guard dictation != nil else { return }
        dictation?.commit()
        transcript = ""
    }
}
