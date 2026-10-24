import XCTest
@testable import PostureAnalysisApp

final class PersonaContextBuilderTests: XCTestCase {
    private var now: Date { PersonaFixtures.date(day: 24, month: 10, year: 2026, hour: 12) }
    private var calendar: Calendar { PersonaFixtures.calendar }

    func testFamiliarityBoundariesAndLongTermSpan() {
        XCTAssertEqual(context(workoutDaysAgo: Array(0..<4)).familiarity, .new)
        XCTAssertEqual(context(workoutDaysAgo: Array(0..<5)).familiarity, .familiar)
        XCTAssertEqual(context(workoutDaysAgo: Array(0..<14)).familiarity, .familiar)
        XCTAssertEqual(context(workoutDaysAgo: Array(0..<15)).familiarity, .established)
        XCTAssertEqual(context(workoutDaysAgo: Array(0..<39)).familiarity, .established)

        let longTermOffsets = Array(0..<39) + [56]
        XCTAssertEqual(context(workoutDaysAgo: longTermOffsets).familiarity, .longTerm)
        XCTAssertEqual(context(workoutDaysAgo: Array(0..<40)).familiarity, .established)
    }

    func testResetDateFiltersRelationshipRecordsAndFamiliarityOnly() {
        let resetDate = date(daysAgo: 4)
        let records = [
            PersonaFixtures.record(endingAt: date(daysAgo: 8)),
            PersonaFixtures.record(endingAt: date(daysAgo: 5)),
            PersonaFixtures.record(endingAt: date(daysAgo: 4)),
            PersonaFixtures.record(endingAt: date(daysAgo: 3)),
            PersonaFixtures.record(endingAt: date(daysAgo: 2)),
        ]

        let result = build(records: records, resetDate: resetDate)

        XCTAssertEqual(result.records.count, 5)
        XCTAssertEqual(result.relationshipRecords.count, 3)
        XCTAssertTrue(result.relationshipRecords.allSatisfy { $0.endedAt >= resetDate })
        XCTAssertEqual(result.familiarity, .new)
    }

    func testTrajectoryBoundaries() {
        XCTAssertEqual(
            context(workoutDaysAgo: [1, 7, 13, 20]).trajectory,
            .improving
        )
        XCTAssertEqual(
            context(workoutDaysAgo: [1, 20, 21, 27]).trajectory,
            .declining
        )
        XCTAssertEqual(
            context(workoutDaysAgo: [1, 7, 20, 27]).trajectory,
            .stable
        )
        XCTAssertEqual(
            context(workoutDaysAgo: [1, 7, 20]).trajectory,
            .unknown
        )
    }

    func testBuilderSortsRecordsAndAssessmentsAscending() {
        let newest = date(daysAgo: 1)
        let middle = date(daysAgo: 2)
        let oldest = date(daysAgo: 3)
        let records = [
            PersonaFixtures.record(endingAt: newest),
            PersonaFixtures.record(endingAt: oldest),
            PersonaFixtures.record(endingAt: middle),
        ]
        let assessments = [
            PersonaFixtures.assessment(date: newest),
            PersonaFixtures.assessment(date: oldest),
            PersonaFixtures.assessment(date: middle),
        ]

        let result = build(records: records, assessments: assessments)

        XCTAssertEqual(result.records.map(\.endedAt), [oldest, middle, newest])
        XCTAssertEqual(result.assessments.map(\.date), [oldest, middle, newest])
    }

    func testReminderSlotTimesRespectEnabledStateAndAreAscending() {
        var disabledSettings = PersonaFixtures.reminderSettings
        disabledSettings.enabled = false
        XCTAssertTrue(build(records: [], settings: disabledSettings).reminderSlotTimes.isEmpty)

        let enabled = build(records: [], settings: PersonaFixtures.reminderSettings)
        XCTAssertFalse(enabled.reminderSlotTimes.isEmpty)
        XCTAssertEqual(enabled.reminderSlotTimes, enabled.reminderSlotTimes.sorted())
    }

    private func context(workoutDaysAgo offsets: [Int]) -> PersonaContext {
        let records = offsets.enumerated().map { index, offset in
            PersonaFixtures.record(id: identifier(index + 1), endingAt: date(daysAgo: offset))
        }
        return build(records: records)
    }

    func testContextKeepsTheRawHistoryAndIntroCountsPendingImmediateMessages() {
        let routineID = UUID()
        let history = PersonaHistory(records: [PersonaFixtures.record(endingAt: date(daysAgo: 1))], routineNames: [routineID: "Upper"])
        func context(traces: PersonaTraceState) -> PersonaContext {
            PersonaContextBuilder.build(
                history: history, settings: PersonaFixtures.reminderSettings, extraPersonableEnabled: true,
                personaResetDate: nil, traceState: traces, trigger: .reconcile, acknowledgmentWillFire: false,
                appIsActive: false, now: now, calendar: calendar
            )
        }
        XCTAssertEqual(context(traces: .empty).history, history)
        XCTAssertTrue(context(traces: .empty).isIntro)

        let observation = PersonaFixtures.observation(.lapse, "comeback", salience: .medium)
        func trace(identifier: String) -> PersonaDecisionTrace {
            PersonaDecisionTrace(
                id: UUID(), decisionID: UUID(), decidedAt: now, observation: observation, salience: .medium,
                delivery: .passive, tone: .warm, familiarity: .new, trajectory: .unknown, templateID: nil, title: nil,
                body: nil, standaloneCountToday: 0, quietDeferred: true, cooling: .none, recentSimilarCount: 0,
                whyThisWon: "", outcome: .sent(fireDate: now.addingTimeInterval(3_600), identifier: identifier)
            )
        }
        let pendingImmediate = PersonaTraceState(sent: [trace(identifier: PersonaNotificationRequest.immediatePrefix + "x")])
        XCTAssertFalse(context(traces: pendingImmediate).isIntro, "a deferred first message already carries the intro")
        let pendingProjected = PersonaTraceState(sent: [trace(identifier: PersonaNotificationRequest.projectedPrefix + "x")])
        XCTAssertTrue(context(traces: pendingProjected).isIntro, "projected messages are replaced, so they do not count")
    }

    private func build(
        records: [WorkoutRecord],
        assessments: [PostureAssessment] = [],
        settings: WorkoutReminderSettings = PersonaFixtures.reminderSettings,
        resetDate: Date? = nil,
        now: Date? = nil
    ) -> PersonaContext {
        PersonaContextBuilder.build(
            history: PersonaHistory(records: records, assessments: assessments),
            settings: settings,
            extraPersonableEnabled: true,
            personaResetDate: resetDate,
            traceState: .empty,
            trigger: .reconcile,
            acknowledgmentWillFire: false,
            appIsActive: false,
            now: now ?? self.now,
            calendar: calendar
        )
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    }

    private func identifier(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }
}
