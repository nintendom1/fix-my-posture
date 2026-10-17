import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AssessmentViewModel {
    private(set) var assessment: PostureAssessment
    private(set) var state: AssessmentState

    let baselineAssessment: PostureAssessment?
    let image: UIImage?
    let referenceProvider: PostureReferenceProviding

    private let repository: (any AssessmentRepository)?

    init(
        assessment: PostureAssessment,
        baselineAssessment: PostureAssessment? = nil,
        image: UIImage? = nil,
        repository: (any AssessmentRepository)? = nil,
        referenceProvider: PostureReferenceProviding = DefaultPostureReferenceProvider()
    ) {
        self.assessment = assessment
        self.baselineAssessment = baselineAssessment
        self.image = image
        self.repository = repository
        self.referenceProvider = referenceProvider
        state = Self.makeState(assessment: assessment, baseline: baselineAssessment)
    }

    func saveEditedPose(_ pose: BodyPose) {
        guard let repository else { return }
        let metadata = ImageMetadata(width: pose.imageWidth, height: pose.imageHeight, source: .synthetic)
        let analyzed = PostureAnalyzer().analyze(
            pose: pose,
            imageMetadata: metadata,
            view: assessment.view,
            horizonContext: assessment.horizonContext
        )
        let updated = PostureAssessment(
            id: assessment.id,
            date: assessment.date,
            imageRelativePath: assessment.imageRelativePath,
            view: assessment.view,
            pose: pose,
            measurements: analyzed.measurements,
            warnings: analyzed.warnings,
            isBaseline: assessment.isBaseline,
            appVersion: assessment.appVersion,
            horizonContext: assessment.horizonContext
        )
        do {
            try repository.update(updated)
            assessment = updated
            state = Self.makeState(assessment: updated, baseline: baselineAssessment)
        } catch {
            state = Self.makeState(assessment: assessment, baseline: baselineAssessment, errorMessage: error.localizedDescription)
        }
    }

    private static func makeState(
        assessment: PostureAssessment,
        baseline: PostureAssessment?,
        errorMessage: String? = nil
    ) -> AssessmentState {
        let matchingBaseline = baseline.flatMap { $0.view == assessment.view ? $0 : nil }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMM d, yyyy"

        let comparisonText: String
        if let matchingBaseline {
            let baselineDateFormatter = DateFormatter()
            baselineDateFormatter.locale = Locale(identifier: "en_US_POSIX")
            baselineDateFormatter.dateFormat = "MMM d"
            comparisonText = "\(viewName(assessment.view)) · compared with baseline from \(baselineDateFormatter.string(from: matchingBaseline.date))"
        } else {
            comparisonText = viewName(assessment.view)
        }

        let comparisonByID = Dictionary(
            uniqueKeysWithValues: (matchingBaseline.map { BaselineComparisonEngine.compare(current: assessment, baseline: $0) } ?? [])
                .map { ($0.measurementID, $0) }
        )
        let baselineByID = Dictionary(uniqueKeysWithValues: (matchingBaseline?.measurements ?? []).map { ($0.measurementID, $0) })
        let rows = assessment.measurements.map { measurement in
            let reading = MeasurementPresentation.reading(
                measurement,
                pose: assessment.pose,
                view: assessment.view,
                horizonContext: assessment.horizonContext
            )
            let valueText = formattedValue(reading: reading, unit: measurement.unit, measurement: measurement, view: assessment.view)
            let comparison = comparisonByID[measurement.measurementID]
            let deltaText: String? = comparison.map { item in
                item.deltaValue == 0
                    ? "No change"
                    : "\(item.deltaValue < 0 ? "−" : "+")\(String(format: "%.1f", abs(item.deltaValue)))\(item.unit) vs baseline"
            }
            let baselineText: String? = baselineByID[measurement.measurementID].map { base in
                let baseReading = MeasurementPresentation.reading(
                    base,
                    pose: matchingBaseline?.pose,
                    view: matchingBaseline?.view ?? assessment.view,
                    horizonContext: matchingBaseline?.horizonContext
                )
                return "Baseline \(formattedValue(reading: baseReading, unit: base.unit, measurement: base, view: matchingBaseline?.view ?? assessment.view))"
            }
            return AssessmentMeasurementRow(
                id: measurement.measurementID,
                name: MeasurementPresentation.name(measurement),
                valueText: valueText,
                deltaText: deltaText,
                baselineText: baselineText
            )
        }

        return AssessmentState(
            dateText: dateFormatter.string(from: assessment.date),
            viewComparisonText: comparisonText,
            measurements: rows,
            notice: "These are geometric measurements from your photo.",
            errorMessage: errorMessage
        )
    }

    private static func formattedValue(
        reading: String,
        unit: String,
        measurement: PostureMeasurement,
        view: PostureView
    ) -> String {
        guard let first = reading.first, first == "+" || first == "−" else { return "\(reading)\(unit)" }
        let magnitude = String(reading.dropFirst())
        let qualifier: String
        switch measurement.measurementID {
        case .shoulderLineAngle, .hipLineAngle:
            guard view == .front else { return "\(magnitude)\(unit)" }
            qualifier = first == "+" ? "left high" : "right high"
        case .torsoLateralDeviation, .bodyCenterlineDeviation:
            guard view == .front else { return "\(magnitude)\(unit)" }
            qualifier = first == "+" ? "right" : "left"
        case .headTiltAngle:
            guard view == .front else { return "\(magnitude)\(unit)" }
            qualifier = first == "+" ? "right" : "left"
        case .forwardHeadAngle, .earShoulderHorizontalOffset, .torsoInclinationAngle,
             .hipKneeAlignmentAngle, .overallSagittalBodyLean:
            guard view == .leftSide || view == .rightSide else { return "\(magnitude)\(unit)" }
            qualifier = first == "+" ? "forward" : "back"
        default:
            return "\(magnitude)\(unit)"
        }
        return "\(magnitude)\(unit) \(qualifier)"
    }

    private static func viewName(_ view: PostureView) -> String {
        switch view {
        case .front: return "Front view"
        case .leftSide, .rightSide: return "Side view"
        case .uncertain: return "View not classified"
        }
    }
}
