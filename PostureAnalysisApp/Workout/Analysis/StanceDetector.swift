import CoreGraphics
import Foundation

/// Configuration for deciding whether a body is facing the phone or side-on to it.
struct StanceDetector {
    struct Configuration: Codable, Equatable {
        var facingRatio: Double = 0.5
        var sideOnRatio: Double = 0.3
        var armFacingRatio: Double = 0.75
        var armSideOnRatio: Double = 0.4
        var holdSeconds: TimeInterval = 1.0
        var minimumConfidence: Double = 0.3
        var edgeMargin: Double = 0.1
        var turningAfter: TimeInterval = 0.2
        var turningClearsAfter: TimeInterval = 0.3
        var turningCap: TimeInterval = 3.0

        static let standard = Configuration()
    }

    enum Reading: String, Codable, Equatable {
        case facing
        case sideOn = "side"
        case unclear
        case absent

        var stance: BodyStance? {
            switch self {
            case .facing: return .facing
            case .sideOn: return .sideOn
            case .unclear, .absent: return nil
            }
        }
    }

    struct Observation: Codable, Equatable {
        var settled: BodyStance?
        var turning: Bool
    }

    /// Sampled timestamps can land a hair short of a duration they reach, as `1.3 - 1.1` falls just below 0.2.
    static let timeTolerance: TimeInterval = 1e-6

    private let configuration: Configuration
    private(set) var observation: Observation

    init(configuration: Configuration = .standard, seed: BodyStance? = nil) {
        self.configuration = configuration
        observation = Observation(settled: seed, turning: false)
    }

    private var stanceCandidate: (stance: BodyStance, since: TimeInterval)?
    private var turningEvidenceSince: TimeInterval?
    private var turningSince: TimeInterval?
    private var turningClearSince: TimeInterval?
    private var suppressTurningUntilEvidenceClears = false

    /// True while turning, and from the first reading that suggests a turn until `turningAfter` confirms it. Framing
    /// uses it so the start of a turn is bridged too; the reducer still waits for `observation.turning`.
    var mayBeTurning: Bool { observation.turning || turningEvidenceSince != nil }

    /// Updates settled stance and turning state using only the frame's capture timestamp.
    mutating func update(_ frame: PoseFrame) -> Observation {
        let reading = Self.reading(of: frame, configuration: configuration)
        let time = frame.timestamp

        if let stance = reading.stance, stance != observation.settled {
            if stanceCandidate?.stance != stance {
                stanceCandidate = (stance, time)
            }
            if let stanceCandidate, Self.elapsed(configuration.holdSeconds, from: stanceCandidate.since, to: time) {
                observation.settled = stance
                self.stanceCandidate = nil
            }
        } else {
            stanceCandidate = nil
        }

        updateTurning(for: reading, at: time)
        return observation
    }

    /// Resets the detector to a known stance, if one is available.
    mutating func reset(seed: BodyStance?) {
        observation = Observation(settled: seed, turning: false)
        stanceCandidate = nil
        turningEvidenceSince = nil
        turningSince = nil
        turningClearSince = nil
        suppressTurningUntilEvidenceClears = false
    }

    /// Classifies a single pose from pixel-space geometry, independent of image aspect ratio.
    static func reading(of frame: PoseFrame, configuration: Configuration) -> Reading {
        let confidence = configuration.minimumConfidence
        let hasBody = frame.pose.landmarks.values.contains { $0.confidence >= confidence }
        guard hasBody else { return .absent }

        let left = frame.point(.leftShoulder, minimumConfidence: confidence)
        let right = frame.point(.rightShoulder, minimumConfidence: confidence)
        if let left, let right {
            let width = Double(ArmGeometry.distance(left, right))
            let hips = BodySide.allCases.compactMap { frame.point($0.hip, minimumConfidence: confidence) }
            if let torso = torsoLength(shoulders: ArmGeometry.midpoint(left, right), hips: hips) {
                return classify(width / torso, facing: configuration.facingRatio, sideOn: configuration.sideOnRatio)
            }

            let upperArms = BodySide.allCases.compactMap { side -> Double? in
                guard let shoulder = frame.point(side.shoulder, minimumConfidence: confidence),
                      let elbow = frame.point(side.elbow, minimumConfidence: confidence) else { return nil }
                return Double(ArmGeometry.distance(shoulder, elbow))
            }
            guard let upperArm = upperArms.max(), upperArm > 1 else { return .unclear }
            return classify(width / upperArm, facing: configuration.armFacingRatio,
                            sideOn: configuration.armSideOnRatio)
        }

        guard let shoulder = left ?? right else { return .unclear }
        let side: BodySide = left == nil ? .right : .left
        let attached = frame.point(side.hip, minimumConfidence: confidence) != nil
            || frame.point(side.elbow, minimumConfidence: confidence) != nil
        return attached && isInsideMargins(shoulder, frame.imageSize, margin: configuration.edgeMargin)
            ? .sideOn : .unclear
    }

    private mutating func updateTurning(for reading: Reading, at time: TimeInterval) {
        let stance = reading.stance
        let isSettledReading = observation.settled != nil && stance == observation.settled
        let isOpposite = observation.settled != nil && stance != nil && stance != observation.settled
        let isEvidence = reading == .unclear || isOpposite

        if isEvidence {
            turningClearSince = nil
            guard !suppressTurningUntilEvidenceClears else { return }
            let evidenceSince = turningEvidenceSince ?? time
            turningEvidenceSince = evidenceSince

            if observation.turning {
                if let turningSince, Self.elapsed(configuration.turningCap, from: turningSince, to: time) {
                    observation.turning = false
                    self.turningSince = nil
                    turningEvidenceSince = nil
                    suppressTurningUntilEvidenceClears = true
                }
            } else if Self.elapsed(configuration.turningAfter, from: evidenceSince, to: time) {
                observation.turning = true
                turningSince = time
            }
            return
        }

        turningEvidenceSince = nil
        suppressTurningUntilEvidenceClears = false
        guard reading == .absent || isSettledReading else {
            turningClearSince = nil
            return
        }

        guard observation.turning else {
            turningClearSince = nil
            return
        }
        let clearSince = turningClearSince ?? time
        turningClearSince = clearSince
        if Self.elapsed(configuration.turningClearsAfter, from: clearSince, to: time) {
            observation.turning = false
            turningSince = nil
            turningClearSince = nil
        }
    }

    private static func elapsed(_ duration: TimeInterval, from start: TimeInterval, to time: TimeInterval) -> Bool {
        time - start >= duration - timeTolerance
    }

    private static func torsoLength(shoulders: CGPoint, hips: [CGPoint]) -> Double? {
        guard !hips.isEmpty else { return nil }
        let hip = CGPoint(x: hips.map(\.x).reduce(0, +) / CGFloat(hips.count),
                          y: hips.map(\.y).reduce(0, +) / CGFloat(hips.count))
        let length = Double(ArmGeometry.distance(shoulders, hip))
        return length > 1 ? length : nil
    }

    private static func classify(_ ratio: Double, facing: Double, sideOn: Double) -> Reading {
        if ratio >= facing { return .facing }
        if ratio <= sideOn { return .sideOn }
        return .unclear
    }

    private static func isInsideMargins(_ point: CGPoint, _ size: CGSize, margin: Double) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let horizontal = CGFloat(margin) * size.width
        let vertical = CGFloat(margin) * size.height
        return point.x >= horizontal && point.x <= size.width - horizontal
            && point.y >= vertical && point.y <= size.height - vertical
    }
}
