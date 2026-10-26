import Foundation

/// "Mark that", "flag that", or "note, …" during a recorded workout starts a marker; whatever follows is its note.
/// `WorkoutVoiceController` checks it before every command, so a note may say "pause" or "wait 17" without running it.
enum MarkerPhraseParser {
    struct Marker: Equatable {
        /// The words after the trigger, as heard; nil when nothing followed.
        var note: String?
    }

    static let triggers: [[String]] = [["mark", "that"], ["flag", "that"]]
    /// Starts a marker only as the first word that isn't a filler.
    static let noteWord = "note"
    /// Hints for the recognizer while markers are on.
    static let vocabulary = ["mark that", "flag that", "note"]
    /// Longer notes are cut, so a microphone left listening can't fill the recording.
    static let maximumNoteLength = 280
    /// A marker's note ends once nothing new has been heard for this long.
    static let settleTime: TimeInterval = 1.5

    static func parse(_ transcript: String) -> Marker? {
        let tokens = words(in: transcript)
        let words = tokens.map(\.word)
        if let first = words.firstIndex(where: { !VoiceCommandParser.fillers.contains($0) }), words[first] == noteWord {
            return Marker(note: note(in: transcript, after: tokens[first].range))
        }
        for trigger in triggers where words.count >= trigger.count {
            for start in 0...(words.count - trigger.count) where Array(words[start..<(start + trigger.count)]) == trigger {
                return Marker(note: note(in: transcript, after: tokens[start + trigger.count - 1].range))
            }
        }
        return nil
    }

    /// Text heard after a marker's trigger, trimmed and cut to `maximumNoteLength`; nil when empty.
    static func trimmedNote(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumNoteLength))
    }

    /// Words split where `VoiceCommandParser.normalize` splits them, with where each sits in the transcript.
    private static func words(in text: String) -> [(word: String, range: Range<String.Index>)] {
        var tokens: [(word: String, range: Range<String.Index>)] = []
        var start: String.Index?
        var index = text.startIndex
        while index <= text.endIndex {
            let isWordCharacter = index < text.endIndex
                && (text[index].isLetter || text[index].isNumber || text[index] == "'" || text[index] == "’")
            if isWordCharacter, start == nil { start = index }
            if !isWordCharacter, let begin = start {
                let word = VoiceCommandParser.normalize(String(text[begin..<index])).joined()
                if !word.isEmpty { tokens.append((word, begin..<index)) }
                start = nil
            }
            guard index < text.endIndex else { break }
            index = text.index(after: index)
        }
        return tokens
    }

    private static func note(in text: String, after range: Range<String.Index>) -> String? {
        trimmedNote(String(text[range.upperBound...]))
    }
}
