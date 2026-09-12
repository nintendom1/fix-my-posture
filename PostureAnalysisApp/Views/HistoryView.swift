import SwiftUI
import SwiftData

public struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AssessmentEntity.date, order: .reverse) private var storedAssessments: [AssessmentEntity]

    public var body: some View {
        List {
            if storedAssessments.isEmpty {
                ContentUnavailableView("No Assessments Saved", systemImage: "figure.walk", description: Text("Take or import a standing photo to begin tracking posture."))
            } else {
                Section("Saved Assessments") {
                    ForEach(storedAssessments) { entity in
                        NavigationLink(destination: detailView(for: entity)) {
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

    private func detailView(for entity: AssessmentEntity) -> some View {
        let currentAssessment = convertToDomain(entity)
        let uiImg = ImageStore.shared.loadImage(relativePath: entity.imageRelativePath)

        let baselineEntity = storedAssessments.first(where: { $0.isBaseline && $0.viewRawValue == entity.viewRawValue && $0.id != entity.id })
        let baselineAssessment = baselineEntity.map { convertToDomain($0) }

        return AssessmentDetailView(assessment: currentAssessment, image: uiImg, baselineAssessment: baselineAssessment)
    }

    private func convertToDomain(_ entity: AssessmentEntity) -> PostureAssessment {
        var landmarks: [LandmarkType: Landmark] = [:]
        for lm in entity.landmarks {
            if let type = LandmarkType(rawValue: lm.typeRawValue) {
                landmarks[type] = Landmark(
                    type: type,
                    normalizedLocation: CGPoint(x: lm.normalizedX, y: lm.normalizedY),
                    imageLocation: CGPoint(x: lm.imageX, y: lm.imageY),
                    confidence: lm.confidence,
                    isManuallyCorrected: lm.isManuallyCorrected
                )
            }
        }

        var measurements: [PostureMeasurement] = []
        for m in entity.measurements {
            let mID = m.resolvedID
            let lmTypes = m.landmarksUsedRaw.split(separator: ",").compactMap { LandmarkType(rawValue: String($0)) }
            measurements.append(PostureMeasurement(
                id: mID,
                name: m.name,
                value: m.value,
                unit: m.unit,
                landmarksUsed: lmTypes,
                confidence: m.confidence,
                explanation: m.explanation
            ))
        }

        let pose = BodyPose(landmarks: landmarks, imageWidth: CGFloat(entity.imageWidth), imageHeight: CGFloat(entity.imageHeight))
        let pView = PostureView(rawValue: entity.viewRawValue) ?? .uncertain

        let horizonCtx: HorizonContext?
        if let angle = entity.horizonAngle,
           let srcRaw = entity.horizonSourceRawValue,
           let src = HorizonSource(rawValue: srcRaw),
           let applied = entity.isHorizonCompensationApplied {
            horizonCtx = HorizonContext(angleDegrees: angle, source: src, isCompensationApplied: applied)
        } else {
            horizonCtx = nil
        }

        return PostureAssessment(
            id: entity.id,
            date: entity.date,
            imageRelativePath: entity.imageRelativePath,
            view: pView,
            pose: pose,
            measurements: measurements,
            warnings: [],
            isBaseline: entity.isBaseline,
            appVersion: entity.appVersion,
            horizonContext: horizonCtx
        )
    }

    private func toggleBaseline(entity: AssessmentEntity) {
        let newValue = !entity.isBaseline
        if newValue {
            for item in storedAssessments where item.viewRawValue == entity.viewRawValue {
                item.isBaseline = false
            }
        }
        entity.isBaseline = newValue
        try? modelContext.save()
    }

    private func deleteAssessment(at offsets: IndexSet) {
        for index in offsets {
            let item = storedAssessments[index]
            ImageStore.shared.deleteImage(relativePath: item.imageRelativePath)
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}
