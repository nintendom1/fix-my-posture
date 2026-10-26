import SwiftUI
import CoreGraphics

public enum ReferenceStyle: String, CaseIterable, Identifiable {
    case combined = "Combined"
    case skeleton = "Skeleton"
    case silhouette = "Silhouette"

    public var id: String { rawValue }
}

/// Controls whether the reference head keeps its standing oval or follows the pose's head direction.
public enum ReferenceHeadOrientation: Equatable {
    case vertical
    case noseToNeck
}

/// Canvas overlay rendering a stylized figure (Silhouette, Skeleton, or Combined) for reference geometry.
public struct AlignmentReferenceOverlayView: View {
    public let referencePose: ReferencePose
    public let imageSize: CGSize
    public let containerSize: CGSize
    public let style: ReferenceStyle
    public let headOrientation: ReferenceHeadOrientation
    public var strokeColor: Color = .purple
    public var fillColor: Color = Color.purple.opacity(0.3)
    public var proportionWidth: CGFloat? = nil

    public init(
        referencePose: ReferencePose,
        imageSize: CGSize,
        containerSize: CGSize,
        style: ReferenceStyle = .combined,
        headOrientation: ReferenceHeadOrientation = .vertical,
        strokeColor: Color = .purple,
        fillColor: Color = Color.purple.opacity(0.3),
        proportionWidth: CGFloat? = nil
    ) {
        self.referencePose = referencePose
        self.imageSize = imageSize
        self.containerSize = containerSize
        self.style = style
        self.headOrientation = headOrientation
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.proportionWidth = proportionWidth
    }

    public var body: some View {
        Canvas { context, size in
            guard imageSize.width > 0 && imageSize.height > 0 && size.width > 0 && size.height > 0 else { return }

            let fitRect = CoordinateConverter.aspectFitRect(for: imageSize, in: size)
            guard fitRect.width > 0 && fitRect.height > 0 else { return }
            let proportion = proportionWidth ?? fitRect.width

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

            if style == .silhouette || style == .combined,
               let floorY = lyingFloorLineY(in: joints, imageSize: imageSize) {
                var floorPath = Path()
                floorPath.move(to: convertPixelPoint(CGPoint(x: 0, y: floorY)))
                floorPath.addLine(to: convertPixelPoint(CGPoint(x: imageSize.width, y: floorY)))
                context.stroke(floorPath, with: .color(strokeColor.opacity(0.6)),
                               lineWidth: max(2, proportion * 0.008))
            }

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
                    context.stroke(torsoPath, with: .color(strokeColor.opacity(0.85)), lineWidth: 3)
                } else {
                    // A side-view pose commonly contains only the visible shoulder and hip.
                    for (shoulder, hip) in [(LandmarkType.leftShoulder, LandmarkType.leftHip), (.rightShoulder, .rightHip)] {
                        if let shoulderPoint = joints[shoulder], let hipPoint = joints[hip] {
                            var torsoPath = Path()
                            torsoPath.move(to: convertPixelPoint(shoulderPoint))
                            torsoPath.addLine(to: convertPixelPoint(hipPoint))
                            context.stroke(
                                torsoPath,
                                with: .color(fillColor),
                                style: StrokeStyle(lineWidth: proportion * 0.10, lineCap: .round)
                            )
                            context.stroke(torsoPath, with: .color(strokeColor.opacity(0.4)), lineWidth: 1.5)
                            break
                        }
                    }
                }

                // Head ellipse
                let headOrigin = joints[.nose] ?? joints[.leftEar] ?? joints[.rightEar] ?? joints[.neck]
                if let hPt = headOrigin {
                    let containerCenter = convertPixelPoint(hPt)
                    let headRadius: CGFloat = proportion * 0.05
                    let headPath = Self.headEllipsePath(center: containerCenter, radius: headRadius,
                                                        joints: joints, orientation: headOrientation)
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

                let limbThickness: CGFloat = proportion * 0.035
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
                            lineWidth: 4.0,
                            dash: [6.0, 3.0]
                        )
                        context.stroke(linePath, with: .color(strokeColor), style: strokeStyle)
                    }
                }

                // Reference Joint Dots
                for (_, pt) in joints {
                    let p = convertPixelPoint(pt)
                    let radius: CGFloat = 6.0
                    let dotRect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: dotRect), with: .color(strokeColor))
                    context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1.5)
                }
            }
        }
    }

    /// Returns a baseline only for a nearly horizontal side pose with a planted shoulder and ankle.
    private func lyingFloorLineY(in joints: [LandmarkType: CGPoint], imageSize: CGSize) -> CGFloat? {
        for side in BodySide.allCases {
            guard let shoulder = joints[side.shoulder], let ankle = joints[side.ankle],
                  let hip = joints[side.hip], let knee = joints[side.knee] else { continue }
            let bodyLength = ArmGeometry.distance(shoulder, ankle)
            guard bodyLength > 0,
                  abs(shoulder.y - ankle.y) <= max(imageSize.height * 0.03, bodyLength * 0.08),
                  hip.x.isFinite, knee.x.isFinite else { continue }
            return max(shoulder.y, ankle.y) + min(bodyLength * 0.13, imageSize.height * 0.025)
        }
        return nil
    }

    /// Computes the oval geometry used by the Canvas, so orientation behavior stays testable without rendering.
    static func headEllipsePath(center: CGPoint, radius: CGFloat,
                                joints: [LandmarkType: CGPoint],
                                orientation: ReferenceHeadOrientation) -> Path {
        let bounds = CGRect(x: -radius, y: -radius * 1.2, width: radius * 2, height: radius * 2.4)
        let angle = headRotation(in: joints, orientation: orientation)
        guard angle != 0 else {
            return Path(ellipseIn: CGRect(x: center.x + bounds.minX, y: center.y + bounds.minY,
                                          width: bounds.width, height: bounds.height))
        }
        let transform = CGAffineTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle),
                                          tx: center.x, ty: center.y)
        return Path(ellipseIn: bounds).applying(transform)
    }

    /// The nose-to-neck vector is horizontal for the supine figure. Assessment references stay vertical by default.
    private static func headRotation(in joints: [LandmarkType: CGPoint],
                                     orientation: ReferenceHeadOrientation) -> CGFloat {
        guard orientation == .noseToNeck else { return 0 }
        guard let nose = joints[.nose], let neck = joints[.neck] else { return 0 }
        let dx = neck.x - nose.x
        let dy = neck.y - nose.y
        guard hypot(dx, dy) > 0.001 else { return 0 }
        return atan2(dy, dx) - .pi / 2
    }
}
