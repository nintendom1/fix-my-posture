import CoreGraphics
import Foundation

/// The ghost demo for one moment of the guide's motion, in container points. `WorkoutGhostOverlayView` only
/// strokes this geometry; this type alone decides whether a ghost can be drawn. Empty means nothing can be drawn.
struct WorkoutGhostGeometry: Equatable {
    /// One ghost stroke: an arm (shoulder, elbow, wrist; on the floor wrist, elbow, shoulder), a leg (ankle,
    /// knee, hip), or the line joining the two ghost shoulders or hips.
    struct Stroke: Equatable {
        var points: [CGPoint]
        var lineWidth: CGFloat
        /// An arm holding a dumbbell at `points[2]`, with its elbow at `points[1]`.
        var holdsDumbbell = false
    }

    var limbs: [Stroke] = []
    /// Joins the two ghost shoulders (floor) or hips (legs) when both were placed.
    var connector: Stroke?
    /// Ghost forearm length in container points, for sizing dumbbells; 0 for legs.
    var forearmLength: CGFloat = 0

    var isEmpty: Bool { limbs.isEmpty }

    /// The ghost for `angles` and `legs` (one sample of `motion`) over the user's own smoothed joints.
    static func make(overlay: WorkoutOverlayState, metrics: GuideMetrics?, motion: ArmMotion,
                     cameraView: ExerciseCameraView, containerSize: CGSize,
                     angles: ArmAngles, legs: LegPose) -> WorkoutGhostGeometry {
        let imageSize = overlay.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return WorkoutGhostGeometry() }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
        guard fit.width > 0 else { return WorkoutGhostGeometry() }
        // #69 will add sizing fallbacks for Ready poses that do not provide measured metrics.
        guard let metrics else { return WorkoutGhostGeometry() }

        let scale = fit.width / imageSize.width
        let arms = (upper: metrics.upperArm * scale, fore: metrics.forearm * scale)

        if cameraView == .floor {
            func point(_ type: LandmarkType) -> CGPoint? {
                guard let joint = overlay.joints[type], !joint.isStale else { return nil }
                return CoordinateConverter.normalizedToContainer(normalized: joint.location,
                                                                 imageSize: imageSize,
                                                                 containerSize: containerSize)
            }

            var geometry = WorkoutGhostGeometry(forearmLength: arms.fore)
            var shoulders: [CGPoint] = []
            for side in BodySide.allCases {
                let other: BodySide = side == .left ? .right : .left
                guard let wrist = point(side.wrist), let otherWrist = point(other.wrist) else { continue }
                let outward: CGFloat = wrist.x >= otherWrist.x ? 1 : -1
                let arm = ArmMotion.place(shoulder: .zero, outward: outward, upperArm: arms.upper,
                                          forearm: arms.fore, angles: angles)
                let shoulder = CGPoint(x: wrist.x - arm.wrist.x, y: wrist.y - arm.wrist.y)
                let elbow = CGPoint(x: shoulder.x + arm.elbow.x, y: shoulder.y + arm.elbow.y)
                geometry.limbs.append(Stroke(points: [wrist, elbow, shoulder],
                                             lineWidth: max(8, arms.fore * 0.16)))
                shoulders.append(shoulder)
            }
            if shoulders.count == 2 {
                geometry.connector = Stroke(points: shoulders, lineWidth: 8)
            }
            return geometry
        }

