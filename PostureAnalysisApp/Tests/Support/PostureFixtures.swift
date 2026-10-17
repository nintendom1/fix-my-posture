import SwiftUI
@testable import PostureAnalysisApp

enum PostureFixtures {
    static let ids: Set<String> = ["posture"]

    @MainActor
    static func designTabView() -> some View {
        TabView(selection: .constant(AppTab.posture)) {
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
                .tag(AppTab.train)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.routines.title, systemImage: "list.number") }
                .tag(AppTab.routines)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.progress.title, systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
            NavigationStack {
                ZStack {
                    AuraBackground(tab: .posture)
                    PostureHomeScreen(state: state, send: { _ in })
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label(AppTab.posture.title, systemImage: "figure.stand") }
            .tag(AppTab.posture)
        }
        .tint(Color(hex: TabBarStyle.design.tintHex(for: .posture)))
    }

    private static var state: PostureHomeState {
        PostureHomeState(assessments: [
            PostureHomeAssessmentRow(id: id(10), dateLabel: "Oct 10, 2026", viewLabel: "Front view", isBaseline: false),
            PostureHomeAssessmentRow(id: id(24), dateLabel: "Sep 24, 2026", viewLabel: "Side view", isBaseline: false),
            PostureHomeAssessmentRow(id: id(2), dateLabel: "Sep 2, 2026", viewLabel: "Front view", isBaseline: true)
        ])
    }

    private static func id(_ day: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", day))!
    }
}
