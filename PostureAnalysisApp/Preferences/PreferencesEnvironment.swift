import SwiftUI

private struct PreferencesEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AppPreferencesStoring = UserDefaultsPreferences()
}

extension EnvironmentValues {
    var preferences: any AppPreferencesStoring {
        get { self[PreferencesEnvironmentKey.self] }
        set { self[PreferencesEnvironmentKey.self] = newValue }
    }
}
