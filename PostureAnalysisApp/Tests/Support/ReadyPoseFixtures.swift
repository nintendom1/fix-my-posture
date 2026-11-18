import CoreGraphics
import Foundation
@testable import PostureAnalysisApp

/// One pose that should take an exercise to Ready, built from the guide's own start position.
struct ReadyPoseVariant {
    /// For failure messages, such as "full", "minimal", or "minimal right".
    let name: String
    /// Only the joints framing requires: `requiredJoints` plus one `anyOfRequiredJoints` set.
    let isMinimal: Bool
    /// Unmirrored image pixels in a `ReadyPoseFixtures.imageSize` image.
    let pose: BodyPose
}

/// Ready-valid poses for every catalog exercise, centered with headroom and inside any phone-distance limits so
/// framing gives no guidance. Pass a definition from `everyView` to pose any of an exercise's camera views.
enum ReadyPoseFixtures {
    static let imageSize = CGSize(width: 1080, height: 1920)
    static let confidence = 0.9

    /// The full demonstration pose, then one minimal pose per way of satisfying framing, all drawn in the
    /// definition's own camera view with its own joint sets.
    static func variants(for exercise: ExerciseDefinition) -> [ReadyPoseVariant] {
        let motion = exercise.guide.motion
        let reference = ExerciseDemoFigureView.pose(for: motion.startSample,
                                                     forearmPlane: motion.forearmPlane,
                                                     cameraView: exercise.cameraView).jointLocations
        var variants = [ReadyPoseVariant(name: "full", isMinimal: false,
                                         pose: pose(for: Set(reference.keys), reference: reference,
                                                    exercise: exercise))]

        if exercise.anyOfRequiredJoints.isEmpty {
            variants.append(ReadyPoseVariant(name: "minimal", isMinimal: true,
                                             pose: pose(for: exercise.requiredJoints, reference: reference,
                                                        exercise: exercise)))
        } else {
            for (index, alternative) in exercise.anyOfRequiredJoints.enumerated() {
                let sides = Set(alternative.compactMap(BodySide.side(of:)))
                let isOneSided = sides.count == 1 && alternative.allSatisfy { BodySide.side(of: $0) != nil }
                let name: String
                if isOneSided, let side = sides.first {
                    name = "minimal \(side.rawValue)"
                } else {
                    name = "minimal alternative \(index + 1)"
                }
                variants.append(ReadyPoseVariant(name: name, isMinimal: true,
                                                 pose: pose(for: exercise.requiredJoints.union(alternative),
                                                            reference: reference, exercise: exercise)))
            }
        }
        return variants
    }

    static func frame(_ variant: ReadyPoseVariant, at time: TimeInterval) -> PoseFrame {
        PoseFrame(pose: variant.pose, timestamp: time)
    }

    /// The exercise's guide demonstration at `motionTime`, every joint the figure draws, placed like the ready poses.
    /// `mirrored` turns the figure around, so a side-view exercise sees the other arm or leg.
    static func demoFrame(_ exercise: ExerciseDefinition, motionTime: TimeInterval, at time: TimeInterval,
                          mirrored isMirrored: Bool = false) -> PoseFrame {
        let motion = exercise.guide.motion
        let drawn = ExerciseDemoFigureView.pose(for: motion.sample(at: motionTime), forearmPlane: motion.forearmPlane,
                                                cameraView: exercise.cameraView).jointLocations
        let reference = isMirrored ? mirrored(drawn) : drawn
        return PoseFrame(pose: pose(for: Set(reference.keys), reference: reference, exercise: exercise), timestamp: time)
    }

