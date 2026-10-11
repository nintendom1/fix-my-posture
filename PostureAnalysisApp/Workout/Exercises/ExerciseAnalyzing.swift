import Foundation

/// A rep completed by one analyzer instance. The session drops events whose epoch is stale.
struct RepEvent: Equatable {
    let epoch: Int
    let timestamp: TimeInterval
    /// Sides credited with the rep: both for a two-arm rep, one for an independent arm.
    let sides: Set<BodySide>
}

/// One frame of analyzer output.
struct ExerciseAnalysis {
    var repEvents: [RepEvent] = []
    /// Arms currently held at the counted end position; the overlay draws them green.
    var endPositionSides: Set<BodySide> = []
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