        if motion.animatesLegs {
            func point(_ type: LandmarkType) -> CGPoint? {
                guard let joint = overlay.joints[type], !joint.isStale else { return nil }
                return CoordinateConverter.normalizedToContainer(normalized: joint.location,
                                                                 imageSize: imageSize,
                                                                 containerSize: containerSize)
            }

            let standing = ExerciseDemoFigureView.figureJoints
            let lowered = ExerciseDemoFigureView.lowered(standing, by: legs)
            var geometry = WorkoutGhostGeometry()
            var hips: [CGPoint] = []
            for side in BodySide.allCases {
                let other: BodySide = side == .left ? .right : .left
                guard let ankle = point(side.ankle), let knee = point(side.knee), let hip = point(side.hip),
                      let otherAnkle = point(other.ankle),
                      let figureAnkle = standing[side.ankle], let figureKnee = standing[side.knee],
                      let figureHip = standing[side.hip], let loweredKnee = lowered[side.knee],
                      let loweredHip = lowered[side.hip] else { continue }
                let figureLength = ArmGeometry.distance(figureAnkle, figureKnee)
                    + ArmGeometry.distance(figureKnee, figureHip)
                guard figureLength > 0 else { continue }
                let scale = (ArmGeometry.distance(ankle, knee) + ArmGeometry.distance(knee, hip)) / figureLength
                // The figure's left leg is on its larger-x side; match whichever way the user's leg points.
                let flip: CGFloat = (side == .left ? 1 : -1) * (ankle.x >= otherAnkle.x ? 1 : -1)
                func place(_ figurePoint: CGPoint) -> CGPoint {
                    CGPoint(x: ankle.x + (figurePoint.x - figureAnkle.x) * scale * flip,
                            y: ankle.y + (figurePoint.y - figureAnkle.y) * scale)
                }
                let ghostHip = place(loweredHip)
                geometry.limbs.append(Stroke(points: [ankle, place(loweredKnee), ghostHip], lineWidth: 10))
                hips.append(ghostHip)
            }
            if hips.count == 2 {
                geometry.connector = Stroke(points: hips, lineWidth: 10)
            }
            return geometry
        }

        let armAnchors = anchors(overlay: overlay, cameraView: cameraView, containerSize: containerSize)
        guard !armAnchors.isEmpty else { return WorkoutGhostGeometry() }
        var geometry = WorkoutGhostGeometry(forearmLength: arms.fore)
        for (shoulder, outward) in armAnchors {
            let arm = ArmMotion.place(shoulder: shoulder, outward: outward, upperArm: arms.upper,
                                      forearm: arms.fore, angles: angles, forearmPlane: motion.forearmPlane)
            geometry.limbs.append(Stroke(points: [shoulder, arm.elbow, arm.wrist],
                                         lineWidth: max(8, arms.fore * 0.16),
                                         holdsDumbbell: motion.holdsDumbbells))
        }
        return geometry
    }

    /// Where each ghost arm hangs from, and which way is outward. From the front, both shoulders, outward
    /// away from each other. From the side, the near shoulder, outward the way the user faces.
    static func anchors(overlay: WorkoutOverlayState, cameraView: ExerciseCameraView,
                        containerSize: CGSize) -> [(shoulder: CGPoint, outward: CGFloat)] {
        func point(_ joint: OverlayJoint) -> CGPoint {
            CoordinateConverter.normalizedToContainer(normalized: joint.location, imageSize: overlay.imageSize,
                                                      containerSize: containerSize)
        }
        switch cameraView {
        case .front:
            guard let left = overlay.joints[.leftShoulder], !left.isStale,
                  let right = overlay.joints[.rightShoulder], !right.isStale else { return [] }
            let (a, b) = (point(left), point(right))
            return [(a, a.x >= b.x ? 1 : -1), (b, b.x >= a.x ? 1 : -1)]
        case .side:
            guard let side = nearSide(in: overlay), let joint = overlay.joints[side.shoulder] else { return [] }
            let shoulder = point(joint)
            return [(shoulder, facing(from: shoulder, in: overlay, containerSize: containerSize) ?? 1)]
        case .floor:
            // Floor exercises anchor on the hands instead; see the floor geometry above.
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
        let point = CoordinateConverter.normalizedToContainer(normalized: nose.normalizedLocation,
                                                              imageSize: overlay.imageSize,
                                                              containerSize: containerSize)
        return point.x >= shoulder.x ? 1 : -1
    }
}
