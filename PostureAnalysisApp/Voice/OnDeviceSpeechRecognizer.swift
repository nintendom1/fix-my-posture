import AVFoundation
import Speech

enum SpeechRecognizerState: Equatable {
    case idle
    case listening
    case unavailable(String)
}

/// Streams microphone audio into speech recognition. Call from the main thread; callbacks arrive on it.
protocol SpeechRecognizing: AnyObject {
    var onTranscript: ((_ text: String, _ isFinal: Bool) -> Void)? { get set }
    var onStateChanged: ((SpeechRecognizerState) -> Void)? { get set }
    func setContextualStrings(_ strings: [String])
    /// Starts the audio engine and a recognition task. The audio session must already be active.
    func start()
    /// Stops audio and recognition, discarding any partial transcript.
    func stop()
    /// Begins a fresh recognition task on the running engine, discarding the current transcript.
    func restartTask()
    /// Reinstalls the microphone tap with the current input format, for example after a route change.
    func reconfigureInput()
    /// Stops and replaces the audio engine after a media-services reset; call `start()` afterward.
    func rebuild()
}

/// English speech recognition that never leaves the device. Without on-device support it reports
/// `.unavailable` and touch controls keep working.
///
/// Tasks restart after every final result, every ~50 s (recognition requests are time-limited),
/// and on errors with a 0.5–4 s backoff. Five consecutive failures report `.unavailable`.
final class OnDeviceSpeechRecognizer: NSObject, SpeechRecognizing, SFSpeechRecognizerDelegate {
    static let taskRefreshInterval: TimeInterval = 50
    static let maximumConsecutiveFailures = 5

    var onTranscript: ((String, Bool) -> Void)?
    var onStateChanged: ((SpeechRecognizerState) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private var engine = AVAudioEngine()
    // The tap appends from the audio thread, so the live request is guarded.
    private let requestLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var taskGeneration = 0
    private var receivedTranscript = false
    private var contextualStrings: [String] = []
    private var isRunning = false
    private var consecutiveFailures = 0
    private var refreshTimer: Timer?
    private var retryWork: DispatchWorkItem?
    private let timing: AudioWorkTiming?

    init(locale: Locale = .current, timing: AudioWorkTiming? = nil) {
        self.timing = timing
        let english = locale.language.languageCode?.identifier == "en" ? locale : Locale(identifier: "en-US")
        recognizer = SFSpeechRecognizer(locale: english) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        recognizer?.queue = .main
        recognizer?.delegate = self
    }

    private var unavailableReason: String? {
        guard let recognizer else { return "Speech recognition isn't available for English on this iPhone." }
        guard recognizer.supportsOnDeviceRecognition else {
            return "On-device speech recognition isn't available on this iPhone. Use the buttons instead."
        }
        guard recognizer.isAvailable else { return "Speech recognition is temporarily unavailable." }
        return nil
    }

    func setContextualStrings(_ strings: [String]) {
        contextualStrings = strings
    }

    func start() {
        guard !isRunning else { return }
        if let reason = unavailableReason {
            onStateChanged?(.unavailable(reason))
            return
        }
        isRunning = true
        do {
            try startEngine()
        } catch {
            recordFailure()
            return
        }
        startTask()
        onStateChanged?(.listening)
    }

    func stop() {
        guard isRunning || engine.isRunning else { return }
        isRunning = false
        retryWork?.cancel()
        retryWork = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancelTask()
        stopEngine(removingTap: true)
        onStateChanged?(.idle)
    }

    func restartTask() {
        guard isRunning else { return }
        cancelTask()
        startTask()
    }

    func reconfigureInput() {
        guard isRunning else { return }
        stopEngine(removingTap: false)
        do {
            try startEngine()
        } catch {
            recordFailure()
        }
    }

    private func measured<T>(_ step: AudioWorkStep, _ work: () throws -> T) rethrows -> T {
        if let timing { return try timing.measure(step, work) }
        return try work()
    }

    func rebuild() {
        stop()
        measured(.engineRebuild) { engine = AVAudioEngine() }
    }

    // MARK: - Engine and tasks

    private func startEngine() throws {
        try measured(.engineStart) { try installTapAndStartEngine() }
    }

    private func stopEngine(removingTap: Bool) {
        measured(.engineStop) {
            engine.stop()
            if removingTap { engine.inputNode.removeTap(onBus: 0) }
        }
    }

    private func installTapAndStartEngine() throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecognizerError.noInput }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        requestLock.lock()
        let request = self.request
        requestLock.unlock()
        request?.append(buffer)
    }

    private func startTask() {
        guard recognizer != nil else { return }
        measured(.taskStart) { beginRecognitionTask() }
    }

    private func beginRecognitionTask() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.contextualStrings = contextualStrings
        requestLock.lock()
        self.request = request
        requestLock.unlock()

        taskGeneration += 1
        let generation = taskGeneration
        receivedTranscript = false
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, generation == self.taskGeneration else { return }
            if let result {
                self.receivedTranscript = true
                self.consecutiveFailures = 0
                self.onTranscript?(result.bestTranscription.formattedString, result.isFinal)
                // The transcript handler may already have restarted the task.
                if result.isFinal, generation == self.taskGeneration { self.restartTask() }
            } else if let error {
                self.taskEnded(with: error)
            }
        }

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.taskRefreshInterval, repeats: false) { [weak self] _ in
            self?.restartTask()
        }
    }

    private func cancelTask() {
        measured(.taskCancel) { endRecognitionTask() }
    }

    private func endRecognitionTask() {
        taskGeneration += 1
        task?.cancel()
        task = nil
        requestLock.lock()
        request?.endAudio()
        request = nil
        requestLock.unlock()
    }

    private func taskEnded(with error: Error) {
        guard isRunning else { return }
        let nsError = error as NSError
        // "No speech detected" and tasks that already produced text just roll over to a new task.
        let isBenign = receivedTranscript || (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110)
        if isBenign {
            restartTask()
        } else {
            cancelTask()
            recordFailure()
        }
    }

    private func recordFailure() {
        consecutiveFailures += 1
        guard consecutiveFailures < Self.maximumConsecutiveFailures else {
            stop()
            consecutiveFailures = 0
            onStateChanged?(.unavailable("Voice commands stopped after repeated errors. Tap the microphone to try again."))
            return
        }
        let delay = min(4, 0.5 * pow(2, Double(consecutiveFailures - 1)))
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            if self.engine.isRunning {
                self.startTask()
            } else {
                do {
                    try self.startEngine()
                    self.startTask()
                    self.onStateChanged?(.listening)
                } catch {
                    self.recordFailure()
                }
            }
        }
        retryWork?.cancel()
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        // Keep every callback on the main thread, as the protocol promises.
        let report = { [weak self] in
            guard let self, !available, self.isRunning else { return }
            self.stop()
            self.onStateChanged?(.unavailable("Speech recognition is temporarily unavailable. Tap the microphone to try again."))
        }
        if Thread.isMainThread { report() } else { DispatchQueue.main.async(execute: report) }
    }

    private enum RecognizerError: Error {
        case noInput
    }
}
