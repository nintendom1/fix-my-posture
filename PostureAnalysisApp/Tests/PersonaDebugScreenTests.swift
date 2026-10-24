import XCTest
@testable import PostureAnalysisApp

final class PersonaDebugScreenTests: XCTestCase {
    @MainActor
    func testEmptyPersonaDebugScreenRenders() throws {
        let viewModel = PersonaDebugViewModel(
            catalog: nil,
            loadError: "No persona content.",
            provider: nil,
            scheduler: FakePreviewScheduler(),
            preferences: InMemoryPreferences(),
            now: { FixedClock.date },
            calendar: FixedClock.calendar
        )

        _ = try SnapshotHost.render(
            PersonaDebugScreen(viewModel: viewModel),
            frameId: "persona-debug-empty",
            testCase: self
        )
    }

    @MainActor
    func testPopulatedPersonaDebugScreenRenders() throws {
        let decisionID = UUID()
        let sent = makeTrace(
            decisionID: decisionID,
            date: FixedClock.date,
            outcome: .sent(fireDate: FixedClock.date, identifier: "persona-sent")
        )
        let suppressed = makeTrace(
            decisionID: decisionID,
            date: FixedClock.date.addingTimeInterval(-60),
            outcome: .suppressed(.lowerPriorityThanSelected)
        )
        let viewModel = PersonaDebugViewModel(
            catalog: PersonaFixtures.catalog(),
            loadError: nil,
            provider: FakePersonaDebugProvider(
                status: PersonaStatus(
                    extraPersonableEnabled: true,
                    isActive: true,
                    familiarity: .established,
                    trajectory: .improving,
                    cooling: .mild,
                    standaloneCountToday: 1,
                    dailyCap: 2,
                    pendingCount: 1,
                    quietHoursSummary: "22:00–08:00",
                    isQuietNow: false,
                    personaResetDate: FixedClock.date.addingTimeInterval(-86_400)
                ),
                state: PersonaTraceState(sent: [sent], suppressed: [suppressed])
            ),
            scheduler: FakePreviewScheduler(),
            preferences: InMemoryPreferences(),
            now: { FixedClock.date },
            calendar: FixedClock.calendar
        )

        _ = try SnapshotHost.render(
            PersonaDebugScreen(viewModel: viewModel),
            frameId: "persona-debug-populated",
            testCase: self
        )
    }

    private func makeTrace(
        decisionID: UUID,
        date: Date,
        outcome: PersonaDecisionTrace.Outcome
    ) -> PersonaDecisionTrace {
        let observation = PersonaFixtures.observation(
            .achievement,
            "pr.weight",
            salience: .high,
            strength: 4,
            contentKey: "achievement.pr.weight"
        )
        return PersonaDecisionTrace(
            id: UUID(),
            decisionID: decisionID,
            decidedAt: date,
            observation: observation,
            salience: .high,
            delivery: .active,
            tone: .proud,
            familiarity: .established,
            trajectory: .improving,
            templateID: "achievement.pr.weight#t0b0",
            title: "New record",
            body: "20 lb. New high.",
            standaloneCountToday: 0,
            quietDeferred: false,
            cooling: .mild,
            recentSimilarCount: 1,
            whyThisWon: "High salience beat the other candidate.",
            outcome: outcome
        )
    }

    @MainActor
    private final class FakePersonaDebugProvider: PersonaDebugProviding {
        let status: PersonaStatus
        let state: PersonaTraceState

        init(status: PersonaStatus, state: PersonaTraceState) {
            self.status = status
            self.state = state
        }

        func personaStatus() -> PersonaStatus { status }
        func personaTraceState() -> PersonaTraceState { state }
        func runPersonaDetectorsNow() async {}
        func resetPersona() async {}
    }
}
