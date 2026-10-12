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

/// A short horizontal segment the wrist (or other tracked point) must pass, in unmirrored image
/// pixels (y grows downward), with the label drawn beside it.
struct ThresholdLine: Equatable {
    var from: CGPoint
    var to: CGPoint
    var label: String

    var y: CGFloat { from.y }
}

/// Where one arm's checkpoints sit. These are the analyzer's actual thresholds, so drawing them shows
/// exactly what counts. "Top" is the counted end of the movement, which isn't always the highest point.
struct ArmThresholds: Equatable {
    let startLine: ThresholdLine
    let topLine: ThresholdLine
    /// The reference was locked at the start position and is held until the arm returns.
    let isLocked: Bool
    /// The checkpoint this arm last confirmed.
    let confirmed: RepCheckpoint?

    /// The checkpoint the arm is heading toward.
    var next: RepCheckpoint { confirmed == .start ? .top : .start }

    func line(_ checkpoint: RepCheckpoint) -> ThresholdLine {
        checkpoint == .start ? startLine : topLine
    }
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
    /// Rep attempts judged for form on this frame, counted or not.
    var repForms: [RepForm] = []
    /// Continuous form conditions that hold on this frame.
    var formSignals: Set<CoachingCueID> = []
    /// The last attempt's form values, for Show Measurements.
    var formReadings: [FormReading] = []
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
