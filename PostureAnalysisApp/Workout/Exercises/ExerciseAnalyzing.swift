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
    /// Rep attempts let go on this frame without counting, and why. Diagnostic only: nothing counts from it.
    var rejections: [RepRejection] = []
}

/// How far a rep attempt had got when it was let go.
enum RepAttemptStage: String, Equatable {
    /// Still at the start position: nothing was lost.
    case atStart
    /// Left the start but hadn't reached the counted end.
    case moving
    /// Reached the counted end (on at least one side) but hadn't come back.
    case reachedEnd

    /// `reachedEnd` wins; otherwise any zone away from the start means moving.
    static func of(reachedEnd: Bool, zones: some Sequence<MovementZone>) -> RepAttemptStage {
        if reachedEnd { return .reachedEnd }
        return zones.contains { $0 != .bottom } ? .moving : .atStart
    }
}

/// Why an analyzer let a rep attempt go without counting it.
enum RepRejectionReason: Equatable {
    /// Back at the start sooner than the exercise's minimum rep time.
    case tooFast(duration: TimeInterval, minimum: TimeInterval)
    /// Back at the start with only some arms having reached the counted end.
    case partialEnd(reached: Set<BodySide>)
    /// The joints the analyzer needs were missing for longer than it allows, so the attempt was reset.
    case trackingGap(seconds: TimeInterval, maximum: TimeInterval, stage: RepAttemptStage)
    /// Counting stopped partway through the attempt: tracking became unreliable, or the set paused.
    case countingStopped(stage: RepAttemptStage)
    /// The analyzer switched to the other arm or leg partway through the attempt.
    case sideSwitched(stage: RepAttemptStage)
    /// Away from the start longer than the exercise allows, so its start reference and the attempt were dropped.
    case referenceExpired(stage: RepAttemptStage)
}

struct RepRejection: Equatable {
    /// The sample timestamp of the frame that let the attempt go.
    var timestamp: TimeInterval
    /// The arm or leg, for exercises that count sides separately; nil when the body counts as one.
    var side: BodySide?
    var reason: RepRejectionReason

    /// A gap or a counting stop at the start position loses nothing, so it isn't reported.
    static func lost(at timestamp: TimeInterval, side: BodySide? = nil, _ reason: RepRejectionReason) -> RepRejection? {
        switch reason {
        case .trackingGap(_, _, .atStart), .countingStopped(.atStart), .sideSwitched(.atStart),
             .referenceExpired(.atStart): return nil
        default: return RepRejection(timestamp: timestamp, side: side, reason: reason)
        }
    }
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
