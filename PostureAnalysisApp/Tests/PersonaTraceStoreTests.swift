import XCTest
@testable import PostureAnalysisApp

final class PersonaTraceStoreTests: XCTestCase {
    private var now: Date { PersonaFixtures.date(day: 16, hour: 12) }

    func testFiredCommittedAndRecentToneSelection() {
        let fired = trace(offset: -60, tone: .warm, identifier: PersonaNotificationRequest.projectedPrefix + "old")
        let pendingProjected = trace(offset: 60, tone: .concerned, identifier: PersonaNotificationRequest.projectedPrefix + "pending")
        let pendingImmediate = trace(offset: 60, tone: .proud, identifier: PersonaNotificationRequest.immediatePrefix + "pending")
        let pendingFold = trace(offset: 60, tone: .pleased, identifier: nil, delivery: .foldedReplace)
        let state = PersonaTraceState(sent: [pendingProjected, pendingImmediate, pendingFold, fired])

        XCTAssertEqual(state.fired(asOf: now).map(\.id), [fired.id])
        XCTAssertEqual(
            Set(state.committed(asOf: now).map(\.id)),
            Set([fired.id, pendingImmediate.id, pendingFold.id])
        )
        XCTAssertEqual(state.recentTones(asOf: now, limit: 1), [.warm])
        XCTAssertEqual(state.recentTones(asOf: now, limit: 0), [])
    }

    func testReplacePendingKeepsImmediateAndFoldedAndTrimsFired() {
        var state = PersonaTraceState(sent: [
            trace(offset: -500, tone: .proud, identifier: "old.1"),
            trace(offset: -400, tone: .proud, identifier: "old.2"),
            trace(offset: -300, tone: .proud, identifier: "old.3"),
            trace(offset: 120, tone: .warm, identifier: PersonaNotificationRequest.projectedPrefix + "replace"),
            trace(offset: 90, tone: .pleased, identifier: PersonaNotificationRequest.immediatePrefix + "keep"),
            trace(offset: 80, tone: .smug, identifier: nil, delivery: .foldedAppend),
        ])
        let incomingFired = trace(offset: -30, tone: .competitive, identifier: "incoming")
        let sameKeyOld = trace(offset: -20, tone: nil, identifier: nil, outcome: .suppressed(.lowSalience), key: "duplicate")
        let sameKeyNew = trace(offset: -10, tone: nil, identifier: nil, outcome: .suppressed(.recentlySent), key: "duplicate")
        let freshSuppression = trace(offset: -5, tone: nil, identifier: nil, outcome: .suppressed(.cooling), key: "fresh")
        state.suppressed = [sameKeyOld, trace(offset: -100, tone: nil, identifier: nil, outcome: .suppressed(.lowSalience), key: "old")]

        var policy = PersonaPolicy.standard
        policy.sentTraceLimit = 2
        policy.suppressedTraceLimit = 2
        state.replacePending(with: [incomingFired, sameKeyNew, freshSuppression], now: now, policy: policy)

        let sentIDs = Set(state.sent.map(\.id))
        XCTAssertTrue(sentIDs.contains(incomingFired.id))
        XCTAssertTrue(state.sent.contains { $0.identifier == PersonaNotificationRequest.immediatePrefix + "keep" })
        XCTAssertTrue(state.sent.contains { $0.delivery == .foldedAppend })
        XCTAssertFalse(state.sent.contains { $0.identifier == PersonaNotificationRequest.projectedPrefix + "replace" })
        XCTAssertEqual(state.sent.filter { $0.isFired(asOf: now) }.count, 2)
        XCTAssertEqual(state.suppressed.count, 2)
        XCTAssertEqual(
            Set(state.suppressed.map { $0.observation.key.string }),
            Set(["achievement.pr.weight.duplicate.-", "achievement.pr.weight.fresh.-"])
        )
        XCTAssertEqual(state.suppressed.first?.id, freshSuppression.id)
        XCTAssertTrue(state.suppressed.contains { $0.id == sameKeyNew.id })
        XCTAssertFalse(state.suppressed.contains { $0.id == sameKeyOld.id })
    }

    func testRecordTrimsEngagementAtPolicyLimit() {
        var state = PersonaTraceState()
        var policy = PersonaPolicy.standard
        policy.engagementLimit = 2
        let events = (0..<3).map { index in
            PersonaEngagementEvent(
                traceID: UUID(), observationKey: "key.\(index)", kind: .tapped,
                date: now.addingTimeInterval(TimeInterval(index))
            )
        }
        for event in events { state.record(event, policy: policy) }
        XCTAssertEqual(state.engagement.map(\.observationKey), ["key.2", "key.1"])
    }

