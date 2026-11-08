import Foundation

/// What Settings shows about Adaptive Training: the areas in the rotation, what could be added, and the equipment.
/// The engine derives it from the profile; the app only shows it.
public struct AdaptiveTrainingOverview: Hashable, Sendable {
    /// One area in the rotation and what it prescribes now.
    public struct Area: Hashable, Sendable {
        public let family: MovementFamilyID
        public let current: RungDose

        public init(family: MovementFamilyID, current: RungDose) {
            self.family = family
            self.current = current
        }
    }

    /// True until a calibration has been committed.
    public let needsCalibration: Bool
    /// Active families with their current prescription, in catalog order.
    public let areas: [Area]
    /// Families that aren't active and can be offered with the built exercises and current equipment, in catalog
    /// order.
    public let addableFamilies: [MovementFamilyID]
    /// The equipment the profile knows about, sorted.
    public let equipment: [TrainingEquipment]

    public init(needsCalibration: Bool, areas: [Area], addableFamilies: [MovementFamilyID],
                equipment: [TrainingEquipment]) {
        self.needsCalibration = needsCalibration
        self.areas = areas
        self.addableFamilies = addableFamilies
        self.equipment = equipment
    }

    /// The rotation always keeps at least one area, so the last one can't be removed.
    public var canRemoveAreas: Bool { areas.count > 1 }
}
