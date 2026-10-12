import CoreGraphics
import Foundation

/// One Euro filter (Casiez et al.): steady at rest, responsive during fast movement.
struct OneEuroFilter {
    /// Cutoff in Hz while still; lower is smoother.
    var minCutoff: Double
    /// How quickly the cutoff rises with speed; higher reduces lag.
    var beta: Double
    var derivativeCutoff: Double = 1.0
    private var previousValue: Double?
    private var previousDerivative = 0.0
    private var previousTime: TimeInterval?

    init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard let lastValue = previousValue, let lastTime = previousTime, time > lastTime else {
            previousValue = value
            previousTime = time
            previousDerivative = 0
            return value
        }
        let interval = time - lastTime
        let derivative = (value - lastValue) / interval
        let derivativeAlpha = Self.alpha(cutoff: derivativeCutoff, interval: interval)
        let smoothedDerivative = derivativeAlpha * derivative + (1 - derivativeAlpha) * previousDerivative
        let alpha = Self.alpha(cutoff: minCutoff + beta * abs(smoothedDerivative), interval: interval)
        let result = alpha * value + (1 - alpha) * lastValue
        previousValue = result
        previousDerivative = smoothedDerivative
        previousTime = time
        return result
    }

    private static func alpha(cutoff: Double, interval: TimeInterval) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / interval)
    }
}

/// A display joint in mirrored, normalized Vision coordinates.
struct OverlayJoint: Equatable {
    var location: CGPoint
    /// Recently missing; drawn muted until it disappears.
    var isStale: Bool
}

/// Display-only smoothing. Rep counting and framing always use raw samples.
struct LandmarkSmoother {
    /// Tuned for normalized coordinates at 10 Hz.
    var minCutoff = 2.0
    var beta = 2.0
    /// Missing joints stay muted this long, then disappear.
    var staleAfter: TimeInterval = 0.3
    private var filters: [LandmarkType: (x: OneEuroFilter, y: OneEuroFilter)] = [:]
    private var lastSeen: [LandmarkType: (location: CGPoint, time: TimeInterval)] = [:]

    mutating func update(pose: BodyPose, joints: Set<LandmarkType>, at time: TimeInterval) -> [LandmarkType: OverlayJoint] {
        var result: [LandmarkType: OverlayJoint] = [:]
        for joint in joints {
            if let landmark = pose[joint] {
                var filter = filters[joint] ?? (OneEuroFilter(minCutoff: minCutoff, beta: beta), OneEuroFilter(minCutoff: minCutoff, beta: beta))
                // A joint returning after a gap starts fresh instead of gliding from its old spot.
                if let seen = lastSeen[joint], time - seen.time > staleAfter {
                    filter = (OneEuroFilter(minCutoff: minCutoff, beta: beta), OneEuroFilter(minCutoff: minCutoff, beta: beta))
                }
                let location = CGPoint(x: filter.x.filter(Double(landmark.normalizedLocation.x), at: time),
                                       y: filter.y.filter(Double(landmark.normalizedLocation.y), at: time))
                filters[joint] = filter
                lastSeen[joint] = (location, time)
                result[joint] = OverlayJoint(location: location, isStale: false)
            } else if let seen = lastSeen[joint], time - seen.time <= staleAfter {
                result[joint] = OverlayJoint(location: seen.location, isStale: true)
            }
        }
        return result
    }

    mutating func reset() {
        filters = [:]
        lastSeen = [:]
    }
}