    func testFileStoreRoundTripCreatesParentDirectoryAndPreservesDates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("nested/persona-traces.json")
        let exactDate = Date(timeIntervalSince1970: 1_792_167_262.123_456)
        let sent = trace(offset: 0, tone: .smug, identifier: "fixed", date: exactDate)
        let event = PersonaEngagementEvent(
            traceID: sent.id,
            observationKey: sent.observation.key.string,
            kind: .dismissed,
            date: exactDate.addingTimeInterval(0.000_123)
        )
        let state = PersonaTraceState(sent: [sent], suppressed: [
            trace(offset: 0, tone: nil, identifier: nil, outcome: .suppressed(.noContent), key: "suppressed", date: exactDate)
        ], engagement: [event])

        let store = FilePersonaTraceStore(url: url)
        store.save(state)
        XCTAssertEqual(store.load(), state)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testFileStoreMissingAndCorruptFilesLoadEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("persona-traces.json")
        let store = FilePersonaTraceStore(url: url)
        XCTAssertEqual(store.load(), .empty)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(store.load(), .empty)
    }

    func testFixedQuietHoursCrossingMidnightBoundaries() {
        let quiet = FixedQuietHours(startHour: 22, endHour: 8)
        let calendar = PersonaFixtures.calendar
        XCTAssertNil(quiet.quietInterval(containing: PersonaFixtures.date(day: 16, hour: 21, minute: 59), calendar: calendar))

        let atStart = quiet.quietInterval(containing: PersonaFixtures.date(day: 16, hour: 22), calendar: calendar)
        XCTAssertEqual(atStart?.start, PersonaFixtures.date(day: 16, hour: 22))
        XCTAssertEqual(atStart?.end, PersonaFixtures.date(day: 17, hour: 8))

        let beforeEnd = quiet.quietInterval(containing: PersonaFixtures.date(day: 17, hour: 7, minute: 59), calendar: calendar)
        XCTAssertEqual(beforeEnd?.start, PersonaFixtures.date(day: 16, hour: 22))
        XCTAssertEqual(beforeEnd?.end, PersonaFixtures.date(day: 17, hour: 8))
        XCTAssertNil(quiet.quietInterval(containing: PersonaFixtures.date(day: 17, hour: 8), calendar: calendar))
    }

    func testFixedQuietHoursNonCrossingBoundaries() {
        let quiet = FixedQuietHours(startHour: 9, endHour: 17)
        let calendar = PersonaFixtures.calendar
        XCTAssertNil(quiet.quietInterval(containing: PersonaFixtures.date(day: 16, hour: 8, minute: 59), calendar: calendar))
        XCTAssertEqual(
            quiet.quietInterval(containing: PersonaFixtures.date(day: 16, hour: 9), calendar: calendar)?.start,
            PersonaFixtures.date(day: 16, hour: 9)
        )
        XCTAssertNotNil(quiet.quietInterval(containing: PersonaFixtures.date(day: 16, hour: 16, minute: 59), calendar: calendar))
        XCTAssertNil(quiet.quietInterval(containing: PersonaFixtures.date(day: 16, hour: 17), calendar: calendar))
        XCTAssertNil(FixedQuietHours(startHour: 9, endHour: 9).quietInterval(containing: now, calendar: calendar))
    }

    private func trace(
        offset: TimeInterval,
        tone: PersonaTone?,
        identifier: String?,
        delivery: PersonaDelivery = .active,
        outcome: PersonaDecisionTrace.Outcome? = nil,
        key: String? = nil,
        date: Date? = nil
    ) -> PersonaDecisionTrace {
        let decidedAt = date ?? now.addingTimeInterval(offset)
        let fireDate = date ?? decidedAt
        let observation = PersonaFixtures.observation(
            .achievement, "pr.weight", subject: key ?? UUID().uuidString,
            salience: .high
        )
        return PersonaDecisionTrace(
            id: UUID(),
            decisionID: UUID(),
            decidedAt: decidedAt,
            observation: observation,
            salience: .high,
            delivery: delivery,
            tone: tone,
            familiarity: .established,
            trajectory: .stable,
            templateID: "fixture#t0b0",
            title: tone == nil ? nil : "Title",
            body: tone == nil ? nil : "Body",
            standaloneCountToday: 0,
            quietDeferred: false,
            cooling: .none,
            recentSimilarCount: 0,
            whyThisWon: "Fixture.",
            outcome: outcome ?? .sent(fireDate: fireDate, identifier: identifier)
        )
    }
}
