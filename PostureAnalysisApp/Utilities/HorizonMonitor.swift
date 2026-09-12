import Foundation
import CoreMotion

/// Sensor reading of camera horizon angle and gravity magnitude.
public struct HorizonReading: Equatable, Hashable, Sendable {
    public var angleDegrees: Double
    public var timestamp: TimeInterval
    public var gravityMagnitude: Double

    public init(angleDegrees: Double, timestamp: TimeInterval, gravityMagnitude: Double) {
        self.angleDegrees = angleDegrees
        self.timestamp = timestamp
        self.gravityMagnitude = gravityMagnitude
    }
}

/// Abstract interface for motion-backed horizon monitoring.
public protocol HorizonMonitoring: AnyObject {
    var isFrontCamera: Bool { get set }
    var latestReading: HorizonReading? { get }
    func startUpdates()
    func stopUpdates()
}

/// Core Motion-backed monitor sampling device roll at 30 Hz with gravity low-pass filtering.
public final class CoreMotionHorizonMonitor: HorizonMonitoring, @unchecked Sendable {
    public var isFrontCamera: Bool = true {
        didSet {
            lock.lock()
            defer { lock.unlock() }
            // Invalidate current reading on camera switch
            cachedReading = nil
            smoothedGravity = nil
        }
    }

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()

    private var smoothedGravity: CMAcceleration?
    private var cachedReading: HorizonReading?
    private var isUpdating = false

    public init() {
        queue.name = "com.postureanalysis.horizonMonitor"
        queue.maxConcurrentOperationCount = 1
    }

    deinit {
        stopUpdates()
    }

    public var latestReading: HorizonReading? {
        lock.lock()
        defer { lock.unlock() }
        guard let reading = cachedReading else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        // Must be at most 0.25 seconds old
        guard now - reading.timestamp <= 0.25 else { return nil }
        // Absolute roll at most 45 degrees
        guard abs(reading.angleDegrees) <= 45.0 else { return nil }
        // Projected gravity magnitude at least 0.75
        guard reading.gravityMagnitude >= 0.75 else { return nil }
        return reading
    }

    public func startUpdates() {
        lock.lock()
        defer { lock.unlock() }
        guard !isUpdating else { return }
        cachedReading = nil
        smoothedGravity = nil

        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        isUpdating = true

        let isFront = isFrontCamera
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            self.processMotion(motion.gravity, isFrontCamera: isFront)
        }
    }

    public func stopUpdates() {
        lock.lock()
        defer { lock.unlock() }
        guard isUpdating else { return }
        isUpdating = false
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        cachedReading = nil
        smoothedGravity = nil
    }

    /// Internal process method for gravity updates (also accessible for unit testing).
    public func processMotion(_ gravity: CMAcceleration, isFrontCamera: Bool, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        defer { lock.unlock() }

        // Low-pass filter (0.2 factor)
        let alpha = 0.2
        let smoothed: CMAcceleration
        if let prev = smoothedGravity {
            smoothed = CMAcceleration(
                x: alpha * gravity.x + (1.0 - alpha) * prev.x,
                y: alpha * gravity.y + (1.0 - alpha) * prev.y,
                z: alpha * gravity.z + (1.0 - alpha) * prev.z
            )
        } else {
            smoothed = gravity
        }
        smoothedGravity = smoothed

        // Projected gravity magnitude in portrait XY plane
        let projectedMagnitude = sqrt(smoothed.x * smoothed.x + smoothed.y * smoothed.y)
        guard projectedMagnitude >= 0.75 else {
            cachedReading = nil
            return
        }

        // Calculate roll angle relative to portrait upright
        let rawAngle = atan2(-smoothed.x, -smoothed.y) * (180.0 / .pi)
        let angle = isFrontCamera ? -rawAngle : rawAngle

        guard abs(angle) <= 45.0 else {
            cachedReading = nil
            return
        }

        cachedReading = HorizonReading(
            angleDegrees: angle,
            timestamp: timestamp,
            gravityMagnitude: projectedMagnitude
        )
    }
}
