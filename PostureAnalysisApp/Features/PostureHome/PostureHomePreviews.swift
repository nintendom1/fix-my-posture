import SwiftUI

#Preview("Posture Home") {
    PostureHomeScreen(state: PostureHomeState(assessments: []), send: { _ in })
}

#Preview("Assessment History") {
    NavigationStack {
        PostureHistoryScreen(state: PostureHomeState(assessments: []), send: { _ in })
    }
}
