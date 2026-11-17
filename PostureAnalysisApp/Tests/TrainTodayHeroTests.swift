import AdaptiveTraining
import Foundation
import SwiftUI
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class TrainTodayHeroTests: XCTestCase {
    private let catalog = MemoryExerciseCatalog(exercises: [
        ShoulderPressExercise.definition(),
        AirSquatExercise.definition(),
        DumbbellRowExercise.definition(),
        PushUpExercise.definition(),
        WallPushUpExercise.definition()
    ])

    func testReadyStatusMapsTheSessionAndRoundsTheEstimate() {
        let provider = FakeTodaySessionHeroProvider(status: .ready(session(estimatedSeconds: 30)))
        let viewModel = makeViewModel(provider: provider)

        XCTAssertEqual(viewModel.state.todayHero?.eyebrow, "TODAY'S SESSION")
        XCTAssertEqual(viewModel.state.todayHero?.title, "Push")
        XCTAssertEqual(viewModel.state.todayHero?.subtitle, "Wall Push-Up × 4 · about 1 min")
        XCTAssertEqual(viewModel.state.todayHero?.action, .startTodaySession)
        XCTAssertEqual(viewModel.state.todayHero?.actionTitle, "Start")

        provider.todayStatus = .ready(session(estimatedSeconds: 90))
        viewModel.send(.appeared)

        XCTAssertEqual(viewModel.state.todayHero?.subtitle, "Wall Push-Up × 4 · about 2 min")
    }

    func testCompletedStatusUsesTheNextAreaOrNiceWorkAndHasNoAction() {
        let provider = FakeTodaySessionHeroProvider(
            status: .completedToday(family: .push, next: session(family: .squat, estimatedSeconds: 60))
        )
        let viewModel = makeViewModel(provider: provider)

        XCTAssertEqual(viewModel.state.todayHero?.title, "Done for today")
        XCTAssertEqual(viewModel.state.todayHero?.subtitle, "Next time: Squat")
        XCTAssertNil(viewModel.state.todayHero?.action)
        XCTAssertNil(viewModel.state.todayHero?.actionTitle)

        provider.todayStatus = .completedToday(family: .push, next: nil)
        viewModel.send(.appeared)
        XCTAssertEqual(viewModel.state.todayHero?.subtitle, "Nice work.")
    }

    func testNeedsCalibrationMapsToTheStartingPointInvitation() {
        let viewModel = makeViewModel(provider: FakeTodaySessionHeroProvider(status: .needsCalibration))

        XCTAssertEqual(viewModel.state.todayHero?.eyebrow, "ADAPTIVE TRAINING")
        XCTAssertEqual(viewModel.state.todayHero?.title, "Find your starting point")
        XCTAssertEqual(viewModel.state.todayHero?.subtitle, "A few tiny samples, then a short session each day.")
        XCTAssertEqual(viewModel.state.todayHero?.action, .findStartingPoint)
        XCTAssertEqual(viewModel.state.todayHero?.actionTitle, "Find your starting point")
    }

    func testStartSuccessOpensTodaySessionAndFailureKeepsTheProblemUntilRefresh() throws {
        let successRouter = AppRouter()
        let successfulProvider = FakeTodaySessionHeroProvider(status: .ready(session()), launch: makeLaunch())
        let successfulViewModel = makeViewModel(provider: successfulProvider, router: successRouter)

        successfulViewModel.send(.startTodaySession)

        XCTAssertEqual(successRouter.presentedFullScreenRoute, .todaySession)

        let failureRouter = AppRouter()
        let failedProvider = FakeTodaySessionHeroProvider(status: .ready(session()), problem: "Storage is unavailable.")
        let failedViewModel = makeViewModel(provider: failedProvider, router: failureRouter)

        failedViewModel.send(.startTodaySession)

        XCTAssertNil(failureRouter.presentedFullScreenRoute)
        XCTAssertEqual(failedViewModel.state.todayHero?.startProblem, "Storage is unavailable.")
        XCTAssertEqual(failedViewModel.state.todayHero?.actionTitle, "Start")

        failedViewModel.send(.appeared)
        XCTAssertNil(failedViewModel.state.todayHero?.startProblem)

        let fallbackRouter = AppRouter()
        let fallbackViewModel = makeViewModel(
            provider: FakeTodaySessionHeroProvider(status: .ready(session())),
            router: fallbackRouter
        )
        fallbackViewModel.send(.startTodaySession)
        XCTAssertNil(fallbackRouter.presentedFullScreenRoute)
        XCTAssertEqual(fallbackViewModel.state.todayHero?.startProblem, "Today's Session couldn't start.")
    }

    func testFindStartingPointOpensCalibration() {
        let router = AppRouter()
        let viewModel = makeViewModel(
            provider: FakeTodaySessionHeroProvider(status: .needsCalibration),
            router: router
        )

        viewModel.send(.findStartingPoint)

        XCTAssertEqual(router.presentedFullScreenRoute, .calibration)
    }

    func testRoutineLinkStillStartsTheRoutineAlongsideTheTodayHero() throws {
        let savedRoutine = try routine(name: "Upper Body", ids: [.shoulderPress])
        let router = AppRouter()
        let viewModel = makeViewModel(
            provider: FakeTodaySessionHeroProvider(status: .ready(session())),
            routines: MemoryRoutineRepository(entries: [SavedExerciseSetRecord(set: savedRoutine, updatedAt: FixedClock.date)]),
            router: router
        )

        XCTAssertEqual(viewModel.state.heroRoutine?.name, "Upper Body")
        viewModel.send(.startRoutine)

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: nil, routineID: savedRoutine.id))
    }

    func testNothingOfferedOrNoProviderKeepsRoutineHeroAndItsAnchors() throws {
        let savedRoutine = try routine(name: "Upper Body", ids: [.shoulderPress])
        let repository = MemoryRoutineRepository(entries: [
            SavedExerciseSetRecord(set: savedRoutine, updatedAt: FixedClock.date)
        ])

        let providers: [(any TodaySessionHeroProviding)?] = [
            FakeTodaySessionHeroProvider(status: .nothingOffered),
            nil
        ]
        for provider in providers {
            let viewModel = makeViewModel(provider: provider, routines: repository)
            XCTAssertNil(viewModel.state.todayHero)
            XCTAssertEqual(viewModel.state.heroRoutine?.id, savedRoutine.id)

            let result = try SnapshotHost.render(
                TrainHomeScreen(state: viewModel.state, send: { _ in }),
                frameId: "train-routine-hero-no-adaptive",
                testCase: self
            )
            XCTAssertNotNil(result.snapshotMeasuredAnchors["train.hero"])
            XCTAssertNotNil(result.snapshotMeasuredAnchors["train.hero.title"])
            XCTAssertNotNil(result.snapshotMeasuredAnchors["train.hero.subtitle"])
            XCTAssertNotNil(result.snapshotMeasuredAnchors["train.hero.cta"])
            XCTAssertNotNil(result.snapshotMeasuredAnchors["train.hero.lastDone"])
        }
    }

    private func makeViewModel(
        provider: (any TodaySessionHeroProviding)? = nil,
        routines: MemoryRoutineRepository? = nil,
        router: AppRouter? = nil
    ) -> TrainHomeViewModel {
        TrainHomeViewModel(
            routines: routines ?? MemoryRoutineRepository(entries: []),
            workoutHistory: TrainTodayMemoryWorkoutHistoryRepository(),
            exerciseCatalog: catalog,
            preferences: InMemoryPreferences(),
            router: router ?? AppRouter(),
            todaySession: provider,
            now: { FixedClock.date }
        )
    }

    private func session(family: MovementFamilyID = .push, estimatedSeconds: Int = 30) -> TodaySession {
        TodaySession(
            family: family,
            main: RungDose(variant: VariantID(rawValue: "push.wall_push_up"), dose: .reps(4)),
            harderSample: nil,
            offersBonus: false,
            isTiny: true,
            confidence: .low,
            estimatedSeconds: estimatedSeconds,
            rationale: "",
            basedOnTransitionID: nil
        )
    }

    private func makeLaunch() -> TodaySessionLaunch {
        let itemID = UUID()
        let target = RungDose(variant: VariantID(rawValue: "push.wall_push_up"), dose: .reps(4))
        let prescription = Prescription(
            id: UUID(),
            issuedAt: FixedClock.date,
            kind: .todaySession,
            policyVersion: .v1,
            catalogVersion: "ladders-1",
            items: [PrescriptionItem(id: itemID, family: .push, target: target)],
            rationale: ""
        )
        let plan = WorkoutPlan(name: "Today's Session", items: [
            WorkoutPlanItem(id: itemID, exerciseID: .wallPushUp, sets: 1, targetReps: 4...4)
        ])
        let item = AdaptivePlanItem(
            itemID: itemID,
            role: .main,
            family: .push,
            rungDose: target,
            exerciseID: .wallPushUp,
            reducedRange: false
        )
        return TodaySessionLaunch(prescription: prescription, plan: plan, items: [item])
    }

    private func routine(name: String, ids: [ExerciseID]) throws -> SavedExerciseSet {
        let items = try ids.map { id -> SavedExerciseSetItem in
            let exercise = try XCTUnwrap(catalog.exercise(id))
            return SavedExerciseSetItem(
                exerciseID: id,
                setCount: 2,
                targetRepMinimum: exercise.targetReps.lowerBound,
                targetRepMaximum: exercise.targetReps.upperBound
            )
        }
        return SavedExerciseSet(name: name, items: items)
    }
}

@MainActor
private final class FakeTodaySessionHeroProvider: TodaySessionHeroProviding {
    var todayStatus: TodaySessionStatus
    var launch: TodaySessionLaunch?
    var lastStartProblem: String?

    init(status: TodaySessionStatus, launch: TodaySessionLaunch? = nil, problem: String? = nil) {
        todayStatus = status
        self.launch = launch
        lastStartProblem = problem
    }

    func status(asOf now: Date) -> TodaySessionStatus { todayStatus }

    func displayName(of variant: VariantID) -> String {
        variant.rawValue == "push.wall_push_up" ? "Wall Push-Up" : variant.rawValue
    }

    func start(asOf now: Date) -> TodaySessionLaunch? { launch }
}

@MainActor
private final class TrainTodayMemoryWorkoutHistoryRepository: WorkoutHistoryRepository {
    func list() throws -> [WorkoutRecord] { [] }
    func save(_ record: WorkoutRecord) throws {}
    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}
