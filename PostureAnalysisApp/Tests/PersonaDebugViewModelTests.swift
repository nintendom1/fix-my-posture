import XCTest
@testable import PostureAnalysisApp

final class PersonaDebugViewModelTests: XCTestCase {
    @MainActor
    func testRefreshSortsAndLimitsSentAndSuppressedTraces() {
        let sent = (0..<12).map { offset in
            makeTrace(
                decisionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                date: FixedClock.date.addingTimeInterval(TimeInterval(offset * 60)),
                outcome: .sent(
                    fireDate: FixedClock.date.addingTimeInterval(TimeInterval(offset * 60)),
                    identifier: "sent-\(offset)"
                )
            )
        }
        let suppressed = (0..<24).map { offset in
            makeTrace(
                date: FixedClock.date.addingTimeInterval(TimeInterval(offset * 60)),
                outcome: .suppressed(.lowSalience)
            )
        }
        let provider = FakePersonaDebugProvider(state: PersonaTraceState(sent: sent, suppressed: suppressed))
        let viewModel = makeViewModel(provider: provider)

        XCTAssertEqual(viewModel.sent.count, 10)
        XCTAssertEqual(viewModel.sent.first?.identifier, "sent-11")
        XCTAssertEqual(viewModel.sent.last?.identifier, "sent-2")
        XCTAssertEqual(viewModel.suppressed.count, 20)
        XCTAssertEqual(viewModel.suppressed.first?.decidedAt, suppressed.last?.decidedAt)
        XCTAssertEqual(viewModel.status, provider.status)
    }

    @MainActor
    func testOtherCandidatesUseTheSharedDecisionIDAcrossBothLists() {
        let decisionID = UUID()
        let selected = makeTrace(decisionID: decisionID, outcome: .sent(fireDate: FixedClock.date, identifier: "sent"))
        let suppressed = makeTrace(decisionID: decisionID, outcome: .suppressed(.lowerPriorityThanSelected))
        let unrelated = makeTrace(outcome: .suppressed(.lowSalience))
        let provider = FakePersonaDebugProvider(state: PersonaTraceState(
            sent: [selected],
            suppressed: [unrelated, suppressed]
        ))
        let viewModel = makeViewModel(provider: provider)

        XCTAssertEqual(viewModel.otherCandidates(for: selected).map(\.id), [suppressed.id])
    }

    @MainActor
    func testVariantSteppingWrapsAtBothEnds() {
        let viewModel = makeViewModel()
        let count = viewModel.variantCount

        XCTAssertGreaterThanOrEqual(count, 1)
        for _ in 0..<count {
            viewModel.stepVariant(by: 1)
        }
        XCTAssertEqual(viewModel.variantIndex, 0)

        viewModel.stepVariant(by: -1)

        XCTAssertEqual(viewModel.variantIndex, count - 1)
        if let preview = viewModel.preview {
            XCTAssertEqual(preview.content.scenarioID, viewModel.selectedContentKey)
        }
    }

