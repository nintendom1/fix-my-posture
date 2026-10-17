import Foundation

struct AssessmentMeasurementRow: Equatable, Identifiable {
    let id: MeasurementID
    let name: String
    let valueText: String
    let deltaText: String?
    let baselineText: String?
}

struct AssessmentState: Equatable {
    let dateText: String
    let viewComparisonText: String
    let measurements: [AssessmentMeasurementRow]
    let notice: String
    var errorMessage: String? = nil
}
