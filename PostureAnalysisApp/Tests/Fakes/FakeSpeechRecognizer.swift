import Foundation
@testable import PostureAnalysisApp

/// Speech recognition driven by the test: `hear` delivers a transcript as the recognizer would.
final class FakeSpeechRecognizer: SpeechRecognizing {
    var onTranscript: ((String, Bool) -> Void)?
    var onStateChanged: ((SpeechRecognizerState) -> Void)?
    var onTaskStarted: (() -> Void)?
    private(set) var contextualStrings: [String] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var restartCount = 0

    func setContextualStrings(_ strings: [String]) { contextualStrings = strings }
    func start() {
        startCount += 1
        onTaskStarted?()
        onStateChanged?(.listening)
    }
    func stop() { stopCount += 1 }
    func restartTask() {
        restartCount += 1
        onTaskStarted?()
    }
    func reconfigureInput() {}
    func rebuild() {}

    func hear(_ text: String, final isFinal: Bool = false) { onTranscript?(text, isFinal) }
    /// The recognizer replaces its task on its own, as its 50 s refresh and error recovery do.
    func rollOver() { onTaskStarted?() }
}

struct GrantedVoicePermissions: VoicePermissionProviding {
    var microphone: VoicePermissionStatus { .granted }
    var speechRecognition: VoicePermissionStatus { .granted }
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) {}
    func requestSpeechRecognition(_ completion: @escaping @MainActor (Bool) -> Void) {}
}
