import Foundation

/// What an exercise is done with, which decides what kind of weight can be recorded.
enum ExerciseEquipment: Equatable {
    case dumbbells
    case band
    case bodyweight
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case pounds
    case kilograms

    var id: Self { self }
    var symbol: String { self == .pounds ? "lb" : "kg" }
    var spokenName: String { self == .pounds ? "pounds" : "kilograms" }
}

/// The load for a set: a mass per dumbbell in the unit the user gave, or a band's label.
enum WorkoutWeight: Codable, Equatable {
    case mass(Double, WeightUnit)
    case band(String)

    /// "17.5 lb", "8 kg", or "Red band".
    var label: String {
        switch self {
        case .mass(let value, let unit): return "\(Self.number(value)) \(unit.symbol)"
        case .band(let name): return name
        }
    }

    /// "17.5 pounds" or "Red band".
    var spokenLabel: String {
        switch self {
        case .mass(let value, let unit): return "\(Self.number(value)) \(value == 1 ? String(unit.spokenName.dropLast()) : unit.spokenName)"
        case .band(let name): return name
        }
    }

    /// Whole numbers without a decimal point; otherwise up to two decimals.
    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%g", (value * 100).rounded() / 100)
    }
}
