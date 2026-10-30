import AdaptiveTraining
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
    let adaptiveTraining: AdaptiveTrainingEngine?
    /// Prepares Today's Session and records effort evidence; nil when persistence is unavailable.
    let adaptiveCoordinator: AdaptiveTrainingCoordinator?
    let trainHomeViewModel: TrainHomeViewModel
    let routinesViewModel: RoutinesViewModel
    let libraryViewModel: LibraryViewModel
    let progressViewModel: ProgressViewModel
    let postureHomeViewModel: PostureHomeViewModel
    let persistenceError: String?
    /// Loaded once; nil when the app's scenario data set is missing or invalid.
    let notificationScenarioCatalog: NotificationScenarioCatalog?
    let notificationScenarioError: String?
    /// Plain-text record of what the notification code decided and what iOS accepted, for diagnosing the phone.
    let notificationEventLog = FileNotificationEventLog()
    /// Extra Personable copy and art; nil when the data set is missing or invalid.
    let personaContentCatalog: PersonaContentCatalog?
    let personaContentError: String?
    /// Persona decision traces and engagement. Nil for in-memory environments (previews and tests), which keeps the
    /// persona quiet there.
    let personaTraceStore: (any PersonaTraceStoring)?
    /// Developer workout session recordings. Nil for in-memory environments, so previews and tests never record.
    let workoutRecordings: (any WorkoutRecordingStoring)?

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
            personaContentCatalog = try PersonaContentCatalog.bundled()
            personaContentError = nil
        } catch {
            personaContentCatalog = nil
            personaContentError = String(describing: error)
        }
        personaTraceStore = inMemory ? nil : FilePersonaTraceStore()
        let workoutRecordings: (any WorkoutRecordingStoring)? = inMemory ? nil : FileWorkoutRecordingStore()
        self.workoutRecordings = workoutRecordings
        let isAppActive: () -> Bool = { UIApplication.shared.applicationState == .active }

        do {
            let container = try AppModelContainer.make(inMemory: inMemory)
            let repositories = AppRepositories(context: container.mainContext)
            let reminderCoordinator = WorkoutReminderCoordinator(
                preferences: preferences,
                routines: repositories.routines,
                workoutHistory: repositories.workoutHistory,
                exerciseCatalog: exerciseCatalog,
                router: router,
                scenarioCatalog: notificationScenarioCatalog,
                eventLog: notificationEventLog,
                assessments: repositories.assessments,
                personaCatalog: personaContentCatalog,
                personaTraces: personaTraceStore,
                isAppActive: isAppActive
            )
            modelContainer = container
            self.repositories = repositories
            let adaptiveEngine = AdaptiveTrainingEngine(
                store: repositories.adaptiveTraining,
                builtExerciseIDs: ExerciseVariantBridge().availability(equipment: []).builtExerciseIDs,
                calendar: .current
            )
            let coordinator = AdaptiveTrainingCoordinator(engine: adaptiveEngine)
            adaptiveTraining = adaptiveEngine
            adaptiveCoordinator = coordinator
            workoutReminderCoordinator = reminderCoordinator
            workoutCoachFactory = WorkoutCoachFactory(
                preferences: preferences,
                exerciseCatalog: exerciseCatalog,
                routines: repositories.routines,
                recordings: workoutRecordings,
                adaptive: coordinator
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
                router: router,
                preferences: preferences
            )
            persistenceError = nil
        } catch {
            modelContainer = nil
            repositories = nil
            adaptiveTraining = nil
            adaptiveCoordinator = nil
            let reminderCoordinator = WorkoutReminderCoordinator(
                preferences: preferences,
                routines: nil,
                workoutHistory: nil,
                exerciseCatalog: exerciseCatalog,
                router: router,
                scenarioCatalog: notificationScenarioCatalog,
                eventLog: notificationEventLog,
                personaCatalog: personaContentCatalog,
                personaTraces: personaTraceStore,
                isAppActive: isAppActive
            )
            workoutReminderCoordinator = reminderCoordinator
            workoutCoachFactory = WorkoutCoachFactory(
                preferences: preferences,
                exerciseCatalog: exerciseCatalog,
                routines: nil,
                recordings: workoutRecordings
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
                router: router,
                preferences: preferences
            )
            persistenceError = error.localizedDescription
        }

        let reminderCoordinator = workoutReminderCoordinator
        WorkoutReminderNotificationBridge.shared.install { [weak reminderCoordinator] target in
            reminderCoordinator?.handleTap(target)
        }
        WorkoutReminderNotificationBridge.shared.installEngagement { [weak reminderCoordinator] event in
            reminderCoordinator?.recordPersonaEngagement(event)
        }
    }

    func makePersonaDebugViewModel() -> PersonaDebugViewModel {
        PersonaDebugViewModel(
            catalog: personaContentCatalog,
            loadError: personaContentError,
            provider: workoutReminderCoordinator,
            scheduler: UserNotificationPreviewScheduler(),
            preferences: preferences
        )
    }

    func makeAdaptiveDebugViewModel() -> AdaptiveDebugViewModel {
        let router = router
        var openCalibration: (@MainActor () -> Void)?
        if adaptiveCoordinator != nil { openCalibration = { router.open(.calibration) } }
        return AdaptiveDebugViewModel(provider: adaptiveTraining, todayStarter: adaptiveCoordinator,
                                      openTodaySession: { router.open(.todaySession) },
                                      openCalibration: openCalibration)
    }

    /// The requested calibration's screen state, or nil when persistence is unavailable. It saves nothing until the
    /// screen appears; leaving the screen runs `onFinish`.
    func makeCalibrationViewModel(kind: CalibrationKind,
                                  onFinish: @escaping @MainActor () -> Void) -> CalibrationViewModel? {
        guard let adaptiveCoordinator else { return nil }
        return CalibrationViewModel(coordinator: adaptiveCoordinator, kind: kind, onFinish: onFinish)
    }

    func makeWorkoutRecordingsViewModel() -> WorkoutRecordingsViewModel? {
        workoutRecordings.map { WorkoutRecordingsViewModel(store: $0, preferences: preferences) }
    }

    func makeNotificationPreviewViewModel() -> NotificationPreviewViewModel {
        NotificationPreviewViewModel(
            catalog: notificationScenarioCatalog,
            loadError: notificationScenarioError,
            preferences: preferences,
            scheduler: UserNotificationPreviewScheduler(),
            diagnostics: UserNotificationDiagnosticsProvider(eventLog: notificationEventLog),
            diagnosticsReportURL: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("notification-diagnostics.txt")
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
