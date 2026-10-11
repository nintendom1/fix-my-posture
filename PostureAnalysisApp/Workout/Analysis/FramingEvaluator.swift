import CoreGraphics
import Foundation

/// The single most useful framing instruction, worded relative to the user.
enum FramingGuidance: String, Equatable {
    case stepIntoView
    case stepBack
    case moreHeadroom
    case moveLeft
    case moveRight

    var spokenText: String {
        switch self {
        case .stepIntoView: return "Step into view, facing the phone."
        case .stepBack: return "Step back until your shoulders, elbows, wrists, and hips are in view."
        case .moreHeadroom: return "Step back a little more so there's room above your hands."
        case .moveLeft: return "Move a little to your left."
        case .moveRight: return "Move a little to your right."
        }
    }

    var shortText: String {
        switch self {
        case .stepIntoView: return "Step into view"
        case .stepBack: return "Step back: show shoulders to hips"
        case .moreHeadroom: return "Step back: leave room overhead"
        case .moveLeft: return "Move a little to your left"
        case .moveRight: return "Move a little to your right"
        }
    }
}

struct FramingStatus: Equatable {
    /// Required joints have been steadily visible; counting may run.
    var isReliable: Bool
    var guidance: FramingGuidance?

    static let lost = FramingStatus(isReliable: false, guidance: nil)
}

/// Prototype framing thresholds; tune on device.
struct FramingConfiguration {
    var minimumConfidence: Double = 0.4
    /// Required joints must stay visible this long before tracking is reliable.
    var reliableAfter: TimeInterval = 0.6
    /// Tracking becomes unreliable after required joints are missing this long.
    var unreliableAfter: TimeInterval = 0.3
    /// Fraction of image height kept clear above the overhead reach.
    var headroomMargin: CGFloat = 0.02
    /// Allowed body-center offset from the image center, as a fraction of image width.
    var centerTolerance: CGFloat = 0.17
    /// Fewer confident joints than this means nobody is in view.
    var minimumBodyJoints = 3
}

/// Decides tracking reliability and framing guidance from an exercise's required joints.
struct FramingEvaluator {
    let requiredJoints: Set<LandmarkType>
    /// Overhead room needed above the shoulders, in measured arm lengths; nil skips the check.
    let headroomArmLengths: CGFloat?
    let configuration: FramingConfiguration
    private var presentSince: TimeInterval?
    private var lastPresent: TimeInterval?
    private(set) var isReliable = false

    init(requiredJoints: Set<LandmarkType>, headroomArmLengths: CGFloat?, configuration: FramingConfiguration = FramingConfiguration()) {
        self.requiredJoints = requiredJoints
        self.headroomArmLengths = headroomArmLengths
        self.configuration = configuration
    }

    mutating func evaluate(_ frame: PoseFrame) -> FramingStatus {
        let time = frame.timestamp
        let present = requiredJoints.allSatisfy { frame.point($0, minimumConfidence: configuration.minimumConfidence) != nil }
        if present {
            let since = presentSince ?? time
            presentSince = since
            lastPresent = time
            if !isReliable, time - since >= configuration.reliableAfter { isReliable = true }
        } else {
            presentSince = nil
            if isReliable, time - (lastPresent ?? time) >= configuration.unreliableAfter { isReliable = false }
        }
        return FramingStatus(isReliable: isReliable, guidance: guidance(for: frame, requiredPresent: present))
    }

    mutating func reset() {
        presentSince = nil
        lastPresent = nil
        isReliable = false
    }

    private func guidance(for frame: PoseFrame, requiredPresent: Bool) -> FramingGuidance? {
        let confidence = configuration.minimumConfidence
        let visible = frame.pose.landmarks.values.filter { $0.confidence >= confidence }
        guard visible.count >= configuration.minimumBodyJoints else { return .stepIntoView }
        guard requiredPresent else { return .stepBack }

        if let headroomArmLengths {
            let arms = BodySide.allCases.compactMap { ArmGeometry.arm($0, in: frame, minimumConfidence: confidence) }
            if let reach = arms.map(\.armLength).max(),
               let shoulderTop = arms.map(\.shoulder.y).min(),
               shoulderTop - headroomArmLengths * reach < configuration.headroomMargin * frame.pose.imageHeight {
                return .moreHeadroom
            }
        }

        let anchors = [LandmarkType.leftShoulder, .rightShoulder, .leftHip, .rightHip]
            .compactMap { frame.point($0, minimumConfidence: confidence) }
        guard !anchors.isEmpty, frame.pose.imageWidth > 0 else { return nil }
        let centerX = anchors.map(\.x).reduce(0, +) / CGFloat(anchors.count) / frame.pose.imageWidth
        // Unmirrored front-camera x grows toward the user's left, so a small x means
        // the user stands to their right of center and should move left.
        if centerX < 0.5 - configuration.centerTolerance { return .moveLeft }
        if centerX > 0.5 + configuration.centerTolerance { return .moveRight }
        return nil
    }
}
