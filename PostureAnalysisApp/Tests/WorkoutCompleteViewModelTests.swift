import XCTest
@testable import PostureAnalysisApp

@MainActor
final class WorkoutCompleteViewModelTests: XCTestCase {
    func testStateComesFromTheFinishedRecord() {
        let viewModel = WorkoutCompleteViewModel(record: record(), router: AppRouter())

        XCTAssertEqual(viewModel.state.title, "Workout complete!")
        XCTAssertEqual(viewModel.state.routineName, "Upper Body")
        XCTAssertEqual(viewModel.state.stats.exerciseCount, 1)
        XCTAssertEqual(viewModel.state.stats.totalSets, 2)
        XCTAssertEqual(viewModel.state.stats.totalReps, 19)
        XCTAssertEqual(viewModel.state.stats.durationLabel, "2m")
    }

    func testDoneDismissesWorkoutAndReturnsToTrainRoot() {
        let router = AppRouter(selectedTab: .progress)
        router.setPath([.library, .exercise(id: .shoulderPress)], for: .train)
        router.open(.workout(exerciseID: .shoulderPress, routineID: nil))
        let viewModel = WorkoutCompleteViewModel(record: record(), router: router)

        viewModel.done()

        XCTAssertEqual(router.selectedTab, .train)
        XCTAssertTrue(router.path(for: .train).isEmpty)
        XCTAssertNil(router.presentedFullScreenRoute)
    }

    func testViewHistoryDismissesWorkoutAndRoutesToHistory() {
        let router = AppRouter()
        router.open(.workout(exerciseID: .shoulderPress, routineID: nil))
        let viewModel = WorkoutCompleteViewModel(record: record(), router: router)

        viewModel.viewHistory()

        XCTAssertEqual(router.selectedTab, .progress)
        XCTAssertEqual(router.path(for: .progress).last, .history)
        XCTAssertNil(router.presentedFullScreenRoute)
    }

    private func record() -> WorkoutRecord {
        WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 220),
            planName: "Upper Body",
            entries: [WorkoutRecordEntry(
                exerciseID: .shoulderPress,
                name: "Shoulder Press",
                outcome: nil,
                sets: [RecordedSet(reps: 10, side: nil, weight: nil),
                       RecordedSet(reps: 9, side: nil, weight: nil)]
            )]
        )
    }
}
