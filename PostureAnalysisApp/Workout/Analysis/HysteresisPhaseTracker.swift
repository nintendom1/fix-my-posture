import Foundation

/// Where one sample sits in a rep. `middle` is the hysteresis band and never changes the confirmed end.
enum MovementZone: Equatable {
    case bottom
    case middle
    case top
}

/// Confirms a bottom or top end only after consecutive samples, so noise near a threshold cannot double count.
struct HysteresisPhaseTracker {
    let requiredSamples: Int
    /// The last confirmed end, `.bottom` or `.top`; nil until the first confirmation.
    private(set) var confirmed: MovementZone?
    private(set) var lastZone: MovementZone?
    private var candidate: MovementZone?
    private var candidateCount = 0

    init(requiredSamples: Int = 2) {
        self.requiredSamples = max(1, requiredSamples)
    }

    /// Returns the end zone this sample newly confirms, if any.
    mutating func update(_ zone: MovementZone) -> MovementZone? {
        lastZone = zone
        guard zone != .middle, zone != confirmed else {
            candidate = nil
            candidateCount = 0
            return nil
        }
        if candidate == zone {
            candidateCount += 1
        } else {
            candidate = zone
            candidateCount = 1
        }
        guard candidateCount >= requiredSamples else { return nil }
        confirmed = zone
        candidate = nil
        candidateCount = 0
        return zone
    }

    mutating func reset() {
        self = HysteresisPhaseTracker(requiredSamples: requiredSamples)
    }
}
