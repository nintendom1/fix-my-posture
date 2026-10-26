import CoreGraphics
import Foundation

/// The ghost demo for one moment of the guide's motion, in container points. `WorkoutGhostOverlayView` only
/// strokes this geometry; this type alone decides whether a ghost can be drawn. Empty means nothing can be drawn.
struct WorkoutGhostGeometry: Equatable {
    private struct SideBodyResult {
        var geometry: WorkoutGhostGeometry
        var joints: [LandmarkType: CGPoint]
        var bodyScale: CGFloat
        var dumbbells: [Figure.Dumbbell]
        var forearmLength: CGFloat
    }

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
                      containerSize: CGSize, sample: ArmMotionSample) -> Figure {
        let imageSize = overlay?.imageSize ?? defaultImageSize
        guard containerSize.width > 0, containerSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return Figure() }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
        let canvas = ExerciseDemoFigureView.canvasSize
        guard fit.width > 0, fit.height > 0 else { return Figure() }

        let bounds = ExerciseDemoFigureView.bounds(for: motion, cameraView: cameraView)
        let scale = 0.9 * min(fit.width / bounds.width, fit.height / bounds.height)
        guard scale > 0 else { return Figure() }
        let pose = ExerciseDemoFigureView.pose(for: sample, forearmPlane: motion.forearmPlane,
                                               cameraView: cameraView)
        let mirrored = idealNeedsMirror(overlay: overlay, motion: motion, cameraView: cameraView,
                                        containerSize: containerSize)
        let fittedBounds = mirrored
            ? CGRect(x: canvas.width - bounds.maxX, y: bounds.minY,
                     width: bounds.width, height: bounds.height)
            : bounds
        let offset = CGPoint(x: fit.midX - fittedBounds.width * scale / 2 - fittedBounds.minX * scale,
                             y: fit.midY - fittedBounds.height * scale / 2 - fittedBounds.minY * scale)
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
                           sample: ArmMotionSample) -> Figure? {
        guard GhostCalibration.canFit(overlay: fitOverlay, metrics: metrics, motion: motion,
                                      cameraView: cameraView, sample: sample),
              let fitOverlay,
              fitOverlay.imageSize.width > 0, fitOverlay.imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return nil }

        if cameraView == .side, motion.movesSideBody {
            guard let result = sideBody(overlay: fitOverlay, motion: motion,
                                        containerSize: containerSize, sample: sample) else { return nil }
            return Figure(joints: result.joints, bodyScale: result.bodyScale,
                          dumbbells: result.dumbbells, forearmLength: result.forearmLength,
                          isCalibrated: true)
        }
        if cameraView == .lyingSide {
            guard let result = lyingSideBody(overlay: fitOverlay, motion: motion,
                                             containerSize: containerSize, sample: sample) else { return nil }
            return Figure(joints: result.joints, bodyScale: result.bodyScale,
                          dumbbells: result.dumbbells, forearmLength: result.forearmLength,
                          isCalibrated: true)
        }

        let limbs = make(overlay: fitOverlay, metrics: metrics, motion: motion, cameraView: cameraView,
                         containerSize: containerSize, sample: sample).limbs
        let fit = CoordinateConverter.aspectFitRect(for: fitOverlay.imageSize, in: containerSize)
        guard fit.width > 0 else { return nil }
        let fitScale = fit.width / fitOverlay.imageSize.width
        let canvas = ExerciseDemoFigureView.canvasSize
        let bounds = ExerciseDemoFigureView.bounds(for: motion, cameraView: cameraView)
        let fallbackScale = 0.9 * min(fit.width / bounds.width, fit.height / bounds.height)
        let pose = ExerciseDemoFigureView.pose(for: sample, forearmPlane: motion.forearmPlane,
                                               cameraView: cameraView)
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
            if motion.animatesLegs {
                let ankle = limbs.first?.joints.first ?? LandmarkType.leftAnkle
                targetAnchor = limbs.first?.points.first ?? point(ankle, in: fitOverlay,
                                                                   containerSize: containerSize)
                    ?? CGPoint(x: fit.midX, y: fit.midY)
                sourceAnchor = pose.jointLocations[ankle]
                    ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            } else {
                let shoulderSide = nearSide(in: fitOverlay)
                let trackedShoulder = shoulderSide.flatMap { point($0.shoulder, in: fitOverlay,
                                                                   containerSize: containerSize) }
                targetAnchor = limbs.first?.points.first ?? trackedShoulder ?? CGPoint(x: fit.midX, y: fit.midY)
                sourceAnchor = pose.jointLocations[.leftShoulder]
                    ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            }
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
            // The figure's relaxed shoulders sit on the user's, so a shrug keeps the head and hips in place.
            let figureLift = CGFloat(shoulderLift(of: sample, in: motion)) * ExerciseDemoFigureView.upperArm
            sourceAnchor = midpoint(of: figureShoulders).map { CGPoint(x: $0.x, y: $0.y + figureLift) }
                ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
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

    /// The ghost for one resolved sample of `motion` over the user's own smoothed joints.
    static func make(overlay: WorkoutOverlayState, metrics: GuideMetrics?, motion: ArmMotion,
                     cameraView: ExerciseCameraView, containerSize: CGSize,
                     sample: ArmMotionSample) -> WorkoutGhostGeometry {
        let imageSize = overlay.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return WorkoutGhostGeometry() }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
        guard fit.width > 0 else { return WorkoutGhostGeometry() }
        let scale = fit.width / imageSize.width

        if cameraView == .side, motion.movesSideBody {
            return sideBody(overlay: overlay, motion: motion, containerSize: containerSize,
                            sample: sample)?.geometry ?? WorkoutGhostGeometry()
        }
        if cameraView == .lyingSide {
            return lyingSideBody(overlay: overlay, motion: motion, containerSize: containerSize,
                                 sample: sample)?.geometry ?? WorkoutGhostGeometry()
        }

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
                                          forearm: arms.fore, angles: sample.angles)
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
            let lowered = ExerciseDemoFigureView.lowered(standing, by: sample.legs)
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
        // The start sample hangs from the user's own shoulders; a front-view shrug raises the ghost's
        // shoulders and arms above them by the lift in the user's upper-arm lengths.
        let rise = cameraView == .front ? CGFloat(shoulderLift(of: sample, in: motion)) * arms.upper : 0
        for anchor in armAnchors {
            let shoulder = CGPoint(x: anchor.shoulder.x, y: anchor.shoulder.y - rise)
            let arm = ArmMotion.place(shoulder: shoulder, outward: anchor.outward, upperArm: arms.upper,
                                      forearm: arms.fore, angles: sample.angles, forearmPlane: motion.forearmPlane)
            geometry.limbs.append(Stroke(points: [shoulder, arm.elbow, arm.wrist],
                                         lineWidth: max(8, arms.fore * 0.16),
                                         holdsDumbbell: motion.holdsDumbbells,
                                         joints: [anchor.side.shoulder, anchor.side.elbow, anchor.side.wrist]))
        }
        return geometry
    }

    /// Poses a side-view moving body from the four Ready-guaranteed joints on one side. Arms refine from tracked
    /// elbows and wrists when available, and otherwise scale from the guide figure's leg proportions.
    private static func sideBody(overlay: WorkoutOverlayState, motion: ArmMotion,
                                 containerSize: CGSize, sample: ArmMotionSample) -> SideBodyResult? {
        guard overlay.imageSize.width > 0, overlay.imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0,
              let side = sideBodySide(in: overlay),
              let shoulderStart = point(side.shoulder, in: overlay, containerSize: containerSize),
              let hipStart = point(side.hip, in: overlay, containerSize: containerSize),
              let kneeStart = point(side.knee, in: overlay, containerSize: containerSize),
              let ankle = point(side.ankle, in: overlay, containerSize: containerSize) else { return nil }

        let thigh = ArmGeometry.distance(hipStart, kneeStart)
        let shin = ArmGeometry.distance(kneeStart, ankle)
        let legLength = thigh + shin
        let torsoLength = ArmGeometry.distance(shoulderStart, hipStart)
        let facing = sideBodyFacing(hip: hipStart, knee: kneeStart, shoulder: shoulderStart,
                                    overlay: overlay,
                                    containerSize: containerSize)
        let startShape = motion.startSample.shape
        let hip = CGPoint(x: hipStart.x - facing * CGFloat(sample.shape.hipShift - startShape.hipShift) * thigh,
                          y: hipStart.y + CGFloat(sample.shape.hipDrop - startShape.hipDrop) * legLength)
        let knee = sample.shape == startShape
            ? kneeStart
            : ArmGeometry.twoBoneKnee(hip: hip, ankle: ankle, thighLength: thigh,
                                      shinLength: shin, bendDirection: facing)

        // Output uses the guide figure's labels (near limbs left, rear leg right) whichever side Vision tracked,
        // so the ideal and calibrated figures share joints and a finished glide leaves no stray ideal limbs.
        let near: BodySide = .left
        let rear: BodySide = .right
        var joints: [LandmarkType: CGPoint] = [near.shoulder: shoulderStart,
                                               near.hip: hip,
                                               near.knee: knee,
                                               near.ankle: ankle]
        let hasRearFoot = sample.shape.stride > 0
        if hasRearFoot {
            let rearAnkle = CGPoint(x: ankle.x - facing * CGFloat(sample.shape.stride) * legLength,
                                    y: ankle.y)
            let rearKnee = ArmGeometry.twoBoneKnee(hip: hip, ankle: rearAnkle,
                                                   thighLength: thigh, shinLength: shin,
                                                   bendDirection: facing)
            joints[rear.hip] = hip
            joints[rear.knee] = rearKnee
            joints[rear.ankle] = rearAnkle
        }

        let startPitch = startShape.torsoPitch ?? motion.torsoPitch
        let pitch = (sample.shape.torsoPitch ?? motion.torsoPitch) - startPitch
        let radians = pitch * Double(facing) * .pi / 180
        func rotateFromStart(_ point: CGPoint) -> CGPoint {
            let dx = point.x - hipStart.x
            let dy = point.y - hipStart.y
            return CGPoint(x: hip.x + dx * CGFloat(cos(radians)) - dy * CGFloat(sin(radians)),
                           y: hip.y + dx * CGFloat(sin(radians)) + dy * CGFloat(cos(radians)))
        }
        let shoulder = rotateFromStart(shoulderStart)
        joints[near.shoulder] = shoulder
        if let nose = overlay.pose[.nose] {
            let imageNose = nose.normalizedLocation
            let nosePoint = CoordinateConverter.normalizedToContainer(normalized: imageNose,
                                                                       imageSize: overlay.imageSize,
                                                                       containerSize: containerSize)
            joints[.nose] = rotateFromStart(nosePoint)
        } else if torsoLength > 0 {
            let guideHip = ExerciseDemoFigureView.sideFigureJoints[.leftHip] ?? .zero
            let guideShoulder = ExerciseDemoFigureView.sideFigureJoints[.leftShoulder] ?? .zero
            let guideNose = ExerciseDemoFigureView.sideFigureJoints[.nose] ?? .zero
            let guideTorso = ArmGeometry.distance(guideHip, guideShoulder)
            let ratio = guideTorso > 0 ? torsoLength / guideTorso : 1
            let baseNose = CGPoint(x: hipStart.x + facing * (guideNose.x - guideHip.x) * ratio,
                                   y: hipStart.y + (guideNose.y - guideHip.y) * ratio)
            joints[.nose] = rotateFromStart(baseNose)
        }

        let measuredArm: (CGFloat, CGFloat)? = {
            guard let elbow = point(side.elbow, in: overlay, containerSize: containerSize),
                  let wrist = point(side.wrist, in: overlay, containerSize: containerSize) else { return nil }
            let upper = ArmGeometry.distance(shoulderStart, elbow)
            let fore = ArmGeometry.distance(elbow, wrist)
            guard upper > 0, fore > 0 else { return nil }
            return (upper, fore)
        }()
        let guideHip = ExerciseDemoFigureView.sideFigureJoints[.leftHip] ?? .zero
        let guideKnee = ExerciseDemoFigureView.sideFigureJoints[.leftKnee] ?? .zero
        let guideAnkle = ExerciseDemoFigureView.sideFigureJoints[.leftAnkle] ?? .zero
        let guideLegLength = ArmGeometry.distance(guideHip, guideKnee) + ArmGeometry.distance(guideKnee, guideAnkle)
        let fallbackScale = guideLegLength > 0 ? legLength / guideLegLength : 1
        let armLengths = measuredArm ?? (ExerciseDemoFigureView.upperArm * fallbackScale,
                                         ExerciseDemoFigureView.forearm * fallbackScale)
        let arm = ArmMotion.place(shoulder: shoulder, outward: facing, upperArm: armLengths.0,
                                  forearm: armLengths.1, angles: sample.angles,
                                  forearmPlane: motion.forearmPlane)
        joints[near.elbow] = arm.elbow
        joints[near.wrist] = arm.wrist

        var geometry = WorkoutGhostGeometry(forearmLength: armLengths.1)
        geometry.limbs.append(Stroke(points: [ankle, knee, hip], lineWidth: max(8, legLength * 0.035),
                                     joints: [near.ankle, near.knee, near.hip]))
        if hasRearFoot,
           let rearAnkle = joints[rear.ankle], let rearKnee = joints[rear.knee] {
            geometry.limbs.append(Stroke(points: [rearAnkle, rearKnee, hip],
                                         lineWidth: max(8, legLength * 0.035),
                                         joints: [rear.ankle, rear.knee, rear.hip]))
        }
        geometry.limbs.append(Stroke(points: [shoulder, arm.elbow, arm.wrist],
                                     lineWidth: max(8, armLengths.1 * 0.16),
                                     holdsDumbbell: motion.holdsDumbbells,
                                     joints: [near.shoulder, near.elbow, near.wrist]))
        let dumbbells = motion.holdsDumbbells
            ? [Figure.Dumbbell(elbow: arm.elbow, wrist: arm.wrist)] : []
        let bodyScale = guideLegLength > 0 ? legLength / guideLegLength : fallbackScale
        return SideBodyResult(geometry: geometry, joints: joints, bodyScale: bodyScale,
                              dumbbells: dumbbells, forearmLength: armLengths.1)
    }

    /// Calibrates the supine guide from the Ready-guaranteed shoulder and ankle. The top hip follows the
    /// user's measured torso and thigh lengths, with the first sample kept exact on the person.
    private static func lyingSideBody(overlay: WorkoutOverlayState, motion: ArmMotion,
                                      containerSize: CGSize, sample: ArmMotionSample) -> SideBodyResult? {
        guard overlay.imageSize.width > 0, overlay.imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0,
              let side = sideBodySide(in: overlay),
              let shoulder = point(side.shoulder, in: overlay, containerSize: containerSize),
              let hipStart = point(side.hip, in: overlay, containerSize: containerSize),
              let kneeStart = point(side.knee, in: overlay, containerSize: containerSize),
              let ankle = point(side.ankle, in: overlay, containerSize: containerSize) else { return nil }

        let thighLength = ArmGeometry.distance(hipStart, kneeStart)
        let shinLength = ArmGeometry.distance(kneeStart, ankle)
        let torsoLength = ArmGeometry.distance(shoulder, hipStart)
        let facing = ankle.x >= shoulder.x ? CGFloat(1) : CGFloat(-1)
        let startPose = ExerciseDemoFigureView.pose(for: motion.startSample,
                                                    forearmPlane: motion.forearmPlane,
                                                    cameraView: .lyingSide)
        let samplePose = ExerciseDemoFigureView.pose(for: sample,
                                                     forearmPlane: motion.forearmPlane,
                                                     cameraView: .lyingSide)
        guard let guideShoulder = startPose.jointLocations[.leftShoulder],
              let guideAnkle = startPose.jointLocations[.leftAnkle] else { return nil }

        let guideAxisLength = ArmGeometry.distance(guideShoulder, guideAnkle)
        let userAxisLength = ArmGeometry.distance(shoulder, ankle)
        let scale = guideAxisLength > 0 ? userAxisLength / guideAxisLength : 1
        let axisX = userAxisLength > 0 ? (ankle.x - shoulder.x) / userAxisLength : facing
        let axisY = userAxisLength > 0 ? (ankle.y - shoulder.y) / userAxisLength : 0
        let normalX = -axisY * facing
        let normalY = abs(axisX)

        func transform(_ point: CGPoint) -> CGPoint {
            let along = (point.x - guideShoulder.x) * scale
            let across = (point.y - guideShoulder.y) * scale
            return CGPoint(x: shoulder.x + along * axisX + across * normalX,
                           y: shoulder.y + along * axisY + across * normalY)
        }

        var joints = samplePose.jointLocations.mapValues(transform)
        let top = lyingBridgeTop(shoulder: shoulder, ankle: ankle, downHip: hipStart,
                                 torsoLength: torsoLength, thighLength: thighLength,
                                 shinLength: shinLength)
        let hipLift = CGFloat(sample.shape.hipLift)
        let hip = CGPoint(x: hipStart.x + (top.hip.x - hipStart.x) * hipLift,
                          y: hipStart.y + (top.hip.y - hipStart.y) * hipLift)
        let knee: CGPoint
        if hipLift == 0 || sample.shape == motion.startSample.shape {
            knee = kneeStart
        } else if abs(hipLift - 1) < 0.000_001 {
            knee = top.knee
        } else {
            knee = ArmGeometry.twoBoneKnee(hip: hip, ankle: ankle, thighLength: thighLength,
                                            shinLength: shinLength, bendDirection: facing)
        }

        // Labels match the single near-side figure in the guide, including for right-side-only Ready poses.
        joints[.leftShoulder] = shoulder
        joints[.leftHip] = hip
        joints[.leftKnee] = knee
        joints[.leftAnkle] = ankle

        guard let elbow = joints[.leftElbow], let wrist = joints[.leftWrist] else { return nil }
        var geometry = WorkoutGhostGeometry()
        geometry.limbs = [
            Stroke(points: [shoulder, elbow, wrist], lineWidth: max(8, thighLength * 0.12),
                   joints: [.leftShoulder, .leftElbow, .leftWrist]),
            Stroke(points: [ankle, knee, hip], lineWidth: max(8, thighLength * 0.12),
                   joints: [.leftAnkle, .leftKnee, .leftHip])
        ]
        return SideBodyResult(geometry: geometry, joints: joints, bodyScale: scale,
                              dumbbells: [], forearmLength: 0)
    }

    /// Solves the straight top chain from the planted shoulder and ankle. If the measured segments cannot
    /// close exactly, it keeps torso and thigh lengths and chooses the nearest reachable shin length.
    private static func lyingBridgeTop(shoulder: CGPoint, ankle: CGPoint, downHip: CGPoint,
                                       torsoLength: CGFloat, thighLength: CGFloat,
                                       shinLength: CGFloat) -> (hip: CGPoint, knee: CGPoint) {
        let radius = torsoLength + thighLength
        let dx = ankle.x - shoulder.x
        let dy = ankle.y - shoulder.y
        let centerDistance = hypot(dx, dy)
        guard radius.isFinite, radius > 0, shinLength.isFinite, shinLength > 0,
              centerDistance.isFinite else {
            return (downHip, ArmGeometry.twoBoneKnee(hip: downHip, ankle: ankle,
                                                      thighLength: thighLength, shinLength: shinLength))
        }

        guard centerDistance > 0.000_001 else {
            let knee = CGPoint(x: shoulder.x, y: shoulder.y - radius)
            let hip = CGPoint(x: shoulder.x, y: shoulder.y - torsoLength)
            return (hip, knee)
        }

        let minimumReach = abs(radius - centerDistance)
        let maximumReach = radius + centerDistance
        let reachableShin = min(max(shinLength, minimumReach), maximumReach)
        let along = (radius * radius + centerDistance * centerDistance
                     - reachableShin * reachableShin) / (2 * centerDistance)
        let acrossSquared = max(0, radius * radius - along * along)
        let across = sqrt(acrossSquared)
        let unitX = dx / centerDistance
        let unitY = dy / centerDistance
        let perpendicularX = -unitY
        let perpendicularY = unitX
        let base = CGPoint(x: shoulder.x + unitX * along, y: shoulder.y + unitY * along)
        let firstKnee = CGPoint(x: base.x + perpendicularX * across,
                                y: base.y + perpendicularY * across)
        let secondKnee = CGPoint(x: base.x - perpendicularX * across,
                                 y: base.y - perpendicularY * across)
        let knee = firstKnee.y <= secondKnee.y ? firstKnee : secondKnee
        let ratio = torsoLength / radius
        let hip = CGPoint(x: shoulder.x + (knee.x - shoulder.x) * ratio,
                          y: shoulder.y + (knee.y - shoulder.y) * ratio)
        return (hip, knee)
    }

    private static func sideBodySide(in overlay: WorkoutOverlayState) -> BodySide? {
        func tracked(_ joint: LandmarkType) -> Bool { overlay.joints[joint].map { !$0.isStale } ?? false }
        let candidates = BodySide.allCases.filter { side in
            [side.shoulder, side.hip, side.knee, side.ankle].allSatisfy(tracked)
        }
        return candidates.max { lhs, rhs in
            func confidence(_ side: BodySide) -> Double {
                [side.shoulder, side.hip, side.knee, side.ankle]
                    .compactMap { overlay.pose[$0]?.confidence }
                    .reduce(0, +)
            }
            return confidence(lhs) < confidence(rhs)
        }
    }

    private static func sideBodyFacing(hip: CGPoint, knee: CGPoint, shoulder: CGPoint,
                                       overlay: WorkoutOverlayState, containerSize: CGSize) -> CGFloat {
        if let nose = overlay.pose[.nose] {
            let nosePoint = CoordinateConverter.normalizedToContainer(normalized: nose.normalizedLocation,
                                                                       imageSize: overlay.imageSize,
                                                                       containerSize: containerSize)
            return nosePoint.x >= shoulder.x ? 1 : -1
        }
        let kneeDirection = knee.x - hip.x
        if abs(kneeDirection) > 1 { return kneeDirection >= 0 ? 1 : -1 }
        return facing(from: shoulder, in: overlay, containerSize: containerSize) ?? 1
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
        case .lyingSide:
            // The lying path uses the shoulder and ankle as a two-point body axis.
            return []
        }
    }

    private static func idealNeedsMirror(overlay: WorkoutOverlayState?, motion: ArmMotion,
                                         cameraView: ExerciseCameraView, containerSize: CGSize) -> Bool {
        if cameraView == .lyingSide, let overlay,
           let side = sideBodySide(in: overlay),
           let shoulder = point(side.shoulder, in: overlay, containerSize: containerSize),
           let ankle = point(side.ankle, in: overlay, containerSize: containerSize) {
            return ankle.x < shoulder.x
        }
        if cameraView == .side {
            if motion.movesSideBody, let overlay,
               let side = sideBodySide(in: overlay),
               let hip = point(side.hip, in: overlay, containerSize: containerSize),
               let knee = point(side.knee, in: overlay, containerSize: containerSize),
               let shoulder = point(side.shoulder, in: overlay, containerSize: containerSize) {
                return sideBodyFacing(hip: hip, knee: knee, shoulder: shoulder,
                                      overlay: overlay, containerSize: containerSize) < 0
            }
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

    /// How far a sample's shoulders sit above the start sample's, in upper-arm lengths.
    private static func shoulderLift(of sample: ArmMotionSample, in motion: ArmMotion) -> Double {
        sample.shape.shoulderLift - motion.startSample.shape.shoulderLift
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
