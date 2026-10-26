import Foundation

/// Audio steps that run synchronously on the main thread around coach speech and listening. They are the building
/// blocks every path shares (retries and recovery included), so each is timed once; only a failed ducking, which
/// restores other audio, nests one inside another.
enum AudioWorkStep: String, Equatable {
    /// Session deactivation, ducking category, and activation before the coach speaks.
    case beginDucking
    /// One attempt at deactivating, restoring the category, and reactivating for listening after the coach speaks.
    case restoreOtherAudio
    case activateForListening
    case stopListening
    case deactivate
    /// Installing the microphone tap and starting the audio engine.
    case engineStart
    case engineStop
    case engineRebuild
    /// Creating a speech recognition task.
    case taskStart
    case taskCancel
    /// Handing an utterance to the speech synthesizer.
    case speechStart
    case speechStop
}

/// Times audio work that blocks the main thread (session activation, engine start, recognition tasks), so a
/// workout recording shows what a stall after the coach speaks is made of. Main thread only.
final class AudioWorkTiming {
    /// Called after each measured step with its duration in seconds.
    var onMeasured: ((AudioWorkStep, TimeInterval) -> Void)?

    func measure<T>(_ step: AudioWorkStep, _ work: () throws -> T) rethrows -> T {
        let start = ProcessInfo.processInfo.systemUptime
        defer { onMeasured?(step, ProcessInfo.processInfo.systemUptime - start) }
        return try work()
    }
}
