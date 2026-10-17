import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AppRouteTests: XCTestCase {
    private let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let assessmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let shoulderPress = ExerciseID(rawValue: "shoulder_press")

    func testEveryRouteSurvivesCodableRoundTrip() throws {
        let routes: [AppRoute] = [
            .train, .routines, .routine(id: routineID), .routineEditor(id: nil),
            .routineEditor(id: routineID), .library, .exercise(id: shoulderPress),
            .workout(exerciseID: nil, routineID: nil),
            .workout(exerciseID: shoulderPress, routineID: routineID),
            .workoutComplete, .progress, .history, .posture,
            .assessment(id: assessmentID), .livePostureCheck,
            .photoAssessment(view: .front), .settings, .postureHistory
        ]

        for route in routes {
            let data = try JSONEncoder().encode(route)
            XCTAssertEqual(try JSONDecoder().decode(AppRoute.self, from: data), route, "Round trip for \(route)")
        }
    }

    func testEveryRouteHasAnOwningTab() {
        let expected: [(AppRoute, AppTab)] = [
            (.train, .train), (.routines, .routines), (.routine(id: routineID), .routines),
            (.routineEditor(id: nil), .routines), (.library, .train),
            (.exercise(id: shoulderPress), .train),
            (.workout(exerciseID: shoulderPress, routineID: routineID), .train),
            (.workoutComplete, .train), (.progress, .progress), (.history, .progress),
            (.posture, .posture), (.assessment(id: assessmentID), .posture),
            (.postureHistory, .posture), (.livePostureCheck, .posture),
            (.photoAssessment(view: .leftSide), .posture), (.settings, .train)
        ]

        for (route, tab) in expected {
            XCTAssertEqual(route.owningTab, tab, "Owner for \(route)")
        }
    }

    func testOpeningHistorySelectsProgressAndPushesHistory() {
        let router = AppRouter()

        router.open(.history)

        XCTAssertEqual(router.selectedTab, .progress)
        XCTAssertEqual(router.path(for: .progress), [.history])
    }

    func testOpeningSettingsPresentsFullScreen() {
        let router = AppRouter()

        router.open(.settings)

        XCTAssertEqual(router.presentedFullScreenRoute, .settings)
        XCTAssertEqual(router.path(for: .train), [])
    }

    func testReselectingCurrentTabPopsItsPathToRoot() {
        let router = AppRouter()
        router.open(.routine(id: routineID))
        XCTAssertEqual(router.path(for: .routines), [.routine(id: routineID)])

        router.select(.routines)

        XCTAssertEqual(router.path(for: .routines), [])
    }

    func testOpeningWorkoutPresentsCameraFullScreen() {
        let router = AppRouter()
        let route = AppRoute.workout(exerciseID: shoulderPress, routineID: routineID)

        router.open(route)

        XCTAssertEqual(router.presentedFullScreenRoute, route)
        XCTAssertEqual(router.selectedTab, .train)
    }
}
