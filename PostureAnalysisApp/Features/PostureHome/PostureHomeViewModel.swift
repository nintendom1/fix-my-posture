import Foundation
import Observation

@MainActor
@Observable
final class PostureHomeViewModel {
    private(set) var state: PostureHomeState

    private let assessments: (any AssessmentRepository)?
    private let images: (any ImageStoring)?
    private let router: AppRouter
    private let preferences: any AppPreferencesStoring

    init(
        assessments: (any AssessmentRepository)?,
        images: (any ImageStoring)?,
        router: AppRouter,
        preferences: any AppPreferencesStoring = InMemoryPreferences()
    ) {
        self.assessments = assessments
        self.images = images
        self.router = router
        self.preferences = preferences
        state = PostureHomeState(assessments: [])
        refresh()
    }

    func send(_ intent: PostureHomeIntent) {
        switch intent {
        case .appeared:
            refresh()
        case .startLiveCheck:
            router.open(.livePostureCheck)
        case .takePhoto:
            router.open(.capturePosturePhoto(view: .uncertain))
        case .choosePhoto:
            router.open(.importPosturePhoto(view: .uncertain))
        case .startPhotoAssessment(let view):
            router.open(.photoAssessment(view: view))
        case .openAssessment(let id):
            router.open(.assessment(id: id))
        case .openHistory:
            router.open(.postureHistory)
        case .dismissPersonaIntro:
            preferences.personaIntroCardDismissed = true
            state.showsPersonaIntro = false
        case .openPersonaSettings:
            router.present(.settings)
        case .setBaseline(let id, let isBaseline):
            do {
                try assessments?.setBaseline(id: id, isBaseline: isBaseline)
                refresh()
            } catch {
                state = PostureHomeState(
                    assessments: state.assessments,
                    errorMessage: error.localizedDescription,
                    showsPersonaIntro: state.showsPersonaIntro
                )
            }
        case .deleteAssessment(let id):
            guard state.assessments.contains(where: { $0.id == id }) else { return }
            do {
                if let stored = try assessments?.list().first(where: { $0.id == id }) {
                    images?.deleteImage(relativePath: stored.imageRelativePath)
                }
                try assessments?.delete(id: id)
                refresh()
            } catch {
                state = PostureHomeState(
                    assessments: state.assessments,
                    errorMessage: error.localizedDescription,
                    showsPersonaIntro: state.showsPersonaIntro
                )
            }
        }
    }

    private func refresh() {
        do {
            let values = try assessments?.list() ?? []
            state = PostureHomeState(
                assessments: values.sorted { $0.date > $1.date }.map(makeRow),
                showsPersonaIntro: shouldShowPersonaIntro
            )
        } catch {
            state = PostureHomeState(
                assessments: [],
                errorMessage: error.localizedDescription,
                showsPersonaIntro: shouldShowPersonaIntro
            )
        }
    }

    private var shouldShowPersonaIntro: Bool {
        let reminderSettings = preferences.workoutReminderSettings
        return reminderSettings.enabled
            && reminderSettings.style == .character
            && preferences.extraPersonableEnabled
            && !preferences.personaIntroCardDismissed
    }

    private func makeRow(_ assessment: PostureAssessment) -> PostureHomeAssessmentRow {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"

        let viewLabel: String
        switch assessment.view {
        case .front: viewLabel = "Front view"
        case .leftSide, .rightSide: viewLabel = "Side view"
        case .uncertain: viewLabel = "View not classified"
        }
        return PostureHomeAssessmentRow(
            id: assessment.id,
            dateLabel: formatter.string(from: assessment.date),
            viewLabel: viewLabel,
            isBaseline: assessment.isBaseline
        )
    }
}
