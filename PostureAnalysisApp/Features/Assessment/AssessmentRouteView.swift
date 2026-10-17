import SwiftData
import SwiftUI

struct AssessmentRouteView: View {
    @Environment(\.appRepositories) private var appRepositories
    @Query(sort: \AssessmentEntity.date, order: .reverse) private var storedAssessments: [AssessmentEntity]

    let id: UUID

    var body: some View {
        let revision = storedAssessments.map { entity in
            let measurements = entity.measurements
                .map { "\($0.measurementIDRawValue):\($0.value)" }
                .joined(separator: ",")
            return "\(entity.id.uuidString):\(entity.isBaseline):\(entity.viewRawValue):\(measurements)"
        }
        .joined(separator: "|")

        if let appRepositories,
           let values = try? appRepositories.assessments.list(),
           let assessment = values.first(where: { $0.id == id }) {
            let baseline = values.first {
                $0.isBaseline && $0.view == assessment.view && $0.id != assessment.id
            }
            AssessmentScreen(viewModel: AssessmentViewModel(
                assessment: assessment,
                baselineAssessment: baseline,
                image: appRepositories.images.loadImage(relativePath: assessment.imageRelativePath),
                repository: appRepositories.assessments
            ))
            .id(revision)
        } else {
            ContentUnavailableView("Assessment Unavailable", systemImage: "figure.stand")
        }
    }
}
