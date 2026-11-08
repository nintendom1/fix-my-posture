import AVFoundation
import Foundation

/// The AV speech operations `SpeechCoach` needs, with identifiers crossing delegate callbacks safely.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    var delegate: (any SpeechSynthesizingDelegate)? { get set }
    var isSpeaking: Bool { get }
    func speak(_ utterance: AVSpeechUtterance)
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

/// Main-actor callbacks corresponding to the synthesizer's delegate events.
@MainActor
protocol SpeechSynthesizingDelegate: AnyObject {
    func speechSynthesizingDidStart(_ utteranceID: ObjectIdentifier)
    func speechSynthesizingDidFinish(_ utteranceID: ObjectIdentifier)
    func speechSynthesizingDidCancel(_ utteranceID: ObjectIdentifier)
}

/// One-to-one wrapper around the system synthesizer. Delegate events reach the client on the main queue.
@MainActor
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing {
    private let synthesizer: AVSpeechSynthesizer
    weak var delegate: (any SpeechSynthesizingDelegate)?

    var isSpeaking: Bool { synthesizer.isSpeaking }

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ utterance: AVSpeechUtterance) {
        synthesizer.speak(utterance)
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        synthesizer.stopSpeaking(at: boundary)
    }
}

extension SystemSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.delegate?.speechSynthesizingDidStart(utteranceID) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.delegate?.speechSynthesizingDidFinish(utteranceID) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.delegate?.speechSynthesizingDidCancel(utteranceID) }
        }
    }
}
