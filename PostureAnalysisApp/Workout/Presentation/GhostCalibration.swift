import CoreGraphics
import Foundation

/// When the setup ghost can leave its ideal spot and fit itself to the user's body.
enum GhostCalibration {
    /// The joints the ghost's moving limbs hang from are in view and its sizing is known. This mirrors
    /// `WorkoutGhostGeometry`'s limb rules, and the two must agree.
    static func canFit(overlay: WorkoutOverlayState?, metrics: GuideMetrics?, motion: ArmMotion,
                       cameraView: ExerciseCameraView, sample _: ArmMotionSample) -> Bool {
        guard let overlay else { return false }

        func counts(_ joint: LandmarkType) -> Bool {
            overlay.joints[joint].map { !$0.isStale } ?? false
        }

        if cameraView == .side && motion.wallPushUp {
            return BodySide.allCases.contains { side in
                [side.shoulder, side.elbow, side.wrist, side.hip].allSatisfy(counts)
            }
        } else if cameraView == .lyingSide {
            guard overlay.imageSize.width > 0, overlay.imageSize.height > 0 else { return false }
            return BodySide.allCases.contains { side in
                [side.shoulder, side.hip, side.knee, side.ankle].allSatisfy(counts)
            }
        } else if cameraView == .floor {
            guard metrics != nil else { return false }
            return counts(.leftWrist) && counts(.rightWrist)
        } else if cameraView == .side && motion.movesSideBody {
            guard overlay.imageSize.width > 0, overlay.imageSize.height > 0 else { return false }
            return BodySide.allCases.contains { side in
                [side.shoulder, side.hip, side.knee, side.ankle].allSatisfy(counts)
            }
        } else if motion.animatesLegs {
            return BodySide.allCases.contains { side in
                let other: BodySide = side == .left ? .right : .left
                return counts(side.ankle) && counts(side.knee) && counts(side.hip) && counts(other.ankle)
            }
        } else if cameraView == .front {
            guard metrics != nil else { return false }
            return counts(.leftShoulder) && counts(.rightShoulder)
        } else {
            guard metrics != nil else { return false }
            return BodySide.allCases.contains { counts($0.shoulder) }
        }
    }
}

/// Calibrates once the ghost's inputs have been available for `calibrateAfter`, and releases after they have
/// been missing for `releaseAfter`.
struct GhostCalibrationGate {
    var calibrateAfter: TimeInterval = FramingConfiguration().reliableAfter
    var releaseAfter: TimeInterval = 1.0
    private(set) var isCalibrated = false
    private var presentSince: TimeInterval?
    private var lastPresent: TimeInterval?

    /// Feeds one frame; returns `isCalibrated` after it.
    mutating func update(available: Bool, at time: TimeInterval) -> Bool {
        if available {
            let since = presentSince ?? time
            presentSince = since
            lastPresent = time
            if !isCalibrated, time - since >= calibrateAfter {
                isCalibrated = true
            }
        } else if isCalibrated {
            if time - (lastPresent ?? time) >= releaseAfter {
                isCalibrated = false
                presentSince = nil
                lastPresent = nil
            }
        } else {
            presentSince = nil
            lastPresent = nil
        }
        return isCalibrated
    }

    mutating func reset() {
        isCalibrated = false
        presentSince = nil
        lastPresent = nil
    }
}
