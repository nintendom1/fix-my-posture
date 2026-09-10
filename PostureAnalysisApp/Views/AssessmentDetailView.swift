import SwiftUI

public struct AssessmentDetailView: View {
    public let assessment: PostureAssessment
    public let image: UIImage?
    public var baselineAssessment: PostureAssessment? = nil

    @State private var showOverlay: Bool = true

    public init(assessment: PostureAssessment, image: UIImage?, baselineAssessment: PostureAssessment? = nil) {
        self.assessment = assessment
        self.image = image
        self.baselineAssessment = baselineAssessment
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image = image {
                    GeometryReader { geo in
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)

                            if showOverlay {
                                LandmarkOverlayView(
                                    pose: assessment.pose,
                                    containerSize: geo.size
                                )
                            }
                        }
                    }
                    .frame(height: 350)
                }

                Toggle("Show Landmark Overlay", isOn: $showOverlay)
                    .padding(.horizontal)
                    .accessibilityIdentifier("toggleOverlaySwitch")

                if let base = baselineAssessment {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Baseline Comparison")
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
                                        .foregroundColor(comp.deltaValue == 0 ? .primary : (comp.deltaValue > 0 ? .red : .green))
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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(m.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(String(format: "%.1f", m.value))\(m.unit)")
                                    .bold()
                                    .foregroundColor(.blue)
                            }
                            Text(m.explanation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(assessment.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}
