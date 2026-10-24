import XCTest
import UIKit
@testable import PostureAnalysisApp

@MainActor
final class PostureHomeViewModelTests: XCTestCase {
    func testRowsStayNewestFirstAndExposeBaselineBadges() {
        let baseline = assessment(id: 1, date: date(2), view: .front, isBaseline: true)
        let latest = assessment(id: 2, date: date(3), view: .leftSide)
        let previous = assessment(id: 3, date: date(1), view: .front)
        let repository = MemoryAssessmentRepository(assessments: [previous, baseline, latest])
        let viewModel = PostureHomeViewModel(assessments: repository, images: MemoryImageStore(), router: AppRouter())

        XCTAssertEqual(viewModel.state.assessments.map(\.id), [latest.id, baseline.id, previous.id])
        XCTAssertEqual(viewModel.state.assessments.map(\.isBaseline), [false, true, false])
    }

    func testLiveCheckRoutesToRealtimePostureCheck() {
        let router = AppRouter()
        let viewModel = PostureHomeViewModel(assessments: MemoryAssessmentRepository(assessments: []), images: MemoryImageStore(), router: router)

        viewModel.send(.startLiveCheck)

        XCTAssertEqual(router.selectedTab, .posture)
        XCTAssertEqual(router.presentedFullScreenRoute, .livePostureCheck)
        XCTAssertTrue(router.path(for: .posture).isEmpty)
    }

    func testPersonaIntroReadsSharedPreferencesAgainOnAppearance() {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = WorkoutReminderSettings(enabled: true, style: .character)
        let viewModel = PostureHomeViewModel(
            assessments: MemoryAssessmentRepository(assessments: []),
            images: MemoryImageStore(),
            router: AppRouter(),
            preferences: preferences
        )
        XCTAssertTrue(viewModel.state.showsPersonaIntro)

        preferences.personaIntroCardDismissed = true
        viewModel.send(.appeared)

        XCTAssertFalse(viewModel.state.showsPersonaIntro)
    }

    func testPhotoFlowCarriesTheSelectedView() {
        let router = AppRouter()
        let viewModel = PostureHomeViewModel(assessments: MemoryAssessmentRepository(assessments: []), images: MemoryImageStore(), router: router)

        viewModel.send(.startPhotoAssessment(view: .front))

        XCTAssertEqual(router.path(for: .posture), [.photoAssessment(view: .front)])
    }

    func testPhotoTilesRouteDirectlyToTheirSource() {
        let router = AppRouter()
        let viewModel = PostureHomeViewModel(assessments: MemoryAssessmentRepository(assessments: []), images: MemoryImageStore(), router: router)

        viewModel.send(.takePhoto)
        XCTAssertEqual(router.path(for: .posture), [.capturePosturePhoto(view: .uncertain)])

        router.setPath([], for: .posture)
        viewModel.send(.choosePhoto)
        XCTAssertEqual(router.path(for: .posture), [.importPosturePhoto(view: .uncertain)])
    }

    func testDeleteRemovesImageAndAssessment() {
        let saved = assessment(id: 4, date: date(1), view: .front)
        let repository = MemoryAssessmentRepository(assessments: [saved])
        let images = MemoryImageStore()
        let viewModel = PostureHomeViewModel(assessments: repository, images: images, router: AppRouter())

        viewModel.send(.deleteAssessment(id: saved.id))

        XCTAssertEqual(images.deletedPaths, [saved.imageRelativePath])
        XCTAssertTrue(repository.assessments.isEmpty)
        XCTAssertTrue(viewModel.state.assessments.isEmpty)
    }

    func testBaselineCanBeToggledAndOnlyOneBaselineRemainsPerView() {
        let first = assessment(id: 5, date: date(1), view: .front, isBaseline: true)
        let second = assessment(id: 6, date: date(2), view: .front)
        let side = assessment(id: 7, date: date(3), view: .leftSide)
        let repository = MemoryAssessmentRepository(assessments: [first, second, side])
        let viewModel = PostureHomeViewModel(assessments: repository, images: MemoryImageStore(), router: AppRouter())

        viewModel.send(.setBaseline(id: second.id, isBaseline: true))

        XCTAssertEqual(repository.assessments.first { $0.id == first.id }?.isBaseline, false)
        XCTAssertEqual(repository.assessments.first { $0.id == second.id }?.isBaseline, true)
        XCTAssertEqual(repository.assessments.first { $0.id == side.id }?.isBaseline, false)
        XCTAssertEqual(viewModel.state.assessments.first { $0.id == second.id }?.isBaseline, true)

        viewModel.send(.setBaseline(id: second.id, isBaseline: false))
        XCTAssertEqual(repository.assessments.first { $0.id == second.id }?.isBaseline, false)
    }

    private func date(_ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func assessment(id: Int, date: Date, view: PostureView, isBaseline: Bool = false) -> PostureAssessment {
        PostureAssessment(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
            date: date,
            imageRelativePath: "assessment-\(id).jpg",
            view: view,
            pose: BodyPose(landmarks: [:], imageWidth: 100, imageHeight: 200),
            measurements: [],
            isBaseline: isBaseline
        )
    }
}

@MainActor
private final class MemoryAssessmentRepository: AssessmentRepository {
    var assessments: [PostureAssessment]

    init(assessments: [PostureAssessment]) { self.assessments = assessments }

    func list() throws -> [PostureAssessment] { assessments.sorted { $0.date > $1.date } }

    func save(_ assessment: PostureAssessment, imageRelativePath: String) throws {
        assessments.removeAll { $0.id == assessment.id }
        assessments.append(assessment)
    }

    func setBaseline(id: UUID, isBaseline: Bool) throws {
        guard let selected = assessments.first(where: { $0.id == id }) else { return }
        assessments = assessments.map { value in
            var updated = value
            if isBaseline && value.view == selected.view { updated.isBaseline = false }
            if value.id == id { updated.isBaseline = isBaseline }
            return updated
        }
    }

    func delete(id: UUID) throws { assessments.removeAll { $0.id == id } }
}

private final class MemoryImageStore: ImageStoring {
    private(set) var deletedPaths: [String] = []

    func saveImage(_ image: UIImage, filename: String) throws -> String { filename }
    func loadImage(relativePath: String) -> UIImage? { nil }
    func deleteImage(relativePath: String) { deletedPaths.append(relativePath) }
}
