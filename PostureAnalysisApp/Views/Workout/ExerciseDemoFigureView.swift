import SwiftUI

/// Draws a dumbbell held at the wrist: the handle runs across the forearm, plates seen edge-on.
enum DumbbellDrawing {
    static let fill = Color(white: 0.32)

    static func draw(in context: GraphicsContext, elbow: CGPoint, wrist: CGPoint, forearmLength: CGFloat,
                     color: Color = fill, outline: Color = .white.opacity(0.85)) {
        let dx = wrist.x - elbow.x
        let dy = wrist.y - elbow.y
        let length = max(hypot(dx, dy), 0.001)
        let along = CGVector(dx: dx / length, dy: dy / length)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        // The hand grips just past the wrist.
        let center = CGPoint(x: wrist.x + along.dx * forearmLength * 0.14, y: wrist.y + along.dy * forearmLength * 0.14)
        let halfHandle = forearmLength * 0.34
        let plateLength = forearmLength * 0.5
        let plateThickness = forearmLength * 0.17

        var handle = Path()
        handle.move(to: CGPoint(x: center.x - across.dx * halfHandle, y: center.y - across.dy * halfHandle))
        handle.addLine(to: CGPoint(x: center.x + across.dx * halfHandle, y: center.y + across.dy * halfHandle))
        context.stroke(handle, with: .color(outline), style: StrokeStyle(lineWidth: forearmLength * 0.09 + 2, lineCap: .round))
        context.stroke(handle, with: .color(color), style: StrokeStyle(lineWidth: forearmLength * 0.09, lineCap: .round))

        // Rotate each plate so its long side follows the forearm.
        let rotation = atan2(along.dy, along.dx) - .pi / 2
        let plateShape = Path(roundedRect: CGRect(x: -plateThickness / 2, y: -plateLength / 2,
                                                  width: plateThickness, height: plateLength),
                              cornerRadius: plateThickness * 0.35)
        for sign: CGFloat in [-1, 1] {
            let plateCenter = CGPoint(x: center.x + across.dx * halfHandle * sign, y: center.y + across.dy * halfHandle * sign)
            let plate = plateShape.applying(CGAffineTransform(translationX: plateCenter.x, y: plateCenter.y).rotated(by: rotation))
            context.fill(plate, with: .color(color))
            context.stroke(plate, with: .color(outline), lineWidth: 1.5)
        }
    }
}

/// A canonical front-view figure holding two dumbbells, posed by `ArmAngles`.
/// The body reuses the posture reference silhouette renderer.
struct ExerciseDemoFigureView: View {
    let angles: ArmAngles
    var forearmPlane: MotionPlane = .frontal
    var tint: Color = Color(red: 0.62, green: 0.42, blue: 0.95)

    /// Figure coordinates in pixels, origin top-left.
    static let canvasSize = CGSize(width: 300, height: 470)
    static let upperArm: CGFloat = 70
    static let forearm: CGFloat = 62
    static let figureJoints: [LandmarkType: CGPoint] = [
        .nose: CGPoint(x: 150, y: 136),
        .neck: CGPoint(x: 150, y: 160),
        .leftShoulder: CGPoint(x: 196, y: 168), .rightShoulder: CGPoint(x: 104, y: 168),
        .leftHip: CGPoint(x: 182, y: 300), .rightHip: CGPoint(x: 118, y: 300),
        .leftKnee: CGPoint(x: 184, y: 385), .rightKnee: CGPoint(x: 116, y: 385),
        .leftAnkle: CGPoint(x: 186, y: 460), .rightAnkle: CGPoint(x: 114, y: 460)
    ]

    static func pose(for angles: ArmAngles, forearmPlane: MotionPlane = .frontal) -> ReferencePose {
        var joints = figureJoints
        for side in BodySide.allCases {
            let other: BodySide = side == .left ? .right : .left
            guard let shoulder = figureJoints[side.shoulder], let otherShoulder = figureJoints[other.shoulder] else { continue }
            let arm = ArmMotion.place(shoulder: shoulder, otherShoulder: otherShoulder,
                                      upperArm: upperArm, forearm: forearm, angles: angles, forearmPlane: forearmPlane)
            joints[side.elbow] = arm.elbow
            joints[side.wrist] = arm.wrist
        }
        return ReferencePose(jointLocations: joints)
    }

    var body: some View {
        let pose = Self.pose(for: angles, forearmPlane: forearmPlane)
        ZStack {
            AlignmentReferenceOverlayView(referencePose: pose, imageSize: Self.canvasSize, containerSize: Self.canvasSize,
                                          style: .silhouette, strokeColor: tint, fillColor: tint.opacity(0.5))
            Canvas { context, size in
                let fit = CoordinateConverter.aspectFitRect(for: Self.canvasSize, in: size)
                guard fit.width > 0 else { return }
                let scale = fit.width / Self.canvasSize.width
                func map(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: fit.minX + point.x * scale, y: fit.minY + point.y * scale)
                }
                for side in BodySide.allCases {
                    guard let elbow = pose.jointLocations[side.elbow], let wrist = pose.jointLocations[side.wrist] else { continue }
                    DumbbellDrawing.draw(in: context, elbow: map(elbow), wrist: map(wrist), forearmLength: Self.forearm * scale)
                }
            }
        }
        .aspectRatio(Self.canvasSize.width / Self.canvasSize.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
