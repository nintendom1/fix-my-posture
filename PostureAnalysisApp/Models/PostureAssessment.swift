import Foundation

/// Represents a posture assessment result.
public struct PostureAssessment: Codable, Identifiable, Hashable {
    public let id: UUID
    public var date: Date
    public var imageRelativePath: String
    public var view: PostureView
    public var pose: BodyPose
    public var measurements: [PostureMeasurement]
    public var warnings: [String]
    public var isBaseline: Bool
    public var appVersion: String
    public var horizonContext: HorizonContext?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        imageRelativePath: String,
        view: PostureView,
        pose: BodyPose,
        measurements: [PostureMeasurement],
        warnings: [String] = [],
        isBaseline: Bool = false,
        appVersion: String = "1.0.0",
        horizonContext: HorizonContext? = nil
    ) {
        self.id = id
        self.date = date
        self.imageRelativePath = imageRelativePath
        self.view = view
        self.pose = pose
        self.measurements = measurements
        self.warnings = warnings
        self.isBaseline = isBaseline
        self.appVersion = appVersion
        self.horizonContext = horizonContext
    }
}
