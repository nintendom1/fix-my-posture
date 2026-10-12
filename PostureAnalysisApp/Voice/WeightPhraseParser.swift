import Foundation

/// Recognizes a spoken weight: "my weights are 17.5 pounds", "add weight seventeen point five pounds",
/// "weight 8 kilograms", or a band such as "using the red band". Pure, so it can be tested without audio.
///
/// A mass needs a unit and a weight word ("weight", "weights") or "using" before the number, with only number
/// words between, so numbers in other speech never set a weight. Speech recognition often hears "weight" as
/// "wait", so its sound-alikes count as weight words too.
enum WeightPhraseParser {
    static let units: [String: WeightUnit] = [
        "pounds": .pounds, "pound": .pounds, "lbs": .pounds, "lb": .pounds,
        "kilograms": .kilograms, "kilogram": .kilograms, "kilos": .kilograms, "kilo": .kilograms, "kg": .kilograms, "kgs": .kilograms
    ]
    static let bandNames = ["red", "yellow", "green", "blue", "black", "purple", "orange", "gray", "grey", "light", "medium", "heavy"]
    /// What speech recognition commonly writes for "weight".
    static let soundsLikeWeight: Set<String> = ["wait", "waits", "weigh", "weighs", "weighed"]
    private static let cues: Set<String> = Set(["weight", "weights", "using"]).union(soundsLikeWeight)
    /// Words allowed between the weight word and the unit, other than the number itself.
    private static let joiners: Set<String> = ["is", "are", "of", "at", "the", "a", "about"]
    private static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
                               "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]

    static func parse(_ transcript: String) -> WorkoutWeight? {
        let words = tokens(transcript)
        if let band = words.firstIndex(of: "band"), band > 0, bandNames.contains(words[band - 1]) {
            return .band(words[band - 1].capitalized + " band")
        }
        guard let unitIndex = words.firstIndex(where: { units[$0] != nil }), let unit = units[words[unitIndex]],
              let cue = words[..<unitIndex].lastIndex(where: cues.contains) else { return nil }
        let spoken = words[(cue + 1)..<unitIndex].filter { !joiners.contains($0) }
        guard spoken.allSatisfy(isNumberWord), let value = number(Array(spoken)), value > 0, value < 1000 else { return nil }
        return .mass(value, unit)
    }

    /// A weight is still being said: the last weight word is followed by part of a number and nothing else
    /// yet ("wait 17", "weight seventeen point"), so a command shouldn't fire on it.
    static func isInProgress(_ transcript: String) -> Bool {
        let words = tokens(transcript)
        guard let cue = words.lastIndex(where: cues.contains) else { return false }
        let rest = words[(cue + 1)...].filter { !joiners.contains($0) }
        return !rest.isEmpty && rest.allSatisfy(isNumberWord)
    }

    private static func isNumberWord(_ word: String) -> Bool {
        Double(word) != nil || ones.contains(word) || tens[word] != nil || ["point", "and", "half"].contains(word)
    }

    /// Lowercased words, keeping a decimal point between digits ("17.5") as part of the number.
    static func tokens(_ text: String) -> [String] {
        let characters = Array(text.lowercased())
        var cleaned = ""
        for (index, character) in characters.enumerated() {
            let between = index > 0 && index + 1 < characters.count
                && characters[index - 1].isNumber && characters[index + 1].isNumber
            if character.isLetter || character.isNumber || (character == "." && between) {
                cleaned.append(character)
            } else {
                cleaned.append(" ")
            }
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    /// "17.5", "17 point 5", "seventeen point five", "twenty two and a half".
    static func number(_ words: [String]) -> Double? {
        guard !words.isEmpty else { return nil }
        if words.count == 1, let value = Double(words[0]) { return value }
        var whole: Double?
        var index = 0
        // Whole part: digits, or number words such as "twenty two".
        if let digits = Double(words[index]) {
            whole = digits
            index += 1
        } else {
            var total = 0
            var matched = false
            while index < words.count {
                if let value = tens[words[index]] {
                    total += value
                } else if let value = ones.firstIndex(of: words[index]) {
                    total += value
                } else {
                    break
                }
                matched = true
                index += 1
            }
            if matched { whole = Double(total) }
        }
        guard var value = whole else { return nil }
        // "point five" or "point 5": each following digit word is one decimal place.
        if index < words.count, words[index] == "point" {
            index += 1
            var scale = 0.1
            while index < words.count {
                let digit = Int(words[index]) ?? ones.firstIndex(of: words[index]).flatMap { $0 < 10 ? $0 : nil }
                guard let digit, digit < 10 else { break }
                value += Double(digit) * scale
                scale /= 10
                index += 1
            }
        }
        // "and a half"
        if words[index...].contains("half") { value += 0.5 }
        return value
    }
}