    static func pose(for joints: Set<LandmarkType>, reference: [LandmarkType: CGPoint],
                     exercise: ExerciseDefinition) -> BodyPose {
        // The side figure shows only its left side; a right-side variant turns the whole figure around.
        let source = joints.allSatisfy { reference[$0] != nil } ? reference : mirrored(reference)
        var positions: [LandmarkType: CGPoint] = [:]
        for type in joints {
            guard let point = source[type] else {
                preconditionFailure("Ready pose for \(exercise.id) cannot provide required joint \(type).")
            }
            positions[type] = point
        }

        // Framing also needs three visible body landmarks before it can report Ready. Pad with joints the ghost
        // never reads first, so a ghost that quietly depends on the nose (side-view facing) still fails here.
        let padding: [LandmarkType] = [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .nose, .neck, .root]
        for type in padding where positions.count < FramingConfiguration().minimumBodyJoints {
            if let point = source[type], positions[type] == nil {
                positions[type] = point
            }
        }
        guard positions.count >= FramingConfiguration().minimumBodyJoints else {
            preconditionFailure("Ready pose for \(exercise.id) cannot meet the minimum visible body-joint count.")
        }

        let centeredJoints = positions.filter { type, _ in
            type == .leftShoulder || type == .rightShoulder || type == .leftHip || type == .rightHip
        }
        let pointsToCenter = centeredJoints.isEmpty ? Array(positions.values) : Array(centeredJoints.values)
        guard !pointsToCenter.isEmpty else {
            preconditionFailure("Ready pose for \(exercise.id) has no joints to center.")
        }
        let centerX = pointsToCenter.reduce(0) { $0 + $1.x } / CGFloat(pointsToCenter.count)
        let (scale, yOffset) = placement(for: exercise)
        let xOffset = CGFloat(540) - centerX * scale
        let landmarks = Dictionary(uniqueKeysWithValues: positions.map { type, point in
            let pixel = CGPoint(x: point.x * scale + xOffset, y: point.y * scale + yOffset)
            return (type, Landmark(type: type,
                                   normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                    pixel: pixel, imageWidth: imageSize.width, imageHeight: imageSize.height),
                                   imageLocation: pixel,
                                   confidence: confidence))
        })
        return BodyPose(landmarks: landmarks, imageWidth: imageSize.width, imageHeight: imageSize.height)
    }

    /// Figure-to-pixel scale and vertical offset, fixed per camera view so every frame of its motion lines up. An
    /// exercise with phone-distance limits stands where a real user passes them: the start pose's shoulder span and
    /// lowest wrist sit two clearances inside each limit, below the point where a distance warning clears. A side
    /// figure draws one shoulder, so it has no span to fit.
    private static func placement(for exercise: ExerciseDefinition) -> (scale: CGFloat, yOffset: CGFloat) {
        // Exercises that need room beside the arms (side-room framing) stand a little farther back.
        var scale: CGFloat = exercise.sideroomArmLengths == nil ? 3 : 2.5
        var yOffset = (imageSize.height - ExerciseDemoFigureView.canvasSize.height * scale) / 2
        guard exercise.maximumShoulderSpan != nil || exercise.maximumWristHeightFraction != nil else {
            return (scale, yOffset)
        }
        let motion = exercise.guide.motion
        let start = ExerciseDemoFigureView.pose(for: motion.startSample, forearmPlane: motion.forearmPlane,
                                                cameraView: exercise.cameraView).jointLocations
        let margin = 2 * FramingConfiguration().shoulderSpanClearance
        if exercise.cameraView != .side, let limit = exercise.maximumShoulderSpan,
           let left = start[.leftShoulder], let right = start[.rightShoulder] {
            let span = hypot(left.x - right.x, left.y - right.y)
            let widest = (limit - margin) * imageSize.width
            if span > 0, widest > 0, span * scale > widest {
                scale = widest / span
                yOffset = (imageSize.height - ExerciseDemoFigureView.canvasSize.height * scale) / 2
            }
        }
        if let limit = exercise.maximumWristHeightFraction,
           let lowest = [start[.leftWrist], start[.rightWrist]].compactMap({ $0?.y }).max() {
            yOffset = min(yOffset, (limit - margin) * imageSize.height - lowest * scale)
        }
        return (scale, yOffset)
    }

    /// The figure facing the other way: left and right joints swap, and x mirrors across the canvas.
    static func mirrored(_ reference: [LandmarkType: CGPoint]) -> [LandmarkType: CGPoint] {
        Dictionary(uniqueKeysWithValues: reference.map { type, point in
            (oppositeSide(of: type) ?? type, CGPoint(x: ExerciseDemoFigureView.canvasSize.width - point.x, y: point.y))
        })
    }

    private static func oppositeSide(of joint: LandmarkType) -> LandmarkType? {
        guard let side = BodySide.side(of: joint) else { return nil }
        let other: BodySide = side == .left ? .right : .left
        if joint == side.shoulder { return other.shoulder }
        if joint == side.elbow { return other.elbow }
        if joint == side.wrist { return other.wrist }
        if joint == side.hip { return other.hip }
        if joint == side.knee { return other.knee }
        if joint == side.ankle { return other.ankle }
        return nil
    }
}
