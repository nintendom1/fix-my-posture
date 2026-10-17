import Foundation

struct PostureHomeAssessmentRow: Equatable, Identifiable {
    let id: UUID
    let dateLabel: String
    let viewLabel: String
    let isBaseline: Bool
}

struct PostureHomeState: Equatable {
    let assessments: [PostureHomeAssessmentRow]
    var errorMessage: String? = nil
}

enum PostureHomeIntent: Equatable {
    case appeared
    case startLiveCheck
    case takePhoto
    case choosePhoto
    case startPhotoAssessment(view: PostureView)
    case openAssessment(UUID)
    case openHistory
    case setBaseline(id: UUID, isBaseline: Bool)
    case deleteAssessment(id: UUID)
}
