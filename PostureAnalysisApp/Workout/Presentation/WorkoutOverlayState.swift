import CoreGraphics
import Foundation

/// Overlay display state in mirrored, normalized Vision coordinates.
struct WorkoutOverlayState: Equatable {
    var imageSize: CGSize
    var joints: [LandmarkType: OverlayJoint]
    var segments: [FocusSegment]
    /// Arms at their counted end position while counting.
    var endPositionSides: Set<BodySide>
    /// Every detected joint, mirrored but unsmoothed; tips keep clear of the whole body.
    var pose: BodyPose
    /// Joints the active corrective tip refers to; drawn amber.
    var emphasizedJoints: Set<LandmarkType> = []
}
