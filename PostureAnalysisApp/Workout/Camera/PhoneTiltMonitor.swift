import CoreMotion
import Foundation

/// How far the phone leans forward or back from upright, in degrees. Positive leans back
/// (front camera pointing upward). A leaning phone squashes or stretches heights unevenly,
/// more so up close, which skews the rep thresholds.
struct PhoneTilt: Equatable {
    var pitchDegrees: Double
}

@MainActor
protocol PhoneTiltMonitoring: AnyObject {
    /// Nil when motion data is unavailable.
    var latestTilt: PhoneTilt? { get }
    func start()
    func stop()
}

/// When to warn about tilt. The warning is advisory and never blocks a set.
enum PhoneTiltPolicy {
    static let tiltedPitch: Double = 15
    /// Lower than `tiltedPitch` so the warning doesn't flicker near the boundary.
    static let uprightPitch: Double = 10
    /// The phone must stay tilted this long before the warning appears.
    static let settleTime: TimeInterval = 1.0
}

/// Debounced, with hysteresis, so the warning neither flickers nor fires on a brief bump.
/// Pure, so it can be tested without motion hardware.
struct PhoneTiltDetector {
    private(set) var isTilted = false
    private var tiltedSince: TimeInterval?

    /// Nil pitch (no motion data) never reports a tilt.
    mutating func update(pitchDegrees: Double?, at now: TimeInterval) -> Bool {
        let limit = isTilted ? PhoneTiltPolicy.uprightPitch : PhoneTiltPolicy.tiltedPitch
        guard let pitch = pitchDegrees.map({ abs($0) }), pitch > limit else {
            reset()
            return isTilted
        }
        let since = tiltedSince ?? now
        tiltedSince = since
        if now - since >= PhoneTiltPolicy.settleTime { isTilted = true }
        return isTilted
    }

    mutating func reset() {
        isTilted = false
        tiltedSince = nil
    }
}

/// Gravity-based pitch at 10 Hz, independent of the posture horizon monitor, which tracks roll.
final class CoreMotionTiltMonitor: PhoneTiltMonitoring {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var tilt: PhoneTilt?

    init() {
        queue.name = "com.postureanalysis.phoneTilt"
        queue.maxConcurrentOperationCount = 1
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }

    @MainActor var latestTilt: PhoneTilt? {
        lock.lock()
        defer { lock.unlock() }
        return tilt
    }

    @MainActor func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            // Upright portrait has gravity (0, -1, 0); leaning back moves it toward -z.
            let pitch = atan2(-gravity.z, -gravity.y) * 180 / .pi
            self.lock.lock()
            self.tilt = PhoneTilt(pitchDegrees: pitch)
            self.lock.unlock()
        }
    }

    @MainActor func stop() {
        manager.stopDeviceMotionUpdates()
        lock.lock()
        tilt = nil
        lock.unlock()
    }
}
