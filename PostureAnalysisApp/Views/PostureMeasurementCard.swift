import SwiftUI

public enum PostureFeedbackPalette {
    public static func color(for feedback: MeasurementFeedback, darkAppearance: Bool = true) -> Color {
        if feedback.isLowConfidence { return .gray }
        switch feedback.severity {
        case .unavailable: return .gray
        case .aligned: return darkAppearance ? Color(red: 0.31, green: 0.87, blue: 0.64) : Color(red: 0.0, green: 0.45, blue: 0.30)
        case .moderate: return darkAppearance ? Color(red: 1.0, green: 0.73, blue: 0.37) : Color(red: 0.68, green: 0.38, blue: 0.0)
        case .high: return darkAppearance ? Color(red: 1.0, green: 0.44, blue: 0.49) : Color(red: 0.72, green: 0.08, blue: 0.13)
        }
    }
}

public struct PostureMeasurementCard: View {
    public let measurement: PostureMeasurement
    public let feedback: MeasurementFeedback
    public var explanation: String? = nil
    public var reading: String? = nil
    public var compact = false
    public var darkAppearance = false

    @ScaledMetric(relativeTo: .headline) private var compactLabelSize: CGFloat = 18
    @ScaledMetric(relativeTo: .headline) private var reportLabelSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 30

    public init(
        measurement: PostureMeasurement,
        feedback: MeasurementFeedback,
        explanation: String? = nil,
        reading: String? = nil,
        compact: Bool = false,
        darkAppearance: Bool = false
    ) {
        self.measurement = measurement
        self.feedback = feedback
        self.explanation = explanation
        self.reading = reading
        self.compact = compact
        self.darkAppearance = darkAppearance
    }

    public var body: some View {
        let severityColor = PostureFeedbackPalette.color(for: feedback, darkAppearance: darkAppearance)
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Text(measurement.name.uppercased())
                .font(.system(size: compact ? compactLabelSize : reportLabelSize, weight: .bold, design: .rounded))
                .foregroundStyle(severityColor)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text("\((reading ?? String(format: "%.1f", measurement.value)))\(measurement.unit)")
                .font(.system(size: valueSize, weight: .black, design: .monospaced))
                .foregroundStyle(severityColor)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Label(feedback.label, systemImage: feedback.symbolName)
                .font(.system(size: compactLabelSize, weight: .bold, design: .rounded))
                .foregroundStyle(feedback.isLowConfidence ? Color.orange : severityColor)
                .lineLimit(2)

            if let explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(darkAppearance ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(darkAppearance ? Color.black.opacity(0.82) : Color(uiColor: .secondarySystemBackground))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(severityColor.opacity(0.8), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(measurement.name), \((reading ?? String(format: "%.1f", measurement.value))) \(measurement.unit), \(feedback.label)")
    }
}
