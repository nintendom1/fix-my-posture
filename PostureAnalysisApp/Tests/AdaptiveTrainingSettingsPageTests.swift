import AdaptiveTraining
import SwiftUI
import XCTest
@testable import PostureAnalysisApp

/// Settings › Adaptive Training renders each state, and the Settings home shows its group only when it's available.
@MainActor
final class AdaptiveTrainingSettingsPageTests: XCTestCase {
    func testNotCalibratedStateRendersItsDescriptionAndButton() throws {
        let provider = FakeProvider(value: makeOverview(needsCalibration: true))
        let viewModel = makeViewModel(provider)
        viewModel.refresh()
        XCTAssertTrue(viewModel.needsCalibration)
        XCTAssertEqual(AdaptiveTrainingSettingsCopy.initialDescription,
                       "Find a comfortable starting point in a few minutes. A few tiny samples, then a short session each day.")
        try render(AdaptiveTrainingSettingsPage(viewModel: viewModel), id: "adaptive-settings-not-calibrated")
        XCTAssertEqual(viewModel.pageSections.map(\.id), ["notCalibrated"])
    }

    func testCalibratedStateRendersAreasAddRecalibrateAndEquipment() throws {
        let provider = FakeProvider(value: makeOverview(needsCalibration: false,
                                                        areas: [(.push, "push.wall", 4), (.squat, "squat.air", 3)],
                                                        addable: [.row], equipment: [.dumbbells]))
        let viewModel = makeViewModel(provider)
        viewModel.refresh()
        XCTAssertEqual(viewModel.areaLines.map(\.text), ["Push: push.wall × 4", "Squat: squat.air × 3"])
        XCTAssertTrue(viewModel.canRemoveAreas)
        XCTAssertTrue(viewModel.showsAddArea)
        try render(AdaptiveTrainingSettingsPage(viewModel: viewModel), id: "adaptive-settings-calibrated")
        let sections = viewModel.pageSections
        XCTAssertEqual(sections.map(\.id), ["areas", "addArea", "recalibrate", "equipment"])
        guard case .areas(let rows, let canRemove)? = sections.first else {
            return XCTFail("The calibrated page should begin with its area rows.")
        }
        XCTAssertEqual(rows.map(\.family), [.push, .squat])
        XCTAssertTrue(canRemove)
        guard case .equipment(let equipment)? = sections.last else {
            return XCTFail("The calibrated page should end with equipment controls.")
        }
        XCTAssertEqual(equipment, TrainingEquipment.allCases)

        let oneArea = makeViewModel(FakeProvider(value: makeOverview(needsCalibration: false,
                                                                      areas: [(.push, "push.wall", 4)])))
        oneArea.refresh()
        try render(AdaptiveTrainingSettingsPage(viewModel: oneArea), id: "adaptive-settings-one-area")
        guard case .areas(let singleAreaRows, let canRemoveSingleArea)? = oneArea.pageSections.first else {
            return XCTFail("The one-area page should render its area section.")
        }
        XCTAssertEqual(singleAreaRows.map(\.family), [.push])
        XCTAssertFalse(canRemoveSingleArea)
        XCTAssertFalse(oneArea.pageSections.map(\.id).contains("addArea"))
    }

    func testUnavailableStateRendersWithoutSettingsControls() throws {
        let viewModel = makeViewModel(FakeProvider(value: nil))
        viewModel.refresh()
        XCTAssertFalse(viewModel.isAvailable)
        try render(AdaptiveTrainingSettingsPage(viewModel: viewModel), id: "adaptive-settings-unavailable")
        XCTAssertEqual(viewModel.pageSections.map(\.id), ["unavailable"])
    }

    func testSettingsHomeAddsItsRowOnlyWhenTheProviderIsAvailable() throws {
        let without = SettingsViewModel(preferences: InMemoryPreferences(), router: AppRouter())
        XCTAssertNil(without.adaptiveTraining)
        try render(SettingsScreen(viewModel: without), id: "settings-without-adaptive-training")
        XCTAssertEqual(without.homeSections, [])

        let provider = FakeProvider(value: makeOverview(needsCalibration: false,
                                                        areas: [(.push, "push.wall", 4), (.squat, "squat.air", 3)]))
        let adaptive = makeViewModel(provider)
        let with = SettingsViewModel(preferences: InMemoryPreferences(), router: AppRouter())
        with.adaptiveTraining = adaptive
        XCTAssertNotNil(with.adaptiveTraining)
        try render(SettingsScreen(viewModel: with), id: "settings-with-adaptive-training")
        XCTAssertEqual(with.homeSections, [.adaptiveTraining])
        XCTAssertEqual(adaptive.rowValue, "Push · Squat")
        XCTAssertEqual(provider.overviewCalls, 1)
        XCTAssertEqual(with.path, [], "Settings home renders without opening the Adaptive Training page.")

        provider.value = makeOverview(needsCalibration: true)
        try render(SettingsScreen(viewModel: with), id: "settings-reappeared")
        XCTAssertEqual(with.homeSections, [.adaptiveTraining])
        XCTAssertEqual(adaptive.rowValue, "Not set up")
        XCTAssertEqual(provider.overviewCalls, 2)
    }

    private func render<Content: View>(_ view: Content, id: String,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let result = try SnapshotHost.render(view, frameId: id, testCase: self)
        XCTAssertGreaterThan(result.image.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(result.image.size.height, 0, file: file, line: line)
    }

    private func makeViewModel(_ provider: FakeProvider) -> AdaptiveTrainingSettingsViewModel {
        AdaptiveTrainingSettingsViewModel(provider: provider, openCalibration: { _ in })
    }

    private func makeOverview(needsCalibration: Bool, areas: [(MovementFamilyID, String, Int)] = [],
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
        private(set) var overviewCalls = 0
        init(value: AdaptiveTrainingOverview?) { self.value = value }
        func overview() -> AdaptiveTrainingOverview? {
            overviewCalls += 1
            return value
        }
        func removeArea(_ family: MovementFamilyID, asOf now: Date) -> Bool { true }
        func setEquipment(_ equipment: Set<TrainingEquipment>, asOf now: Date) -> Bool { true }
        func displayName(of variant: VariantID) -> String { variant.rawValue }
    }
}
