import Foundation

public enum CalibrationKind: String, Codable, CaseIterable, Sendable {
    /// The first calibration.
    case initial
    /// Revisiting calibration from the current prescriptions.
    case recalibration
    /// Calibrating one more family later.
    case addFamily
}

public enum CalibrationStatus: String, Codable, CaseIterable, Sendable {
    case inProgress
    /// The user reached the summary and accepted it; only now do `startingPoints` affect recommendations.
    case committed
    /// The user left before committing; the previous recommendations stay active.
    case abandoned
}

public struct CalibrationStart: Codable, Hashable, Sendable {
    public let family: MovementFamilyID
    public let start: RungDose

    public init(family: MovementFamilyID, start: RungDose) {
        self.family = family
        self.start = start
    }
}

/// One calibration attempt. It is the only fact that is updated in place (its status moves from in progress to
/// committed or abandoned); its probes are separate `AdaptiveEvidence` with this record's id.
public struct CalibrationSessionRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let kind: CalibrationKind
    public let startedAt: Date
    public var endedAt: Date?
    public var status: CalibrationStatus
    public var families: [MovementFamilyID]
    /// The quiz's equipment answer, when the quiz asked.
    public var equipment: [TrainingEquipment]?
    /// The accepted starting point per family; empty until committed.
    public var startingPoints: [CalibrationStart]

    public init(id: UUID, kind: CalibrationKind, startedAt: Date, endedAt: Date? = nil,
                status: CalibrationStatus = .inProgress, families: [MovementFamilyID] = [],
                equipment: [TrainingEquipment]? = nil, startingPoints: [CalibrationStart] = []) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.families = families
        self.equipment = equipment
        self.startingPoints = startingPoints
    }

    /// Whether `newer` may replace this stored record: the same attempt (id, kind, start time), and either this record
    /// is still in progress or `newer` is identical. A committed or abandoned attempt never changes; a new attempt
    /// needs a new id.
    public func canBeReplaced(by newer: CalibrationSessionRecord) -> Bool {
        guard newer.id == id, newer.kind == kind, newer.startedAt == startedAt else { return false }
        return status == .inProgress || newer == self
    }
}
