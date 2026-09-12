import SwiftUI

public struct PostureCalloutOverlayView: View {
    public let measurements: [PostureMeasurement]
    public let pose: BodyPose
    public let view: PostureView
    public let profile: PostureReferenceProfile
    public var reservedRects: [CGRect] = []

    public var sourcePose: BodyPose?
    public var horizonContext: HorizonContext?
    public var targetRects: [CGRect]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var previous: [PostureCalloutPlacement] = []

    public init(
        measurements: [PostureMeasurement],
        pose: BodyPose,
        view: PostureView,
        profile: PostureReferenceProfile,
        sourcePose: BodyPose? = nil,
        horizonContext: HorizonContext? = nil,
        targetRects: [CGRect] = [],
        reservedRects: [CGRect] = []
    ) {
        self.measurements = measurements
        self.pose = pose
        self.view = view
        self.profile = profile
        self.reservedRects = reservedRects
        self.sourcePose = sourcePose
        self.horizonContext = horizonContext
        self.targetRects = targetRects
    }

    public var body: some View {
        GeometryReader { geometry in
            let items = PostureCalloutLayout.items(
                measurements: measurements, pose: pose, containerSize: geometry.size,
                view: view, profile: profile)
            let placements = PostureCalloutLayout.placements(
                items: items,
                pose: pose,
                containerSize: geometry.size,
                reservedRects: reservedRects,
                targetRects: targetRects,
                previous: previous,
                contentHeight: { item, width in
                    let valueHost = UIHostingController(rootView: PostureCalloutValue(reading: reading(item), unit: item.measurement.unit)
                        .environment(\.dynamicTypeSize, dynamicTypeSize).fixedSize())
                    let naturalValueSize = valueHost.sizeThatFits(in: CGSize(width: 10000, height: 10000))
                    guard naturalValueSize.width <= width - 10 else { return .infinity }
                    let host = UIHostingController(rootView: PostureFloatingCallout(item: item,
                        reading: reading(item)).environment(\.dynamicTypeSize, dynamicTypeSize)
                        .frame(width: width).fixedSize(horizontal: false, vertical: true))
                    return ceil(host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
                }
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for placement in placements {
                        var line = Path()
                        line.move(to: placement.item.anchor)
                        line.addLine(to: nearestPoint(on: placement.frame, to: placement.item.anchor))
                        context.stroke(line, with: .color(PostureFeedbackPalette.color(for: placement.item.feedback)),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }

                ForEach(placements) { placement in
                    PostureFloatingCallout(item: placement.item, reading: reading(placement.item))
                        .frame(width: placement.frame.width, height: placement.frame.height)
                        .position(x: placement.frame.midX, y: placement.frame.midY)
                }
            }
            .onChange(of: placements, initial: true) { _, value in
                if previous != value { previous = value }
            }
        }
        .allowsHitTesting(false)
    }

    private func reading(_ item: PostureCalloutItem) -> String {
        MeasurementPresentation.reading(item.measurement, pose: sourcePose ?? pose, view: view, horizonContext: horizonContext)
    }

    private func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                y: min(max(point.y, rect.minY), rect.maxY))
    }
}

private struct PostureFloatingCallout: View {
    let item: PostureCalloutItem
    let reading: String
    @ScaledMetric(relativeTo: .headline) private var labelSize: CGFloat = 16

    var body: some View {
        let color = PostureFeedbackPalette.color(for: item.feedback)
        VStack(alignment: .leading, spacing: 3) {
            Text(PostureCalloutLayout.shortName(for: item.measurement.measurementID))
                .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            PostureCalloutValue(reading: reading, unit: item.measurement.unit)
                .fixedSize()
            if item.measurement.unit.count > 1 {
                Text(item.measurement.unit)
                    .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(color)
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.black.opacity(0.82))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.9), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.measurement.name), \(reading) \(item.measurement.unit), \(item.feedback.label)")
    }
}

private struct PostureCalloutValue: View {
    let reading: String
    let unit: String
    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 28

    var body: some View {
        Text(reading + (unit.count <= 1 ? unit : ""))
            .font(.system(size: valueSize, weight: .black, design: .monospaced))
    }
}
