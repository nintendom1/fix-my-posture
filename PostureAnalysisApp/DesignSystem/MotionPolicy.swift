import SwiftUI

public enum MotionPolicy: Sendable {
    case full
    case reduced
}

private struct MotionPolicyKey: EnvironmentKey {
    static let defaultValue: MotionPolicy = .full
}

public extension EnvironmentValues {
    var motionPolicy: MotionPolicy {
        get { self[MotionPolicyKey.self] }
        set { self[MotionPolicyKey.self] = newValue }
    }
}
