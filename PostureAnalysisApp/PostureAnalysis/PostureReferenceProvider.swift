import Foundation

/// Protocol supplying reference profiles for posture alignment.
public protocol PostureReferenceProviding {
    var currentProfile: PostureReferenceProfile { get }
    func profile(for view: PostureView) -> PostureReferenceProfile
}

/// Default provider supplying the bundled geometric alignment profile v1.0.
public final class DefaultPostureReferenceProvider: PostureReferenceProviding {
    public let currentProfile: PostureReferenceProfile

    public init() {
        let frontRules: [TargetAlignmentRule] = [
            TargetAlignmentRule(measurementID: .shoulderLineAngle, targetValue: 0.0, tolerance: 0.5),
            TargetAlignmentRule(measurementID: .hipLineAngle, targetValue: 0.0, tolerance: 0.5),
            TargetAlignmentRule(measurementID: .headTiltAngle, targetValue: 0.0, tolerance: 0.5),
            TargetAlignmentRule(measurementID: .torsoLateralDeviation, targetValue: 0.0, tolerance: 0.5),
            TargetAlignmentRule(measurementID: .bodyCenterlineDeviation, targetValue: 0.0, tolerance: 0.5),
            TargetAlignmentRule(measurementID: .kneeAnkleStanceRatio, targetValue: 1.0, tolerance: 0.05)
        ]

        let sideRules: [TargetAlignmentRule] = [
            TargetAlignmentRule(measurementID: .earShoulderHorizontalOffset, targetValue: 0.0, tolerance: 0.5),
            TargetAlignmentRule(measurementID: .torsoInclinationAngle, targetValue: 0.0, tolerance: 0.5),
            TargetAlignmentRule(measurementID: .hipKneeAlignmentAngle, targetValue: 0.0, tolerance: 0.5),
            TargetAlignmentRule(measurementID: .kneeJointAngle, targetValue: 180.0, tolerance: 1.0),
            TargetAlignmentRule(measurementID: .overallSagittalBodyLean, targetValue: 0.0, tolerance: 0.5)
        ]

        self.currentProfile = PostureReferenceProfile(
            id: "default-v1",
            name: "Standard Geometric Alignment",
            version: "1.0",
            perViewRules: [
                .front: frontRules,
                .leftSide: sideRules,
                .rightSide: sideRules
            ]
        )
    }

    public func profile(for view: PostureView) -> PostureReferenceProfile {
        return currentProfile
    }
}
