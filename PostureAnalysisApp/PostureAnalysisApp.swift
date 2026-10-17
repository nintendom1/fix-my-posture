//
//  PostureAnalysisApp.swift
//  PostureAnalysisApp
//

import SwiftUI
import SwiftData
import OSLog

@main
struct PostureAnalysisApp: App {
    @State private var preferences = UserDefaultsPreferences()
    private let modelContainer: ModelContainer?
    private let persistenceError: String?

    @MainActor
    init() {
        do {
            modelContainer = try AppModelContainer.make()
            persistenceError = nil
        } catch {
            Logger(subsystem: "FixMyPosture", category: "Persistence")
                .error("The app could not open its local database: \(error.localizedDescription, privacy: .public)")
            modelContainer = nil
            persistenceError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .environment(\.preferences, preferences)
                    .environment(\.appRepositories, AppRepositories(context: modelContainer.mainContext))
                    .modelContainer(modelContainer)
            } else {
                PersistenceUnavailableView(message: persistenceError ?? "The local database is unavailable.")
            }
        }
    }
}

private struct PersistenceUnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.largeTitle)
            Text("Local Data Unavailable")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
