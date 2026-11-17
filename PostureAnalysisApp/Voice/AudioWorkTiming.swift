import Foundation

/// Audio operations around coach speech and listening. These are the building blocks every path shares (retries
/// and recovery included), so each is timed once; only failed ducking, which restores other audio, nests one inside
/// another. Execution context records whether a step ran on the main thread or the audio session worker.
enum AudioWorkStep: String, Equatable, Sendable {
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

enum AudioWorkExecutionContext: String, Equatable, Sendable {
    case main
    case worker
}

/// Measures blocking audio work and reports its measured duration on the caller's executor.
final class AudioWorkTiming {
    /// Called after each measured step with its duration in seconds.
    var onMeasured: ((AudioWorkStep, TimeInterval, AudioWorkExecutionContext) -> Void)?

    func measure<T>(_ step: AudioWorkStep, _ work: () throws -> T) rethrows -> T {
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            let context: AudioWorkExecutionContext = Thread.isMainThread ? .main : .worker
            record(step, duration: ProcessInfo.processInfo.systemUptime - start, executionContext: context)
        }
        return try work()
    }

    /// Reports worker-measured work after it returns to the MainActor.
    func record(_ step: AudioWorkStep, duration: TimeInterval, executionContext: AudioWorkExecutionContext) {
        onMeasured?(step, duration, executionContext)
    }
}
