import SwiftUI

/// Draws a dumbbell held at the wrist: the handle runs across the forearm, plates seen edge-on.
enum DumbbellDrawing {
    static let fill = Color(white: 0.32)
    private static let centerOffset: CGFloat = 0.14
    private static let halfHandle: CGFloat = 0.34
    private static let halfPlateLength: CGFloat = 0.25
    private static let halfPlateThickness: CGFloat = 0.085
    private static let handleLineWidth: CGFloat = 0.09

    static func draw(in context: GraphicsContext, elbow: CGPoint, wrist: CGPoint, forearmLength: CGFloat,
                     color: Color = fill, outline: Color = .white.opacity(0.85)) {
        let dx = wrist.x - elbow.x
        let dy = wrist.y - elbow.y
        let length = max(hypot(dx, dy), 0.001)
        let along = CGVector(dx: dx / length, dy: dy / length)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        // The hand grips just past the wrist.
        let center = CGPoint(x: wrist.x + along.dx * forearmLength * centerOffset,
                             y: wrist.y + along.dy * forearmLength * centerOffset)
        let halfHandle = forearmLength * Self.halfHandle
        let plateLength = forearmLength * Self.halfPlateLength * 2
        let plateThickness = forearmLength * Self.halfPlateThickness * 2

        var handle = Path()
        handle.move(to: CGPoint(x: center.x - across.dx * halfHandle, y: center.y - across.dy * halfHandle))
        handle.addLine(to: CGPoint(x: center.x + across.dx * halfHandle, y: center.y + across.dy * halfHandle))
        context.stroke(handle, with: .color(outline), style: StrokeStyle(lineWidth: forearmLength * Self.handleLineWidth + 2, lineCap: .round))
        context.stroke(handle, with: .color(color), style: StrokeStyle(lineWidth: forearmLength * Self.handleLineWidth, lineCap: .round))

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

    /// Conservative bounds for the actual handle and plates, including their outlines.
    static func bounds(elbow: CGPoint, wrist: CGPoint, forearmLength: CGFloat) -> CGRect {
        let dx = wrist.x - elbow.x
        let dy = wrist.y - elbow.y
        let length = max(hypot(dx, dy), 0.001)
        let along = CGVector(dx: dx / length, dy: dy / length)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        let center = CGPoint(x: wrist.x + along.dx * forearmLength * centerOffset,
                             y: wrist.y + along.dy * forearmLength * centerOffset)
        let handleHalfWidth = forearmLength * halfHandle
        var result = CGRect.null
        func include(_ point: CGPoint, radius: CGFloat) {
            result = result.union(CGRect(x: point.x - radius, y: point.y - radius,
                                         width: radius * 2, height: radius * 2))
        }

        let handleRadius = abs(forearmLength) * handleLineWidth / 2 + 2
        for sign: CGFloat in [-1, 1] {
            include(CGPoint(x: center.x + across.dx * handleHalfWidth * sign,
                            y: center.y + across.dy * handleHalfWidth * sign), radius: handleRadius)
            let plateCenter = CGPoint(x: center.x + across.dx * handleHalfWidth * sign,
                                      y: center.y + across.dy * handleHalfWidth * sign)
            for alongSign: CGFloat in [-1, 1] {
                for acrossSign: CGFloat in [-1, 1] {
                    include(CGPoint(x: plateCenter.x
                                        + along.dx * forearmLength * halfPlateLength * alongSign
                                        + across.dx * forearmLength * halfPlateThickness * acrossSign,
                                    y: plateCenter.y
                                        + along.dy * forearmLength * halfPlateLength * alongSign
                                        + across.dy * forearmLength * halfPlateThickness * acrossSign),
                            radius: 2.75)
                }
            }
        }
        return result
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
    var shape: FigureShape = .neutral
    /// Bounds from `bounds(for:cameraView:)`; the default keeps the original canvas framing.
    var figureBounds: CGRect = CGRect(x: 0, y: 0, width: 300, height: 470)
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

    /// Hands planted on the floor in the floor view; the shoulders hang above them by the arm pose.
    static let floorHands: [BodySide: CGPoint] = [.left: CGPoint(x: 196, y: 430), .right: CGPoint(x: 104, y: 430)]

    /// Seen from a phone on the floor facing the head: hands planted, shoulders above them by the arm
    /// pose, head above the shoulders, and the hips just beyond them as the body recedes.
    static func floorPose(for angles: ArmAngles) -> ReferencePose {
        var joints: [LandmarkType: CGPoint] = [:]
        for side in BodySide.allCases {
            guard let hand = floorHands[side] else { continue }
            let arm = ArmMotion.place(shoulder: .zero, outward: side == .left ? 1 : -1, upperArm: upperArm, forearm: forearm, angles: angles)
            let shoulder = CGPoint(x: hand.x - arm.wrist.x, y: hand.y - arm.wrist.y)
            joints[side.shoulder] = shoulder
            joints[side.elbow] = CGPoint(x: shoulder.x + arm.elbow.x, y: shoulder.y + arm.elbow.y)
            joints[side.wrist] = hand
        }
        if let left = joints[.leftShoulder], let right = joints[.rightShoulder] {
            let middle = ArmGeometry.midpoint(left, right)
            joints[.nose] = CGPoint(x: middle.x, y: middle.y - 34)
            joints[.leftHip] = CGPoint(x: middle.x + 26, y: middle.y - 16)
            joints[.rightHip] = CGPoint(x: middle.x - 26, y: middle.y - 16)
        }
        return ReferencePose(jointLocations: joints)
    }

    static func pose(for angles: ArmAngles, legs: LegPose = .standing, forearmPlane: MotionPlane = .frontal,
                     cameraView: ExerciseCameraView = .front, torsoPitch: Double = 0) -> ReferencePose {
        pose(for: ArmMotionSample(angles: angles, stepIndex: 0, legs: legs,
                                  shape: FigureShape(torsoPitch: torsoPitch)),
             forearmPlane: forearmPlane, cameraView: cameraView)
    }

    /// Primary figure-pose entry point for one resolved guide sample.
    static func pose(for sample: ArmMotionSample, forearmPlane: MotionPlane = .frontal,
                     cameraView: ExerciseCameraView = .front) -> ReferencePose {
        let angles = sample.angles
        let legs = sample.legs
        if cameraView == .floor { return floorPose(for: angles) }
        if cameraView == .side {
            var joints = sidePose(shape: sample.shape)
            if let shoulder = joints[.leftShoulder] {
                // Outward is the direction the figure faces.
                let arm = ArmMotion.place(shoulder: shoulder, outward: 1, upperArm: upperArm, forearm: forearm,
                                          angles: angles, forearmPlane: forearmPlane)
                joints[.leftElbow] = arm.elbow
                joints[.leftWrist] = arm.wrist
            }
            return ReferencePose(jointLocations: joints)
        }
        var joints = lifted(lowered(figureJoints, by: legs), shoulderLift: sample.shape.shoulderLift)
        for side in BodySide.allCases {
            let other: BodySide = side == .left ? .right : .left
            guard let shoulder = joints[side.shoulder], let otherShoulder = joints[other.shoulder] else { continue }
            let arm = ArmMotion.place(shoulder: shoulder, otherShoulder: otherShoulder,
                                      upperArm: upperArm, forearm: forearm, angles: angles, forearmPlane: forearmPlane)
            joints[side.elbow] = arm.elbow
            joints[side.wrist] = arm.wrist
        }
        return ReferencePose(jointLocations: joints)
    }

    /// The smallest canvas-space rectangle that contains the original canvas and all poses in a motion.
    /// Nine samples per move capture wide or long intermediate shapes between keyframes.
    static func bounds(for motion: ArmMotion, cameraView: ExerciseCameraView) -> CGRect {
        var result = CGRect(origin: .zero, size: canvasSize)
        guard !motion.keyframes.isEmpty else { return result }
        var samples = [motion.startSample]
        var elapsed: TimeInterval = 0
        for keyframe in motion.keyframes {
            if keyframe.moveDuration > 0 {
                for index in 1...9 {
                    samples.append(motion.sample(at: elapsed + keyframe.moveDuration * Double(index) / 9))
                }
            }
            samples.append(motion.sample(of: keyframe))
            elapsed += keyframe.moveDuration + keyframe.holdDuration
        }

        for sample in samples {
            let pose = pose(for: sample, forearmPlane: motion.forearmPlane, cameraView: cameraView)
            for point in pose.jointLocations.values {
                guard point.x.isFinite, point.y.isFinite else { continue }
                result = result.union(CGRect(x: point.x, y: point.y, width: 0.001, height: 0.001))
            }
            if let nose = pose.jointLocations[.nose] {
                let radiusX = canvasSize.width * 0.05
                let radiusY = radiusX * 1.2
                result = result.union(CGRect(x: nose.x - radiusX, y: nose.y - radiusY,
                                             width: radiusX * 2, height: radiusY * 2))
            }
            if motion.holdsDumbbells {
                for side in BodySide.allCases {
                    guard let elbow = pose.jointLocations[side.elbow],
                          let wrist = pose.jointLocations[side.wrist] else { continue }
                    result = result.union(DumbbellDrawing.bounds(elbow: elbow, wrist: wrist,
                                                                 forearmLength: forearm))
                }
            }
        }
        return result
    }

    private static func sidePose(shape: FigureShape) -> [LandmarkType: CGPoint] {
        var joints = sideFigureJoints
        guard let standingHip = sideFigureJoints[.leftHip],
              let standingKnee = sideFigureJoints[.leftKnee],
              let standingAnkle = sideFigureJoints[.leftAnkle] else { return joints }
        let thigh = ArmGeometry.distance(standingHip, standingKnee)
        let shin = ArmGeometry.distance(standingKnee, standingAnkle)
        let leg = thigh + shin
        let hip = CGPoint(x: standingHip.x - CGFloat(shape.hipShift) * thigh,
                          y: standingHip.y + CGFloat(shape.hipDrop) * leg)
        let knee = ArmGeometry.twoBoneKnee(hip: hip, ankle: standingAnkle, thighLength: thigh,
                                           shinLength: shin, bendDirection: 1)
        joints[.leftHip] = hip
        joints[.leftKnee] = knee
        joints[.leftAnkle] = standingAnkle
        if shape.stride > 0 {
            let rearAnkle = CGPoint(x: standingAnkle.x - CGFloat(shape.stride) * leg,
                                    y: standingAnkle.y)
            joints[.rightHip] = hip
            joints[.rightKnee] = ArmGeometry.twoBoneKnee(hip: hip, ankle: rearAnkle,
                                                         thighLength: thigh, shinLength: shin,
                                                         bendDirection: 1)
            joints[.rightAnkle] = rearAnkle
        }

        let pitch = (shape.torsoPitch ?? 0) * .pi / 180
        for joint in [LandmarkType.nose, .leftShoulder] {
            guard let point = sideFigureJoints[joint] else { continue }
            let moved = CGPoint(x: point.x + hip.x - standingHip.x,
                                y: point.y + hip.y - standingHip.y)
            let dx = moved.x - hip.x
            let dy = moved.y - hip.y
            joints[joint] = CGPoint(x: hip.x + dx * CGFloat(cos(pitch)) - dy * CGFloat(sin(pitch)),
                                    y: hip.y + dx * CGFloat(sin(pitch)) + dy * CGFloat(cos(pitch)))
        }
        return joints
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

    /// Front view shrugging: both shoulders and the neck rise by `shoulderLift` upper-arm lengths while the nose
    /// and hips stay put, so the torso stretches up to the raised shoulders. Arms then hang from the new shoulders.
    static func lifted(_ joints: [LandmarkType: CGPoint], shoulderLift: Double) -> [LandmarkType: CGPoint] {
        guard shoulderLift != 0 else { return joints }
        var result = joints
        let rise = CGFloat(shoulderLift) * upperArm
        for joint in [LandmarkType.neck, .leftShoulder, .rightShoulder] {
            result[joint]?.y -= rise
        }
        return result
    }

    /// `shape` with the view-level pitch filled in when the shape doesn't set its own.
    private var resolvedShape: FigureShape {
        var resolved = shape
        resolved.torsoPitch = shape.torsoPitch ?? torsoPitch
        return resolved
    }

    /// The same resolved sample and pose used by the guide and detail figure renderers.
    var displayedPose: ReferencePose {
        let sample = ArmMotionSample(angles: angles, stepIndex: 0, legs: legs, shape: resolvedShape)
        return Self.pose(for: sample, forearmPlane: forearmPlane, cameraView: cameraView)
    }

    var body: some View {
        let pose = displayedPose
        let bounds = figureBounds.width > 0 && figureBounds.height > 0
            ? figureBounds : CGRect(origin: .zero, size: Self.canvasSize)
        let localPose = ReferencePose(jointLocations: pose.jointLocations.mapValues { point in
            CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
        })
        GeometryReader { geometry in
            let size = geometry.size
            let fit = CoordinateConverter.aspectFitRect(for: bounds.size, in: size)
            let scale = fit.width / bounds.width
            ZStack {
                AlignmentReferenceOverlayView(referencePose: localPose,
                                              imageSize: bounds.size, containerSize: size,
                                              style: .silhouette, strokeColor: tint, fillColor: tint.opacity(0.5),
                                              proportionWidth: Self.canvasSize.width * scale)
                Canvas { context, _ in
                    guard fit.width > 0 else { return }
                    func map(_ point: CGPoint) -> CGPoint {
                        CGPoint(x: fit.minX + (point.x - bounds.minX) * scale,
                                y: fit.minY + (point.y - bounds.minY) * scale)
                    }
                    if cameraView == .floor {
                        var floorLine = Path()
                        floorLine.move(to: map(CGPoint(x: 20, y: 436)))
                        floorLine.addLine(to: map(CGPoint(x: 280, y: 436)))
                        context.stroke(floorLine, with: .color(tint.opacity(0.6)), lineWidth: 2)
                    }
                    for side in BodySide.allCases {
                        guard let elbow = pose.jointLocations[side.elbow],
                              let wrist = pose.jointLocations[side.wrist], holdsDumbbells else { continue }
                        DumbbellDrawing.draw(in: context, elbow: map(elbow), wrist: map(wrist),
                                             forearmLength: Self.forearm * scale)
                    }
                }
            }
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
