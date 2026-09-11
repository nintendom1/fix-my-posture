import SwiftUI
import CoreGraphics

public struct LandmarkOverlayView: View {
    public let pose: BodyPose
    public let containerSize: CGSize
    public var selectedLandmark: LandmarkType?
    public var onSelectLandmark: ((LandmarkType) -> Void)?
    public var showSkeleton: Bool = true
    public var showLandmarks: Bool = true
    public var distanceEmphasis: Bool = false
    public var feedback: [LandmarkType: MeasurementFeedback] = [:]

    public init(
        pose: BodyPose,
        containerSize: CGSize,
        selectedLandmark: LandmarkType? = nil,
        onSelectLandmark: ((LandmarkType) -> Void)? = nil,
        showSkeleton: Bool = true,
        showLandmarks: Bool = true,
        distanceEmphasis: Bool = false,
        feedback: [LandmarkType: MeasurementFeedback] = [:]
    ) {
        self.pose = pose
        self.containerSize = containerSize
        self.selectedLandmark = selectedLandmark
        self.onSelectLandmark = onSelectLandmark
        self.showSkeleton = showSkeleton
        self.showLandmarks = showLandmarks
        self.distanceEmphasis = distanceEmphasis
        self.feedback = feedback
    }

    public var body: some View {
        Canvas { context, size in
            guard size.width > 0 && size.height > 0 && pose.imageWidth > 0 && pose.imageHeight > 0 else { return }

            let imageSize = CGSize(width: pose.imageWidth, height: pose.imageHeight)

            // Helper to convert normalized coordinate (Vision space) to aspect-fitted container coordinates
            func convertPoint(_ normPt: CGPoint) -> CGPoint {
                CoordinateConverter.normalizedToContainer(normalized: normPt, imageSize: imageSize, containerSize: size)
            }

            // 1. Draw Skeleton Connections
            if showSkeleton {
                for (jointA, jointB) in BodyPose.connections {
                    if let lmA = pose[jointA], let lmB = pose[jointB] {
                        let pA = convertPoint(lmA.normalizedLocation)
                        let pB = convertPoint(lmB.normalizedLocation)

                        var path = Path()
                        path.move(to: pA)
                        path.addLine(to: pB)

                        let isCorrected = lmA.isManuallyCorrected || lmB.isManuallyCorrected
                        let strokeColor = isCorrected && onSelectLandmark != nil ? Color.orange : Color.gray
                        context.stroke(path, with: .color(strokeColor.opacity(0.9)), lineWidth: distanceEmphasis ? 5 : 3)
                    }
                }
            }

            // 2. Draw Landmark Points
            if showLandmarks {
                for (type, landmark) in pose.landmarks {
                    let pt = convertPoint(landmark.normalizedLocation)
                    let isSelected = (type == selectedLandmark)
                    let isCorrected = landmark.isManuallyCorrected

                    let radius: CGFloat = isSelected ? 12.0 : (distanceEmphasis ? 9.0 : 7.0)
                    let color: Color = isSelected ? .yellow : (isCorrected && onSelectLandmark != nil ? .orange : feedback[type].map { PostureFeedbackPalette.color(for: $0) } ?? .gray)

                    let circleRect = CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: circleRect), with: .color(color))
                    context.stroke(Path(ellipseIn: circleRect), with: .color(.white), lineWidth: 2)
                }
            }
        }
        .accessibilityLabel(MeasurementPresentation.convention)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    guard let onSelectLandmark = onSelectLandmark else { return }
                    let touchPoint = value.location
                    let imageSize = CGSize(width: pose.imageWidth, height: pose.imageHeight)

                    var closestType: LandmarkType? = nil
                    var minDistance: CGFloat = 35.0 // Touch threshold in container pixels

                    for (type, landmark) in pose.landmarks {
                        let pt = CoordinateConverter.normalizedToContainer(normalized: landmark.normalizedLocation, imageSize: imageSize, containerSize: containerSize)
                        let dist = hypot(pt.x - touchPoint.x, pt.y - touchPoint.y)
                        if dist < minDistance {
                            minDistance = dist
                            closestType = type
                        }
                    }

                    if let selected = closestType {
                        onSelectLandmark(selected)
                    }
                }
        )
    }
}
