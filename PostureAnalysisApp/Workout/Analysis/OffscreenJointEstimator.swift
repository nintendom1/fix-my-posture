import CoreGraphics
import Foundation

/// Prototype thresholds for estimating joints that leave the image through an edge; tune on device.
struct OffscreenJointConfiguration: Codable {
    /// A joint at or above this confidence counts as seen.
    var observedConfidence: Double = FramingConfiguration().minimumConfidence
    /// A joint last seen within this fraction of the image dimension from an edge may have left through it.
    var edgeMargin: CGFloat = 0.08
    /// Movement away from that edge up to this fraction of the image dimension still counts as leaving.
    var outwardTolerance: CGFloat = 0.01
    /// Estimates stop this long after the joint was last seen.
    var maximumDuration: TimeInterval = 1.5
    /// The largest turn, in degrees, a limb may take about its parent to stay out of view.
    var maximumRotation: Double = 35
    /// A planted joint is dropped once its parent is farther away than this many of its longest seen bones.
    var plantedReach: CGFloat = 1.25
}

/// Fills in a joint that just left the image through an edge, from the seen joint it hangs off.
/// Estimates feed only counting during a set; see "Joints past the frame edge" in `docs/workout.md`.
struct OffscreenJointEstimator {
    let joints: Set<LandmarkType>
    /// Joints resting on the floor, held where they were last seen instead of carried with their limb.
    let plantedJoints: Set<LandmarkType>
    let configuration: OffscreenJointConfiguration

    private var memory: [LandmarkType: JointMemory] = [:]

    private struct Observation {
        let position: CGPoint
        let time: TimeInterval
        let confidence: Double
    }

    private struct JointMemory {
        var observations: [Observation] = []
        var lastVector: CGVector?
        var longestBone: CGFloat?

        mutating func remember(_ observation: Observation) {
            observations.append(observation)
            if observations.count > 2 { observations.removeFirst() }
        }

        var lastObservation: Observation? { observations.last }
        var lastMovement: CGVector {
            guard observations.count > 1, let first = observations.first, let last = observations.last else {
                return .zero
            }
            return CGVector(dx: last.position.x - first.position.x,
                            dy: last.position.y - first.position.y)
        }
    }

    private enum Edge: CaseIterable {
        case top
        case bottom
        case left
        case right

        var outward: CGVector {
            switch self {
            case .top: return CGVector(dx: 0, dy: -1)
            case .bottom: return CGVector(dx: 0, dy: 1)
            case .left: return CGVector(dx: -1, dy: 0)
            case .right: return CGVector(dx: 1, dy: 0)
            }
        }

        var dimensionIsHeight: Bool { self == .top || self == .bottom }

        func distance(from point: CGPoint, in size: CGSize) -> CGFloat {
            switch self {
            case .top: return max(0, point.y) / size.height
            case .bottom: return max(0, size.height - point.y) / size.height
            case .left: return max(0, point.x) / size.width
            case .right: return max(0, size.width - point.x) / size.width
            }
        }

        func contains(_ point: CGPoint, in size: CGSize, margin: CGFloat) -> Bool {
            switch self {
            case .top: return point.y <= margin * size.height
            case .bottom: return point.y >= size.height - margin * size.height
            case .left: return point.x <= margin * size.width
            case .right: return point.x >= size.width - margin * size.width
            }
        }

        func bandBoundary(in size: CGSize, margin: CGFloat) -> CGFloat {
            switch self {
            case .top: return -margin * size.height
            case .bottom: return size.height - margin * size.height
            case .left: return -margin * size.width
            case .right: return size.width - margin * size.width
            }
        }
    }

    init(joints: Set<LandmarkType>, plantedJoints: Set<LandmarkType>,
         configuration: OffscreenJointConfiguration = OffscreenJointConfiguration()) {
        self.joints = joints
        self.plantedJoints = plantedJoints
        self.configuration = configuration
    }

    /// The joint a limb hangs off: wrist to elbow, elbow to shoulder, ankle to knee, and knee to hip.
    static func parent(of joint: LandmarkType) -> LandmarkType? {
        guard let side = BodySide.side(of: joint) else { return nil }
        switch joint {
        case side.wrist: return side.elbow
        case side.elbow: return side.shoulder
        case side.ankle: return side.knee
        case side.knee: return side.hip
        default: return nil
        }
    }

