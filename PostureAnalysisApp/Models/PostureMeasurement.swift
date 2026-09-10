import Foundation

/// Individual posture metric measurement.
public struct PostureMeasurement: Codable, Hashable, Identifiable {
    /// Stable identifier for metrics tracking across releases.
    public let measurementID: MeasurementID

    public var id: String { measurementID.rawValue }

    /// User-facing descriptive name of the measurement.
    public let name: String

    /// Numeric value (e.g., degrees or percentage difference).
    public let value: Double

    /// Unit string (e.g., "°", "%", "normalized ratio").
    public let unit: String

    /// Landmarks used to compute this measurement.
    public let landmarksUsed: [LandmarkType]

    /// Calculated confidence / reliability of the measurement [0.0..1.0].
    public let confidence: Double

    /// Objective, non-diagnostic explainable summary of the measurement.
    public let explanation: String

    public init(
        id: MeasurementID,
        name: String,
        value: Double,
        unit: String,
        landmarksUsed: [LandmarkType],
        confidence: Double,
        explanation: String
    ) {
        self.measurementID = id
        self.name = name
        self.value = value
        self.unit = unit
        self.landmarksUsed = landmarksUsed
        self.confidence = confidence
        self.explanation = explanation
    }
}
