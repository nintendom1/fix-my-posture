import Foundation

/// Defines the source for horizon measurements.
public enum HorizonSource: String, Codable, Hashable, Sendable {
    case deviceMotion
}

/// Context information about camera horizon and roll angle compensation.
public struct HorizonContext: Codable, Hashable, Sendable {
    public var angleDegrees: Double
    public var source: HorizonSource
    public var isCompensationApplied: Bool

    public init(
        angleDegrees: Double,
        source: HorizonSource = .deviceMotion,
        isCompensationApplied: Bool = true
    ) {
        self.angleDegrees = angleDegrees
        self.source = source
        self.isCompensationApplied = isCompensationApplied
    }
}
