import SwiftUI

// MARK: - SwiftUI Previews for Primary Views

#Preview("Content View - Home") {
    ContentView()
        .modelContainer(for: [AssessmentEntity.self], inMemory: true)
}

#Preview("History View - Empty") {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: [AssessmentEntity.self], inMemory: true)
}

#Preview("Assessment Detail View") {
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

    return NavigationStack {
        AssessmentDetailView(assessment: assessment, image: nil)
    }
}

#Preview("Measurement Feedback Cards") {
    let profile = DefaultPostureReferenceProvider().currentProfile
    let evaluator = MeasurementFeedbackEvaluator()
    let measurements = [
        PostureMeasurement(id: .shoulderLineAngle, name: "Shoulder Line Angle", value: 0.4, unit: "°", landmarksUsed: [], confidence: 0.95, explanation: "Within the geometric reference tolerance."),
        PostureMeasurement(id: .shoulderLineAngle, name: "Shoulder Line Angle", value: 0.8, unit: "°", landmarksUsed: [], confidence: 0.95, explanation: "Outside the geometric reference tolerance."),
        PostureMeasurement(id: .shoulderLineAngle, name: "Shoulder Line Angle", value: 3.2, unit: "°", landmarksUsed: [], confidence: 0.95, explanation: "Farther from the geometric reference."),
        PostureMeasurement(id: .shoulderLineAngle, name: "Shoulder Line Angle", value: 0.4, unit: "°", landmarksUsed: [], confidence: 0.35, explanation: "Detection confidence is too low for color feedback.")
    ]

    return ScrollView {
        VStack(spacing: 16) {
            ForEach(Array(measurements.enumerated()), id: \.offset) { _, measurement in
                PostureMeasurementCard(
                    measurement: measurement,
                    feedback: evaluator.feedback(for: measurement, view: .front, profile: profile),
                    explanation: measurement.explanation
                )
            }
        }
        .padding()
    }
}
