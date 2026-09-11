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

    // Compare coordinate components explicitly for SDKs where CGPoint does not
    // provide the protocol conformances needed for synthesized implementations.
    public static func == (lhs: ReferencePose, rhs: ReferencePose) -> Bool {
        guard lhs.jointLocations.count == rhs.jointLocations.count else {
            return false
        }

        for (type, point) in lhs.jointLocations {
            guard let otherPoint = rhs.jointLocations[type],
                  point.x == otherPoint.x,
                  point.y == otherPoint.y else {
                return false
            }
        }

        return lhs.connections == rhs.connections
            && lhs.supportedRegions == rhs.supportedRegions
            && lhs.achievedChanges == rhs.achievedChanges
            && lhs.unavailabilityReason == rhs.unavailabilityReason
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(jointLocations.count)
        for (type, point) in jointLocations.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            hasher.combine(type)
            hasher.combine(point.x)
            hasher.combine(point.y)
        }
        hasher.combine(connections)
        hasher.combine(supportedRegions)
        hasher.combine(achievedChanges)
        hasher.combine(unavailabilityReason)
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
