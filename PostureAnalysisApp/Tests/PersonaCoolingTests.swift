import XCTest
@testable import PostureAnalysisApp

final class PersonaCoolingTests: XCTestCase {
    private let now = PersonaFixtures.date(day: 24, hour: 12)

    func testCoolingDismissalBoundariesAndTapPreventsMildCooling() {
        let traces = (0..<3).map { trace(offsetHours: TimeInterval($0 * 2)) }
        XCTAssertEqual(level(traces: Array(traces.prefix(1)), dismissals: 1), .none)
        XCTAssertEqual(level(traces: Array(traces.prefix(2)), dismissals: 2), .mild)
        XCTAssertEqual(level(traces: traces, dismissals: 2), .mild)
        XCTAssertEqual(level(traces: traces, dismissals: 3), .strong)
        XCTAssertEqual(level(traces: traces, dismissals: 2, taps: 1), .none)
    }

    func testUnansweredCoolingRequiresAllFiveOlderThanNoResponseBoundary() {
        let oldTraces = (0..<5).map { trace(offsetHours: 30 + Double($0)) }
        XCTAssertEqual(level(traces: oldTraces), .strong)

        let boundaryTraces = (0..<4).map { trace(offsetHours: 30 + Double($0)) }
            + [trace(offsetHours: 24)]
        XCTAssertEqual(level(traces: boundaryTraces), .none)

        let engaged = [event(for: oldTraces[2], kind: .dismissed)]
        XCTAssertEqual(PersonaCooling.level(engagement: engaged, sent: oldTraces, now: now), .none)
    }

    func testCoolingDecayIgnoresOldMessagesAndEngagement() {
        let old = trace(offsetDays: 15)
        let oldDismissal = PersonaEngagementEvent(
            traceID: old.id,
            observationKey: old.observation.key.string,
            kind: .dismissed,
            date: now.addingTimeInterval(-15 * 86_400)
        )
        XCTAssertEqual(PersonaCooling.level(engagement: [oldDismissal], sent: [old], now: now), .none)

        let boundary = trace(offsetDays: 14)
        let boundaryDismissals = (0..<3).map { index in
            PersonaEngagementEvent(
                traceID: boundary.id,
                observationKey: boundary.observation.key.string,
                kind: .dismissed,
                date: now.addingTimeInterval(-TimeInterval(index))
            )
        }
        XCTAssertEqual(PersonaCooling.level(engagement: boundaryDismissals, sent: [boundary], now: now), .strong)
    }

    func testTapOnNewestFiredMessageClearsCooling() {
        let traces = (0..<4).map { trace(offsetHours: Double($0)) }
        var events = traces.dropFirst().map { event(for: $0, kind: .dismissed) }
        events.append(event(for: traces[0], kind: .tapped))
        XCTAssertEqual(PersonaCooling.level(engagement: events, sent: traces, now: now), .none)
    }

    func testAdjustedSalienceForEachCoolingLevel() {
        let achievement = PersonaFixtures.observation(.achievement, "pr.weight", salience: .high)
        let pattern = PersonaFixtures.observation(.pattern, "weekday", salience: .high)
        let comeback = PersonaFixtures.observation(.lapse, "comeback", salience: .high)

        for salience in PersonaSalience.allCases {
            XCTAssertEqual(PersonaCooling.adjusted(salience, for: pattern, level: .none), salience)
        }
        XCTAssertEqual(PersonaCooling.adjusted(.high, for: pattern, level: .mild), .high)
        XCTAssertEqual(PersonaCooling.adjusted(.medium, for: pattern, level: .mild), .low)
        XCTAssertEqual(PersonaCooling.adjusted(.low, for: pattern, level: .mild), .low)
        XCTAssertEqual(PersonaCooling.adjusted(.high, for: achievement, level: .strong), .high)
        XCTAssertNil(PersonaCooling.adjusted(.medium, for: achievement, level: .strong))
        XCTAssertNil(PersonaCooling.adjusted(.high, for: pattern, level: .strong))
        XCTAssertEqual(PersonaCooling.adjusted(.high, for: comeback, level: .strong), .high)
        XCTAssertNil(PersonaCooling.adjusted(.low, for: comeback, level: .strong))
    }

    private func level(
        traces: [PersonaDecisionTrace],
        dismissals: Int = 0,
        taps: Int = 0
    ) -> PersonaCoolingLevel {
        let events = traces.prefix(dismissals).map { event(for: $0, kind: .dismissed) }
            + traces.suffix(taps).map { event(for: $0, kind: .tapped) }
        return PersonaCooling.level(engagement: events, sent: traces, now: now)
    }

    private func event(for trace: PersonaDecisionTrace, kind: PersonaEngagementEvent.Kind) -> PersonaEngagementEvent {
        PersonaEngagementEvent(
            traceID: trace.id,
            observationKey: trace.observation.key.string,
            kind: kind,
            date: now.addingTimeInterval(-60)
        )
    }

    func testFoldedMessagesNeverCountAsUnanswered() {
        let folds = (0..<5).map { trace(offsetHours: 30 + Double($0), delivery: .foldedReplace) }
        XCTAssertEqual(level(traces: folds), .none, "folds ride on the acknowledgment and cannot report engagement")
        let mixed = folds + (0..<5).map { trace(offsetHours: 40 + Double($0)) }
        XCTAssertEqual(level(traces: mixed), .strong)
    }

    private func trace(offsetHours: TimeInterval = 0, offsetDays: Int = 0, delivery: PersonaDelivery = .active) -> PersonaDecisionTrace {
        let fireDate = now.addingTimeInterval(-TimeInterval(offsetDays) * 86_400 - offsetHours * 3_600)
        let observation = PersonaFixtures.observation(.achievement, "pr.weight", subject: UUID().uuidString, salience: .high)
        return PersonaDecisionTrace(
            id: UUID(),
            decisionID: UUID(),
            decidedAt: fireDate,
            observation: observation,
            salience: .high,
            delivery: delivery,
            tone: .proud,
            familiarity: .established,
            trajectory: .stable,
            templateID: "fixture#t0b0",
            title: "Title",
            body: "Body",
            standaloneCountToday: 0,
            quietDeferred: false,
            cooling: .none,
            recentSimilarCount: 0,
            whyThisWon: "Fixture.",
            outcome: .sent(fireDate: fireDate, identifier: "fixture.\(UUID().uuidString)")
        )
    }
}
