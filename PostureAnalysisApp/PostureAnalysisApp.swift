//
//  PostureAnalysisApp.swift
//  PostureAnalysisApp
//

import SwiftUI

@main
@MainActor
struct PostureAnalysisApp: App {
    @State private var appEnvironment: AppEnvironment

    init() {
        TabBarAppearance.configure()
        _appEnvironment = State(initialValue: AppEnvironment())
    }

    var body: some Scene {
        WindowGroup {
            if appEnvironment.modelContainer != nil {
                AppShellView(environment: appEnvironment)
            } else {
                PersistenceUnavailableView(message: appEnvironment.persistenceError ?? "The local database is unavailable.")
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
