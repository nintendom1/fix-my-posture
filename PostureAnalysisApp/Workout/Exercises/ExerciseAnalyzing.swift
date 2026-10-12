import CoreGraphics
import Foundation

/// A rep completed by one analyzer instance. The session drops events whose epoch is stale.
struct RepEvent: Equatable {
    let epoch: Int
    let timestamp: TimeInterval
    /// Sides credited with the rep: both for a two-arm rep, one for an independent arm.
    let sides: Set<BodySide>
}

/// Live per-arm signals, shown by Show Measurements for on-device tuning.
struct ArmReading: Equatable {
    /// The exercise's primary signal, such as wrist height above the shoulder in arm lengths.
    let signal: Double
    let elbowAngle: Double
    let zone: MovementZone
}

/// The two checkpoints of a rep: it begins and ends at the start, turning around at the top.
enum RepCheckpoint: Hashable {
    case start
    case top
}

/// Where one arm's checkpoints sit, in unmirrored image pixels (y grows downward).
/// These are the analyzer's actual thresholds, so drawing them shows exactly what counts.
struct ArmThresholds: Equatable {
    /// The reference shoulder; locked while the arm is away from the start.
    let shoulder: CGPoint
    /// Arm length used as the ruler.
    let ruler: CGFloat
    /// The wrist must be below this to be at the start.
    let startY: CGFloat
    /// The wrist must be above this to be at the top.
    let topY: CGFloat
    /// The reference was locked at the start position and is held until the arm returns.
    let isLocked: Bool
    /// The checkpoint this arm last confirmed.
    let confirmed: RepCheckpoint?

    /// The checkpoint the arm is heading toward.
    var next: RepCheckpoint { confirmed == .start ? .top : .start }
}

/// One frame of analyzer output.
struct ExerciseAnalysis {
    var repEvents: [RepEvent] = []
    /// Arms currently held at the counted end position; the overlay draws them green.
    var endPositionSides: Set<BodySide> = []
    /// Every arm is confirmed at the start position, whether or not counting is on.
    var startPositionHeld = false
    var readings: [BodySide: ArmReading] = [:]
    var thresholds: [BodySide: ArmThresholds] = [:]
}

/// Exercise-specific rep counting over reliable, unmirrored pixel geometry.
/// A fresh instance replaces the old one whenever the set restarts or the exercise changes.
protocol ExerciseAnalyzing: AnyObject {
    /// Stamped on every rep event.
    var epoch: Int { get }

    /// With `counting` false, end positions still update for the overlay, but the next rep
    /// must begin from a fresh start position.
    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis
}
