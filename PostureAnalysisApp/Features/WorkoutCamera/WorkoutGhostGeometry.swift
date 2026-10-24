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
        /// The body labels for each point, in the same order as `points`.
        var joints: [LandmarkType] = []
    }

    /// The guide figure in container points, labeled like the guide figure (`ExerciseDemoFigureView`).
    struct Figure: Equatable {
        struct Dumbbell: Equatable { var elbow: CGPoint; var wrist: CGPoint }
        var joints: [LandmarkType: CGPoint] = [:]
        /// Container points per guide-canvas unit; the head and limbs are sized like the guide figure's.
        var bodyScale: CGFloat = 0
        var dumbbells: [Dumbbell] = []
        var forearmLength: CGFloat = 0
        var isCalibrated = false
        var isEmpty: Bool { joints.isEmpty }
    }

    static let glideDuration: TimeInterval = 0.4
    static let defaultImageSize = CGSize(width: 1080, height: 1920)

    var limbs: [Stroke] = []
    /// Joins the two ghost shoulders (floor) or hips (legs) when both were placed.
    var connector: Stroke?
    /// Ghost forearm length in container points, for sizing dumbbells; 0 for legs.
    var forearmLength: CGFloat = 0

    var isEmpty: Bool { limbs.isEmpty }

    /// The figure at the spot framing wants the user, looping the guide motion.
    static func ideal(overlay: WorkoutOverlayState?, motion: ArmMotion, cameraView: ExerciseCameraView,
                      containerSize: CGSize, angles: ArmAngles, legs: LegPose) -> Figure {
        let imageSize = overlay?.imageSize ?? defaultImageSize
        guard containerSize.width > 0, containerSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return Figure() }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
        let canvas = ExerciseDemoFigureView.canvasSize
        guard fit.width > 0, fit.height > 0 else { return Figure() }

        let scale = 0.9 * min(fit.width / canvas.width, fit.height / canvas.height)
        guard scale > 0 else { return Figure() }
        let offset = CGPoint(x: fit.midX - canvas.width * scale / 2,
                             y: fit.midY - canvas.height * scale / 2)
        let pose = ExerciseDemoFigureView.pose(for: angles, legs: legs,
                                               forearmPlane: motion.forearmPlane,
                                               cameraView: cameraView,
                                               torsoPitch: motion.torsoPitch)
        let mirrored = idealNeedsMirror(overlay: overlay, motion: motion, cameraView: cameraView,
                                        containerSize: containerSize)
        func map(_ point: CGPoint) -> CGPoint {
            let x = mirrored ? canvas.width - point.x : point.x
            return CGPoint(x: offset.x + x * scale, y: offset.y + point.y * scale)
        }
        let joints = pose.jointLocations.mapValues(map)
        let dumbbells: [Figure.Dumbbell] = motion.holdsDumbbells
            ? BodySide.allCases.compactMap { side in
                guard let elbow = joints[side.elbow], let wrist = joints[side.wrist] else { return nil }
                return Figure.Dumbbell(elbow: elbow, wrist: wrist)
            }
            : []
        return Figure(joints: joints,
                      bodyScale: scale,
                      dumbbells: dumbbells,
                      forearmLength: ExerciseDemoFigureView.forearm * scale,
                      isCalibrated: false)
    }

    /// The figure fitted to the user: exact limbs from `make`, with the body placed around them.
    static func calibrated(fitOverlay: WorkoutOverlayState?, metrics: GuideMetrics?, motion: ArmMotion,
                           cameraView: ExerciseCameraView, containerSize: CGSize,
                           angles: ArmAngles, legs: LegPose) -> Figure? {
        guard GhostCalibration.canFit(overlay: fitOverlay, metrics: metrics, motion: motion,
                                      cameraView: cameraView),
              let fitOverlay,
              fitOverlay.imageSize.width > 0, fitOverlay.imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return nil }

        let limbs = make(overlay: fitOverlay, metrics: metrics, motion: motion, cameraView: cameraView,
                         containerSize: containerSize, angles: angles, legs: legs).limbs
        let fit = CoordinateConverter.aspectFitRect(for: fitOverlay.imageSize, in: containerSize)
        guard fit.width > 0 else { return nil }
        let fitScale = fit.width / fitOverlay.imageSize.width
        let canvas = ExerciseDemoFigureView.canvasSize
        let fallbackScale = 0.9 * min(fit.width / canvas.width, fit.height / canvas.height)
        let pose = ExerciseDemoFigureView.pose(for: angles, legs: legs,
                                               forearmPlane: motion.forearmPlane,
                                               cameraView: cameraView,
                                               torsoPitch: motion.torsoPitch)
        let mirrored = calibratedNeedsMirror(overlay: fitOverlay, limbs: limbs, pose: pose,
                                             motion: motion, cameraView: cameraView,
                                             containerSize: containerSize)
        let scale: CGFloat
        if motion.animatesLegs {
            // Measured on the user's own leg, not the ghost's lowered one, so the body keeps its size
            // through the squat.
            let legScales = limbs.compactMap { limb -> CGFloat? in
                guard limb.joints.count == 3,
                      let ankle = point(limb.joints[0], in: fitOverlay, containerSize: containerSize),
                      let knee = point(limb.joints[1], in: fitOverlay, containerSize: containerSize),
                      let hip = point(limb.joints[2], in: fitOverlay, containerSize: containerSize),
                      let figureAnkle = ExerciseDemoFigureView.figureJoints[limb.joints[0]],
                      let figureKnee = ExerciseDemoFigureView.figureJoints[limb.joints[1]],
                      let figureHip = ExerciseDemoFigureView.figureJoints[limb.joints[2]] else { return nil }
                let figureLength = ArmGeometry.distance(figureAnkle, figureKnee)
                    + ArmGeometry.distance(figureKnee, figureHip)
                guard figureLength > 0 else { return nil }
                return (ArmGeometry.distance(ankle, knee) + ArmGeometry.distance(knee, hip)) / figureLength
            }
            scale = legScales.isEmpty
                ? fallbackScale
                : legScales.reduce(0, +) / CGFloat(legScales.count)
        } else {
            let metrics = metrics ?? GuideMetrics(upperArm: ExerciseDemoFigureView.upperArm,
                                                  forearm: ExerciseDemoFigureView.forearm)
            let guideLength = ExerciseDemoFigureView.upperArm + ExerciseDemoFigureView.forearm
            scale = (metrics.upperArm + metrics.forearm) * fitScale / guideLength
        }

        let targetAnchor: CGPoint
        let sourceAnchor: CGPoint
        if cameraView == .side {
            let shoulderSide = nearSide(in: fitOverlay)
            let trackedShoulder = shoulderSide.flatMap { point($0.shoulder, in: fitOverlay,
                                                               containerSize: containerSize) }
            targetAnchor = limbs.first?.points.first ?? trackedShoulder ?? CGPoint(x: fit.midX, y: fit.midY)
            sourceAnchor = pose.jointLocations[.leftShoulder] ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        } else if cameraView == .floor {
            let hands = [point(.leftWrist, in: fitOverlay, containerSize: containerSize),
                         point(.rightWrist, in: fitOverlay, containerSize: containerSize)].compactMap { $0 }
            targetAnchor = midpoint(of: hands) ?? CGPoint(x: fit.midX, y: fit.midY)
            let figureHands = [ExerciseDemoFigureView.floorHands[.left],
                               ExerciseDemoFigureView.floorHands[.right]].compactMap { $0 }
            sourceAnchor = midpoint(of: figureHands) ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        } else if motion.animatesLegs {
            if limbs.count == 1 {
                let label = limbs[0].joints.first ?? .leftAnkle
                targetAnchor = limbs[0].points.first ?? point(label, in: fitOverlay, containerSize: containerSize)
                    ?? CGPoint(x: fit.midX, y: fit.midY)
                sourceAnchor = pose.jointLocations[label] ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            } else if limbs.count >= 2,
                      let left = limbs.first(where: { $0.joints.first == LandmarkType.leftAnkle })?.points.first,
                      let right = limbs.first(where: { $0.joints.first == LandmarkType.rightAnkle })?.points.first,
                      let leftAnkle = pose.jointLocations[.leftAnkle],
                      let rightAnkle = pose.jointLocations[.rightAnkle] {
                targetAnchor = ArmGeometry.midpoint(left, right)
                sourceAnchor = ArmGeometry.midpoint(leftAnkle, rightAnkle)
            } else {
                let userAnkles = [point(.leftAnkle, in: fitOverlay, containerSize: containerSize),
                                  point(.rightAnkle, in: fitOverlay, containerSize: containerSize)].compactMap { $0 }
                targetAnchor = midpoint(of: userAnkles) ?? CGPoint(x: fit.midX, y: fit.midY)
                let figureAnkles = [pose.jointLocations[.leftAnkle], pose.jointLocations[.rightAnkle]].compactMap { $0 }
                sourceAnchor = midpoint(of: figureAnkles) ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            }
        } else {
            let userShoulders = [point(.leftShoulder, in: fitOverlay, containerSize: containerSize),
                                 point(.rightShoulder, in: fitOverlay, containerSize: containerSize)].compactMap { $0 }
            targetAnchor = midpoint(of: userShoulders) ?? CGPoint(x: fit.midX, y: fit.midY)
            let figureShoulders = [pose.jointLocations[.leftShoulder],
                                   pose.jointLocations[.rightShoulder]].compactMap { $0 }
            sourceAnchor = midpoint(of: figureShoulders) ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        }

        let transformedSource = transform(sourceAnchor, scale: scale, mirrored: mirrored)
        let translation = CGPoint(x: targetAnchor.x - transformedSource.x,
                                  y: targetAnchor.y - transformedSource.y)
        func map(_ point: CGPoint) -> CGPoint {
            let scaled = transform(point, scale: scale, mirrored: mirrored)
            return CGPoint(x: scaled.x + translation.x, y: scaled.y + translation.y)
        }

        var joints = pose.jointLocations.mapValues(map)
        var dumbbells: [Figure.Dumbbell] = []
        for limb in limbs where limb.holdsDumbbell && limb.points.count >= 3 {
            let labels = calibratedLabels(for: limb.joints, cameraView: cameraView, motion: motion)
            for (label, point) in zip(labels, limb.points) {
                joints[label] = point
            }
            dumbbells.append(Figure.Dumbbell(elbow: limb.points[1], wrist: limb.points[2]))
        }
        for limb in limbs where !limb.holdsDumbbell {
            let labels = calibratedLabels(for: limb.joints, cameraView: cameraView, motion: motion)
            for (label, point) in zip(labels, limb.points) {
                joints[label] = point
            }
        }
        let forearmLength = motion.animatesLegs
            ? ExerciseDemoFigureView.forearm * scale
            : (metrics?.forearm ?? ExerciseDemoFigureView.forearm) * fitScale
        return Figure(joints: joints,
                      bodyScale: scale,
                      dumbbells: dumbbells,
                      forearmLength: forearmLength,
                      isCalibrated: true)
    }

    /// Linear blend of figure geometry, keeping labels that only appear in either endpoint.
    static func blended(from: Figure, to: Figure, progress: Double) -> Figure {
        let amount = CGFloat(max(0, min(1, progress)))
        var joints = from.joints
        for (label, point) in to.joints {
            if let start = from.joints[label] {
                joints[label] = interpolate(start, point, amount)
            } else {
                joints[label] = point
            }
        }
        if from.dumbbells.count == to.dumbbells.count {
            let dumbbells = zip(from.dumbbells, to.dumbbells).map { start, end in
                Figure.Dumbbell(elbow: interpolate(start.elbow, end.elbow, amount),
                                wrist: interpolate(start.wrist, end.wrist, amount))
            }
            return Figure(joints: joints,
                          bodyScale: from.bodyScale + (to.bodyScale - from.bodyScale) * amount,
                          dumbbells: dumbbells,
                          forearmLength: from.forearmLength + (to.forearmLength - from.forearmLength) * amount,
                          isCalibrated: to.isCalibrated)
        }
        return Figure(joints: joints,
                      bodyScale: from.bodyScale + (to.bodyScale - from.bodyScale) * amount,
                      dumbbells: to.dumbbells,
                      forearmLength: from.forearmLength + (to.forearmLength - from.forearmLength) * amount,
                      isCalibrated: to.isCalibrated)
    }

    /// Eased 0…1 progress of a glide that started at `start`.
    static func glideProgress(since start: TimeInterval?, now: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion, let start else { return 1 }
        let progress = max(0, min(1, (now - start) / glideDuration))
        return progress * progress * (3 - 2 * progress)
    }

    /// The ghost for `angles` and `legs` (one sample of `motion`) over the user's own smoothed joints.
    static func make(overlay: WorkoutOverlayState, metrics: GuideMetrics?, motion: ArmMotion,
                     cameraView: ExerciseCameraView, containerSize: CGSize,
                     angles: ArmAngles, legs: LegPose) -> WorkoutGhostGeometry {
        let imageSize = overlay.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return WorkoutGhostGeometry() }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
        guard fit.width > 0 else { return WorkoutGhostGeometry() }
        let scale = fit.width / imageSize.width

        if cameraView == .floor {
            // The pipeline supplies metrics whenever floor exercises are Ready.
            guard let metrics else { return WorkoutGhostGeometry() }
            let arms = (upper: metrics.upperArm * scale, fore: metrics.forearm * scale)

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
                                             lineWidth: max(8, arms.fore * 0.16),
                                             joints: [side.wrist, side.elbow, side.shoulder]))
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
                geometry.limbs.append(Stroke(points: [ankle, place(loweredKnee), ghostHip],
                                             lineWidth: 10,
                                             joints: [side.ankle, side.knee, side.hip]))
                hips.append(ghostHip)
            }
            if hips.count == 2 {
                geometry.connector = Stroke(points: hips, lineWidth: 10)
            }
            return geometry
        }

        // The pipeline supplies metrics whenever arm exercises are Ready.
        guard let metrics else { return WorkoutGhostGeometry() }
        let arms = (upper: metrics.upperArm * scale, fore: metrics.forearm * scale)

        let armAnchors = anchors(overlay: overlay, cameraView: cameraView, containerSize: containerSize)
        guard !armAnchors.isEmpty else { return WorkoutGhostGeometry() }
        var geometry = WorkoutGhostGeometry(forearmLength: arms.fore)
        for anchor in armAnchors {
            let arm = ArmMotion.place(shoulder: anchor.shoulder, outward: anchor.outward, upperArm: arms.upper,
                                      forearm: arms.fore, angles: angles, forearmPlane: motion.forearmPlane)
            geometry.limbs.append(Stroke(points: [anchor.shoulder, arm.elbow, arm.wrist],
                                         lineWidth: max(8, arms.fore * 0.16),
                                         holdsDumbbell: motion.holdsDumbbells,
                                         joints: [anchor.side.shoulder, anchor.side.elbow, anchor.side.wrist]))
        }
        return geometry
    }

    /// Where each ghost arm hangs from, its body side, and which way is outward.
    static func anchors(overlay: WorkoutOverlayState, cameraView: ExerciseCameraView,
                        containerSize: CGSize) -> [(side: BodySide, shoulder: CGPoint, outward: CGFloat)] {
        func point(_ joint: OverlayJoint) -> CGPoint {
            CoordinateConverter.normalizedToContainer(normalized: joint.location, imageSize: overlay.imageSize,
                                                      containerSize: containerSize)
        }
        switch cameraView {
        case .front:
            guard let left = overlay.joints[.leftShoulder], !left.isStale,
                  let right = overlay.joints[.rightShoulder], !right.isStale else { return [] }
            let (a, b) = (point(left), point(right))
            return [(.left, a, a.x >= b.x ? 1 : -1), (.right, b, b.x >= a.x ? 1 : -1)]
        case .side:
            guard let side = nearSide(in: overlay), let joint = overlay.joints[side.shoulder] else { return [] }
            let shoulder = point(joint)
            return [(side, shoulder, facing(from: shoulder, in: overlay, containerSize: containerSize) ?? 1)]
        case .floor:
            // Floor exercises anchor on the hands instead; see the floor geometry above.
            return []
        }
    }

    private static func idealNeedsMirror(overlay: WorkoutOverlayState?, motion: ArmMotion,
                                         cameraView: ExerciseCameraView, containerSize: CGSize) -> Bool {
        if cameraView == .side {
            guard let overlay, let side = nearSide(in: overlay),
                  let joint = overlay.joints[side.shoulder], !joint.isStale else { return false }
            let shoulder = CoordinateConverter.normalizedToContainer(normalized: joint.location,
                                                                      imageSize: overlay.imageSize,
                                                                      containerSize: containerSize)
            return facing(from: shoulder, in: overlay, containerSize: containerSize) == -1
        }
        return cameraView == .front || cameraView == .floor || motion.animatesLegs
    }

    private static func calibratedNeedsMirror(overlay: WorkoutOverlayState, limbs: [Stroke], pose: ReferencePose,
                                              motion: ArmMotion, cameraView: ExerciseCameraView,
                                              containerSize: CGSize) -> Bool {
        if cameraView == .side {
            guard let side = nearSide(in: overlay), let joint = overlay.joints[side.shoulder], !joint.isStale else {
                return false
            }
            let shoulder = CoordinateConverter.normalizedToContainer(normalized: joint.location,
                                                                      imageSize: overlay.imageSize,
                                                                      containerSize: containerSize)
            return (facing(from: shoulder, in: overlay, containerSize: containerSize) ?? 1) < 0
        }

        let sides: (LandmarkType, LandmarkType)
        if motion.animatesLegs {
            sides = (.leftAnkle, .rightAnkle)
        } else if cameraView == .floor {
            sides = (.leftWrist, .rightWrist)
        } else {
            sides = (.leftShoulder, .rightShoulder)
        }
        guard let userLeft = point(sides.0, in: overlay, containerSize: containerSize),
              let userRight = point(sides.1, in: overlay, containerSize: containerSize),
              let figureLeft = pose.jointLocations[sides.0],
              let figureRight = pose.jointLocations[sides.1] else { return false }
        return (userLeft.x < userRight.x) != (figureLeft.x < figureRight.x)
    }

    private static func calibratedLabels(for labels: [LandmarkType], cameraView: ExerciseCameraView,
                                         motion: ArmMotion) -> [LandmarkType] {
        guard cameraView == .side, !motion.animatesLegs, labels.count == 3 else { return labels }
        return [.leftShoulder, .leftElbow, .leftWrist]
    }

    private static func transform(_ point: CGPoint, scale: CGFloat, mirrored: Bool) -> CGPoint {
        let x = mirrored ? ExerciseDemoFigureView.canvasSize.width - point.x : point.x
        return CGPoint(x: x * scale, y: point.y * scale)
    }

    private static func interpolate(_ from: CGPoint, _ to: CGPoint, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * amount,
                y: from.y + (to.y - from.y) * amount)
    }

    private static func midpoint(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let total = points.reduce(CGPoint.zero) { result, point in
            CGPoint(x: result.x + point.x, y: result.y + point.y)
        }
        return CGPoint(x: total.x / CGFloat(points.count), y: total.y / CGFloat(points.count))
    }

    private static func point(_ type: LandmarkType, in overlay: WorkoutOverlayState,
                              containerSize: CGSize) -> CGPoint? {
        guard let joint = overlay.joints[type], !joint.isStale else { return nil }
        return CoordinateConverter.normalizedToContainer(normalized: joint.location,
                                                         imageSize: overlay.imageSize,
                                                         containerSize: containerSize)
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
