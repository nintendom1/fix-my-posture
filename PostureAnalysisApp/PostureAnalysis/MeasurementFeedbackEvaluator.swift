import Foundation

public enum MeasurementSeverity: Int, CaseIterable, Comparable {
    case unavailable = -1
    case aligned = 0
    case moderate = 1
    case high = 2

    public static func < (lhs: MeasurementSeverity, rhs: MeasurementSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .unavailable: return "Reference unavailable"
        case .aligned: return "Within reference"
        case .moderate: return "Outside reference"
        case .high: return "Further from reference"
        }
    }

    public var symbolName: String {
        switch self {
        case .unavailable: return "questionmark.circle.fill"
        case .aligned: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        }
    }
}

public struct MeasurementFeedback: Equatable {
    public let severity: MeasurementSeverity
    public let normalizedDeviation: Double?
    public let isLowConfidence: Bool

    public var label: String { isLowConfidence ? "Low confidence" : severity.label }
    public var symbolName: String { isLowConfidence ? "waveform.badge.exclamationmark" : severity.symbolName }
}

/// Converts a geometric measurement into presentation feedback using the versioned reference profile.
public struct MeasurementFeedbackEvaluator {
    public let lowConfidenceThreshold: Double

    public init(lowConfidenceThreshold: Double = 0.5) {
        self.lowConfidenceThreshold = lowConfidenceThreshold
    }

    public func feedback(
        for measurement: PostureMeasurement,
        view: PostureView,
        profile: PostureReferenceProfile
    ) -> MeasurementFeedback {
        guard measurement.value.isFinite,
              let rule = profile.rules(for: view).first(where: { $0.measurementID == measurement.measurementID }),
              rule.tolerance > 0 else {
            return MeasurementFeedback(
                severity: .unavailable,
                normalizedDeviation: nil,
                isLowConfidence: measurement.confidence < lowConfidenceThreshold
            )
        }

        let normalizedDeviation = abs(measurement.value - rule.targetValue) / rule.tolerance
        let severity: MeasurementSeverity
        if normalizedDeviation <= 1 {
            severity = .aligned
        } else if normalizedDeviation <= 2 {
            severity = .moderate
        } else {
            severity = .high
        }
        return MeasurementFeedback(
            severity: severity,
            normalizedDeviation: normalizedDeviation,
            isLowConfidence: measurement.confidence < lowConfidenceThreshold
        )
    }
}
