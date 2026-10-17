import SwiftUI

/// Ghost arms that loop the guide's motion over the user's own body before the set starts, fitted to
/// their shoulders and arm lengths. Aspect-fit scaling is uniform, so angles computed in container
/// points stay correct.
struct WorkoutGhostOverlayView: View {
    let overlay: WorkoutOverlayState
    let metrics: GuideMetrics
    let motion: ArmMotion
    var cameraView: ExerciseCameraView = .front

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let ghostColor = Color(red: 0.76, green: 0.59, blue: 1)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(in: context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let imageSize = overlay.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: size)
        guard fit.width > 0 else { return }
        if cameraView == .floor {
            var context = context
            context.clip(to: Path(fit))
            let scale = fit.width / imageSize.width
            let arms = (upper: metrics.upperArm * scale, fore: metrics.forearm * scale)
            if reduceMotion {
                drawFloorArms(in: context, size: size, arms: arms, angles: motion.topAngles, opacity: 0.3)
                drawFloorArms(in: context, size: size, arms: arms, angles: motion.startAngles, opacity: 0.6)
            } else {
                drawFloorArms(in: context, size: size, arms: arms, angles: motion.sample(at: time).angles, opacity: 0.6)
            }
            return
        }
        if motion.animatesLegs {
            var context = context
            context.clip(to: Path(fit))
            if reduceMotion {
                drawLegs(in: context, size: size, legs: motion.topLegs, opacity: 0.3)
                drawLegs(in: context, size: size, legs: motion.startLegs, opacity: 0.6)
            } else {
                drawLegs(in: context, size: size, legs: motion.sample(at: time).legs, opacity: 0.6)
            }
            return
        }
        let anchors = Self.anchors(overlay: overlay, cameraView: cameraView, containerSize: size)
        guard !anchors.isEmpty else { return }
        let scale = fit.width / imageSize.width
        var context = context
        context.clip(to: Path(fit))
        let arms = (upper: metrics.upperArm * scale, fore: metrics.forearm * scale)
        if reduceMotion {
            drawArms(in: context, anchors: anchors, arms: arms, angles: motion.topAngles, opacity: 0.3)
            drawArms(in: context, anchors: anchors, arms: arms, angles: motion.startAngles, opacity: 0.6)
        } else {
            drawArms(in: context, anchors: anchors, arms: arms, angles: motion.sample(at: time).angles, opacity: 0.6)
        }
    }

    /// Where each ghost arm hangs from, and which way is outward. From the front, both shoulders, outward
    /// away from each other. From the side, the near shoulder, outward the way the user faces.
    static func anchors(overlay: WorkoutOverlayState, cameraView: ExerciseCameraView,
                        containerSize: CGSize) -> [(shoulder: CGPoint, outward: CGFloat)] {
        func point(_ joint: OverlayJoint) -> CGPoint {
            CoordinateConverter.normalizedToContainer(normalized: joint.location, imageSize: overlay.imageSize, containerSize: containerSize)
        }
        switch cameraView {
        case .front:
            guard let left = overlay.joints[.leftShoulder], !left.isStale,
                  let right = overlay.joints[.rightShoulder], !right.isStale else { return [] }
            let (a, b) = (point(left), point(right))
            return [(a, a.x >= b.x ? 1 : -1), (b, b.x >= a.x ? 1 : -1)]
        case .side:
            guard let side = Self.nearSide(in: overlay), let joint = overlay.joints[side.shoulder] else { return [] }
            let shoulder = point(joint)
            return [(shoulder, Self.facing(from: shoulder, in: overlay, containerSize: containerSize) ?? 1)]
        case .floor:
            // Floor exercises anchor on the hands instead; see `drawFloorArms`.
            return []
        }
    }

    /// From the side, the arm nearer the phone: the tracked shoulder with the most of its arm in view.
    private static func nearSide(in overlay: WorkoutOverlayState) -> BodySide? {
        func tracked(_ joint: LandmarkType) -> Bool { overlay.joints[joint].map { !$0.isStale } ?? false }
        return BodySide.allCases.filter { tracked($0.shoulder) }
            .max { lhs, rhs in lhs.armJoints.filter(tracked).count < rhs.armJoints.filter(tracked).count }
    }

    /// +1 when the user faces larger x on screen, judged by the nose against the shoulder; nil without a nose.
    private static func facing(from shoulder: CGPoint, in overlay: WorkoutOverlayState,
                               containerSize: CGSize) -> CGFloat? {
        guard let nose = overlay.pose[.nose] else { return nil }
        let point = CoordinateConverter.normalizedToContainer(normalized: nose.normalizedLocation, imageSize: overlay.imageSize,
                                                              containerSize: containerSize)
        return point.x >= shoulder.x ? 1 : -1
    }

    /// Ghost arms rising from the user's own planted hands, showing where the shoulders go.
    private func drawFloorArms(in context: GraphicsContext, size: CGSize, arms: (upper: CGFloat, fore: CGFloat),
                               angles: ArmAngles, opacity: Double) {
        func point(_ type: LandmarkType) -> CGPoint? {
            guard let joint = overlay.joints[type], !joint.isStale else { return nil }
            return CoordinateConverter.normalizedToContainer(normalized: joint.location, imageSize: overlay.imageSize, containerSize: size)
        }
        var shoulders: [CGPoint] = []
        for side in BodySide.allCases {
            let other: BodySide = side == .left ? .right : .left
            guard let wrist = point(side.wrist), let otherWrist = point(other.wrist) else { continue }
            // Lay the arm out from the hand: the shoulder sits where the arm reaches back up.
            let outward: CGFloat = wrist.x >= otherWrist.x ? 1 : -1
            let arm = ArmMotion.place(shoulder: .zero, outward: outward, upperArm: arms.upper, forearm: arms.fore, angles: angles)
            let shoulder = CGPoint(x: wrist.x - arm.wrist.x, y: wrist.y - arm.wrist.y)
            let elbow = CGPoint(x: shoulder.x + arm.elbow.x, y: shoulder.y + arm.elbow.y)
            var path = Path()
            path.move(to: wrist)
            path.addLine(to: elbow)
            path.addLine(to: shoulder)
            context.stroke(path, with: .color(Self.ghostColor.opacity(opacity)),
                           style: StrokeStyle(lineWidth: max(8, arms.fore * 0.16), lineCap: .round, lineJoin: .round))
            shoulders.append(shoulder)
        }
        if shoulders.count == 2 {
            var line = Path()
            line.move(to: shoulders[0])
            line.addLine(to: shoulders[1])
            context.stroke(line, with: .color(Self.ghostColor.opacity(opacity)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        }
    }

    /// Ghost thighs and shins standing on the user's own ankles, scaled to their leg length, showing how
    /// low the demonstration goes.
    private func drawLegs(in context: GraphicsContext, size: CGSize, legs: LegPose, opacity: Double) {
        func point(_ type: LandmarkType) -> CGPoint? {
            guard let joint = overlay.joints[type], !joint.isStale else { return nil }
            return CoordinateConverter.normalizedToContainer(normalized: joint.location, imageSize: overlay.imageSize, containerSize: size)
        }
        let standing = ExerciseDemoFigureView.figureJoints
        let lowered = ExerciseDemoFigureView.lowered(standing, by: legs)
        var hips: [CGPoint] = []
        for side in BodySide.allCases {
            let other: BodySide = side == .left ? .right : .left
            guard let ankle = point(side.ankle), let knee = point(side.knee), let hip = point(side.hip),
                  let otherAnkle = point(other.ankle),
                  let figureAnkle = standing[side.ankle], let figureKnee = standing[side.knee], let figureHip = standing[side.hip],
                  let loweredKnee = lowered[side.knee], let loweredHip = lowered[side.hip] else { continue }
            let figureLength = ArmGeometry.distance(figureAnkle, figureKnee) + ArmGeometry.distance(figureKnee, figureHip)
            guard figureLength > 0 else { continue }
            let scale = (ArmGeometry.distance(ankle, knee) + ArmGeometry.distance(knee, hip)) / figureLength
            // The figure's left leg is on its larger-x side; match whichever way the user's leg points.
            let flip: CGFloat = (side == .left ? 1 : -1) * (ankle.x >= otherAnkle.x ? 1 : -1)
            func place(_ figurePoint: CGPoint) -> CGPoint {
                CGPoint(x: ankle.x + (figurePoint.x - figureAnkle.x) * scale * flip, y: ankle.y + (figurePoint.y - figureAnkle.y) * scale)
            }
            let ghostHip = place(loweredHip)
            var path = Path()
            path.move(to: ankle)
            path.addLine(to: place(loweredKnee))
            path.addLine(to: ghostHip)
            context.stroke(path, with: .color(Self.ghostColor.opacity(opacity)),
                           style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            hips.append(ghostHip)
        }
        if hips.count == 2 {
            var line = Path()
            line.move(to: hips[0])
            line.addLine(to: hips[1])
            context.stroke(line, with: .color(Self.ghostColor.opacity(opacity)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        }
    }

    private func drawArms(in context: GraphicsContext, anchors: [(shoulder: CGPoint, outward: CGFloat)],
                          arms: (upper: CGFloat, fore: CGFloat), angles: ArmAngles, opacity: Double) {
        for (shoulder, outward) in anchors {
            let arm = ArmMotion.place(shoulder: shoulder, outward: outward, upperArm: arms.upper, forearm: arms.fore,
                                      angles: angles, forearmPlane: motion.forearmPlane)
            var path = Path()
            path.move(to: shoulder)
            path.addLine(to: arm.elbow)
            path.addLine(to: arm.wrist)
            context.stroke(path, with: .color(Self.ghostColor.opacity(opacity)),
                           style: StrokeStyle(lineWidth: max(8, arms.fore * 0.16), lineCap: .round, lineJoin: .round))
            var dumbbell = context
            dumbbell.opacity = opacity + 0.2
            if motion.holdsDumbbells {
                DumbbellDrawing.draw(in: dumbbell, elbow: arm.elbow, wrist: arm.wrist, forearmLength: arms.fore)
            }
        }
    }
}
