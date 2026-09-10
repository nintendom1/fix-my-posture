import Foundation
import CoreGraphics

/// Enumeration of body landmarks used in posture analysis.
public enum LandmarkType: String, Codable, CaseIterable, Hashable, Identifiable {
    case nose
    case neck
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case root // Pelvis / Hip center
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nose: return "Nose"
        case .neck: return "Neck"
        case .leftEye: return "Left Eye"
        case .rightEye: return "Right Eye"
        case .leftEar: return "Left Ear"
        case .rightEar: return "Right Ear"
        case .leftShoulder: return "Left Shoulder"
        case .rightShoulder: return "Right Shoulder"
        case .leftElbow: return "Left Elbow"
        case .rightElbow: return "Right Elbow"
        case .leftWrist: return "Left Wrist"
        case .rightWrist: return "Right Wrist"
        case .root: return "Pelvis / Root"
        case .leftHip: return "Left Hip"
        case .rightHip: return "Right Hip"
        case .leftKnee: return "Left Knee"
        case .rightKnee: return "Right Knee"
        case .leftAnkle: return "Left Ankle"
        case .rightAnkle: return "Right Ankle"
        }
    }
}
