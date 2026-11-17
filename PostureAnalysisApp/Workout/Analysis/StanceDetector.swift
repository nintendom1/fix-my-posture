import Foundation

/// Configuration for deciding whether a body is facing the phone or side-on to it.
struct StanceDetector {
    struct Configuration: Codable, Equatable {
        var facingRatio: Double = 0.5
        var sideOnRatio: Double = 0.3
        var armFacingRatio: Double = 0.75
        var armSideOnRatio: Double = 0.4
        var holdSeconds: TimeInterval = 1.0
        var minimumConfidence: Double = 0.3
        var edgeMargin: Double = 0.1
        var turningAfter: TimeInterval = 0.2
        var turningClearsAfter: TimeInterval = 0.3
        var turningCap: TimeInterval = 3.0

        static let standard = Configuration()
    }

    enum Reading: String, Codable, Equatable {
        case facing
        case sideOn = "side"
        case unclear
        case absent
    }

    struct Observation: Codable, Equatable {
        var settled: BodyStance?
        var turning: Bool
    }

    private let configuration: Configuration
    private(set) var observation: Observation

    init(configuration: Configuration = .standard, seed: BodyStance? = nil) {
        self.configuration = configuration
        observation = Observation(settled: seed, turning: false)
    }

    /// Leaves the settled stance unchanged until stance classification is implemented.
    mutating func update(_ frame: PoseFrame) -> Observation {
        observation
    }

    /// Resets the detector to a known stance, if one is available.
    mutating func reset(seed: BodyStance?) {
        observation = Observation(settled: seed, turning: false)
    }

    /// Classifies a single pose frame; this contract stub reports no detected body.
    static func reading(of frame: PoseFrame, configuration: Configuration) -> Reading {
        .absent
    }
}
