import SwiftUI
import CoreGraphics

public enum ReferenceStyle: String, CaseIterable, Identifiable {
    case combined = "Combined"
    case skeleton = "Skeleton"
    case silhouette = "Silhouette"

    public var id: String { rawValue }
}

/// Canvas overlay rendering a stylized figure (Silhouette, Skeleton, or Combined) for reference geometry.
public struct AlignmentReferenceOverlayView: View {
    public let referencePose: ReferencePose
    public let imageSize: CGSize
    public let containerSize: CGSize
    public let style: ReferenceStyle
    public var strokeColor: Color = .purple
    public var fillColor: Color = Color.purple.opacity(0.3)

    public init(
        referencePose: ReferencePose,
        imageSize: CGSize,
        containerSize: CGSize,
        style: ReferenceStyle = .combined,
        strokeColor: Color = .purple,
        fillColor: Color = Color.purple.opacity(0.3)
    ) {
        self.referencePose = referencePose
        self.imageSize = imageSize
        self.containerSize = containerSize
        self.style = style
        self.strokeColor = strokeColor
        self.fillColor = fillColor
    }

    public var body: some View {
        Canvas { context, size in
            guard imageSize.width > 0 && imageSize.height > 0 && size.width > 0 && size.height > 0 else { return }

            let fitRect = CoordinateConverter.aspectFitRect(for: imageSize, in: size)
            guard fitRect.width > 0 && fitRect.height > 0 else { return }

            // Helper: Pixel (top-left) to Container space mapping
            func convertPixelPoint(_ pxPt: CGPoint) -> CGPoint {
                let normX = pxPt.x / imageSize.width
                let normY = pxPt.y / imageSize.height
                return CGPoint(
                    x: fitRect.origin.x + normX * fitRect.width,
                    y: fitRect.origin.y + normY * fitRect.height
                )
            }

            // Clip context to aspect-fit image boundaries without clamping joint coordinates
            context.clip(to: Path(fitRect))

            let joints = referencePose.jointLocations

            // 1. Draw Silhouette (Torso, Limb Capsules, Head)
            if style == .silhouette || style == .combined {
                // Torso polygon: leftShoulder, rightShoulder, rightHip, leftHip
                if let lSh = joints[.leftShoulder], let rSh = joints[.rightShoulder],
                   let rHip = joints[.rightHip], let lHip = joints[.leftHip] {
                    var torsoPath = Path()
                    torsoPath.move(to: convertPixelPoint(lSh))
                    torsoPath.addLine(to: convertPixelPoint(rSh))
                    torsoPath.addLine(to: convertPixelPoint(rHip))
                    torsoPath.addLine(to: convertPixelPoint(lHip))
                    torsoPath.closeSubpath()

                    context.fill(torsoPath, with: .color(fillColor))
                    context.stroke(torsoPath, with: .color(strokeColor.opacity(0.6)), lineWidth: 2)
                }

                // Head ellipse
                let headOrigin = joints[.nose] ?? joints[.leftEar] ?? joints[.rightEar] ?? joints[.neck]
                if let hPt = headOrigin {
                    let containerCenter = convertPixelPoint(hPt)
                    let headRadius: CGFloat = fitRect.width * 0.05
                    let headRect = CGRect(
                        x: containerCenter.x - headRadius,
                        y: containerCenter.y - headRadius * 1.2,
                        width: headRadius * 2,
                        height: headRadius * 2.4
                    )
                    let headPath = Path(ellipseIn: headRect)
                    context.fill(headPath, with: .color(fillColor))
                    context.stroke(headPath, with: .color(strokeColor.opacity(0.6)), lineWidth: 2)
                }

                // Rounded limb segments (capsules)
                let limbPairs: [(LandmarkType, LandmarkType)] = [
                    (.leftHip, .leftKnee),
                    (.leftKnee, .leftAnkle),
                    (.rightHip, .rightKnee),
                    (.rightKnee, .rightAnkle),
                    (.leftShoulder, .leftElbow),
                    (.leftElbow, .leftWrist),
                    (.rightShoulder, .rightElbow),
                    (.rightElbow, .rightWrist)
                ]

                let limbThickness: CGFloat = fitRect.width * 0.035
                for (jA, jB) in limbPairs {
                    if let ptA = joints[jA], let ptB = joints[jB] {
                        let pA = convertPixelPoint(ptA)
                        let pB = convertPixelPoint(ptB)

                        var capsulePath = Path()
                        capsulePath.move(to: pA)
                        capsulePath.addLine(to: pB)

                        let strokeStyle = StrokeStyle(
                            lineWidth: limbThickness,
                            lineCap: .round,
                            lineJoin: .round
                        )
                        context.stroke(capsulePath, with: .color(fillColor), style: strokeStyle)
                        context.stroke(capsulePath, with: .color(strokeColor.opacity(0.4)), lineWidth: 1.5)
                    }
                }
            }

            // 2. Draw Skeleton (Lines & Joint Dots)
            if style == .skeleton || style == .combined {
                for conn in referencePose.connections {
                    if let ptA = joints[conn.jointA], let ptB = joints[conn.jointB] {
                        let pA = convertPixelPoint(ptA)
                        let pB = convertPixelPoint(ptB)

                        var linePath = Path()
                        linePath.move(to: pA)
                        linePath.addLine(to: pB)

                        let strokeStyle = StrokeStyle(
                            lineWidth: 3.0,
                            dash: [6.0, 3.0]
                        )
                        context.stroke(linePath, with: .color(strokeColor), style: strokeStyle)
                    }
                }

                // Reference Joint Dots
                for (_, pt) in joints {
                    let p = convertPixelPoint(pt)
                    let radius: CGFloat = 5.0
                    let dotRect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: dotRect), with: .color(strokeColor))
                    context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1.5)
                }
            }
        }
    }
}
