import XCTest
@testable import PostureAnalysisApp

@MainActor
final class RouteParityTests: XCTestCase {
    private var routineID: UUID { Self.uuid(0x31) }

    func testTrainWorkoutAndQuickStartReplaceThePresentedWorkoutRoute() {
        let router = AppRouter()
        var trace = [state(router)]

        router.open(.workout(exerciseID: .airSquat, routineID: nil))
        trace.append(state(router))
        router.dismissFullScreen()
        trace.append(state(router))
        router.open(.workout(exerciseID: .lateralRaise, routineID: nil))
        trace.append(state(router))

        XCTAssertEqual(trace, [
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=none;calibrating=false",
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=workout(air_squat,-);calibrating=false",
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=none;calibrating=false",
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=workout(lateral_raise,-);calibrating=false"
        ])
    }

    func testRoutineWorkoutCompletesBackIntoTrainPath() {
        let router = AppRouter(selectedTab: .routines)
        var trace = [state(router)]

        router.open(.routine(id: routineID))
        trace.append(state(router))
        router.open(.workout(exerciseID: nil, routineID: routineID))
        trace.append(state(router))
        router.dismissFullScreen()
        trace.append(state(router))
        router.open(.workoutComplete)
        trace.append(state(router))

        XCTAssertEqual(trace, [
            "tab=routines;train=[];routines=[];progress=[];posture=[];cover=none;calibrating=false",
            "tab=routines;train=[];routines=[routine(00000000-0000-4000-8000-000000000031)];progress=[];posture=[];cover=none;calibrating=false",
            "tab=train;train=[];routines=[routine(00000000-0000-4000-8000-000000000031)];progress=[];posture=[];cover=workout(-,00000000-0000-4000-8000-000000000031);calibrating=false",
            "tab=train;train=[];routines=[routine(00000000-0000-4000-8000-000000000031)];progress=[];posture=[];cover=none;calibrating=false",
            "tab=train;train=[workoutComplete];routines=[routine(00000000-0000-4000-8000-000000000031)];progress=[];posture=[];cover=none;calibrating=false"
        ])
    }

    func testTodaySessionPresentsOverTrainWithoutChangingOtherPaths() {
        let router = AppRouter(selectedTab: .progress)
        router.setPath([.history], for: .progress)

        router.open(.todaySession)

        XCTAssertEqual(state(router),
                       "tab=train;train=[];routines=[];progress=[history];posture=[];cover=todaySession;calibrating=false")
    }

    func testCalibrationFromSettingsKeepsSettingsCoverAndIgnoresReminderTap() {
        let router = AppRouter()
        router.present(.settings)
        router.isCalibratingInSettings = true
        let beforeTap = state(router)
        let coordinator = WorkoutReminderCoordinator(
            preferences: InMemoryPreferences(), routines: nil, workoutHistory: nil,
            exerciseCatalog: LiveExerciseCatalog(), router: router, scenarioCatalog: nil
        )

        coordinator.handleTap(.exercise(.airSquat))

        XCTAssertEqual([beforeTap, state(router)], [
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=settings;calibrating=true",
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=settings;calibrating=true"
        ])
    }

    func testReselectingTabPopsOnlyThatTabPath() {
        let router = AppRouter(selectedTab: .routines)
        router.setPath([.routine(id: routineID)], for: .routines)
        router.setPath([.history], for: .progress)
        router.setPath([.assessment(id: Self.uuid(0x32))], for: .posture)

        let before = state(router)
        router.select(.routines)

        XCTAssertEqual([before, state(router)], [
            "tab=routines;train=[];routines=[routine(00000000-0000-4000-8000-000000000031)];progress=[history];posture=[assessment(00000000-0000-4000-8000-000000000032)];cover=none;calibrating=false",
            "tab=routines;train=[];routines=[];progress=[history];posture=[assessment(00000000-0000-4000-8000-000000000032)];cover=none;calibrating=false"
        ])
    }

    func testPresentingAnotherFullScreenRouteReplacesTheCoverAndClearsSettingsCalibration() {
        let router = AppRouter()
        router.present(.settings)
        router.isCalibratingInSettings = true
        var trace = [state(router)]

        router.present(.workout(exerciseID: .airSquat, routineID: nil))
        trace.append(state(router))
        router.dismissFullScreen()
        trace.append(state(router))

        XCTAssertEqual(trace, [
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=settings;calibrating=true",
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=workout(air_squat,-);calibrating=false",
            "tab=train;train=[];routines=[];progress=[];posture=[];cover=none;calibrating=false"
        ])
    }

    private func state(_ router: AppRouter) -> String {
        func path(_ tab: AppTab) -> String {
            "[" + router.path(for: tab).map(routeLabel).joined(separator: ",") + "]"
        }
        let cover = router.presentedFullScreenRoute.map(routeLabel) ?? "none"
        return "tab=\(router.selectedTab.rawValue);train=\(path(.train));routines=\(path(.routines));"
            + "progress=\(path(.progress));posture=\(path(.posture));cover=\(cover);"
            + "calibrating=\(router.isCalibratingInSettings)"
    }

    private func routeLabel(_ route: AppRoute) -> String {
        switch route {
        case .train: return "train"
        case .routines: return "routines"
        case .routine(let id): return "routine(\(id.uuidString))"
        case .routineEditor(let id): return "routineEditor(\(id?.uuidString ?? "new"))"
        case .library: return "library"
        case .exercise(let id): return "exercise(\(id.rawValue))"
        case .workout(let exerciseID, let routineID):
            return "workout(\(exerciseID?.rawValue ?? "-"),\(routineID?.uuidString ?? "-"))"
        case .todaySession: return "todaySession"
        case .calibration: return "calibration"
        case .workoutComplete: return "workoutComplete"
        case .progress: return "progress"
        case .history: return "history"
        case .posture: return "posture"
        case .postureHistory: return "postureHistory"
        case .assessment(let id): return "assessment(\(id.uuidString))"
        case .livePostureCheck: return "livePostureCheck"
        case .photoAssessment(let view): return "photoAssessment(\(view.rawValue))"
        case .capturePosturePhoto(let view): return "capturePosturePhoto(\(view.rawValue))"
        case .importPosturePhoto(let view): return "importPosturePhoto(\(view.rawValue))"
        case .settings: return "settings"
        }
    }

    private static func uuid(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, value))
    }
}