    /// Remembers what this frame shows; returns it with any joint that just left through an edge filled in.
    mutating func complete(_ frame: PoseFrame) -> PoseFrame {
        let size = frame.imageSize
        guard size.width > 0, size.height > 0 else { return frame }

        var estimates: [LandmarkType: Landmark] = [:]
        for joint in joints {
            var jointMemory = memory[joint] ?? JointMemory()
            let observed = observedLandmark(joint, in: frame)
            let parent = Self.parent(of: joint)
            let observedParent = parent.flatMap { observedLandmark($0, in: frame) }

            if let observed {
                jointMemory.remember(Observation(position: observed.imageLocation, time: frame.timestamp,
                                                 confidence: observed.confidence))
                if let observedParent {
                    let vector = CGVector(dx: observed.imageLocation.x - observedParent.imageLocation.x,
                                          dy: observed.imageLocation.y - observedParent.imageLocation.y)
                    let length = hypot(vector.dx, vector.dy)
                    jointMemory.lastVector = vector
                    jointMemory.longestBone = max(jointMemory.longestBone ?? length, length)
                }
                memory[joint] = jointMemory
                continue
            }

            if parent != nil, let observedParent,
               let estimate = estimate(joint, memory: jointMemory, parent: observedParent.imageLocation,
                                       at: frame.timestamp, in: size) {
                estimates[joint] = Landmark(
                    type: joint,
                    normalizedLocation: CGPoint(x: estimate.x / size.width, y: 1 - estimate.y / size.height),
                    imageLocation: estimate,
                    confidence: jointMemory.lastObservation?.confidence ?? configuration.observedConfidence,
                    isManuallyCorrected: false
                )
            }
            memory[joint] = jointMemory
        }

        guard !estimates.isEmpty else { return frame }
        var completed = frame
        for (joint, landmark) in estimates { completed.pose[joint] = landmark }
        completed.estimatedJoints.formUnion(estimates.keys)
        return completed
    }

    mutating func reset() {
        memory.removeAll()
    }

    private func observedLandmark(_ joint: LandmarkType, in frame: PoseFrame) -> Landmark? {
        guard !frame.estimatedJoints.contains(joint) else { return nil }
        guard let landmark = frame.pose[joint], landmark.confidence >= configuration.observedConfidence else { return nil }
        return landmark
    }

    private func estimate(_ joint: LandmarkType, memory: JointMemory, parent: CGPoint,
                          at time: TimeInterval, in size: CGSize) -> CGPoint? {
        guard let last = memory.lastObservation,
              time - last.time <= configuration.maximumDuration,
              let edge = exitEdge(for: last.position, in: size) else { return nil }
        let edgeDimension = edge.dimensionIsHeight ? size.height : size.width

        if !plantedJoints.contains(joint) {
            let movement = memory.lastMovement
            let outwardMovement = movement.dx * edge.outward.dx + movement.dy * edge.outward.dy
            guard outwardMovement >= -configuration.outwardTolerance * edgeDimension,
                  let vector = memory.lastVector else { return nil }
            let rigid = CGPoint(x: parent.x + vector.dx, y: parent.y + vector.dy)
            if edge.contains(rigid, in: size, margin: configuration.edgeMargin) { return rigid }
            return rotatedEstimate(vector: vector, parent: parent, edge: edge, in: size)
        }

        guard let longestBone = memory.longestBone,
              ArmGeometry.distance(parent, last.position) <= configuration.plantedReach * longestBone else { return nil }
        return last.position
    }

    private func exitEdge(for point: CGPoint, in size: CGSize) -> Edge? {
        Edge.allCases
            .map { ($0, $0.distance(from: point, in: size)) }
            .filter { $0.1 <= configuration.edgeMargin }
            .min { $0.1 < $1.1 }?.0
    }

    private func rotatedEstimate(vector: CGVector, parent: CGPoint, edge: Edge, in size: CGSize) -> CGPoint? {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0 else { return nil }
        let normal = edge.outward
        let boundary = edge.bandBoundary(in: size, margin: configuration.edgeMargin)
        let parentProjection = parent.x * normal.dx + parent.y * normal.dy
        // Aim one pixel inside the band, so rounding can't push the turned point back out.
        let requiredProjection = boundary - parentProjection + 1
        guard requiredProjection <= length else { return nil }

        let targetOffset = acos(Double(max(-1, min(1, requiredProjection / length))))
        let normalAngle = atan2(Double(normal.dy), Double(normal.dx))
        let vectorAngle = atan2(Double(vector.dy), Double(vector.dx))
        let firstTurn = Self.signedAngle(normalAngle + targetOffset - vectorAngle)
        let secondTurn = Self.signedAngle(normalAngle - targetOffset - vectorAngle)
        let turn = abs(firstTurn) <= abs(secondTurn) ? firstTurn : secondTurn
        guard abs(turn) * 180 / .pi <= configuration.maximumRotation else { return nil }

        let rotated = CGPoint(x: parent.x + length * CGFloat(cos(vectorAngle + turn)),
                              y: parent.y + length * CGFloat(sin(vectorAngle + turn)))
        return edge.contains(rotated, in: size, margin: configuration.edgeMargin) ? rotated : nil
    }

    private static func signedAngle(_ radians: Double) -> Double {
        var angle = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if angle > .pi { angle -= 2 * .pi }
        if angle < -.pi { angle += 2 * .pi }
        return angle
    }
}
