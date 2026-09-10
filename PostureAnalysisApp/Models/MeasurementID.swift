import Foundation

/// Stable enumeration of unique measurement identifiers decoupled from user-facing display labels.
public enum MeasurementID: String, Codable, CaseIterable, Identifiable, Hashable {
    // Front View Measurements
    case headTiltAngle = "front.head_tilt_angle"
    case shoulderLineAngle = "front.shoulder_line_angle"
    case shoulderHeightAsymmetry = "front.shoulder_height_asymmetry"
    case hipLineAngle = "front.hip_line_angle"
    case hipHeightAsymmetry = "front.hip_height_asymmetry"
    case torsoLateralDeviation = "front.torso_lateral_deviation"
    case kneeAnkleStanceRatio = "front.knee_ankle_stance_ratio"
    case bodyCenterlineDeviation = "front.body_centerline_deviation"

    // Side View Measurements
    case forwardHeadAngle = "side.forward_head_angle"
    case earShoulderHorizontalOffset = "side.ear_shoulder_horizontal_offset"
    case torsoInclinationAngle = "side.torso_inclination_angle"
    case hipKneeAlignmentAngle = "side.hip_knee_alignment_angle"
    case kneeJointAngle = "side.knee_joint_angle"
    case overallSagittalBodyLean = "side.overall_sagittal_body_lean"

    // Fallback/Custom
    case custom = "custom"

    public var id: String { rawValue }

    public var defaultDisplayName: String {
        switch self {
        case .headTiltAngle: return "Head Tilt Angle"
        case .shoulderLineAngle: return "Shoulder Line Angle"
        case .shoulderHeightAsymmetry: return "Shoulder Height Asymmetry"
        case .hipLineAngle: return "Hip Line Angle"
        case .hipHeightAsymmetry: return "Hip Height Asymmetry"
        case .torsoLateralDeviation: return "Torso Lateral Deviation"
        case .kneeAnkleStanceRatio: return "Knee-to-Ankle Stance Ratio"
        case .bodyCenterlineDeviation: return "Body Centerline Deviation"
        case .forwardHeadAngle: return "Forward Head Angle"
        case .earShoulderHorizontalOffset: return "Ear-Shoulder Horizontal Offset"
        case .torsoInclinationAngle: return "Torso Inclination Angle"
        case .hipKneeAlignmentAngle: return "Hip-Knee Alignment Angle"
        case .kneeJointAngle: return "Knee Joint Angle"
        case .overallSagittalBodyLean: return "Overall Sagittal Body Lean"
        case .custom: return "Custom Metric"
        }
    }

    /// Maps legacy display names from older assessment versions to stable MeasurementIDs.
    public static func fromLegacyName(_ name: String) -> MeasurementID {
        switch name {
        case "Head Tilt Angle": return .headTiltAngle
        case "Shoulder Line Angle": return .shoulderLineAngle
        case "Shoulder Height Asymmetry": return .shoulderHeightAsymmetry
        case "Hip Line Angle": return .hipLineAngle
        case "Hip Height Asymmetry": return .hipHeightAsymmetry
        case "Torso Lateral Deviation": return .torsoLateralDeviation
        case "Knee-to-Ankle Stance Ratio": return .kneeAnkleStanceRatio
        case "Body Centerline Deviation": return .bodyCenterlineDeviation
        case "Forward Head Angle": return .forwardHeadAngle
        case "Ear-Shoulder Horizontal Offset": return .earShoulderHorizontalOffset
        case "Torso Inclination Angle": return .torsoInclinationAngle
        case "Hip-Knee Alignment Angle": return .hipKneeAlignmentAngle
        case "Knee Joint Angle": return .kneeJointAngle
        case "Overall Sagittal Body Lean": return .overallSagittalBodyLean
        default: return .custom
        }
    }
}
