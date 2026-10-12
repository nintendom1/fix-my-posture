import Foundation

/// Matches the longest known phrase in a transcript. Pure, so it can be tested without audio.
struct VoiceCommandParser: VoiceCommandParsing {
    /// Words that don't count against "nearly the whole utterance".
    static let fillers: Set<String> = ["please", "okay", "ok", "coach", "lets", "hey", "now", "um", "uh", "so", "and"]
    /// Extra non-filler words a destructive command tolerates.
    static let destructiveExtraWords = 2

    let aliases: [VoiceCommandAlias]
    /// Each alias with its normalized words, computed once.
    private let entries: [(alias: VoiceCommandAlias, tokens: [String])]

    init(exercises: [ExerciseDefinition]) {
        aliases = VoiceCommandAlias.standard + VoiceCommandAlias.exerciseSelection(exercises)
        entries = aliases.map { ($0, $0.tokens) }
    }

    var vocabulary: [String] {
        var seen = Set<String>()
        let weights = ["my weights are", "add weight", "pounds", "kilograms", "red band"]
        return (aliases.map(\.display) + weights).filter { seen.insert($0).inserted }
    }

    func parse(_ transcript: String) -> VoiceCommandMatch? {
        // A spoken weight can still grow ("17" then "17.5 pounds"), so it waits for the transcript to settle.
        if let weight = WeightPhraseParser.parse(transcript) {
            return VoiceCommandMatch(command: .setWeight(weight), phrase: "Weight \(weight.label)", isPrefixOfLongerPhrase: true)
        }
        let words = Self.normalize(transcript)
        guard !words.isEmpty else { return nil }

        var candidates: [(alias: VoiceCommandAlias, tokens: [String], end: Int)] = []
        for (alias, tokens) in entries where tokens.count <= words.count {
            for start in 0...(words.count - tokens.count) where Array(words[start..<(start + tokens.count)]) == tokens {
                candidates.append((alias, tokens, start + tokens.count))
            }
        }
        // Longest phrase wins; among equals, the most recent words win.
        candidates.sort { lhs, rhs in
            lhs.tokens.count != rhs.tokens.count ? lhs.tokens.count > rhs.tokens.count : lhs.end > rhs.end
        }
        let meaningfulWords = words.filter { !Self.fillers.contains($0) }.count
        guard let best = candidates.first(where: { candidate in
            !candidate.alias.isDestructive
                || meaningfulWords - candidate.tokens.filter({ !Self.fillers.contains($0) }).count <= Self.destructiveExtraWords
        }) else { return nil }

        let endsTranscript = best.end == words.count
        let isPrefix = endsTranscript && entries.contains { other in
            other.alias.command != best.alias.command && other.tokens.count > best.tokens.count
                && Array(other.tokens.prefix(best.tokens.count)) == best.tokens
        }
        return VoiceCommandMatch(command: best.alias.command, phrase: best.alias.display, isPrefixOfLongerPhrase: isPrefix)
    }

    /// Lowercase words without punctuation or apostrophes ("Let's go!" becomes ["lets", "go"]).
    static func normalize(_ text: String) -> [String] {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }
}
