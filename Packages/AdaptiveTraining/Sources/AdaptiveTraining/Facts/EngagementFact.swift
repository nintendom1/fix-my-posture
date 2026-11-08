import Foundation

/// Engagement, not capacity: these change confidence and copy at most, never a rung or dose.
public enum EngagementKind: String, Codable, CaseIterable, Sendable {
    case notificationOpened
    case notificationDismissed
    /// The user explicitly chose to skip today's session.
    case sessionSkipped
}

public struct EngagementFact: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let kind: EngagementKind
    public let family: MovementFamilyID?
    public let prescriptionID: UUID?

    public init(id: UUID, recordedAt: Date, kind: EngagementKind, family: MovementFamilyID? = nil,
                prescriptionID: UUID? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.kind = kind
        self.family = family
        self.prescriptionID = prescriptionID
    }
}

/// A user choice about what to train with, outside calibration.
public enum SettingsKind: String, Codable, CaseIterable, Sendable {
    case equipmentChanged
    case familyRemoved
}

public struct SettingsFact: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let kind: SettingsKind
    /// The new equipment, for `equipmentChanged`.
    public let equipment: [TrainingEquipment]?
    /// The family, for `familyRemoved`.
    public let family: MovementFamilyID?

    public init(id: UUID, recordedAt: Date, kind: SettingsKind, equipment: [TrainingEquipment]? = nil,
                family: MovementFamilyID? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.kind = kind
        self.equipment = equipment.map { Array(Set($0)).sorted() }
        self.family = family
    }
}
