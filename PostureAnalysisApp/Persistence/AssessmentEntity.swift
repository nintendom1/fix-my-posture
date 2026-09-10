import Foundation
import SwiftData

@Model
public final class AssessmentEntity {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var imageRelativePath: String
    public var viewRawValue: String
    public var isBaseline: Bool
    public var appVersion: String
    public var imageWidth: Double
    public var imageHeight: Double
    public var warningsData: Data

    @Relationship(deleteRule: .cascade) public var landmarks: [LandmarkEntity]
    @Relationship(deleteRule: .cascade) public var measurements: [MeasurementEntity]

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        imageRelativePath: String,
        viewRawValue: String,
        isBaseline: Bool = false,
        appVersion: String = "1.0.0",
        imageWidth: Double = 1000.0,
        imageHeight: Double = 2000.0,
        warningsData: Data = Data(),
        landmarks: [LandmarkEntity] = [],
        measurements: [MeasurementEntity] = []
    ) {
        self.id = id
        self.date = date
        self.imageRelativePath = imageRelativePath
        self.viewRawValue = viewRawValue
        self.isBaseline = isBaseline
        self.appVersion = appVersion
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.warningsData = warningsData
        self.landmarks = landmarks
        self.measurements = measurements
    }
}

@Model
public final class LandmarkEntity {
    public var typeRawValue: String
    public var normalizedX: Double
    public var normalizedY: Double
    public var imageX: Double
    public var imageY: Double
    public var confidence: Double
    public var isManuallyCorrected: Bool

    public init(
        typeRawValue: String,
        normalizedX: Double,
        normalizedY: Double,
        imageX: Double,
        imageY: Double,
        confidence: Double,
        isManuallyCorrected: Bool
    ) {
        self.typeRawValue = typeRawValue
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.imageX = imageX
        self.imageY = imageY
        self.confidence = confidence
        self.isManuallyCorrected = isManuallyCorrected
    }
}

@Model
public final class MeasurementEntity {
    public var measurementIDRawValue: String
    public var name: String
    public var value: Double
    public var unit: String
    public var landmarksUsedRaw: String
    public var confidence: Double
    public var explanation: String

    public init(
        measurementIDRawValue: String = "",
        name: String,
        value: Double,
        unit: String,
        landmarksUsedRaw: String,
        confidence: Double,
        explanation: String
    ) {
        self.measurementIDRawValue = measurementIDRawValue
        self.name = name
        self.value = value
        self.unit = unit
        self.landmarksUsedRaw = landmarksUsedRaw
        self.confidence = confidence
        self.explanation = explanation
    }

    public var resolvedID: MeasurementID {
        if !measurementIDRawValue.isEmpty, let id = MeasurementID(rawValue: measurementIDRawValue) {
            return id
        }
        return MeasurementID.fromLegacyName(name)
    }
}
