import SwiftUI

public struct AssessmentDetailView: View {
    public let assessment: PostureAssessment
    public let image: UIImage?
    public var baselineAssessment: PostureAssessment? = nil
    public var referenceProvider: PostureReferenceProviding

    public init(
        assessment: PostureAssessment,
        image: UIImage?,
        baselineAssessment: PostureAssessment? = nil,
        referenceProvider: PostureReferenceProviding = DefaultPostureReferenceProvider()
    ) {
        self.assessment = assessment
        self.image = image
        self.baselineAssessment = baselineAssessment
        self.referenceProvider = referenceProvider
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let displayPose: BodyPose = {
                    if let uiImg = image {
                        return ImageNormalizer.mapPoseToOrientation(assessment.pose, orientation: uiImg.imageOrientation)
                    }
                    return assessment.pose
                }()

                PostureReportView(
                    image: image,
                    pose: displayPose,
                    view: assessment.view,
                    measurements: assessment.measurements,
                    sourcePose: assessment.pose,
                    referenceProvider: referenceProvider
                )

                if let base = baselineAssessment {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Baseline Comparison")
                        Text("Directional metrics compare magnitude changes; knee angles and stance ratios compare original values.").font(.caption)
                            .font(.title3)
                            .bold()

                        let comparisons = BaselineComparisonEngine.compare(current: assessment, baseline: base)
                        if comparisons.isEmpty {
                            Text("No matching measurements found for baseline comparison.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(comparisons) { comp in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(comp.measurementName)
                                            .font(.subheadline)
                                            .bold()
                                        Text("Current: \(String(format: "%.1f", comp.currentValue))\(comp.unit) | Base: \(String(format: "%.1f", comp.baselineValue))\(comp.unit)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(comp.deltaValue >= 0 ? "+" : "")\(String(format: "%.1f", comp.deltaValue))\(comp.unit)")
                                        .bold()
                                        .foregroundColor(comp.deltaValue == 0 ? .secondary : .blue)
                                }
                                .padding(10)
                                .background(Color(uiColor: .tertiarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Measurements (\(assessment.view.displayName))")
                        .font(.title3)
                        .bold()

                    ForEach(assessment.measurements) { m in
                        let feedback = MeasurementFeedbackEvaluator().feedback(
                            for: m,
                            view: assessment.view,
                            profile: referenceProvider.profile(for: assessment.view)
                        )
                        PostureMeasurementCard(
                            measurement: m,
                            feedback: feedback,
                            explanation: MeasurementPresentation.explanation(m),
                            reading: MeasurementPresentation.reading(m, pose: assessment.pose, view: assessment.view)
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(assessment.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}
