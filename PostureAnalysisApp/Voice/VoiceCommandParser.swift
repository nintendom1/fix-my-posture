import Foundation

/// Matches the longest known phrase in a transcript. Pure, so it can be tested without audio.
struct VoiceCommandParser: VoiceCommandParsing {
    /// Words that don't count against "nearly the whole utterance".
    static let fillers: Set<String> = ["please", "okay", "ok", "coach", "lets", "hey", "now", "um", "uh", "so", "and"]
    /// Extra non-filler words a destructive command tolerates.
    static let destructiveExtraWords = 2
    /// "Wait" may be "weight" heard wrong, with a number still to come, so it runs only after this much quiet.
    static let weightSoundAlikeSettleTime: TimeInterval = 1.0

    let aliases: [VoiceCommandAlias]
    let preferredWeightUnit: PreferredWeightUnit
    /// Each alias with its normalized words, computed once.
    private let entries: [(alias: VoiceCommandAlias, tokens: [String])]

    init(exercises: [ExerciseDefinition], preferredWeightUnit: PreferredWeightUnit = .lb) {
        aliases = VoiceCommandAlias.standard + VoiceCommandAlias.exerciseSelection(exercises)
        entries = aliases.map { ($0, $0.tokens) }
        self.preferredWeightUnit = preferredWeightUnit
    }

    var vocabulary: [String] {
        var seen = Set<String>()
        let weights = ["weight", "my weights are", "add weight", "pounds", "kilograms", "red band"]
        return (aliases.map(\.display) + weights).filter { seen.insert($0).inserted }
    }

    func parse(_ transcript: String) -> VoiceCommandMatch? {
        // Do not let a streaming "wait 17" partial become a preferred-unit weight before its
        // explicit unit arrives or it settles as the pause command.
        if WeightPhraseParser.isInProgress(transcript) { return nil }
        // A spoken weight can still grow ("17" then "17.5 pounds"), so it waits for the transcript to settle.
        if let weight = WeightPhraseParser.parse(transcript, preferredUnit: preferredWeightUnit) {
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
        if endsTranscript, let last = best.tokens.last, WeightPhraseParser.soundsLikeWeight.contains(last) {
            return VoiceCommandMatch(command: best.alias.command, phrase: best.alias.display, isPrefixOfLongerPhrase: true,
                                     settleTime: Self.weightSoundAlikeSettleTime)
        }
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
