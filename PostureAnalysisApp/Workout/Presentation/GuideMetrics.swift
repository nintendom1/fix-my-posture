import CoreGraphics
import Foundation

/// Smoothed arm-segment lengths in image pixels, used to fit the ghost demo to the user.
struct GuideMetrics: Equatable {
    var upperArm: CGFloat
    var forearm: CGFloat

    /// Typical proportions relative to shoulder width, used until segments have been measured.
    static let upperArmToShoulderWidth: CGFloat = 0.85
    static let forearmToShoulderWidth: CGFloat = 0.72
    /// Measured segments outside this shoulder-width-relative range are treated as noise.
    static let plausibleSegmentRatio: ClosedRange<CGFloat> = 0.45...1.4
    /// From the side, shoulder width vanishes, so segments are judged against torso length instead.
    static let upperArmToTorso: CGFloat = 0.53
    static let forearmToTorso: CGFloat = 0.47
    static let plausibleTorsoRatio: ClosedRange<CGFloat> = 0.3...0.9
    /// Typical forearm length as a fraction of upper-arm length when no forearm is visible.
    static let forearmToUpperArm: CGFloat = forearmToTorso / upperArmToTorso
    /// Measured forearms outside this upper-arm-relative range are treated as noise.
    static let plausibleUpperArmRatio: ClosedRange<CGFloat> = 0.6...1.4
    static let smoothing: CGFloat = 0.25
}
