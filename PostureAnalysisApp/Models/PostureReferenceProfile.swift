import Foundation

/// Defines a target alignment rule for a specific posture measurement.
public struct TargetAlignmentRule: Codable, Hashable {
    public let measurementID: MeasurementID
    public let targetValue: Double
    public let tolerance: Double

    public init(measurementID: MeasurementID, targetValue: Double = 0.0, tolerance: Double = 0.5) {
        self.measurementID = measurementID
        self.targetValue = targetValue
        self.tolerance = tolerance
    }
}

/// Versioned, Codable definition of per-view target alignments and tolerances.
public struct PostureReferenceProfile: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let version: String
    public let perViewRules: [PostureView: [TargetAlignmentRule]]

    public init(id: String, name: String, version: String, perViewRules: [PostureView: [TargetAlignmentRule]]) {
        self.id = id
        self.name = name
        self.version = version
        self.perViewRules = perViewRules
    }
}
