import XCTest
@testable import PostureAnalysisApp

/// Pins scenario transitions to the values in `NotificationPolicy` using saved records.
final class NotificationPolicyBoundaryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let origin = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!
        let date = calendar.date(byAdding: .day, value: offset, to: origin)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
    }

    private func record(_ offset: Int, hour: Int = 12) -> WorkoutRecord {
        record(on: day(offset, hour: hour))
    }

    private func record(on end: Date) -> WorkoutRecord {
        return WorkoutRecord(
            startedAt: end.addingTimeInterval(-600), endedAt: end, planName: nil,
            entries: [WorkoutRecordEntry(
                exerciseID: .shoulderPress, name: "Press", sets: [RecordedSet(reps: 1)]
            )]
        )
    }

    private func run(_ endOffset: Int, length: Int, hour: Int = 12) -> [WorkoutRecord] {
        (endOffset - length + 1...endOffset).map { record($0, hour: hour) }
    }

    private func settings(hour: Int = 17, minute: Int = 0) -> WorkoutReminderSettings {
        WorkoutReminderSettings(
            enabled: true, recurrence: .daily, hour: hour, minute: minute,
            everyOtherDayStartDate: day(0), weekdays: Set(1...7)
        )
    }

    private func selected(
        records: [WorkoutRecord], offset: Int, slot: NotificationSlot = .reminder,
        settings: WorkoutReminderSettings? = nil, time: Date? = nil
    ) -> String {
        let activeSettings = settings ?? self.settings()
        let date = day(offset)
        let slotTime = time ?? NotificationSlotSchedule.slots(
            day: date, settings: activeSettings, calendar: calendar
        ).first(where: { $0.slot == slot })!.time
        let facts = NotificationScenarioSelector.nudgeFacts(
            day: date, slot: slot, slotTime: slotTime, records: records,
            settings: activeSettings, isFirstEverNotification: false, calendar: calendar
        )
        return NotificationScenarioSelector.select(nudge: facts).scenarioID
    }

    private func acknowledgmentID(
        _ records: [WorkoutRecord], latest: WorkoutRecord,
        settings: WorkoutReminderSettings? = nil
    ) -> String? {
        NotificationScenarioSelector.acknowledgment(
            for: latest, records: records, settings: settings ?? self.settings(), calendar: calendar
        )?.scenarioID
    }

    private func planner(_ records: [WorkoutRecord], today: Int, policy: NotificationPolicy = .standard) throws
        -> [PlannedNotification] {
        let catalog = try NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self))
        return NotificationPlanner.plan(
            records: records, settings: settings(), now: day(today, hour: 8), calendar: calendar,
            suggestion: nil, isFirstEverNotification: false, catalog: catalog, policy: policy
        )
    }

    func testMeaningfulAndAlmostWeekStreakBoundaries() {
        XCTAssertEqual(selected(records: run(4, length: 4), offset: 5), "early-streak-forming")
        XCTAssertEqual(selected(records: run(4, length: 5), offset: 5), "established-streak-reminder")
        XCTAssertEqual(selected(records: run(4, length: 6), offset: 5), "almost-one-week")
        XCTAssertEqual(selected(records: run(4, length: 7), offset: 5), "established-streak-reminder")
    }

    func testLongAbsenceBoundaryForNudgeAndAcknowledgment() {
        XCTAssertEqual(selected(records: [record(0)], offset: 6), "ordinary-daily-reminder")
        XCTAssertEqual(selected(records: [record(0)], offset: 7), "long-absence")
        let sixDayGap = [record(0), record(6)]
        let sevenDayGap = [record(0), record(7)]
        XCTAssertEqual(acknowledgmentID(sixDayGap, latest: sixDayGap.last!), "session-completed")
        XCTAssertEqual(
            acknowledgmentID(sevenDayGap, latest: sevenDayGap.last!),
            "comeback-after-long-absence"
        )
    }

    func testRecentHistoryBoundaryControlsAdditionalSlots() throws {
        let policy = NotificationPolicy(
            stopAfterDaysWithoutWorkout: 100, taperAfterMissedPlannedDays: 100
        )
        let atCutoff = try planner([record(0)], today: 14, policy: policy)
        let beyondCutoff = try planner([record(0)], today: 15, policy: policy)
        XCTAssertEqual(atCutoff.filter { $0.fireDate.month == 1 && $0.fireDate.day == day(14).day }.map(\.slot),
                       [.reminder, .followUp, .finalWarning])
        let nextDaySlots = beyondCutoff.filter {
            $0.fireDate.month == 1 && $0.fireDate.day == day(15).day
        }.map(\.slot)
        XCTAssertEqual(nextDaySlots, [.reminder])
    }

    func testConsistencyCountsRecentPlannedDaysAtTwoAndThreeOfFour() {
        let two = [record(0), record(2)]
        let three = [record(-1), record(0), record(2)]
        XCTAssertEqual(selected(records: two, offset: 3), "ordinary-daily-reminder")
        XCTAssertEqual(selected(records: three, offset: 3), "neutral-check-in")
    }

    func testHighValueStreakAndPersonalBestBoundaries() {
        let oldRun = run(-22, length: 22)
        let current20 = oldRun + run(20, length: 20)
        let current21 = oldRun + run(21, length: 21)
        XCTAssertEqual(selected(records: current20, offset: 21, slot: .followUp), "established-streak-at-risk")
        XCTAssertEqual(selected(records: current21, offset: 22, slot: .followUp), "high-value-streak-at-risk")

        let personalBest13 = run(-13, length: 13) + run(12, length: 13)
        let personalBest14 = run(-14, length: 14) + run(13, length: 14)
        XCTAssertEqual(selected(records: personalBest13, offset: 13, slot: .followUp), "established-streak-at-risk")
        XCTAssertEqual(selected(records: personalBest14, offset: 14, slot: .followUp), "high-value-streak-at-risk")
    }

    func testPersonalBestMinimumAndApproachingWindowBoundaries() {
        let record6 = run(-6, length: 6) + run(8, length: 5)
        let record7 = run(-7, length: 7) + run(8, length: 5)
        XCTAssertEqual(selected(records: record6, offset: 9), "established-streak-reminder")
        XCTAssertEqual(selected(records: record7, offset: 9), "approaching-personal-best")

        let remaining4 = run(-8, length: 8) + run(8, length: 5)
        let remaining3 = run(-8, length: 8) + run(8, length: 6)
        XCTAssertEqual(selected(records: remaining4, offset: 9), "established-streak-reminder")
        XCTAssertEqual(selected(records: remaining3, offset: 9), "approaching-personal-best")
    }

    func testLateNightAndMorningHourBoundaries() {
        let at2059 = day(3, hour: 20).addingTimeInterval(59 * 60)
        let at2100 = day(3, hour: 21)
        XCTAssertEqual(
            selected(records: [record(2)], offset: 3, time: at2059), "ordinary-daily-reminder"
        )
        XCTAssertEqual(selected(records: [record(2)], offset: 3, time: at2100), "late-night-reminder")

        XCTAssertEqual(selected(records: [record(2)], offset: 3, settings: settings(hour: 9, minute: 59)),
                       "morning-reminder")
        XCTAssertEqual(selected(records: [record(2)], offset: 3, settings: settings(hour: 10)),
                       "ordinary-daily-reminder")
    }

    func testTaperAndStopBoundaries() throws {
        let twoMissed = try planner([record(0)], today: 3)
        let threeMissed = try planner([record(0)], today: 4)
        XCTAssertEqual(twoMissed.filter { $0.fireDate.day == day(3).day }.count, 3)
        XCTAssertEqual(threeMissed.filter { $0.fireDate.day == day(4).day }.map(\.slot), [.reminder])

        let gap13 = try planner([record(0)], today: 13)
        let gap14 = try planner([record(0)], today: 14)
        XCTAssertFalse(gap13.isEmpty)
        XCTAssertTrue(gap14.isEmpty)
    }

    func testRareEscalationStreakAndDivisibilityBoundaries() {
        let dayDivisibleByFive = (50...90).first {
            NotificationCopyPicker.dayNumber(for: day($0), calendar: calendar).isMultiple(of: 5)
        }!
        XCTAssertEqual(
            selected(records: run(dayDivisibleByFive - 1, length: 29), offset: dayDivisibleByFive,
                     slot: .finalWarning), "final-streak-warning"
        )
        XCTAssertEqual(
            selected(records: run(dayDivisibleByFive - 1, length: 30), offset: dayDivisibleByFive,
                     slot: .finalWarning), "rare-escalation"
        )

        let nonFiveDivisor = (50...90).first {
            let number = NotificationCopyPicker.dayNumber(for: day($0), calendar: calendar)
            return number.isMultiple(of: 4) && !number.isMultiple(of: 5)
        }!
        XCTAssertEqual(
            selected(records: run(nonFiveDivisor - 1, length: 30, hour: 23), offset: nonFiveDivisor,
                     slot: .finalWarning), "strong-repeated-dismissal"
        )
        let nonFiveSixDivisor = (50...90).first {
            let number = NotificationCopyPicker.dayNumber(for: day($0), calendar: calendar)
            return number.isMultiple(of: 6) && !number.isMultiple(of: 5)
        }!
        XCTAssertEqual(
            selected(records: run(nonFiveSixDivisor - 1, length: 30), offset: nonFiveSixDivisor,
                     slot: .finalWarning), "final-streak-warning"
        )
    }

    func testHabitualIgnoreThresholdAtOneAndTwoLateCompletions() {
        let recordsOneLate = (0...4).map { record($0, hour: $0 == 4 ? 23 : 12) }
        let recordsTwoLate = (0...4).map { record($0, hour: $0 >= 3 ? 23 : 12) }
        XCTAssertEqual(selected(records: recordsOneLate, offset: 5, slot: .finalWarning), "final-streak-warning")
        XCTAssertEqual(selected(records: recordsTwoLate, offset: 5, slot: .finalWarning), "strong-repeated-dismissal")
    }

    func testPerfectWeekRequiresThreePlannedDays() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let twoDaySettings = WorkoutReminderSettings(
            enabled: true, recurrence: .weekly, hour: 17, minute: 0,
            everyOtherDayStartDate: monday, weekdays: [3, 5]
        )
        let threeDaySettings = WorkoutReminderSettings(
            enabled: true, recurrence: .weekly, hour: 17, minute: 0,
            everyOtherDayStartDate: monday, weekdays: [3, 5, 7]
        )
        let twoDayRecords = [record(0), record(2)]
        let threeDayRecords = [record(0), record(2), record(4)]
        XCTAssertEqual(
            NotificationScenarioSelector.acknowledgment(
                for: twoDayRecords.last!, records: twoDayRecords, settings: twoDaySettings, calendar: calendar
            )?.scenarioID, "session-completed"
        )
        XCTAssertEqual(
            NotificationScenarioSelector.acknowledgment(
                for: threeDayRecords.last!, records: threeDayRecords,
                settings: threeDaySettings, calendar: calendar
            )?.scenarioID, "perfect-week"
        )
    }

    func testMajorMilestoneBoundariesAroundFourteenAndHundreds() {
        let weeklySettings = WorkoutReminderSettings(
            enabled: true, recurrence: .weekly, hour: 17, minute: 0,
            everyOtherDayStartDate: day(0), weekdays: [3, 5]
        )
        for (length, expected) in [
            (13, "session-completed"), (14, "major-streak-milestone"),
            (99, "session-completed"), (100, "major-streak-milestone"),
            (198, "session-completed"), (199, "session-completed"),
            (200, "major-streak-milestone"), (201, "session-completed")
        ] {
            var records: [WorkoutRecord] = []
            var cursor = day(0)
            while records.count < length {
                if PlannedDays.isPlanned(cursor, settings: weeklySettings, calendar: calendar) {
                    records.append(record(on: cursor.addingTimeInterval(11 * 60 * 60)))
                }
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            }
            let latest = records.removeLast()
            let midday = record(on: calendar.date(
                bySettingHour: 12, minute: 0, second: 0, of: latest.endedAt
            )!)
            records.append(midday)
            XCTAssertEqual(
                acknowledgmentID(records, latest: midday, settings: weeklySettings),
                expected, "run length \(length)"
            )
        }
    }

    // MARK: Constants the first boundary pass missed, found by changing each value by one.

    func testEarlyStreakStartsAtTwoPlannedDays() {
        // Monday, so neither the weekend nor the morning rule can apply.
        XCTAssertEqual(selected(records: run(5, length: 1), offset: 6), "ordinary-daily-reminder")
        XCTAssertEqual(selected(records: run(5, length: 2), offset: 6), "early-streak-forming")
    }

    func testConsistencyLooksAtExactlyTheLastFourPlannedDays() {
        // Streak is 1. Days 3 and 5 fall inside the last four planned days (2 through 5), day 1 does not.
        let outsideTheWindow = [record(1), record(3), record(5)]
        XCTAssertEqual(selected(records: outsideTheWindow, offset: 6), "ordinary-daily-reminder")
        // Day 2 is inside the window, so now three of the last four planned days were workout days.
        let insideTheWindow = [record(2), record(3), record(5)]
        XCTAssertEqual(selected(records: insideTheWindow, offset: 6), "neutral-check-in")
    }

    func testHabitualIgnoreLooksBackAtSevenCompletions() {
        // Late completions on days 3 and 9. Day 3 is the seventh most recent completion before day 10.
        let lateOnThreeAndNine = (0...9).map { record($0, hour: $0 == 3 || $0 == 9 ? 23 : 12) }
        XCTAssertEqual(
            selected(records: lateOnThreeAndNine, offset: 10, slot: .finalWarning), "strong-repeated-dismissal"
        )
        // Day 2 is the eighth most recent completion, so it falls outside the lookback.
        let lateOnTwoAndNine = (0...9).map { record($0, hour: $0 == 2 || $0 == 9 ? 23 : 12) }
        XCTAssertEqual(
            selected(records: lateOnTwoAndNine, offset: 10, slot: .finalWarning), "final-streak-warning"
        )
    }

    func testNotificationFreeSuccessLooksAtThePreviousThreeCompletions() {
        // Saturday, which is not the last planned day of its week, so no weekly rule applies.
        // Two of the previous three completions (days 1 and 2) ended before the first slot; day 3 did not.
        let twoOfThree = [record(1, hour: 8), record(2, hour: 8), record(3, hour: 18), record(4, hour: 8)]
        XCTAssertEqual(acknowledgmentID(twoOfThree, latest: twoOfThree.last!), "notification-free-success")
        // Only one of the previous three (day 1) ended early, so the success is not a habit yet.
        let oneOfThree = [record(1, hour: 8), record(2, hour: 18), record(3, hour: 18), record(4, hour: 8)]
        XCTAssertEqual(acknowledgmentID(oneOfThree, latest: oneOfThree.last!), "session-completed")
    }

    func testPlanCoversFourteenPlannedDaysAndStaysUnderTheSystemLimit() throws {
        // With no history only the reminder slot exists, so each planned day gives exactly one notification.
        let plan = try planner([], today: 0)
        XCTAssertEqual(plan.count, NotificationPolicy.standard.planningHorizonPlannedDays)
        XCTAssertEqual(Set(plan.map(\.fireDate.day)).count, 14)
        XCTAssertEqual(NotificationPolicy.standard.planningHorizonPlannedDays, 14)
        // iOS keeps only 64 pending local notifications, so the plan must stay below that.
        XCTAssertEqual(NotificationPolicy.standard.maximumRequests, 60)
        XCTAssertLessThan(NotificationPolicy.standard.maximumRequests, 64)
    }

    func testRequestCapStopsAHeavyPlan() throws {
        // The default policy tapers and stops long before any cap, so loosen those limits to reach it.
        let heavy = NotificationPolicy(
            recentHistoryDays: 100, stopAfterDaysWithoutWorkout: 100, taperAfterMissedPlannedDays: 100,
            planningHorizonPlannedDays: 30, maximumRequests: 50
        )
        let plan = try planner(run(-1, length: 10), today: 0, policy: heavy)
        XCTAssertEqual(plan.count, 50)
        let uncapped = NotificationPolicy(
            recentHistoryDays: 100, stopAfterDaysWithoutWorkout: 100, taperAfterMissedPlannedDays: 100,
            planningHorizonPlannedDays: 30, maximumRequests: 500
        )
        XCTAssertEqual(try planner(run(-1, length: 10), today: 0, policy: uncapped).count, 90)
    }

    func testAcknowledgmentArrivesThreeSecondsAfterTheWorkoutIsSaved() {
        XCTAssertEqual(NotificationPolicy.standard.acknowledgmentDelaySeconds, 3)
    }
}

private extension Date {
    var day: Int { Calendar(identifier: .gregorian).component(.day, from: self) }
}
