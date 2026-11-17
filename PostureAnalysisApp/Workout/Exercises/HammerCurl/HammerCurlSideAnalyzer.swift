import CoreGraphics
import Foundation

/// Thresholds and shared timing for side-on hammer curls.
struct HammerCurlSideConfiguration: Codable, Equatable {
    /// Start: the wrist hangs this far below the elbow in forearm lengths.
    var bottomMaxRatio: Double = -0.8
    /// Start also requires a nearly straight elbow.
    var bottomMinElbowAngle: Double = 140
    /// Top: the wrist rises this far above the elbow in forearm lengths.
    var topMinRatio: Double = 0.45
    /// Maximum elbow drift from the shoulder in upper-arm lengths.
    var elbowDriftTolerance: Double = 0.35
    /// Maximum shoulder movement relative to the hip in upper-arm lengths.
    var swayTolerance: Double = 0.35
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 0.8
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var rulerWindow = 10
    var elbowSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 6

    static let standard = HammerCurlSideConfiguration()
}

/// Side-on hammer curl analyzer contract; frame analysis is not implemented in this wave.
final class HammerCurlSideAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: HammerCurlSideConfiguration

    init(epoch: Int, configuration: HammerCurlSideConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        ExerciseAnalysis()
    }
}
