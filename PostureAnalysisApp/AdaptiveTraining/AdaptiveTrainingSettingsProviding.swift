import AdaptiveTraining
import Foundation

/// What the Adaptive Training settings page reads and changes. The engine decides what each change means; the page
/// only shows the overview and reports the user's choices.
@MainActor
protocol AdaptiveTrainingSettingsProviding: AnyObject {
    /// The areas, what could be added, and the equipment; nil when the facts couldn't be read.
    func overview() -> AdaptiveTrainingOverview?
    /// Takes an area out of the rotation. Its history stays. False when it couldn't be saved or isn't allowed.
    func removeArea(_ family: MovementFamilyID, asOf now: Date) -> Bool
    /// Records the equipment the user has now. False when it couldn't be saved.
    func setEquipment(_ equipment: Set<TrainingEquipment>, asOf now: Date) -> Bool
    /// A plain name for a rung, such as "Wall Push-Up".
    func displayName(of variant: VariantID) -> String
}
