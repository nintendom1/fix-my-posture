import Foundation

@MainActor
final class WorkoutCompleteViewModel {
    let state: WorkoutCompleteState

    private let router: AppRouter?

    init(record: WorkoutRecord, router: AppRouter?) {
        state = WorkoutCompleteState(record: record)
        self.router = router
    }

    /// Ends the full-screen workout and leaves the Train stack at its root.
    func done() {
        guard let router else { return }
        router.dismissFullScreen()
        router.selectedTab = .train
        router.setPath([], for: .train)
    }

    /// Ends the workout before opening workout history under the Progress tab.
    func viewHistory() {
        guard let router else { return }
        router.dismissFullScreen()
        router.open(.history)
    }
}
