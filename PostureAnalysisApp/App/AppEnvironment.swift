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
    let workoutReminderCoordinator: WorkoutReminderCoordinator
    let trainHomeViewModel: TrainHomeViewModel
    let routinesViewModel: RoutinesViewModel
    let libraryViewModel: LibraryViewModel
    let progressViewModel: ProgressViewModel
    let postureHomeViewModel: PostureHomeViewModel
    let persistenceError: String?
    /// Loaded once; nil when the app's scenario data set is missing or invalid.
    let notificationScenarioCatalog: NotificationScenarioCatalog?
    let notificationScenarioError: String?

    init(inMemory: Bool = false) {
        router = AppRouter()
        preferences = inMemory ? InMemoryPreferences() : UserDefaultsPreferences()
        exerciseCatalog = LiveExerciseCatalog()
        do {
            notificationScenarioCatalog = try NotificationScenarioCatalog.bundled()
            notificationScenarioError = nil
        } catch {
            notificationScenarioCatalog = nil
            notificationScenarioError = error.localizedDescription
        }

        do {
            let container = try AppModelContainer.make(inMemory: inMemory)
            let repositories = AppRepositories(context: container.mainContext)
            let reminderCoordinator = WorkoutReminderCoordinator(
                preferences: preferences,
                routines: repositories.routines,
                workoutHistory: repositories.workoutHistory,
                exerciseCatalog: exerciseCatalog,
                router: router
            )
            modelContainer = container
            self.repositories = repositories
            workoutReminderCoordinator = reminderCoordinator
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
                router: router,
                reminderReconciliation: reminderCoordinator
            )
            routinesViewModel = RoutinesViewModel(
                routines: repositories.routines,
                workoutHistory: repositories.workoutHistory,
                exerciseCatalog: exerciseCatalog,
                preferences: preferences,
                router: router,
                reminderReconciliation: reminderCoordinator
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
            let reminderCoordinator = WorkoutReminderCoordinator(
                preferences: preferences,
                routines: nil,
                workoutHistory: nil,
                exerciseCatalog: exerciseCatalog,
                router: router
            )
            workoutReminderCoordinator = reminderCoordinator
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
                router: router,
                reminderReconciliation: reminderCoordinator
            )
            routinesViewModel = RoutinesViewModel(
                routines: nil,
                workoutHistory: nil,
                exerciseCatalog: exerciseCatalog,
                preferences: preferences,
                router: router,
                reminderReconciliation: reminderCoordinator
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

        let reminderCoordinator = workoutReminderCoordinator
        WorkoutReminderNotificationBridge.shared.install { [weak reminderCoordinator] target in
            reminderCoordinator?.handleTap(target)
        }
    }

    func makeNotificationPreviewViewModel() -> NotificationPreviewViewModel {
        NotificationPreviewViewModel(
            catalog: notificationScenarioCatalog,
            loadError: notificationScenarioError,
            preferences: preferences,
            scheduler: UserNotificationPreviewScheduler()
        )
    }

    func makeRoutineDetailViewModel(id: UUID) -> RoutineDetailViewModel {
        RoutineDetailViewModel(
            id: id,
            routines: repositories?.routines,
            workoutHistory: repositories?.workoutHistory,
            exerciseCatalog: exerciseCatalog,
            preferences: preferences,
            router: router,
            reminderReconciliation: workoutReminderCoordinator
        )
    }

    func makeRoutineEditorViewModel(id: UUID?) -> RoutineEditorViewModel {
        RoutineEditorViewModel(
            id: id,
            routines: repositories?.routines,
            exerciseCatalog: exerciseCatalog,
            preferences: preferences,
            router: router,
            reminderReconciliation: workoutReminderCoordinator
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

private struct WorkoutReminderReconciliationEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any WorkoutReminderReconciliation)? = nil
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

    var workoutReminderReconciliation: (any WorkoutReminderReconciliation)? {
        get { self[WorkoutReminderReconciliationEnvironmentKey.self] }
        set { self[WorkoutReminderReconciliationEnvironmentKey.self] = newValue }
    }
}
