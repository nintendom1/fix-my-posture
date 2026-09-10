import Foundation

/// Standing posture view classification.
public enum PostureView: String, Codable, CaseIterable, Identifiable {
    case front
    case leftSide
    case rightSide
    case uncertain

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .front: return "Front View"
        case .leftSide: return "Left Side View"
        case .rightSide: return "Right Side View"
        case .uncertain: return "Uncertain / Custom View"
        }
    }
}
