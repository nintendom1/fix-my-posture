import AdaptiveTraining
import Foundation

/// An effort answer found in a spoken transcript.
struct EffortPhraseMatch: Equatable {
    let effort: EffortFeedback
    /// The alias that matched, as displayed, for the "Heard" chip.
    let phrase: String
}

/// Reads "too hard", "okay", "easy", and a few variants while the effort card is open. It runs on the raw transcript
/// before `VoiceCommandParser`, because "okay" is a filler word there and could never match. An effort phrase is never
/// a workout command, and "skip" is not an effort phrase.
///
/// Only an affirmative answer matches: the phrase plus polite filler words, nothing else. A transcript that carries a
/// command ("okay start"), a negation ("not easy"), or any other word doesn't match, so it reaches the command parser
/// and the card stays open.
enum EffortPhraseParser {
    static let aliases: [(phrase: String, effort: EffortFeedback)] = [
        ("too hard", .tooHard), ("too difficult", .tooHard), ("that was too hard", .tooHard),
        ("okay", .okay), ("ok", .okay), ("fine", .okay), ("good", .okay), ("that was okay", .okay),
        ("easy", .easy), ("too easy", .easy), ("that was easy", .easy)
    ]

    /// The only other words an answer may carry. "Okay" and "ok" are polite here (never a command), but no verb, noun,
    /// or negation is.
    static let politeWords: Set<String> = [
        "please", "um", "uh", "so", "well", "yeah", "yes", "hey", "coach",
        "that", "was", "it", "its", "really", "pretty", "very", "okay", "ok"
    ]

    private static let entries: [(phrase: String, effort: EffortFeedback, tokens: [String])] = aliases.map {
        ($0.phrase, $0.effort, VoiceCommandParser.normalize($0.phrase))
    }

    static func parse(_ transcript: String) -> EffortPhraseMatch? {
        let words = VoiceCommandParser.normalize(transcript)
        guard !words.isEmpty else { return nil }

        var best: (phrase: String, effort: EffortFeedback, range: Range<Int>)?
        for entry in entries where entry.tokens.count <= words.count {
            for start in 0...(words.count - entry.tokens.count) where Array(words[start..<(start + entry.tokens.count)]) == entry.tokens {
                let range = start..<(start + entry.tokens.count)
                // Longest phrase wins; among equals, the most recent words win.
                if let current = best,
                   current.range.count > range.count
                    || (current.range.count == range.count && current.range.upperBound >= range.upperBound) {
                    continue
                }
                best = (entry.phrase, entry.effort, range)
            }
        }
        guard let match = best else { return nil }
        let others = words[..<match.range.lowerBound] + words[match.range.upperBound...]
        guard others.allSatisfy(politeWords.contains) else { return nil }
        return EffortPhraseMatch(effort: match.effort, phrase: match.phrase)
    }
}

/// The user's answer to "Want one more?".
enum BonusAnswer: Equatable {
    case accept
    case decline
}

/// A bonus answer found in a spoken transcript.
struct BonusPhraseMatch: Equatable {
    let answer: BonusAnswer
    /// The alias that matched, as displayed, for the "Heard" chip.
    let phrase: String
}

/// Reads "one more", "yes", "I'm done", "no thanks", and a few variants while the bonus offer is open. Like
/// `EffortPhraseParser`, it runs on the raw transcript before `VoiceCommandParser` and accepts only the phrase plus
/// polite filler words, so "okay start" or "yes end workout" is not an answer and reaches the command parser. A
/// transcript with both an accept and a decline ("yes no") is not an answer either.
enum BonusPhraseParser {
    static let aliases: [(phrase: String, answer: BonusAnswer)] = [
        ("one more", .accept), ("one more rep", .accept), ("sure", .accept), ("yes", .accept),
        ("I'm done", .decline), ("I am done", .decline), ("no thanks", .decline), ("no", .decline),
        ("done", .decline)
    ]

    /// The only other words an answer may carry; no verb, noun, or other answer is polite.
    static let politeWords: Set<String> = [
        "please", "um", "uh", "so", "well", "hey", "coach", "thanks", "thank", "you", "okay", "ok"
    ]

    private static let entries: [(phrase: String, answer: BonusAnswer, tokens: [String])] = aliases.map {
        ($0.phrase, $0.answer, VoiceCommandParser.normalize($0.phrase))
    }

    static func parse(_ transcript: String) -> BonusPhraseMatch? {
        let words = VoiceCommandParser.normalize(transcript)
        guard !words.isEmpty else { return nil }

        var best: (phrase: String, answer: BonusAnswer, range: Range<Int>)?
        for entry in entries where entry.tokens.count <= words.count {
            for start in 0...(words.count - entry.tokens.count) where Array(words[start..<(start + entry.tokens.count)]) == entry.tokens {
                let range = start..<(start + entry.tokens.count)
                // Longest phrase wins; among equals, the most recent words win.
                if let current = best,
                   current.range.count > range.count
                    || (current.range.count == range.count && current.range.upperBound >= range.upperBound) {
                    continue
                }
                best = (entry.phrase, entry.answer, range)
            }
        }
        guard let match = best else { return nil }
        let others = words[..<match.range.lowerBound] + words[match.range.upperBound...]
        guard others.allSatisfy(politeWords.contains) else { return nil }
        return BonusPhraseMatch(answer: match.answer, phrase: match.phrase)
    }
}
