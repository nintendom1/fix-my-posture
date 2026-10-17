//
//  PostureAnalysisApp.swift
//  PostureAnalysisApp
//

import SwiftUI
import SwiftData

@main
struct PostureAnalysisApp: App {
    @State private var preferences = UserDefaultsPreferences()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.preferences, preferences)
        }
        .modelContainer(for: [AssessmentEntity.self, SavedExerciseSetEntity.self, WorkoutRecordEntity.self])
    }
}
