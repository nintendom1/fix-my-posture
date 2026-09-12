import SwiftUI

/// Shared horizon overlay for realtime, current photo reports, and saved assessments.
public struct HorizonOverlayView: View {
    public let angleDegrees: Double
    public let isCompensationApplied: Bool
    public let isMirrored: Bool
    public let imageSize: CGSize
    public let containerSize: CGSize

    public init(
        angleDegrees: Double,
        isCompensationApplied: Bool = true,
        isMirrored: Bool = false,
        imageSize: CGSize,
        containerSize: CGSize
    ) {
        self.angleDegrees = angleDegrees
        self.isCompensationApplied = isCompensationApplied
        self.isMirrored = isMirrored
        self.imageSize = imageSize
        self.containerSize = containerSize
    }

    public init(
        reading: HorizonReading,
        isCompensationApplied: Bool = true,
        isMirrored: Bool = false,
        imageSize: CGSize,
        containerSize: CGSize
    ) {
        self.init(
            angleDegrees: reading.angleDegrees,
            isCompensationApplied: isCompensationApplied,
            isMirrored: isMirrored,
            imageSize: imageSize,
            containerSize: containerSize
        )
    }

    private var formattedAngle: String {
        let rounded = (angleDegrees * 10).rounded() / 10
        let norm = (rounded == 0 || rounded == -0.0) ? 0.0 : rounded
        return String(format: "%+.1f°", norm)
    }

    private var accessibilityText: String {
        let rounded = (angleDegrees * 10).rounded() / 10
        let norm = (rounded == 0 || rounded == -0.0) ? 0.0 : rounded
        let text = String(format: "Horizon line: %+.1f degrees", norm)
        return isCompensationApplied ? text : "\(text), compensation off"
    }

    public var body: some View {
        GeometryReader { _ in
            let imageRect = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
            let center = CGPoint(x: imageRect.width / 2, y: imageRect.height / 2)
            let length = hypot(imageRect.width, imageRect.height) * 1.1
            // In image pixel space, positive angle rises toward image-right (+Y is down).
            // Rotation in SwiftUI: positive degrees rotates CW.
            // In top-left origin pixel space with Y down, rotating CW by -angleDegrees rotates line upward to image-right.
            // When mirrored horizontally, sign flips.
            let displayAngle = isMirrored ? angleDegrees : -angleDegrees

            ZStack {
                // Dark under-stroke for contrast
                Path { path in
                    path.move(to: CGPoint(x: center.x - length / 2, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + length / 2, y: center.y))
                }
                .stroke(Color.black.opacity(0.85), lineWidth: 3.5)

                // Dashed cyan horizon line
                Path { path in
                    path.move(to: CGPoint(x: center.x - length / 2, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + length / 2, y: center.y))
                }
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.0, dash: [8, 6]))

                // Centered angle badge label
                Text("Horizon \(formattedAngle)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.72))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.cyan.opacity(0.6), lineWidth: 1)
                    )
            }
            .frame(width: imageRect.width, height: imageRect.height)
            .rotationEffect(.degrees(displayAngle), anchor: .center)
            .clipped()
            .position(x: imageRect.midX, y: imageRect.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
        .allowsHitTesting(false)
    }
}
