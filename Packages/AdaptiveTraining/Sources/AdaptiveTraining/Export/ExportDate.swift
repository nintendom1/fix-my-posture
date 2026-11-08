import Foundation

/// UTC ISO-8601 text for export dates, with nine fractional digits so a date survives the round trip exactly: facts
/// recorded a fraction of a millisecond apart keep their order and their decisions when an export is replayed.
/// Plain integer calendar arithmetic, so encoding a large history doesn't build a formatter per date.
enum ExportDate {
    private static let unixOffset: Int64 = 978_307_200
    private static let nanosPerSecond = 1_000_000_000

    /// "2025-01-15T20:00:00.000123456Z". `fractionDigits` (0–9) shortens the fraction for display.
    static func string(_ date: Date, fractionDigits: Int = 9) -> String {
        let seconds = date.timeIntervalSinceReferenceDate
        var whole = seconds.rounded(.down)
        var nanos = Int(((seconds - whole) * Double(nanosPerSecond)).rounded())
        if nanos >= nanosPerSecond {
            whole += 1
            nanos -= nanosPerSecond
        }
        let unix = Int64(whole) + unixOffset
        let days = floorDivide(unix, 86_400)
        let secondOfDay = Int(unix - days * 86_400)
        let (year, month, day) = civil(fromDays: days)
        var text = String(format: "%04lld-%02d-%02dT%02d:%02d:%02d", year, month, day,
                          secondOfDay / 3_600, secondOfDay / 60 % 60, secondOfDay % 60)
        let digits = min(9, max(0, fractionDigits))
        if digits > 0 {
            let fraction = String(format: "%09d", nanos)
            text += "." + fraction.prefix(digits)
        }
        return text + "Z"
    }

    /// Parses "yyyy-MM-ddTHH:mm:ss[.fraction]Z" with 0–9 fractional digits; nil for anything else.
    static func date(_ text: String) -> Date? {
        let characters = Array(text.utf8)
        guard characters.count >= 20, characters.last == UInt8(ascii: "Z"),
              characters[4] == UInt8(ascii: "-"), characters[7] == UInt8(ascii: "-"),
              characters[10] == UInt8(ascii: "T"), characters[13] == UInt8(ascii: ":"),
              characters[16] == UInt8(ascii: ":"),
              let year = number(characters[0..<4]), let month = number(characters[5..<7]),
              let day = number(characters[8..<10]), let hour = number(characters[11..<13]),
              let minute = number(characters[14..<16]), let second = number(characters[17..<19]),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60
        else { return nil }

        var nanos = 0
        let rest = characters[19..<(characters.count - 1)]
        if !rest.isEmpty {
            let digits = rest.dropFirst()
            guard rest.first == UInt8(ascii: "."), (1...9).contains(digits.count),
                  let fraction = number(digits) else { return nil }
            nanos = fraction * Int(pow(10, Double(9 - digits.count)))
        }
        let days = days(fromCivil: Int64(year), month, day)
        let unix = days * 86_400 + Int64(hour * 3_600 + minute * 60 + second)
        return Date(timeIntervalSinceReferenceDate: Double(unix - unixOffset) + Double(nanos) / Double(nanosPerSecond))
    }

    private static func number(_ bytes: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for byte in bytes {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return bytes.isEmpty ? nil : value
    }

    private static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor)
    }

    // Days since 1970-01-01 and back, for the proleptic Gregorian calendar (Howard Hinnant's algorithms).
    private static func days(fromCivil year: Int64, _ month: Int, _ day: Int) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = floorDivide(y, 400)
        let yearOfEra = y - era * 400
        let shiftedMonth = Int64(month > 2 ? month - 3 : month + 9)
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + Int64(day) - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civil(fromDays days: Int64) -> (year: Int64, month: Int, day: Int) {
        let shifted = days + 719_468
        let era = floorDivide(shifted, 146_097)
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = Int(dayOfYear - (153 * shiftedMonth + 2) / 5 + 1)
        let month = Int(shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9)
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}
