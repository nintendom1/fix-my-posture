import Foundation

/// A command recognized in a spoken transcript.
struct VoiceCommandMatch: Equatable {
    let command: WorkoutCommand
    /// The alias that matched, as displayed, for the "Heard" chip.
    let phrase: String
    /// The match ends the transcript and is the start of a longer phrase with a different meaning
    /// ("start" could become "start over"), so it should wait for a final or settled transcript.
    let isPrefixOfLongerPhrase: Bool
}

protocol VoiceCommandParsing {
    /// Phrases to hint to the recognizer.
    var vocabulary: [String] { get }
    func parse(_ transcript: String) -> VoiceCommandMatch?
}

/// One spoken phrase and what it does. Destructive commands only count when they are nearly
/// the whole utterance, so they can't fire from a stray word in conversation.
/// This table drives both the parser and the in-app Voice Commands help.
struct VoiceCommandAlias: Equatable {
    /// Natural spelling for display ("let's go").
    let display: String
    let command: WorkoutCommand
    let isDestructive: Bool

    /// Normalized words the parser matches ("lets", "go").
    var tokens: [String] { VoiceCommandParser.normalize(display) }
}

extension VoiceCommandAlias {
    /// Every command except exercise names. The first phrase for each command is its help title.
    static let standard: [VoiceCommandAlias] = {
        func aliases(_ phrases: [String], _ command: WorkoutCommand, destructive: Bool = false) -> [VoiceCommandAlias] {
            phrases.map { VoiceCommandAlias(display: $0, command: command, isDestructive: destructive) }
        }
        return aliases(["start", "begin", "let's go", "start set", "start the set"], .start)
            + aliases(["pause", "stop", "hold on", "wait", "stop workout", "stop the workout"], .pause)
            + aliases(["resume", "continue", "keep going", "unpause"], .resume)
            + aliases(["start over", "restart", "restart set", "restart this set", "restart the set",
                       "reset set", "reset the set"], .restartSet, destructive: true)
            + aliases(["next set", "finish set", "finish this set", "finish the set", "end set",
                       "end this set", "end the set"], .nextSet, destructive: true)
            + aliases(["change exercise", "change exercises", "switch exercise", "switch exercises",
                       "different exercise"], .changeExercise, destructive: true)
            + aliases(["another round", "one more round", "next round", "go again"], .anotherRound)
            + aliases(["next exercise", "skip exercise", "skip this exercise", "skip the exercise"], .nextExercise, destructive: true)
            + aliases(["cancel", "never mind", "nevermind"], .cancel)
            + aliases(["how many reps", "how many", "rep count", "what's my count"], .repCount)
            + aliases(["which set", "what set", "what set am I on", "which set am I on"], .whichSet)
            + aliases(["repeat that", "repeat", "say that again", "say again"], .repeatLast)
            + aliases(["what can I say", "help", "voice commands", "show commands", "show voice commands"], .help)
            + aliases(["close", "close help", "done", "go back", "hide help"], .closeHelp)
            + aliases(["mute", "mute coach", "mute voice", "be quiet", "quiet"], .muteCoach, destructive: true)
            + aliases(["unmute", "unmute coach", "talk to me"], .unmuteCoach)
            + aliases(["stop listening", "mute microphone", "mute mic"], .muteMicrophone, destructive: true)
            + aliases(["end workout", "end the workout", "finish workout", "finish the workout",
                       "quit workout", "quit the workout"], .endWorkout, destructive: true)
    }()

    /// "[switch to | let's do | do] <exercise> [instead]" for every catalog alias.
    static func exerciseSelection(_ exercises: [ExerciseDefinition]) -> [VoiceCommandAlias] {
        exercises.flatMap { exercise in
            exercise.voiceAliases.flatMap { name in
                ["", "switch to ", "let's do ", "do "].flatMap { prefix in
                    ["", " instead"].map { suffix in
                        VoiceCommandAlias(display: prefix + name + suffix, command: .selectExercise(exercise.id), isDestructive: true)
                    }
                }
            }
        }
    }
}
