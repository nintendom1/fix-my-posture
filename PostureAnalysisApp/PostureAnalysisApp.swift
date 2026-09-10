//
//  PostureAnalysisApp.swift
//  PostureAnalysisApp
//

import SwiftUI
import SwiftData

@main
struct PostureAnalysisApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [AssessmentEntity.self])
    }
}
