import Foundation
import CoreGraphics

/// Pair of joints representing a skeleton connection for reference visualization.
public struct ConnectionPair: Codable, Hashable {
    public let jointA: LandmarkType
    public let jointB: LandmarkType

    public init(_ jointA: LandmarkType, _ jointB: LandmarkType) {
        self.jointA = jointA
        self.jointB = jointB
    }
}

/// Visualization data representing reference posture geometry in image pixel space.
public struct ReferencePose: Codable, Hashable {
    /// Joint locations in image pixel coordinates (origin top-left).
    public var jointLocations: [LandmarkType: CGPoint]

    /// Supported skeleton connections.
    public var connections: [ConnectionPair]

    /// Body regions supported by available anchors in the input pose.
    public var supportedRegions: Set<BodyRegion>

    /// Captions describing changes achieved toward geometric alignment.
    public var achievedChanges: [String]

    /// Explanation if reference generation or playback is unavailable.
    public var unavailabilityReason: String?

    public init(
        jointLocations: [LandmarkType: CGPoint] = [:],
        connections: [ConnectionPair] = [],
        supportedRegions: Set<BodyRegion> = [],
        achievedChanges: [String] = [],
        unavailabilityReason: String? = nil
    ) {
        self.jointLocations = jointLocations
        self.connections = connections
        self.supportedRegions = supportedRegions
        self.achievedChanges = achievedChanges
        self.unavailabilityReason = unavailabilityReason
    }
}
