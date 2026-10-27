import Foundation

/// A change to how an exercise is performed that is small enough not to need its own exercise.
public enum PrescriptionModifier: String, Codable, CaseIterable, Comparable, Sendable {
    /// A shorter movement, such as a shallow wall push-up or a partial sit-to-stand.
    case reducedRange
    /// Holding a wall, chair, or counter for balance.
    case supported

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Equipment a rung needs beyond the body, a wall, and a chair.
public enum TrainingEquipment: String, Codable, CaseIterable, Comparable, Sendable {
    case dumbbells
    case band

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One step on a movement family's ladder.
public struct ProgressionRung: Hashable, Codable, Identifiable, Sendable {
    public let id: VariantID
    /// The app's stable exercise key (`ExerciseID.rawValue`), such as `wall_push_up`.
    public let exerciseID: String
    public let modifiers: [PrescriptionModifier]
    public let doseRange: DoseRange
    public let requiredEquipment: [TrainingEquipment]
    /// True only for the family's explicit floor: where the policy goes when one rep of anything harder is too hard.
    public let isFloor: Bool

    public init(id: VariantID, exerciseID: String, modifiers: [PrescriptionModifier] = [], doseRange: DoseRange,
                requiredEquipment: [TrainingEquipment] = [], isFloor: Bool = false) {
        self.id = id
        self.exerciseID = exerciseID
        self.modifiers = Array(Set(modifiers)).sorted()
        self.doseRange = doseRange
        self.requiredEquipment = Array(Set(requiredEquipment)).sorted()
        self.isFloor = isFloor
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case exerciseID
        case modifiers
        case doseRange
        case requiredEquipment
        case isFloor
    }

    /// Decodes through the normalizing initializer, so modifiers and equipment come back sorted and unique.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(VariantID.self, forKey: .id),
                  exerciseID: try container.decode(String.self, forKey: .exerciseID),
                  modifiers: try container.decode([PrescriptionModifier].self, forKey: .modifiers),
                  doseRange: try container.decode(DoseRange.self, forKey: .doseRange),
                  requiredEquipment: try container.decode([TrainingEquipment].self, forKey: .requiredEquipment),
                  isFloor: try container.decode(Bool.self, forKey: .isFloor))
    }

    /// The smallest prescription on this rung.
    public var minimumDose: Dose { doseRange.minimum }
}

/// An ordered ladder of rungs for one movement pattern, easiest first. The first rung is the explicit floor.
public struct MovementFamily: Hashable, Codable, Identifiable, Sendable {
    public let id: MovementFamilyID
    /// Developer-facing name for the debug view and exports; user-facing copy lives in the app.
    public let debugName: String
    public let rungs: [ProgressionRung]

    public init(id: MovementFamilyID, debugName: String, rungs: [ProgressionRung]) {
        self.id = id
        self.debugName = debugName
        self.rungs = rungs
    }

    public var floor: ProgressionRung? { rungs.first(where: \.isFloor) }

    public func index(of variant: VariantID) -> Int? {
        rungs.firstIndex { $0.id == variant }
    }
}

/// What the device can offer right now: which exercises the app has built, and what equipment the user has.
/// A value, not a callback, so a replay or an export reproduces the same decisions.
public struct Availability: Hashable, Codable, Sendable {
    public var builtExerciseIDs: Set<String>
    public var equipment: Set<TrainingEquipment>

    public init(builtExerciseIDs: Set<String>, equipment: Set<TrainingEquipment> = []) {
        self.builtExerciseIDs = builtExerciseIDs
        self.equipment = equipment
    }

    public func isAvailable(_ rung: ProgressionRung) -> Bool {
        builtExerciseIDs.contains(rung.exerciseID) && rung.requiredEquipment.allSatisfy(equipment.contains)
    }

    private enum CodingKeys: String, CodingKey {
        case builtExerciseIDs
        case equipment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        builtExerciseIDs = Set(try container.decode([String].self, forKey: .builtExerciseIDs))
        equipment = Set(try container.decode([TrainingEquipment].self, forKey: .equipment))
    }

    /// Encodes sets as sorted arrays so exports diff cleanly.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(builtExerciseIDs.sorted(), forKey: .builtExerciseIDs)
        try container.encode(equipment.sorted(), forKey: .equipment)
    }
}

/// A rung and a dose: the unit of every prescription.
public struct RungDose: Hashable, Codable, Sendable, CustomStringConvertible {
    public let variant: VariantID
    public let dose: Dose

    public init(variant: VariantID, dose: Dose) {
        self.variant = variant
        self.dose = dose
    }

    public var description: String { "\(variant.rawValue) × \(dose)" }
}
