import CoreGraphics
import Foundation

/// A JSON value with ordered object keys, written compactly. Numbers use Swift's shortest round-trip form,
/// so recorded joint positions read back bit for bit, and keys keep the order they were written in.
/// Session recordings use this instead of `JSONEncoder` for every per-frame line.
indirect enum DiagnosticJSON {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([DiagnosticJSON])
    case object([(key: String, value: DiagnosticJSON)])
    /// Already-encoded JSON, written as is.
    case raw(String)

    /// An object that leaves out members whose value is nil.
    static func object(_ members: (String, DiagnosticJSON?)...) -> DiagnosticJSON {
        .object(members.compactMap { key, value in value.map { (key: key, value: $0) } })
    }

    /// A number rounded to `places` decimal places, for derived values whose last digits are noise.
    static func rounded(_ value: Double, places: Int = 4) -> DiagnosticJSON {
        guard value.isFinite else { return .null }
        let scale = pow(10, Double(places))
        return .double((value * scale).rounded() / scale)
    }

    static func number(_ value: Double?) -> DiagnosticJSON? {
        value.map { .double($0) }
    }

    static func number(_ value: CGFloat?) -> DiagnosticJSON? {
        value.map { .double(Double($0)) }
    }

    /// A point as `[x, y]`, exact.
    static func point(_ point: CGPoint) -> DiagnosticJSON {
        .array([.double(Double(point.x)), .double(Double(point.y))])
    }

    /// Sorted, so sets read the same from run to run.
    static func strings<S: Sequence>(_ values: S) -> DiagnosticJSON where S.Element == String {
        .array(values.sorted().map { .string($0) })
    }

    var serialized: String {
        var output = ""
        write(into: &output)
        return output
    }

    func write(into output: inout String) {
        switch self {
        case .null:
            output += "null"
        case .bool(let value):
            output += value ? "true" : "false"
        case .int(let value):
            output += String(value)
        case .double(let value):
            if !value.isFinite {
                output += "null"
            } else if value == value.rounded(), abs(value) < 1e15 {
                // "540" rather than "540.0"; integral doubles read back exactly.
                output += String(Int64(value))
            } else {
                output += "\(value)"
            }
        case .string(let value):
            Self.writeString(value, into: &output)
        case .array(let values):
            output += "["
            for (index, value) in values.enumerated() {
                if index > 0 { output += "," }
                value.write(into: &output)
            }
            output += "]"
        case .object(let members):
            output += "{"
            for (index, member) in members.enumerated() {
                if index > 0 { output += "," }
                Self.writeString(member.key, into: &output)
                output += ":"
                member.value.write(into: &output)
            }
            output += "}"
        case .raw(let json):
            output += json
        }
    }

    private static func writeString(_ value: String, into output: inout String) {
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output += "\""
    }
}

extension DiagnosticJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByFloatLiteral, ExpressibleByArrayLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(arrayLiteral elements: DiagnosticJSON...) { self = .array(elements) }
}
