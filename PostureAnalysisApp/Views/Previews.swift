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
