import SwiftData
import SwiftUI

@MainActor
struct AppRepositories {
    let workoutHistory: any WorkoutHistoryRepository
    let routines: any RoutineRepository
    let assessments: any AssessmentRepository
    let images: any ImageStoring

    init(context: ModelContext, images: any ImageStoring = ImageStoreAdapter()) {
        workoutHistory = SwiftDataWorkoutHistoryRepository(context: context)
        routines = BuiltInRoutineRepository(base: SwiftDataRoutineRepository(context: context))
        assessments = SwiftDataAssessmentRepository(context: context)
        self.images = images
    }
}

private struct AppRepositoriesEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppRepositories? = nil
}

extension EnvironmentValues {
    var appRepositories: AppRepositories? {
        get { self[AppRepositoriesEnvironmentKey.self] }
        set { self[AppRepositoriesEnvironmentKey.self] = newValue }
    }
}