    @MainActor
    func testSendRequestsAuthorizationAndSchedulesThePreviewAtSavedDelay() async {
        let preferences = InMemoryPreferences()
        preferences.notificationPreviewDelaySeconds = 7
        let scheduler = FakePreviewScheduler(status: .notDetermined)
        let viewModel = makeViewModel(preferences: preferences, scheduler: scheduler)

        await viewModel.send()

        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled.first?.delay, 7)
        if let preview = viewModel.preview {
            XCTAssertEqual(scheduler.scheduled.first?.content, preview.content)
        }
        XCTAssertEqual(viewModel.sendState, .sent)
    }

    @MainActor
    func testRunDetectorsAndResetCallProviderThenRefresh() async {
        let provider = FakePersonaDebugProvider()
        let viewModel = makeViewModel(provider: provider)

        provider.status = makeStatus(enabled: true)
        await viewModel.runDetectorsNow()
        XCTAssertEqual(provider.runCount, 1)
        XCTAssertEqual(viewModel.status, provider.status)

        provider.state = PersonaTraceState(sent: [makeTrace()])
        await viewModel.resetPersona()
        XCTAssertEqual(provider.resetCount, 1)
        XCTAssertTrue(viewModel.sent.isEmpty)
        XCTAssertTrue(viewModel.suppressed.isEmpty)
    }

    func testMeterHelpersMapCategoriesAndClampInputs() {
        XCTAssertEqual(PersonaDebugMeters.familiarityDots(.new), 1)
        XCTAssertEqual(PersonaDebugMeters.familiarityDots(.familiar), 2)
        XCTAssertEqual(PersonaDebugMeters.familiarityDots(.established), 3)
        XCTAssertEqual(PersonaDebugMeters.familiarityDots(.longTerm), 4)

        XCTAssertEqual(PersonaDebugMeters.trajectoryDots(.unknown), 0)
        XCTAssertEqual(PersonaDebugMeters.trajectoryDots(.declining), 1)
        XCTAssertEqual(PersonaDebugMeters.trajectoryDots(.stable), 2)
        XCTAssertEqual(PersonaDebugMeters.trajectoryDots(.improving), 3)

        XCTAssertEqual(PersonaDebugMeters.evidenceDots(strength: 0), 0)
        XCTAssertEqual(PersonaDebugMeters.evidenceDots(strength: 1), 0)
        XCTAssertEqual(PersonaDebugMeters.evidenceDots(strength: 2), 1)
        XCTAssertEqual(PersonaDebugMeters.evidenceDots(strength: 5), 4)
        XCTAssertEqual(PersonaDebugMeters.evidenceDots(strength: 6), 4)

        XCTAssertEqual(PersonaDebugMeters.repetitionRiskDots(recentSimilarCount: -1), 0)
        XCTAssertEqual(PersonaDebugMeters.repetitionRiskDots(recentSimilarCount: 0), 0)
        XCTAssertEqual(PersonaDebugMeters.repetitionRiskDots(recentSimilarCount: 4), 4)
        XCTAssertEqual(PersonaDebugMeters.repetitionRiskDots(recentSimilarCount: 5), 4)

        XCTAssertEqual(PersonaDebugMeters.coolingDots(.none), 0)
        XCTAssertEqual(PersonaDebugMeters.coolingDots(.mild), 2)
        XCTAssertEqual(PersonaDebugMeters.coolingDots(.strong), 4)
    }

    @MainActor
    private func makeViewModel(
        provider: (any PersonaDebugProviding)? = nil,
        preferences: any AppPreferencesStoring = InMemoryPreferences(),
        scheduler: FakePreviewScheduler? = nil
    ) -> PersonaDebugViewModel {
        PersonaDebugViewModel(
            catalog: PersonaFixtures.catalog(),
            loadError: nil,
            provider: provider,
            scheduler: scheduler ?? FakePreviewScheduler(),
            preferences: preferences,
            now: { FixedClock.date },
            calendar: FixedClock.calendar
        )
    }

    private func makeStatus(enabled: Bool) -> PersonaStatus {
        PersonaStatus(
            extraPersonableEnabled: enabled,
            isActive: enabled,
            familiarity: .established,
            trajectory: .improving,
            cooling: .mild,
            standaloneCountToday: 1,
            dailyCap: 2,
            pendingCount: 3,
            quietHoursSummary: "22:00–08:00",
            isQuietNow: false,
            personaResetDate: FixedClock.date
        )
    }

    private func makeTrace(
        decisionID: UUID = UUID(),
        date: Date = FixedClock.date,
        outcome: PersonaDecisionTrace.Outcome = .sent(fireDate: FixedClock.date, identifier: "trace")
    ) -> PersonaDecisionTrace {
        let observation = PersonaFixtures.observation(
            .achievement,
            "pr.weight",
            salience: .high,
            contentKey: "achievement.pr.weight"
        )
        return PersonaDecisionTrace(
            id: UUID(),
            decisionID: decisionID,
            decidedAt: date,
            observation: observation,
            salience: observation.salience,
            delivery: .active,
            tone: .proud,
            familiarity: .familiar,
            trajectory: .improving,
            templateID: "achievement.pr.weight#t0b0",
            title: "New record",
            body: "20 lb. New high.",
            standaloneCountToday: 0,
            quietDeferred: false,
            cooling: .none,
            recentSimilarCount: 0,
            whyThisWon: "High salience.",
            outcome: outcome
        )
    }

    @MainActor
    private final class FakePersonaDebugProvider: PersonaDebugProviding {
        var status: PersonaStatus = .inactive
        var state = PersonaTraceState.empty
        private(set) var runCount = 0
        private(set) var resetCount = 0

        init(state: PersonaTraceState = .empty) {
            self.state = state
        }

        func personaStatus() -> PersonaStatus { status }
        func personaTraceState() -> PersonaTraceState { state }

        func runPersonaDetectorsNow() async {
            runCount += 1
        }

        func resetPersona() async {
            resetCount += 1
            state = .empty
        }
    }
}
