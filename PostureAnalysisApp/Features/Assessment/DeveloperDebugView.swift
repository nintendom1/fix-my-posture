import SwiftUI
import SwiftData

public struct DeveloperDebugView: View {
    public let assessment: PostureAssessment
    public let processingDuration: TimeInterval

    @Environment(\.dismiss) private var dismiss
    @State private var copiedToClipboard = false

    public init(assessment: PostureAssessment, processingDuration: TimeInterval) {
        self.assessment = assessment
        self.processingDuration = processingDuration
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Summary Diagnostics") {
                    LabeledContent("Posture View", value: assessment.view.displayName)
                    LabeledContent("Processing Time", value: String(format: "%.3f s", processingDuration))
                    LabeledContent("Image Resolution", value: "\(Int(assessment.pose.imageWidth)) x \(Int(assessment.pose.imageHeight)) px")
                    LabeledContent("Total Landmarks", value: "\(assessment.pose.landmarks.count)")
                    LabeledContent("Average Confidence", value: String(format: "%.1f%%", assessment.pose.averageConfidence * 100))
                    LabeledContent("App Version", value: assessment.appVersion)
                }

                Section("Measurements Breakdown") {
                    ForEach(assessment.measurements) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(m.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(String(format: "%.1f", m.value))\(m.unit)")
                                    .bold()
                            }
                            Text("ID: \(m.measurementID.rawValue)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text("Landmarks: " + m.landmarksUsed.map { $0.displayName }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Confidence: \(Int(m.confidence * 100))%")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Raw Landmark Coordinates") {
                    ForEach(Array(assessment.pose.landmarks.values.sorted(by: { $0.type.rawValue < $1.type.rawValue })), id: \.type) { lm in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(lm.type.displayName)
                                    .bold()
                                Spacer()
                                if lm.isManuallyCorrected {
                                    Text("MANUAL")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .cornerRadius(4)
                                }
                                Text(String(format: "Conf: %.0f%%", lm.confidence * 100))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(String(format: "Norm (Vision): (%.3f, %.3f)", lm.normalizedLocation.x, lm.normalizedLocation.y))
                                .font(.caption)
                                .monospaced()
                            Text(String(format: "Pixel (Top-Left): (%.1f, %.1f) px", lm.imageLocation.x, lm.imageLocation.y))
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .monospaced()
                        }
                    }
                }

                Section {
                    Button(action: copyDiagnosticReport) {
                        HStack {
                            Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc")
                            Text(copiedToClipboard ? "Copied Diagnostics to Clipboard!" : "Copy Diagnostics Summary")
                        }
                    }
                }
            }
            .navigationTitle("Developer Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func copyDiagnosticReport() {
        var report = "POSTURE ANALYSIS DIAGNOSTIC REPORT\n"
        report += "Date: \(assessment.date)\n"
        report += "View: \(assessment.view.displayName)\n"
        report += "Processing Time: \(String(format: "%.3f s", processingDuration))\n"
        report += "Image Size: \(Int(assessment.pose.imageWidth))x\(Int(assessment.pose.imageHeight))\n"
        report += "Landmark Count: \(assessment.pose.landmarks.count)\n"
        report += "Average Confidence: \(String(format: "%.1f%%", assessment.pose.averageConfidence * 100))\n\n"
        report += "MEASUREMENTS:\n"
        for m in assessment.measurements {
            report += "- \(m.name) (\(m.measurementID.rawValue)): \(m.value)\(m.unit) [Conf: \(Int(m.confidence * 100))%]\n"
        }

        UIPasteboard.general.string = report
        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            copiedToClipboard = false
        }
    }
}

// MARK: - Previews
#Preview("Developer Debug View") {
    let dummyLandmarks: [LandmarkType: Landmark] = [
        .leftShoulder: Landmark(type: .leftShoulder, normalizedLocation: CGPoint(x: 0.3, y: 0.8), imageLocation: CGPoint(x: 300, y: 400), confidence: 0.95),
        .rightShoulder: Landmark(type: .rightShoulder, normalizedLocation: CGPoint(x: 0.7, y: 0.8), imageLocation: CGPoint(x: 700, y: 400), confidence: 0.95)
    ]
    let pose = BodyPose(landmarks: dummyLandmarks, imageWidth: 1000, imageHeight: 2000)
    let assessment = PostureAssessment(
        imageRelativePath: "dummy.jpeg",
        view: .front,
        pose: pose,
        measurements: [
            PostureMeasurement(id: .shoulderLineAngle, name: "Shoulder Line Angle", value: 1.2, unit: "°", landmarksUsed: [.leftShoulder, .rightShoulder], confidence: 0.95, explanation: "Shoulder line angle is 1.2°.")
        ]
    )
    return DeveloperDebugView(assessment: assessment, processingDuration: 0.124)
}
