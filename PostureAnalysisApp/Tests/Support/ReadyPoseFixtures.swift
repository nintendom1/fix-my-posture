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

/// Ready-valid poses for every catalog exercise, centered with headroom so framing gives no guidance.
enum ReadyPoseFixtures {
    static let imageSize = CGSize(width: 1080, height: 1920)
    static let confidence = 0.9

    /// The full demonstration pose, then one minimal pose per way of satisfying framing.
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

    private static func pose(for joints: Set<LandmarkType>, reference: [LandmarkType: CGPoint],
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
        // Exercises that need room beside the arms (side-room framing) stand a little farther back.
        let scale: CGFloat = exercise.sideroomArmLengths == nil ? 3 : 2.5
        let xOffset = CGFloat(540) - centerX * scale
        let yOffset = (imageSize.height - ExerciseDemoFigureView.canvasSize.height * scale) / 2
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

    /// The figure facing the other way: left and right joints swap, and x mirrors across the canvas.
    private static func mirrored(_ reference: [LandmarkType: CGPoint]) -> [LandmarkType: CGPoint] {
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
