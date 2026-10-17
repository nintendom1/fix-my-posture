import SwiftUI
@testable import PostureAnalysisApp

enum SettingsFixtures {
    static let ids: Set<String> = ["settings"]

    @MainActor
    static func screen() -> some View {
        SettingsScreen(viewModel: SettingsViewModel(
            preferences: InMemoryPreferences(),
            router: AppRouter()
        ))
    }
}
