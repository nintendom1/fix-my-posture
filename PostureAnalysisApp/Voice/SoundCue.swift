import Foundation

/// Semantic sound cue identifiers for future game audio (#132 phase 2). No sounds play.
enum SoundCueID: String, CaseIterable, Sendable {
    case repCounted = "rep.counted"
    case setCompleted = "set.completed"
    case restStarted = "rest.started"
    case restEnding = "rest.ending"
    case workoutCompleted = "workout.completed"
    case menuSelect = "menu.select"
    case dialogueAdvance = "dialogue.advance"
}

/// Policy labels for future shared audio playback; they do not change current mixing.
enum AudioDuckingPolicy: String, CaseIterable, Sendable {
    case pauseDuringRecognition
    case duckForSpeech
    case unaffected
}

/// Relative future playback priority: speech above sound effects above background music.
enum AudioPriority: Int, CaseIterable, Sendable {
    case backgroundMusic = 0
    case soundEffect = 1
    case speech = 2

    var recognitionPolicy: AudioDuckingPolicy {
        switch self {
        case .backgroundMusic, .soundEffect: .pauseDuringRecognition
        case .speech: .unaffected
        }
    }

    var speechPolicy: AudioDuckingPolicy {
        switch self {
        case .backgroundMusic, .soundEffect: .duckForSpeech
        case .speech: .unaffected
        }
    }
}

/// Future background-music playback contract. No implementation or production caller exists in this phase.
protocol BackgroundMusicPlaying: AnyObject {
    func play(trackID: String)
    func pause()
    func resume()
    func stop()
}

/// Future sound-effect playback contract. No implementation or production caller exists in this phase.
protocol SoundEffectPlaying: AnyObject {
    func play(_ cue: SoundCueID)
}
