import AdaptiveTraining
import SwiftUI
import XCTest
@testable import PostureAnalysisApp

/// The calibration screen renders each step from the flow, with the real adaptive engine on an in-memory store.
@MainActor
final class CalibrationScreenTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let wall = VariantID(rawValue: "push.wall_push_up")

    private func makeViewModel() -> CalibrationViewModel {
        let store = InMemoryAdaptiveTrainingStore()
        let bridge = ExerciseVariantBridge()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let engine = AdaptiveTrainingEngine(store: store,
                                            builtExerciseIDs: bridge.availability(equipment: []).builtExerciseIDs,
                                            calendar: calendar)
        let coordinator = AdaptiveTrainingCoordinator(engine: engine, bridge: bridge)
        let date = now
        return CalibrationViewModel(coordinator: coordinator, now: { date })
    }

    /// Through the quiz with push and squat, answering push "wall push-up" and squat "Not sure".
    private func quizDone() -> CalibrationViewModel {
        let viewModel = makeViewModel()
        viewModel.begin()
        viewModel.continueFromEquipment()
        viewModel.continueFromAreas()
        viewModel.answerCloseness(wall)
        viewModel.answerCloseness(nil)
        return viewModel
    }

    /// Starts the sample on screen and reports a rating the way the coach would.
    private func rate(_ viewModel: CalibrationViewModel, _ effort: EffortFeedback) throws {
        viewModel.startSample()
        let launch = try XCTUnwrap(viewModel.probeLaunch)
        viewModel.receive(CalibrationProbeResult(launchID: launch.id, effort: effort,
                                                 confirmed: WorkAmount(launch.rungDose.dose)))
    }

    private func render(_ viewModel: CalibrationViewModel, frameId: String) throws {
        let result = try SnapshotHost.render(CalibrationScreen(viewModel: viewModel), frameId: frameId, testCase: self)
        XCTAssertGreaterThan(result.image.size.width, 0)
        XCTAssertGreaterThan(result.image.size.height, 0)
    }

    func testTheQuizRendersEachQuestion() throws {
        let viewModel = makeViewModel()
        viewModel.begin()
        XCTAssertEqual(viewModel.step, .equipment)
        try render(viewModel, frameId: "calibration-equipment")

        viewModel.toggleEquipment(.dumbbells)
        viewModel.continueFromEquipment()
        XCTAssertEqual(viewModel.step, .families)
        try render(viewModel, frameId: "calibration-areas")

        viewModel.continueFromAreas()
        XCTAssertNotNil(viewModel.closenessArea)
        XCTAssertFalse(viewModel.closenessOptions.isEmpty)
        try render(viewModel, frameId: "calibration-closeness")
    }

    func testASampleAndAHarderOfferRender() throws {
        let viewModel = quizDone()
        XCTAssertEqual(viewModel.sample?.isHarderOffer, false)
        try render(viewModel, frameId: "calibration-sample")

        try rate(viewModel, .easy)
        XCTAssertEqual(viewModel.sample?.isHarderOffer, true)
        try render(viewModel, frameId: "calibration-harder-offer")
    }

    func testTheSummaryRendersEveryStartingPoint() throws {
        let viewModel = quizDone()
        try rate(viewModel, .okay)
        try rate(viewModel, .okay)

        XCTAssertEqual(viewModel.summaryLines.count, 2)
        try render(viewModel, frameId: "calibration-summary")
    }

    func testAnEmptySummaryRendersWithOnlyAWayOut() throws {
        let viewModel = quizDone()
        viewModel.skipArea()
        viewModel.skipArea()

        XCTAssertTrue(viewModel.summaryLines.isEmpty)
        try render(viewModel, frameId: "calibration-summary-empty")
    }

    func testTheDoneStateRendersAfterTheStartingPointsAreSaved() throws {
        let viewModel = quizDone()
        try rate(viewModel, .okay)
        try rate(viewModel, .okay)
        viewModel.useThese()

        XCTAssertEqual(viewModel.outcome, .committed)
        try render(viewModel, frameId: "calibration-done")
    }

    func testTheUnavailableViewRenders() throws {
        let result = try SnapshotHost.render(CalibrationUnavailableView(), frameId: "calibration-unavailable",
                                             testCase: self)
        XCTAssertGreaterThan(result.image.size.width, 0)
    }
}
