import Observation
import SwiftData
import SwiftUI

/// Owns the long-lived app services and constructs them once for the SwiftUI scene.
@MainActor
@Observable
final class AppEnvironment {
    let router: AppRouter
    let preferences: any AppPreferencesStoring
    let modelContainer: ModelContainer?
    let repositories: AppRepositories?
    let exerciseCatalog: any ExerciseCatalogProviding
    let workoutCoachFactory: WorkoutCoachFactory
    let trainHomeViewModel: TrainHomeViewModel
    let routinesViewModel: RoutinesViewModel
    let libraryViewModel: LibraryViewModel
    let progressViewModel: ProgressViewModel
    let postureHomeViewModel: PostureHomeViewModel
    let persistenceError: String?

    init(inMemory: Bool = false) {
        router = AppRouter()
        preferences = inMemory ? InMemoryPreferences() : UserDefaultsPreferences()
        exerciseCatalog = LiveExerciseCatalog()

        do {
            let container = try AppModelContainer.make(inMemory: inMemory)
            let repositories = AppRepositories(context: container.mainContext)
            modelContainer = container
            self.repositories = repositories
            workoutCoachFactory = WorkoutCoachFactory(
                preferences: preferences,
                exerciseCatalog: exerciseCatalog,
                routines: repositories.routines
            )
            trainHomeViewModel = TrainHomeViewModel(
                routines: repositories.routines,
                workoutHistory: repositories.workoutHistory,
                exerciseCatalog: exerciseCatalog,
                preferences: preferences,
                router: router
            )
            routinesViewModel = RoutinesViewModel(
                routines: repositories.routines,
                workoutHistory: repositories.workoutHistory,
                exerciseCatalog: exerciseCatalog,
                preferences: preferences,
                router: router
            )
            libraryViewModel = LibraryViewModel(
                workoutHistory: repositories.workoutHistory,
                exerciseCatalog: exerciseCatalog,
                preferences: preferences,
                router: router
            )
            progressViewModel = ProgressViewModel(
                workoutHistory: repositories.workoutHistory,
                assessments: repositories.assessments,
                router: router
            )
            postureHomeViewModel = PostureHomeViewModel(
                assessments: repositories.assessments,
                images: repositories.images,
                router: router
            )
            persistenceError = nil
        } catch {
            modelContainer = nil
            repositories = nil
            workoutCoachFactory = WorkoutCoachFactory(
                preferences: preferences,
                exerciseCatalog: exerciseCatalog,
                routines: nil
            )
            trainHomeViewModel = TrainHomeViewModel(
                routines: nil,
                workoutHistory: nil,
                exerciseCatalog: exerciseCatalog,
                preferences: preferences,
                router: router
            )
            routinesViewModel = RoutinesViewModel(
                routines: nil,
                workoutHistory: nil,
                exerciseCatalog: exerciseCatalog,
                preferences: preferences,
                router: router
            )
            libraryViewModel = LibraryViewModel(
                workoutHistory: nil,
                exerciseCatalog: exerciseCatalog,
                preferences: preferences,
                router: router
            )
            progressViewModel = ProgressViewModel(
                workoutHistory: nil,
                assessments: nil,
                router: router
            )
            postureHomeViewModel = PostureHomeViewModel(
                assessments: nil,
                images: nil,
                router: router
            )
            persistenceError = error.localizedDescription
        }
    }

    func makeRoutineDetailViewModel(id: UUID) -> RoutineDetailViewModel {
        RoutineDetailViewModel(
            id: id,
            routines: repositories?.routines,
            workoutHistory: repositories?.workoutHistory,
            exerciseCatalog: exerciseCatalog,
            preferences: preferences,
            router: router
        )
    }

    func makeRoutineEditorViewModel(id: UUID?) -> RoutineEditorViewModel {
        RoutineEditorViewModel(
            id: id,
            routines: repositories?.routines,
            exerciseCatalog: exerciseCatalog,
            preferences: preferences,
            router: router
        )
    }

    func makeExerciseDetailViewModel(id: ExerciseID) -> ExerciseDetailViewModel {
        ExerciseDetailViewModel(
            id: id,
            exerciseCatalog: exerciseCatalog,
            preferences: preferences,
            router: router
        )
    }

    func makeHistoryViewModel() -> HistoryViewModel {
        HistoryViewModel(repository: repositories?.workoutHistory,
                         exerciseCatalog: exerciseCatalog,
                         preferences: preferences)
    }
}

private struct AppRouterEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppRouter? = nil
}

private struct ExerciseCatalogEnvironmentKey: EnvironmentKey {
    static let defaultValue: any ExerciseCatalogProviding = LiveExerciseCatalog()
}

private struct WorkoutCoachFactoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: WorkoutCoachFactory? = nil
}

extension EnvironmentValues {
    var appRouter: AppRouter? {
        get { self[AppRouterEnvironmentKey.self] }
        set { self[AppRouterEnvironmentKey.self] = newValue }
    }

    var exerciseCatalog: any ExerciseCatalogProviding {
        get { self[ExerciseCatalogEnvironmentKey.self] }
        set { self[ExerciseCatalogEnvironmentKey.self] = newValue }
    }

    var workoutCoachFactory: WorkoutCoachFactory? {
        get { self[WorkoutCoachFactoryEnvironmentKey.self] }
        set { self[WorkoutCoachFactoryEnvironmentKey.self] = newValue }
    }
}
