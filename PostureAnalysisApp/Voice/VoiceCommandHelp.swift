import Foundation

/// The in-app Voice Commands list, generated from the parser's alias table so it shows exactly
/// what is recognized. Only the short descriptions live here.
enum VoiceCommandHelp {
    struct Entry: Identifiable, Equatable {
        let command: WorkoutCommand
        /// The main phrase, capitalized for display.
        let title: String
        let detail: String
        let alternates: [String]
        /// Must be said nearly on its own to count.
        let isDestructive: Bool

        var id: String { title }
    }

    struct Section: Identifiable, Equatable {
        let title: String
        let entries: [Entry]

        var id: String { title }
    }

    static func sections(exercises: [ExerciseDefinition]) -> [Section] {
        func entries(_ items: [(WorkoutCommand, String)]) -> [Entry] {
            items.compactMap { command, detail in entry(command, detail: detail) }
        }
        let exerciseEntries = exercises.compactMap { exercise -> Entry? in
            guard let name = exercise.voiceAliases.first else { return nil }
            return Entry(command: .selectExercise(exercise.id), title: capitalized(name),
                         detail: "Switches to \(exercise.displayName). \u{201C}Switch to \u{2026}\u{201D} and \u{201C}\u{2026} instead\u{201D} work too.",
                         alternates: Array(exercise.voiceAliases.dropFirst()), isDestructive: true)
        }
        return [
            Section(title: "Sets", entries: entries([
                (.start, "Begins the set, or the next set after rest."),
                (.pause, "Pauses counting during a set."),
                (.resume, "Continues a paused set."),
                (.restartSet, "Restarts the current set from zero."),
                (.nextSet, "Finishes this set and starts rest, or starts the next set after rest.")
            ])),
            Section(title: "Exercises", entries: entries([(.changeExercise, "Asks which exercise to switch to.")])
                + exerciseEntries
                + entries([(.cancel, "Backs out of changing exercise, or closes this list.")])),
            Section(title: "Info", entries: entries([
                (.repCount, "Says your reps so far."),
                (.whichSet, "Says which set you're on."),
                (.repeatLast, "Repeats the last instruction."),
                (.help, "Opens this list."),
                (.closeHelp, "Closes this list.")
            ])),
            Section(title: "Sound", entries: entries([
                (.muteCoach, "Silences the coach. Voice commands keep working."),
                (.unmuteCoach, "Turns the coach's voice back on."),
                (.muteMicrophone, "Stops listening. Tap the microphone to turn it back on.")
            ])),
            Section(title: "Finish", entries: entries([(.endWorkout, "Ends the workout and shows your summary.")]))
        ]
    }

    /// Entries for "Right now", in the order given.
    static func entries(for commands: [WorkoutCommand], exercises: [ExerciseDefinition]) -> [Entry] {
        let all = sections(exercises: exercises).flatMap(\.entries)
        return commands.compactMap { command in all.first { $0.command == command } }
    }

    private static func entry(_ command: WorkoutCommand, detail: String) -> Entry? {
        let aliases = VoiceCommandAlias.standard.filter { $0.command == command }
        guard let main = aliases.first else { return nil }
        return Entry(command: command, title: capitalized(main.display), detail: detail,
                     alternates: aliases.dropFirst().map(\.display), isDestructive: main.isDestructive)
    }

    private static func capitalized(_ phrase: String) -> String {
        phrase.prefix(1).uppercased() + phrase.dropFirst()
    }
}
