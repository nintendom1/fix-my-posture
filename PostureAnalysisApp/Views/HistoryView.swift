import SwiftUI
import SwiftData

public struct HistoryView: View {
    @Environment(\.appRepositories) private var appRepositories
    @Query(sort: \AssessmentEntity.date, order: .reverse) private var storedAssessments: [AssessmentEntity]

    public var body: some View {
        List {
            if storedAssessments.isEmpty {
                ContentUnavailableView("No Assessments Saved", systemImage: "figure.walk", description: Text("Take or import a standing photo to begin tracking posture."))
            } else {
                Section("Saved Assessments") {
                    ForEach(storedAssessments) { entity in
                        NavigationLink(value: AppRoute.assessment(id: entity.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entity.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.headline)

                                        if entity.isBaseline {
                                            Text("BASELINE")
                                                .font(.caption2)
                                                .bold()
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue)
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                        }
                                    }

                                    Text((PostureView(rawValue: entity.viewRawValue) ?? .uncertain).displayName)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: {
                                    toggleBaseline(entity: entity)
                                }) {
                                    Image(systemName: entity.isBaseline ? "star.fill" : "star")
                                        .foregroundColor(entity.isBaseline ? .yellow : .gray)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("baselineToggleButton_\(entity.id.uuidString)")
                            }
                        }
                    }
                    .onDelete(perform: deleteAssessment)
                }
            }
        }
        .navigationTitle("History")
    }

    private func toggleBaseline(entity: AssessmentEntity) {
        let newValue = !entity.isBaseline
        try? appRepositories?.assessments.setBaseline(id: entity.id, isBaseline: newValue)
    }

    private func deleteAssessment(at offsets: IndexSet) {
        guard let appRepositories else { return }
        for index in offsets {
            let item = storedAssessments[index]
            appRepositories.images.deleteImage(relativePath: item.imageRelativePath)
            try? appRepositories.assessments.delete(id: item.id)
        }
    }
}

struct AssessmentRouteView: View {
    @Environment(\.appRepositories) private var appRepositories
    @Query(sort: \AssessmentEntity.date, order: .reverse) private var assessments: [AssessmentEntity]
    let id: UUID

    private var entity: AssessmentEntity? { assessments.first { $0.id == id } }

    var body: some View {
        Group {
            if let entity {
                let baseline = assessments.first {
                    $0.isBaseline && $0.viewRawValue == entity.viewRawValue && $0.id != entity.id
                }
                AssessmentDetailView(
                    assessment: convertToDomain(entity),
                    image: appRepositories?.images.loadImage(relativePath: entity.imageRelativePath),
                    baselineAssessment: baseline.map(convertToDomain)
                )
            } else {
                ContentUnavailableView("Assessment Unavailable", systemImage: "figure.walk")
            }
        }
    }

    private func convertToDomain(_ entity: AssessmentEntity) -> PostureAssessment {
        var landmarks: [LandmarkType: Landmark] = [:]
        for landmark in entity.landmarks {
            guard let type = LandmarkType(rawValue: landmark.typeRawValue) else { continue }
            landmarks[type] = Landmark(
                type: type,
                normalizedLocation: CGPoint(x: landmark.normalizedX, y: landmark.normalizedY),
                imageLocation: CGPoint(x: landmark.imageX, y: landmark.imageY),
                confidence: landmark.confidence,
                isManuallyCorrected: landmark.isManuallyCorrected
            )
        }

        let measurements = entity.measurements.map { measurement in
            PostureMeasurement(
                id: measurement.resolvedID,
                name: measurement.name,
                value: measurement.value,
                unit: measurement.unit,
                landmarksUsed: measurement.landmarksUsedRaw.split(separator: ",")
                    .compactMap { LandmarkType(rawValue: String($0)) },
                confidence: measurement.confidence,
                explanation: measurement.explanation
            )
        }
        let pose = BodyPose(landmarks: landmarks, imageWidth: CGFloat(entity.imageWidth), imageHeight: CGFloat(entity.imageHeight))
        let horizonContext: HorizonContext?
        if let angle = entity.horizonAngle,
           let sourceValue = entity.horizonSourceRawValue,
           let source = HorizonSource(rawValue: sourceValue),
           let applied = entity.isHorizonCompensationApplied {
            horizonContext = HorizonContext(angleDegrees: angle, source: source, isCompensationApplied: applied)
        } else {
            horizonContext = nil
        }

        return PostureAssessment(
            id: entity.id,
            date: entity.date,
            imageRelativePath: entity.imageRelativePath,
            view: PostureView(rawValue: entity.viewRawValue) ?? .uncertain,
            pose: pose,
            measurements: measurements,
            warnings: [],
            isBaseline: entity.isBaseline,
            appVersion: entity.appVersion,
            horizonContext: horizonContext
        )
    }
}
