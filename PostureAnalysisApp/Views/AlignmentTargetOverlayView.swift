import SwiftUI

public struct AlignmentTargetOverlayView: View {
    public let reference: ReferencePose
    public let imageSize: CGSize
    public var mirrored = false

    public static func rects(reference: ReferencePose?, imageSize: CGSize, containerSize: CGSize, mirrored: Bool = false) -> [CGRect] {
        guard let reference, imageSize.width > 0, imageSize.height > 0 else { return [] }
        return reference.jointLocations.values.map { point in
            let normalized = CGPoint(x: mirrored ? 1 - point.x / imageSize.width : point.x / imageSize.width,
                                     y: 1 - point.y / imageSize.height)
            let p = CoordinateConverter.normalizedToContainer(normalized: normalized, imageSize: imageSize, containerSize: containerSize)
            return CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)
        }
    }

    public var body: some View {
        Canvas { context, size in
            context.clip(to: Path(CoordinateConverter.aspectFitRect(for: imageSize, in: size)))
            for rect in Self.rects(reference: reference, imageSize: imageSize, containerSize: size, mirrored: mirrored) {
                let ring = Path(ellipseIn: rect)
                context.stroke(ring, with: .color(.black), lineWidth: 6)
                context.stroke(ring, with: .color(Color(red: 0.76, green: 0.59, blue: 1)), lineWidth: 3)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Hollow violet rings show personalized alignment targets")
    }
}
