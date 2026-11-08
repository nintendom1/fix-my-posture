import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

/// Settings › Adaptive Training: what the page shows for each overview, and the facts each choice records.
@MainActor
final class AdaptiveTrainingSettingsViewModelTests: XCTestCase {
    func testRowValueShowsNotSetUpAndThenJoinsAreaNames() {
        let provider = FakeProvider(overview: overview(needsCalibration: true))
        let viewModel = makeViewModel(provider)
        viewModel.refresh()
        XCTAssertEqual(viewModel.rowValue, "Not set up")

        provider.value = overview(needsCalibration: false, areas: [(.push, "push.wall", 4), (.squat, "squat.air", 3)])
        viewModel.refresh()
        XCTAssertEqual(viewModel.rowValue, "Push · Squat")
    }

    func testAreaLinesUsePlainDisplayNamesAndSummaryCopy() {
        let provider = FakeProvider(overview: overview(needsCalibration: false,
                                                       areas: [(.push, "push.wall", 4), (.squat, "squat.air", 3)]))
        let viewModel = makeViewModel(provider)
        viewModel.refresh()
        XCTAssertEqual(viewModel.areaLines, [
            AdaptiveTrainingSettingsViewModel.AreaLine(family: .push, text: "Push: Wall Push-Up × 4"),
            AdaptiveTrainingSettingsViewModel.AreaLine(family: .squat, text: "Squat: squat.air × 3")
        ])
    }

    func testRemovalRequiresConfirmationAndCanBeCanceled() {
        let provider = FakeProvider(overview: overview(needsCalibration: false,
                                                       areas: [(.push, "push.wall", 4), (.squat, "squat.air", 3)]))
        let viewModel = makeViewModel(provider)
        viewModel.refresh()

        viewModel.requestRemoval(of: .push)
        XCTAssertEqual(viewModel.removalConfirmationTitle, "Remove Push from Today's Session? Its history stays.")
        viewModel.cancelRemoval()
        XCTAssertTrue(provider.removals.isEmpty)

        viewModel.requestRemoval(of: .push)
        viewModel.confirmRemoval()
        XCTAssertEqual(provider.removals, [.push])
    }

    func testOneAreaCannotBeRemovedAndAddAreaFollowsTheOverview() {
        let provider = FakeProvider(overview: overview(needsCalibration: false, areas: [(.push, "push.wall", 4)]))
        let viewModel = makeViewModel(provider)
        viewModel.refresh()
        XCTAssertFalse(viewModel.canRemoveAreas)
        viewModel.requestRemoval(of: .push)
        XCTAssertNil(viewModel.pendingRemoval)

        XCTAssertFalse(viewModel.showsAddArea)
        provider.value = overview(needsCalibration: false, areas: [(.push, "push.wall", 4)], addable: [.squat])
        viewModel.refresh()
        XCTAssertTrue(viewModel.showsAddArea)
    }

    func testEquipmentChangesSendTheFullSet() {
        let provider = FakeProvider(overview: overview(needsCalibration: false,
                                                       areas: [(.push, "push.wall", 4)], equipment: [.dumbbells]))
        let viewModel = makeViewModel(provider)
        viewModel.refresh()
        viewModel.setEquipment(.band, isOn: true)
        XCTAssertEqual(provider.equipmentChanges, [Set([.band, .dumbbells])])
    }

    func testFailedSaveShowsNoticeAndNilOverviewShowsUnavailableState() {
        let provider = FakeProvider(overview: overview(needsCalibration: false,
                                                       areas: [(.push, "push.wall", 4), (.squat, "squat.air", 3)]))
        provider.removeResult = false
        let viewModel = makeViewModel(provider)
        viewModel.refresh()
        viewModel.requestRemoval(of: .push)
        viewModel.confirmRemoval()
        XCTAssertEqual(viewModel.notice, AdaptiveTrainingSettingsCopy.saveFailed)

        provider.value = nil
        viewModel.refresh()
        XCTAssertFalse(viewModel.isAvailable)
    }

    func testCalibrationButtonsRequestTheirMatchingKinds() {
        let provider = FakeProvider(overview: overview(needsCalibration: true))
        var kinds: [CalibrationKind] = []
        let viewModel = AdaptiveTrainingSettingsViewModel(provider: provider,
                                                          openCalibration: { kinds.append($0) })
        viewModel.findStartingPoint()
        viewModel.recalibrate()
        viewModel.addArea()
        XCTAssertEqual(kinds, [.initial, .recalibration, .addFamily])
    }

    private func makeViewModel(_ provider: FakeProvider) -> AdaptiveTrainingSettingsViewModel {
        AdaptiveTrainingSettingsViewModel(provider: provider, now: { Date(timeIntervalSince1970: 100) },
                                          openCalibration: { _ in })
    }

    private func overview(needsCalibration: Bool, areas: [(MovementFamilyID, String, Int)] = [],
                          addable: [MovementFamilyID] = [], equipment: Set<TrainingEquipment> = [])
        -> AdaptiveTrainingOverview {
        AdaptiveTrainingOverview(
            needsCalibration: needsCalibration,
            areas: areas.map { AdaptiveTrainingOverview.Area(family: $0.0,
                                                              current: RungDose(variant: VariantID(rawValue: $0.1),
                                                                                dose: .reps($0.2))) },
            addableFamilies: addable,
            equipment: equipment.sorted()
        )
    }

    @MainActor
    private final class FakeProvider: AdaptiveTrainingSettingsProviding {
        var value: AdaptiveTrainingOverview?
        var removeResult = true
        var equipmentResult = true
        private(set) var removals: [MovementFamilyID] = []
        private(set) var equipmentChanges: [Set<TrainingEquipment>] = []

        init(overview: AdaptiveTrainingOverview?) { value = overview }
        func overview() -> AdaptiveTrainingOverview? { value }
        func removeArea(_ family: MovementFamilyID, asOf now: Date) -> Bool {
            removals.append(family)
            return removeResult
        }
        func setEquipment(_ equipment: Set<TrainingEquipment>, asOf now: Date) -> Bool {
            equipmentChanges.append(equipment)
            return equipmentResult
        }
        func displayName(of variant: VariantID) -> String {
            switch variant.rawValue {
            case "push.wall": return "Wall Push-Up"
            default: return variant.rawValue
            }
        }
    }
}
