import AVFoundation
import Foundation

@MainActor
protocol SpeechCoaching: AnyObject {
    var isSpeaking: Bool { get }
    /// Called with true before the first queued utterance plays and false after the queue drains
    /// and other audio has been restored.
    var onActivityChanged: ((Bool) -> Void)? { get set }
    func speak(_ utterance: Utterance)
    func repeatLastInstruction()
    /// Cancels current and queued speech and restores other audio immediately.
    func stopAll()
}

/// Short spoken coaching over AVSpeechSynthesizer, ducking other audio only while speaking.
@MainActor
final class SpeechCoach: NSObject, SpeechCoaching, SpeechSynthesizingDelegate {
    /// Older pending lines are dropped beyond this, so speech never lags far behind the workout.
    static let maximumQueued = 2
    /// Added to the estimated speaking time before the watchdog gives up on a stuck utterance.
    static let watchdogSlack: TimeInterval = 5

    var onActivityChanged: ((Bool) -> Void)?
    private(set) var lastInstruction: Utterance?
    var isSpeaking: Bool { isActive }

    private let synthesizer: any SpeechSynthesizing
    private let audio: AudioSessionControlling
    private let voice: AVSpeechSynthesisVoice?
    private var queue: [Utterance] = []
    private var current: AVSpeechUtterance?
    private var isActive = false
    private var watchdog: Timer?
    private let timing: AudioWorkTiming?
    private let watchdogScheduling: SpeechWatchdogScheduling?

    init(audio: AudioSessionControlling, timing: AudioWorkTiming? = nil,
         synthesizer: (any SpeechSynthesizing)? = nil,
         scheduleWatchdog: SpeechWatchdogScheduling? = nil) {
        self.audio = audio
        self.timing = timing
        self.synthesizer = synthesizer ?? SystemSpeechSynthesizer()
        watchdogScheduling = scheduleWatchdog
        voice = Self.preferredVoice()
        super.init()
        self.synthesizer.delegate = self
    }

    func speak(_ utterance: Utterance) {
        if utterance.isInstruction { lastInstruction = utterance }
        if utterance.interrupts {
            queue.removeAll()
            // The cancel callback advances to this utterance; speaking immediately after a stop can be dropped.
            if current != nil { stopSynthesizer() }
        }
        queue.append(utterance)
        if queue.count > Self.maximumQueued { queue.removeFirst(queue.count - Self.maximumQueued) }
        if current == nil { speakNext() }
    }

    func repeatLastInstruction() {
        speak(lastInstruction ?? Utterance(text: "Nothing to repeat yet.", isInstruction: false))
    }

    func stopAll() {
        queue.removeAll()
        current = nil
        stopSynthesizer()
        finishActivity()
    }

    private func speakNext() {
        guard current == nil else { return }
        guard !queue.isEmpty else {
            finishActivity()
            return
        }
        let next = queue.removeFirst()
        if !isActive {
            isActive = true
            // Listeners such as speech recognition stop before the session is reconfigured.
            onActivityChanged?(true)
        }
        audio.beginDucking()
        let spoken = AVSpeechUtterance(string: next.text)
        spoken.voice = voice
        current = spoken
        measured(.speechStart) { synthesizer.speak(spoken) }
        armWatchdog(for: spoken)
    }

    private func stopSynthesizer() {
        measured(.speechStop) { _ = synthesizer.stopSpeaking(at: .immediate) }
    }

    private func measured(_ step: AudioWorkStep, _ work: () -> Void) {
        if let timing { timing.measure(step, work) } else { work() }
    }

    private func finishActivity() {
        watchdog?.invalidate()
        watchdog = nil
        audio.endDucking()
        guard isActive else { return }
        isActive = false
        onActivityChanged?(false)
    }

    private func isCurrent(_ id: ObjectIdentifier) -> Bool {
        current.map(ObjectIdentifier.init) == id
    }

    private func completed(_ id: ObjectIdentifier) {
        guard isCurrent(id) else { return }
        current = nil
        watchdog?.invalidate()
        watchdog = nil
        speakNext()
    }

    /// Recovers if the synthesizer never reports completion, so other audio is never left lowered.
    private func armWatchdog(for utterance: AVSpeechUtterance) {
        watchdog?.invalidate()
        let words = utterance.speechString.split(separator: " ").count
        let estimate = max(1, Double(words) / 2.5)
        let id = ObjectIdentifier(utterance)
        let delay = estimate + Self.watchdogSlack
        let timeout: @MainActor () -> Void = { [weak self] in
            guard let self, self.isCurrent(id) else { return }
            self.stopAll()
        }
        if let watchdogScheduling {
            watchdog = watchdogScheduling(delay, timeout)
        } else {
            watchdog = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                MainActor.assumeIsolated { timeout() }
            }
        }
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let current = AVSpeechSynthesisVoice.currentLanguageCode()
        let language = current.hasPrefix("en") ? current : "en-US"
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        return best ?? AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension SpeechCoach {
    func speechSynthesizingDidStart(_ utteranceID: ObjectIdentifier) {
        guard isCurrent(utteranceID), let current else { return }
        // Time the watchdog from actual playback rather than from queueing.
        armWatchdog(for: current)
    }

    func speechSynthesizingDidFinish(_ utteranceID: ObjectIdentifier) {
        completed(utteranceID)
    }

    func speechSynthesizingDidCancel(_ utteranceID: ObjectIdentifier) {
        completed(utteranceID)
    }
}

typealias SpeechWatchdogScheduling = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Timer
