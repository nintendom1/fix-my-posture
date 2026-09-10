import Foundation

/// Comparison metric between a target assessment and a baseline assessment using stable `MeasurementID`.
public struct PostureComparisonItem: Identifiable, Hashable {
    public var id: MeasurementID { measurementID }

    public let measurementID: MeasurementID
    public let measurementName: String
    public let currentValue: Double
    public let baselineValue: Double
    public let deltaValue: Double
    public let unit: String
    public let explanation: String
}

public struct BaselineComparisonEngine {

    public static func compare(current: PostureAssessment, baseline: PostureAssessment) -> [PostureComparisonItem] {
        guard current.view == baseline.view else {
            return [] // Only compare assessments with identical view perspectives
        }

        var comparisons: [PostureComparisonItem] = []

        // Group baseline measurements safely by stable ID
        var baselineMap: [MeasurementID: PostureMeasurement] = [:]
        for base in baseline.measurements {
            baselineMap[base.measurementID] = base
        }

        for curr in current.measurements {
            if let base = baselineMap[curr.measurementID] {
                let delta = curr.value - base.value
                let roundedDelta = (delta * 10.0).rounded() / 10.0

                let signStr = roundedDelta >= 0 ? "+\(roundedDelta)" : "\(roundedDelta)"
                let exp = "\(curr.name): baseline was \(base.value)\(base.unit), current is \(curr.value)\(curr.unit) (change: \(signStr)\(curr.unit))."

                comparisons.append(PostureComparisonItem(
                    measurementID: curr.measurementID,
                    measurementName: curr.name,
                    currentValue: curr.value,
                    baselineValue: base.value,
                    deltaValue: roundedDelta,
                    unit: curr.unit,
                    explanation: exp
                ))
            }
        }

        return comparisons
    }
}
