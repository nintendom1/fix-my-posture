import Foundation
import Observation

@MainActor
@Observable
final class ProgressViewModel {
    private(set) var state: ProgressState

    private let workoutHistory: (any WorkoutHistoryRepository)?
    private let assessments: (any AssessmentRepository)?
    private let router: AppRouter?
    private let now: () -> Date
    private let calendar: Calendar

    init(
        workoutHistory: (any WorkoutHistoryRepository)?,
        assessments: (any AssessmentRepository)?,
        router: AppRouter?,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.workoutHistory = workoutHistory
        self.assessments = assessments
        self.router = router
        self.now = now
        self.calendar = calendar
        state = ProgressState(
            weeklyStats: WeeklyStats(records: [], now: now(), calendar: calendar),
            postureAssessmentCount: 0,
            latestAssessmentDate: nil
        )
        refresh()
    }

    func send(_ intent: ProgressIntent) {
        switch intent {
        case .appeared:
            refresh()
        case .openHistory:
            router?.open(.history)
        case .openPosture:
            router?.select(.posture)
        }
    }

    private func refresh() {
        let currentDate = now()
        let records = (try? workoutHistory?.list()) ?? []
        let postureRecords = (try? assessments?.list()) ?? []
        state = ProgressState(
            weeklyStats: WeeklyStats(records: records, now: currentDate, calendar: calendar),
            postureAssessmentCount: postureRecords.count,
            latestAssessmentDate: postureRecords.max(by: { $0.date < $1.date })?.date
        )
    }
}
