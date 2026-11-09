import Foundation

/// Smooth temporal weighting for a local keyframe edit.
enum MovementInfluence {
    /// A raised-cosine rise to `peak` and fall from it. Zero-width sides have no influence away from the peak.
    static func weight(at time: TimeInterval, peak: TimeInterval, rise: TimeInterval,
                       fall: TimeInterval) -> Double {
        guard time.isFinite, peak.isFinite, rise.isFinite, fall.isFinite, rise >= 0, fall >= 0 else { return 0 }
        if time == peak { return 1 }

        if time < peak {
            guard rise > 0, time >= peak - rise else { return 0 }
            let progress = (time - (peak - rise)) / rise
            return 0.5 - 0.5 * cos(.pi * progress)
        }

        guard fall > 0, time <= peak + fall else { return 0 }
        let progress = (time - peak) / fall
        return 0.5 + 0.5 * cos(.pi * progress)
    }
}
