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
    var cameraView: ExerciseCameraView = .front
    var holdsDumbbells = true
    var legs: LegPose = .standing
    var torsoPitch: Double = 0
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

    /// A profile facing +x. Only the near (left) side is drawn, which the silhouette renders as a side view.
    static let sideFigureJoints: [LandmarkType: CGPoint] = [
        .nose: CGPoint(x: 164, y: 136),
        .leftShoulder: CGPoint(x: 150, y: 170),
        .leftHip: CGPoint(x: 150, y: 300),
        .leftKnee: CGPoint(x: 153, y: 385),
        .leftAnkle: CGPoint(x: 150, y: 460)
    ]

    static func pose(for angles: ArmAngles, legs: LegPose = .standing, forearmPlane: MotionPlane = .frontal,
                     cameraView: ExerciseCameraView = .front, torsoPitch: Double = 0) -> ReferencePose {
        if cameraView == .side {
            var joints = sideFigureJoints
            // Lean forward from the hips: the head and shoulder swing toward the way the figure faces.
            if torsoPitch != 0, let hip = joints[.leftHip] {
                let radians = torsoPitch * .pi / 180
                for joint in [LandmarkType.nose, .leftShoulder] {
                    guard let point = joints[joint] else { continue }
                    let dx = point.x - hip.x
                    let dy = point.y - hip.y
                    joints[joint] = CGPoint(x: hip.x + dx * CGFloat(cos(radians)) - dy * CGFloat(sin(radians)),
                                            y: hip.y + dx * CGFloat(sin(radians)) + dy * CGFloat(cos(radians)))
                }
            }
            if let shoulder = joints[.leftShoulder] {
                // Outward is the direction the figure faces.
                let arm = ArmMotion.place(shoulder: shoulder, outward: 1, upperArm: upperArm, forearm: forearm,
                                          angles: angles, forearmPlane: forearmPlane)
                joints[.leftElbow] = arm.elbow
                joints[.leftWrist] = arm.wrist
            }
            return ReferencePose(jointLocations: joints)
        }
        var joints = lowered(figureJoints, by: legs)
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

    /// Front view lowering into a squat: the upper body drops with the hips, the knees push out and dip
    /// slightly, and the feet stay planted.
    static func lowered(_ joints: [LandmarkType: CGPoint], by legs: LegPose) -> [LandmarkType: CGPoint] {
        guard legs != .standing, let hip = joints[.leftHip], let knee = joints[.leftKnee],
              let otherHip = joints[.rightHip] else { return joints }
        var result = joints
        let drop = CGFloat(legs.hipDrop) * ArmGeometry.distance(hip, knee)
        for joint in [LandmarkType.nose, .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip] {
            result[joint]?.y += drop
        }
        let halfWidth = abs(hip.x - otherHip.x) / 2
        let center = (hip.x + otherHip.x) / 2
        for side in BodySide.allCases {
            guard let point = result[side.knee] else { continue }
            let outward: CGFloat = point.x >= center ? 1 : -1
            result[side.knee] = CGPoint(x: point.x + outward * CGFloat(legs.kneeSpread) * halfWidth, y: point.y + drop * 0.1)
        }
        return result
    }

    var body: some View {
        let pose = Self.pose(for: angles, legs: legs, forearmPlane: forearmPlane, cameraView: cameraView, torsoPitch: torsoPitch)
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
                    guard holdsDumbbells else { continue }
                    DumbbellDrawing.draw(in: context, elbow: map(elbow), wrist: map(wrist), forearmLength: Self.forearm * scale)
                }
            }
        }
        .aspectRatio(Self.canvasSize.width / Self.canvasSize.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
