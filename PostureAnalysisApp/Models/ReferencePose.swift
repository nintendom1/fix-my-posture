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

    private enum CodingKeys: String, CodingKey {
        case jointLocations
        case connections
        case supportedRegions
        case achievedChanges
        case unavailabilityReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stringJoints = try container.decode([String: CGPoint].self, forKey: .jointLocations)
        var joints: [LandmarkType: CGPoint] = [:]
        for (k, v) in stringJoints {
            if let type = LandmarkType(rawValue: k) {
                joints[type] = v
            }
        }
        self.jointLocations = joints
        self.connections = try container.decode([ConnectionPair].self, forKey: .connections)
        self.supportedRegions = try container.decode(Set<BodyRegion>.self, forKey: .supportedRegions)
        self.achievedChanges = try container.decode([String].self, forKey: .achievedChanges)
        self.unavailabilityReason = try container.decodeIfPresent(String.self, forKey: .unavailabilityReason)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var stringJoints: [String: CGPoint] = [:]
        for (k, v) in jointLocations {
            stringJoints[k.rawValue] = v
        }
        try container.encode(stringJoints, forKey: .jointLocations)
        try container.encode(connections, forKey: .connections)
        try container.encode(supportedRegions, forKey: .supportedRegions)
        try container.encode(achievedChanges, forKey: .achievedChanges)
        try container.encodeIfPresent(unavailabilityReason, forKey: .unavailabilityReason)
    }
}
