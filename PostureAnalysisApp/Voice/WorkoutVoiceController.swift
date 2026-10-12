import Foundation

/// Hands-free control: listens while the coach is quiet and turns phrases into workout commands.
///
/// - Half-duplex: recognition stops (partial transcript discarded) before the coach speaks and
///   resumes once the speech queue drains, so the coach never hears itself.
/// - Unambiguous matches run immediately. A match that could still grow into a different command
///   ("start" → "start over") runs on a final result or once the transcript settles for 0.6 s.
/// - A transcript that stays unchanged for 1.2 s ends the utterance, so later commands aren't buried
///   in earlier chatter.
@MainActor
final class WorkoutVoiceController {
    enum Status: Equatable {
        case off
        case requestingPermission
        case needsPermission
        case listening
        case coachSpeaking
        case paused
        /// The user turned the microphone off.
        case muted
        case unavailable(String)

        /// Voice commands work now or will resume on their own.
        var isUsable: Bool {
            switch self {
            case .listening, .coachSpeaking, .paused: return true
            default: return false
            }
        }
    }

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
    private let audio: WorkoutAudioSession?
    private let clock: () -> TimeInterval
    private var wantsListening = false
    private var isCoachSpeaking = false
    private var isRecognizing = false
    private var transcript = ""
    private var transcriptChangedAt: TimeInterval = 0
    private var pending: VoiceCommandMatch?
    private var checkTimer: Timer?

    init(recognizer: SpeechRecognizing, parser: VoiceCommandParsing, permissions: VoicePermissionProviding,
         audio: WorkoutAudioSession?, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.recognizer = recognizer
        self.parser = parser
        self.permissions = permissions
        self.audio = audio
        self.clock = clock
        recognizer.setContextualStrings(parser.vocabulary)
        recognizer.onTranscript = { [weak self] text, isFinal in
            MainActor.assumeIsolated { self?.handleTranscript(text, isFinal: isFinal) }
        }
        recognizer.onStateChanged = { [weak self] state in
            MainActor.assumeIsolated { self?.handleRecognizerState(state) }
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
        wantsListening = false
        stopRecognizing()
        audio?.stopListening()
        if status.isUsable || status == .requestingPermission { status = newStatus }
    }

    /// The user muted or unmuted the microphone. Unmuting only clears the state; call `enable()` when
    /// capture is running.
    func setMuted(_ muted: Bool) {
        if muted {
            wantsListening = false
            stopRecognizing()
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
        isCoachSpeaking = speaking
        if speaking {
            // Synchronous, before the audio session is reconfigured for ducking.
            stopRecognizing()
            if status == .listening { status = .coachSpeaking }
        } else if wantsListening, status == .coachSpeaking || status == .listening {
            startRecognizing()
        }
    }

    /// The audio route or session changed underneath a running engine.
    func handleAudioEvent(_ event: WorkoutAudioSession.Event) {
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
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTranscript() }
        }
    }

    private func stopRecognizing() {
        checkTimer?.invalidate()
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
            checkTimer?.invalidate()
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
        guard isRecognizing, !transcript.isEmpty else { return }
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
}
