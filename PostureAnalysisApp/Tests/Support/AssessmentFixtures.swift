import SwiftUI
@testable import PostureAnalysisApp

enum AssessmentFixtures {
    static let ids: Set<String> = ["assessment"]

    @MainActor
    static func designTabView() -> some View {
        let current = assessment(date: date(10, month: 10), values: [2.1, 1.8, 0.9, 1.2])
        let baseline = assessment(date: date(2), values: [2.7, 1.6, 1.3, 1.2])
        let viewModel = AssessmentViewModel(assessment: current, baselineAssessment: baseline, image: placeholderImage())

        return TabView(selection: .constant(AppTab.posture)) {
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
                .tag(AppTab.train)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.routines.title, systemImage: "list.number") }
                .tag(AppTab.routines)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.progress.title, systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
            NavigationStack {
                ZStack {
                    AuraBackground(tab: .posture)
                    AssessmentScreen(viewModel: viewModel, showsToolbarMenu: false)
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label(AppTab.posture.title, systemImage: "figure.stand") }
            .tag(AppTab.posture)
        }
        .tint(Color(hex: TabBarStyle.design.tintHex(for: .posture)))
    }

    private static func assessment(date: Date, values: [Double]) -> PostureAssessment {
        let definitions: [(MeasurementID, String, [LandmarkType])] = [
            (.headTiltAngle, "Head Tilt Angle", [.leftEye, .rightEye]),
            (.shoulderLineAngle, "Shoulder Line Angle", [.leftShoulder, .rightShoulder]),
            (.torsoLateralDeviation, "Torso Lateral Deviation", [.neck, .leftHip, .rightHip]),
            (.hipLineAngle, "Hip Line Angle", [.leftHip, .rightHip])
        ]
        let measurements = zip(definitions, values).map { definition, value in
            PostureMeasurement(id: definition.0, name: definition.1, value: value, unit: "°", landmarksUsed: definition.2, confidence: 0.95, explanation: "Geometric observation.")
        }
        return PostureAssessment(
            date: date,
            imageRelativePath: "fixture.jpg",
            view: .front,
            pose: pose(),
            measurements: measurements
        )
    }

    private static func pose() -> BodyPose {
        let points: [(LandmarkType, CGFloat, CGFloat)] = [
            (.nose, 300, 100), (.leftEye, 200, 124), (.rightEye, 400, 120),
            (.neck, 304, 180), (.leftShoulder, 220, 220), (.rightShoulder, 380, 216),
            (.leftHip, 250, 528), (.rightHip, 350, 530),
            (.leftAnkle, 250, 1080), (.rightAnkle, 350, 1080)
        ]
        return BodyPose(landmarks: Dictionary(uniqueKeysWithValues: points.map { type, x, y in
            (type, Landmark(type: type, normalizedLocation: CGPoint(x: x / 600, y: 1 - y / 1200), imageLocation: CGPoint(x: x, y: y), confidence: 0.95))
        }), imageWidth: 600, imageHeight: 1200)
    }

    private static func placeholderImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 330))
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor(red: 0.11, green: 0.12, blue: 0.22, alpha: 1).cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 390, height: 330))
            context.cgContext.setStrokeColor(UIColor(red: 0.62, green: 0.69, blue: 1, alpha: 0.65).cgColor)
            context.cgContext.setLineWidth(2)
            context.cgContext.move(to: CGPoint(x: 195, y: 0))
            context.cgContext.addLine(to: CGPoint(x: 195, y: 330))
            context.cgContext.strokePath()
        }
    }

    private static func date(_ day: Int, month: Int = 9) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: day))!
    }
}
