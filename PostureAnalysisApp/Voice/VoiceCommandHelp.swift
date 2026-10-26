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

    /// `includesMarkers` adds the recording-only marker phrases.
    static func sections(exercises: [ExerciseDefinition], includesMarkers: Bool = false) -> [Section] {
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
                (.pause, "Pauses counting during a set. \u{201C}Wait\u{201D} takes a second, in case you meant \u{201C}weight\u{201D}."),
                (.resume, "Continues a paused set."),
                (.restartSet, "Restarts the current set from zero."),
                (.nextSet, "Finishes this set and starts rest, or starts the next set after rest.")
            ])),
            Section(title: "Exercises", entries: entries([(.changeExercise, "Asks which exercise to switch to."),
                                                         (.nextExercise, "In a Saved Set, skips to the next exercise.")])
                + exerciseEntries
                + entries([(.cancel, "Backs out of changing exercise, or closes this list.")])),
            Section(title: "Info", entries: entries([
                (.repCount, "Says your reps so far."),
                (.whichSet, "Says which set you're on."),
                (.repeatLast, "Repeats the last instruction."),
                (.help, "Opens this list."),
                (.closeHelp, "Closes this list.")
            ])),
            Section(title: "Weights", entries: [
                Entry(command: .setWeight(.mass(17.5, .pounds)), title: "My weights are 17.5 pounds",
                      detail: "Records the weight of each dumbbell for this set and the next ones, until you change it. Kilograms and bands work too.",
                      alternates: ["add weight seventeen point five pounds", "weight 8 kilograms", "using the red band"], isDestructive: false)
            ]),
            Section(title: "Sound", entries: entries([
                (.muteCoach, "Silences the coach. Voice commands keep working."),
                (.unmuteCoach, "Turns the coach's voice back on."),
                (.muteMicrophone, "Stops listening. Tap the microphone to turn it back on.")
            ])),
            Section(title: "Finish", entries: entries([
                (.anotherRound, "After the last set, does the exercise again from set 1."),
                (.endWorkout, "Ends the workout and shows your summary.")
            ]))
        ] + (includesMarkers ? [diagnostics] : [])
    }

    /// Recording-only: markers come from `MarkerPhraseParser`, not the alias table.
    static let diagnostics = Section(title: "Diagnostics", entries: [
        Entry(command: .mark(note: nil, heardSecondsAgo: 0), title: "Mark that",
              detail: "Marks this moment in the workout's recording for review later. Keep talking to add a note, or start with \u{201C}Note\u{201D}.",
              alternates: ["flag that", "note, that rep should have counted"], isDestructive: false)
    ])

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
