import XCTest
@testable import PostureAnalysisApp

final class PersonaDetectorTests: XCTestCase {
    private var calendar: Calendar { PersonaFixtures.calendar }
    private var now: Date { PersonaFixtures.date(day: 24, month: 10, year: 2026, hour: 12) }

    func testWeightPRThresholdMixesUnitsAndHasStableKey() throws {
        let prior = (1...3).map { id in
            makeRecord(id: id, daysAgo: id + 2, entries: [rowSet(8, lb: 40)])
        }
        let trigger = makeRecord(id: 10, daysAgo: 0, entries: [rowSet(8, kg: 20)])
        let observations = achievement(context(records: prior + [trigger], trigger: trigger))
        let result = try XCTUnwrap(observations.first { $0.key.kind == "pr.weight" })

        XCTAssertEqual(result.key, PersonaObservationKey(family: .achievement, kind: "pr.weight", subject: "dumbbell_row", period: "2026-10-24"))
        XCTAssertEqual(result.contentKey, "achievement.pr.weight")
        XCTAssertEqual(result.salience, .high)
        XCTAssertEqual(result.values["value"], "20 kg")
        XCTAssertEqual(result.values["exercise"], PersonaFixtures.rows.rawValue)

        let belowThreshold = makeRecord(id: 11, daysAgo: 0, entries: [rowSet(8, kg: 20)])
        let twoPriorSessions = Array(prior.prefix(2)) + [belowThreshold]
        XCTAssertFalse(achievement(context(records: Array(twoPriorSessions), trigger: belowThreshold))
            .contains { $0.key.kind == "pr.weight" })
    }

    func testWeightPRIgnoresBandsAndSuppressesRepPRForTheExercise() {
        let bandHistory = (1...3).map { id in
            makeRecord(id: id, daysAgo: id + 2, entries: [PersonaFixtures.entry(
                PersonaFixtures.rows,
                sets: [PersonaFixtures.set(30, band: "Red band")]
            )])
        }
        let bandTrigger = makeRecord(id: 10, daysAgo: 0, entries: [PersonaFixtures.entry(
            PersonaFixtures.rows,
            sets: [PersonaFixtures.set(31, band: "Red band")]
        )])
        let bandObservations = achievement(context(records: bandHistory + [bandTrigger], trigger: bandTrigger))
        XCTAssertFalse(bandObservations.contains { $0.key.kind == "pr.weight" || $0.key.kind == "pr.reps" })

        let weightedHistory = (1...3).map { id in
            makeRecord(id: id, daysAgo: id + 2, entries: [rowSet(8, lb: 40)])
        }
        let weightedTrigger = makeRecord(id: 20, daysAgo: 0, entries: [PersonaFixtures.entry(
            PersonaFixtures.rows,
            sets: [PersonaFixtures.set(11, kg: 20), PersonaFixtures.set(8, kg: 22)]
        )])
        let observations = achievement(context(records: weightedHistory + [weightedTrigger], trigger: weightedTrigger))
        XCTAssertTrue(observations.contains { $0.key.kind == "pr.weight" })
        XCTAssertFalse(observations.contains { $0.key.kind == "pr.reps" })
    }

    func testBodyweightRepPRAndRepGainThreshold() throws {
        let prior = [8, 9, 10].enumerated().map { index, reps in
            makeRecord(id: index + 1, daysAgo: index + 2, entries: [rowSet(reps)])
        }
        let trigger = makeRecord(id: 10, daysAgo: 0, entries: [rowSet(13)])
        let result = try XCTUnwrap(achievement(context(records: prior + [trigger], trigger: trigger))
            .first { $0.key.kind == "pr.reps" })

        XCTAssertEqual(result.key, PersonaObservationKey(family: .achievement, kind: "pr.reps", subject: "dumbbell_row", period: "2026-10-24"))
        XCTAssertEqual(result.contentKey, "achievement.pr.reps")
        XCTAssertEqual(result.salience, .high)
        XCTAssertEqual(result.values["count"], "13")
        XCTAssertEqual(result.values["value"], "bodyweight")

        let mediumTrigger = makeRecord(id: 11, daysAgo: 0, entries: [rowSet(12)])
        let medium = try XCTUnwrap(achievement(context(records: prior + [mediumTrigger], trigger: mediumTrigger))
            .first { $0.key.kind == "pr.reps" })
        XCTAssertEqual(medium.salience, .medium)

        let twoPrior = Array(prior.prefix(2)) + [mediumTrigger]
        XCTAssertFalse(achievement(context(records: Array(twoPrior), trigger: mediumTrigger))
            .contains { $0.key.kind == "pr.reps" })
    }

    func testWorkoutMilestoneBoundaryAndSalience() throws {
        let ninePrior = (1...9).map { makeRecord(id: $0, daysAgo: $0 + 1) }
        let tenth = makeRecord(id: 20, daysAgo: 0)
        let medium = try XCTUnwrap(achievement(context(records: ninePrior + [tenth], trigger: tenth))
            .first { $0.key.kind == "milestone" })
        XCTAssertEqual(medium.key.string, "achievement.milestone.workouts.10")
        XCTAssertEqual(medium.contentKey, "achievement.milestone")
        XCTAssertEqual(medium.salience, .medium)

        let eightPrior = Array(ninePrior.prefix(8)) + [tenth]
        XCTAssertFalse(achievement(context(records: eightPrior, trigger: tenth))
            .contains { $0.key.kind == "milestone" })

        let fortyNinePrior = (1...49).map { makeRecord(id: $0, daysAgo: $0) }
        let fiftieth = makeRecord(id: 100, daysAgo: 0)
        let high = try XCTUnwrap(achievement(context(records: fortyNinePrior + [fiftieth], trigger: fiftieth))
            .first { $0.key.kind == "milestone" })
        XCTAssertEqual(high.key.string, "achievement.milestone.workouts.50")
        XCTAssertEqual(high.salience, .high)
    }

    func testWeekdayPatternThresholdAndEstablishedContent() throws {
        let thursdays = [8, 15, 22].map { day in
            makeRecord(id: day, at: PersonaFixtures.date(day: day, month: 10, year: 2026), entries: [])
        }
        let trigger = thursdays.last!
        let result = try XCTUnwrap(pattern(context(records: thursdays, trigger: trigger))
            .first { $0.key.kind == "weekday" })
        XCTAssertEqual(result.key.string, "pattern.weekday.5.2026-W43")
        XCTAssertEqual(result.contentKey, "pattern.weekday")
        XCTAssertEqual(result.salience, .low)
        XCTAssertEqual(result.values["weekday"], "Thursday")
        XCTAssertEqual(result.values["count"], "3")

        let twoWeeks = Array(thursdays.dropFirst())
        let shorterTrigger = twoWeeks.last!
        XCTAssertFalse(pattern(context(records: twoWeeks, trigger: shorterTrigger))
            .contains { $0.key.kind == "weekday" })

        let fiveThursdays = [24, 1, 8, 15, 22].enumerated().map { index, day in
            let month = day == 24 ? 9 : 10
            return makeRecord(id: 40 + index, at: PersonaFixtures.date(day: day, month: month, year: 2026), entries: [])
        }
        let fiveWeekResult = try XCTUnwrap(pattern(context(records: fiveThursdays, trigger: fiveThursdays.last!))
            .first { $0.key.kind == "weekday" })
        XCTAssertEqual(fiveWeekResult.contentKey, "pattern.weekday.established")
        XCTAssertEqual(fiveWeekResult.salience, .medium)
        XCTAssertEqual(fiveWeekResult.evidence.strength, 4)
    }

    func testUpcomingWeekdayGoalGradientThreshold() throws {
        let priorDates = [8, 15, 22].map { PersonaFixtures.date(day: $0, month: 10, year: 2026) }
        let prior = priorDates.enumerated().map { makeRecord(id: $0.offset + 1, at: $0.element, entries: []) }
        let slot = PersonaFixtures.date(day: 29, month: 10, year: 2026, hour: 11)
        let result = try XCTUnwrap(pattern(context(records: prior, now: slot))
            .filter { $0.key.kind == "weekday.upcoming" }
            .first)
        XCTAssertEqual(result.key.string, "pattern.weekday.upcoming.5.2026-W44")
        XCTAssertEqual(result.contentKey, "pattern.weekday.upcoming")
        XCTAssertEqual(result.salience, .low)
        XCTAssertEqual(result.values["count"], "4")

        let twoPrior = Array(prior.dropFirst())
        XCTAssertFalse(pattern(context(records: twoPrior, now: slot))
            .contains { $0.key.kind == "weekday.upcoming" })
    }

    func testRoutineRepeatThresholdAndEstablishedRepeat() throws {
        let routineID = identifier(500)
        let threeRecords = [16, 20, 24].enumerated().map { index, day in
            makeRecord(
                id: index + 1,
                at: PersonaFixtures.date(day: day, month: 10, year: 2026),
                planID: routineID,
                planName: "Upper Day"
            )
        }
        let trigger = threeRecords.last!
        let result = try XCTUnwrap(pattern(context(
            records: threeRecords,
            trigger: trigger,
            routineNames: [routineID: "Upper Day"]
        )).first { $0.key.kind == "routineRepeat" })
        XCTAssertEqual(result.key.string, "pattern.routineRepeat.\(routineID.uuidString).3")
        XCTAssertEqual(result.contentKey, "pattern.routineRepeat")
        XCTAssertEqual(result.salience, .low)
        XCTAssertEqual(result.values["routine"], "Upper Day")
        XCTAssertEqual(result.values["count"], "3")
        XCTAssertFalse(pattern(context(records: Array(threeRecords.dropFirst()), trigger: trigger))
            .contains { $0.key.kind == "routineRepeat" })

        let fiveRecords = [8, 12, 16, 20, 24].enumerated().map { index, day in
            makeRecord(
                id: 20 + index,
                at: PersonaFixtures.date(day: day, month: 10, year: 2026),
                planID: routineID,
                planName: "Upper Day"
            )
        }
        let established = try XCTUnwrap(pattern(context(records: fiveRecords, trigger: fiveRecords.last!))
            .first { $0.key.kind == "routineRepeat" })
        XCTAssertEqual(established.key.period, "5")
        XCTAssertEqual(established.salience, .medium)
    }

    func testTimeOfDayPatternThresholdAndBand() throws {
        let hours = [9, 10, 10, 10, 11]
        let records = hours.enumerated().map { index, hour in
            makeRecord(id: index + 1, daysAgo: 4 - index, hour: hour, entries: [])
        }
        let trigger = records.last!
        let result = try XCTUnwrap(pattern(context(records: records, trigger: trigger))
            .first { $0.key.kind == "timeOfDay" })
        XCTAssertEqual(result.key.string, "pattern.timeOfDay.9.2026-W43")
        XCTAssertEqual(result.contentKey, "pattern.timeOfDay")
        XCTAssertEqual(result.salience, .low)
        XCTAssertEqual(result.values["time"], "10 AM")

        XCTAssertFalse(pattern(context(records: Array(records.dropFirst()), trigger: trigger))
            .contains { $0.key.kind == "timeOfDay" })
        let outsideBand = [9, 10, 10, 10, 12].enumerated().map { index, hour in
            makeRecord(id: 30 + index, daysAgo: 4 - index, hour: hour, entries: [])
        }
        XCTAssertFalse(pattern(context(records: outsideBand, trigger: outsideBand.last!))
            .contains { $0.key.kind == "timeOfDay" })
    }

    func testSkippedExerciseThresholdEscalationAndNegativeBounds() throws {
        let three = skippedRecords(count: 3)
        let result = try XCTUnwrap(lapse(context(records: three, trigger: three.last!))
            .first { $0.key.kind == "skippedExercise" })
        XCTAssertEqual(result.key.string, "lapse.skippedExercise.dumbbell_row.3")
        XCTAssertEqual(result.contentKey, "lapse.skippedExercise")
        XCTAssertEqual(result.salience, .medium)
        XCTAssertEqual(result.values["count"], "3")
        XCTAssertTrue(result.isNegative)
        XCTAssertGreaterThanOrEqual(result.evidence.strength, PersonaPolicy.standard.negativeMinimumStrength)

        let two = skippedRecords(count: 2)
        XCTAssertFalse(lapse(context(records: two, trigger: two.last!))
            .contains { $0.key.kind == "skippedExercise" })

        let six = skippedRecords(count: 6)
        let escalated = try XCTUnwrap(lapse(context(records: six, trigger: six.last!))
            .first { $0.key.kind == "skippedExercise" })
        XCTAssertEqual(escalated.key.period, "6")
        XCTAssertEqual(escalated.contentKey, "lapse.skippedExercise.escalated")
        XCTAssertEqual(escalated.evidence.strength, 5)
    }

    func testNeglectedRoutineThresholdIgnoresDeletedRoutines() throws {
        let routineID = identifier(600)
        let routineRecords = [21, 28, 35].enumerated().map { index, daysAgo in
            makeRecord(id: index + 1, daysAgo: daysAgo, planID: routineID, planName: "Core Day")
        }
        let otherRecords = [7, 14, 20].enumerated().map { index, daysAgo in
            makeRecord(id: index + 10, daysAgo: daysAgo)
        }
        let records = routineRecords + otherRecords
        let result = try XCTUnwrap(lapse(context(
            records: records,
            routineNames: [routineID: "Core Day"]
        ), projected: true).first { $0.key.kind == "neglectedRoutine" })
        XCTAssertEqual(result.key.string, "lapse.neglectedRoutine.\(routineID.uuidString).2026-W43")
        XCTAssertEqual(result.contentKey, "lapse.neglectedRoutine")
        XCTAssertEqual(result.salience, .medium)
        XCTAssertEqual(result.values["routine"], "Core Day")
        XCTAssertEqual(result.values["weeks"], "3")
        XCTAssertEqual(result.suggestion, .routine(id: routineID, name: "Core Day"))

        let belowOtherThreshold = routineRecords + Array(otherRecords.dropFirst())
        XCTAssertFalse(lapse(context(
            records: belowOtherThreshold,
            routineNames: [routineID: "Core Day"]
        ), projected: true).contains { $0.key.kind == "neglectedRoutine" })
        let belowRunThreshold = Array(routineRecords.dropFirst()) + otherRecords
        XCTAssertFalse(lapse(context(
            records: belowRunThreshold,
            routineNames: [routineID: "Core Day"]
        ), projected: true).contains { $0.key.kind == "neglectedRoutine" })

        let recentRoutineRecords = [20, 27, 34].enumerated().map { index, daysAgo in
            makeRecord(id: index + 50, daysAgo: daysAgo, planID: routineID, planName: "Core Day")
        }
        let laterOtherRecords = [5, 10, 15].enumerated().map { index, daysAgo in
            makeRecord(id: index + 60, daysAgo: daysAgo)
        }
        XCTAssertFalse(lapse(context(
            records: recentRoutineRecords + laterOtherRecords,
            routineNames: [routineID: "Core Day"]
        ), projected: true).contains { $0.key.kind == "neglectedRoutine" })
        XCTAssertFalse(lapse(context(records: records), projected: true)
            .contains { $0.key.kind == "neglectedRoutine" })
    }

    func testDecliningWeeksRequiresStrictlyDecreasingCountsAndSuggestsShortestRoutine() throws {
        let records = decliningRecords(counts: [3, 2, 1])
        let routineA = identifier(701)
        let routineB = identifier(702)
        let result = try XCTUnwrap(lapse(context(
            records: records,
            routineNames: [routineA: "Long Day", routineB: "Quick Day"],
            routineMinutes: [routineA: 20, routineB: 8]
        ), projected: true).first { $0.key.kind == "decliningWeeks" })
        XCTAssertEqual(result.key, PersonaObservationKey(family: .lapse, kind: "decliningWeeks", subject: "-", period: "2026-W43"))
        XCTAssertEqual(result.contentKey, "lapse.decliningWeeks")
        XCTAssertEqual(result.salience, .medium)
        XCTAssertEqual(result.values["suggestion"], "Quick Day · about 8 min")
        XCTAssertEqual(result.suggestion, .routine(id: routineB, name: "Quick Day"))

        XCTAssertFalse(lapse(context(records: decliningRecords(counts: [3, 2, 2])), projected: true)
            .contains { $0.key.kind == "decliningWeeks" })
        XCTAssertFalse(lapse(context(records: decliningRecords(counts: [2, 1, 0])), projected: true)
            .contains { $0.key.kind == "decliningWeeks" })
    }

    func testComebackThresholdAndHighSalience() throws {
        let previous = makeRecord(id: 1, daysAgo: 14)
        let trigger = makeRecord(id: 2, daysAgo: 0)
        let result = try XCTUnwrap(lapse(context(records: [previous, trigger], trigger: trigger))
            .first { $0.key.kind == "comeback" })
        XCTAssertEqual(result.key.string, "lapse.comeback.-.2026-10-24")
        XCTAssertEqual(result.contentKey, "lapse.comeback")
        XCTAssertEqual(result.salience, .medium)
        XCTAssertEqual(result.values["days"], "14")

        let shorterPrevious = makeRecord(id: 3, daysAgo: 13)
        let shorterTrigger = makeRecord(id: 4, daysAgo: 0)
        XCTAssertFalse(lapse(context(records: [shorterPrevious, shorterTrigger], trigger: shorterTrigger))
            .contains { $0.key.kind == "comeback" })

        let longHistory = (0..<10).map { index in
            makeRecord(id: 100 + index, daysAgo: 28 + index * 7)
        }
        let highTrigger = makeRecord(id: 200, daysAgo: 0)
        let high = try XCTUnwrap(lapse(context(records: longHistory + [highTrigger], trigger: highTrigger))
            .first { $0.key.kind == "comeback" })
        XCTAssertEqual(high.salience, .high)
        XCTAssertEqual(high.values["days"], "28")
    }

    func testPostureReturnedThresholdFreshnessAndSalience() throws {
        let newest = now
        let previous = assessment(date: date(daysAgo: 21))
        let current = assessment(date: newest)
        let result = try XCTUnwrap(posture(context(
            records: [], assessments: [previous, current], now: newest
        )).first { $0.key.kind == "returned" })
        XCTAssertEqual(result.key.string, "posture.returned.-.2026-10-24")
        XCTAssertEqual(result.contentKey, "posture.returned")
        XCTAssertEqual(result.salience, .low)
        XCTAssertEqual(result.values["days"], "21")

        XCTAssertFalse(posture(context(
            records: [], assessments: [assessment(date: date(daysAgo: 20)), current], now: newest
        )).contains { $0.key.kind == "returned" })

        let medium = try XCTUnwrap(posture(context(
            records: [], assessments: [assessment(date: date(daysAgo: 45)), current], now: newest
        )).first { $0.key.kind == "returned" })
        XCTAssertEqual(medium.salience, .medium)

        let staleCurrent = assessment(date: newest.addingTimeInterval(-37 * 60 * 60))
        let stalePrevious = assessment(date: staleCurrent.date.addingTimeInterval(-30 * 24 * 60 * 60))
        XCTAssertFalse(posture(context(
            records: [], assessments: [stalePrevious, staleCurrent], now: newest
        )).contains { $0.key.kind == "returned" })

        let exactlyFresh = assessment(date: newest.addingTimeInterval(-36 * 60 * 60))
        let exactlyFreshPrevious = assessment(date: calendar.date(byAdding: .day, value: -21, to: exactlyFresh.date) ?? exactlyFresh.date)
        XCTAssertTrue(posture(context(
            records: [], assessments: [exactlyFreshPrevious, exactlyFresh], now: newest
        )).contains { $0.key.kind == "returned" })
    }

    func testPostureImprovementNeedsTwoFollowUpsAndThreshold() throws {
        let baseline = assessment(date: date(daysAgo: 30), value: 4, isBaseline: true)
        let earlierFollowUp = assessment(date: date(daysAgo: 7), value: 2)
        let newestFollowUp = assessment(date: date(daysAgo: 1), value: 2)
        let result = try XCTUnwrap(posture(context(
            records: [],
            assessments: [baseline, earlierFollowUp, newestFollowUp],
            now: now
        )).first { $0.key.kind == "improved" })
        XCTAssertEqual(result.key.string, "posture.improved.front.shoulder_line_angle.2026-10-23")
        XCTAssertEqual(result.contentKey, "posture.improved")
        XCTAssertEqual(result.salience, .medium)
        XCTAssertEqual(result.values["measurement"], "shoulder line angle")

        XCTAssertFalse(posture(context(
            records: [],
            assessments: [baseline, newestFollowUp],
            now: now
        )).contains { $0.key.kind == "improved" })
        let belowThresholdFollowUp = assessment(date: date(daysAgo: 2), value: 2.1)
        XCTAssertFalse(posture(context(
            records: [],
            assessments: [baseline, earlierFollowUp, belowThresholdFollowUp],
            now: now
        )).contains { $0.key.kind == "improved" })

        let exactlyFreshFollowUp = assessment(date: date(daysAgo: 7), value: 2)
        let earlierFreshFollowUp = assessment(date: date(daysAgo: 14), value: 2)
        XCTAssertTrue(posture(context(
            records: [],
            assessments: [baseline, earlierFreshFollowUp, exactlyFreshFollowUp],
            now: now
        )).contains { $0.key.kind == "improved" })
    }

    func testFreshnessModeBoundariesAndResetScope() {
        let staleTrigger = makeRecord(id: 1, daysAgo: 2, entries: [rowSet(10, kg: 20)])
        let staleHistory = (2...4).map { id in
            makeRecord(id: id, daysAgo: id + 3, entries: [rowSet(8, kg: 10)])
        }
        let staleContext = context(records: staleHistory + [staleTrigger], trigger: staleTrigger, now: now)
        XCTAssertTrue(achievement(staleContext, asOf: now).isEmpty)
        XCTAssertTrue(pattern(staleContext, asOf: now).isEmpty)
        XCTAssertTrue(lapse(staleContext, asOf: now).isEmpty)

        let freshSkips = skippedRecords(count: 3)
        let freshTrigger = freshSkips.last!
        let exactlyFresh = freshTrigger.endedAt.addingTimeInterval(Double(PersonaPolicy.standard.achievementFreshnessHours) * 60 * 60)
        XCTAssertTrue(lapse(context(records: freshSkips, trigger: freshTrigger), asOf: exactlyFresh)
            .contains { $0.key.kind == "skippedExercise" })
        XCTAssertFalse(lapse(
            context(records: freshSkips, trigger: freshTrigger),
            asOf: exactlyFresh.addingTimeInterval(1)
        ).contains { $0.key.kind == "skippedExercise" })

        let priorDates = [1, 8, 15].map { PersonaFixtures.date(day: $0, month: 10, year: 2026) }
        let prior = priorDates.enumerated().map { index, date in
            makeRecord(id: index + 10, at: date, entries: [rowSet(8, lb: 40)])
        }
        let trigger = makeRecord(
            id: 20,
            at: PersonaFixtures.date(day: 22, month: 10, year: 2026),
            entries: [rowSet(8, kg: 20)]
        )
        let reset = trigger.endedAt
        let resetContext = context(records: prior + [trigger], trigger: trigger, resetDate: reset)
        XCTAssertEqual(resetContext.relationshipRecords.map(\.id), [trigger.id])
        XCTAssertTrue(pattern(resetContext, asOf: trigger.endedAt).isEmpty)
        XCTAssertTrue(achievement(resetContext, asOf: trigger.endedAt).contains { $0.key.kind == "pr.weight" })
    }

    func testProjectedAndImmediateModesSeparateKindsAndNegativeEvidenceIsBounded() {
        let skipHistory = skippedRecords(count: 3)
        let routineID = identifier(900)
        let routineHistory = [50, 55, 60].enumerated().map { index, daysAgo in
            makeRecord(id: index + 20, daysAgo: daysAgo, planID: routineID, planName: "Core")
        }
        let otherHistory = [21, 28, 35].enumerated().map { index, daysAgo in
            makeRecord(id: index + 30, daysAgo: daysAgo)
        }
        let declines = decliningRecords(counts: [3, 2, 1])
        let history = skipHistory + routineHistory + otherHistory + declines
        let trigger = skipHistory.last!
        let context = context(
            records: history,
            trigger: trigger,
            routineNames: [routineID: "Core"],
            routineMinutes: [routineID: 8]
        )
        let projected = achievement(context, projected: true)
            + pattern(context, projected: true)
            + lapse(context, projected: true)
        XCTAssertFalse(projected.contains { ["pr.weight", "pr.reps", "milestone", "routineRepeat", "timeOfDay", "skippedExercise", "comeback"].contains($0.key.kind) })

        let immediate = pattern(context) + lapse(context)
        XCTAssertFalse(immediate.contains { ["weekday.upcoming", "neglectedRoutine", "decliningWeeks"].contains($0.key.kind) })

        let negatives = lapse(context, projected: true).filter(\.isNegative)
        XCTAssertFalse(negatives.isEmpty)
        XCTAssertTrue(negatives.allSatisfy {
            $0.evidence.strength >= PersonaPolicy.standard.negativeMinimumStrength && $0.salience <= .medium
        })
    }

    private func achievement(
        _ context: PersonaContext,
        asOf: Date? = nil,
        projected: Bool = false
    ) -> [PersonaObservation] {
        AchievementDetector.observations(context, asOf: asOf ?? context.now, projected: projected, policy: .standard)
    }

    private func pattern(
        _ context: PersonaContext,
        asOf: Date? = nil,
        projected: Bool? = nil
    ) -> [PersonaObservation] {
        PatternDetector.observations(
            context,
            asOf: asOf ?? context.now,
            projected: projected ?? (context.trigger.savedRecord == nil),
            policy: .standard
        )
    }

    private func lapse(
        _ context: PersonaContext,
        asOf: Date? = nil,
        projected: Bool? = nil
    ) -> [PersonaObservation] {
        LapseDetector.observations(
            context,
            asOf: asOf ?? context.now,
            projected: projected ?? (context.trigger.savedRecord == nil),
            policy: .standard
        )
    }

    private func posture(_ context: PersonaContext, asOf: Date? = nil) -> [PersonaObservation] {
        PostureDetector.observations(context, asOf: asOf ?? context.now, projected: false, policy: .standard)
    }

    private func context(
        records: [WorkoutRecord],
        assessments: [PostureAssessment] = [],
        trigger: WorkoutRecord? = nil,
        resetDate: Date? = nil,
        routineNames: [UUID: String] = [:],
        routineMinutes: [UUID: Int] = [:],
        now: Date? = nil
    ) -> PersonaContext {
        PersonaContextBuilder.build(
            history: PersonaHistory(
                records: records,
                assessments: assessments,
                routineNames: routineNames,
                routineMinutes: routineMinutes,
                exerciseNames: [:]
            ),
            settings: PersonaFixtures.reminderSettings,
            extraPersonableEnabled: true,
            personaResetDate: resetDate,
            traceState: .empty,
            trigger: trigger.map(PersonaTrigger.workoutSaved) ?? .reconcile,
            acknowledgmentWillFire: false,
            appIsActive: false,
            now: now ?? trigger?.endedAt ?? self.now,
            calendar: calendar
        )
    }

    private func makeRecord(
        id: Int,
        daysAgo: Int,
        hour: Int = 12,
        entries: [WorkoutRecordEntry]? = nil,
        planID: UUID? = nil,
        planName: String? = nil
    ) -> WorkoutRecord {
        makeRecord(
            id: id,
            at: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
            hour: hour,
            entries: entries,
            planID: planID,
            planName: planName
        )
    }

    private func makeRecord(
        id: Int,
        at date: Date,
        hour: Int? = nil,
        entries: [WorkoutRecordEntry]? = nil,
        planID: UUID? = nil,
        planName: String? = nil
    ) -> WorkoutRecord {
        let endingAt: Date
        if let hour {
            endingAt = calendar.date(
                bySettingHour: hour,
                minute: 0,
                second: 0,
                of: calendar.startOfDay(for: date)
            ) ?? date
        } else {
            endingAt = date
        }
        return PersonaFixtures.record(
            id: identifier(id),
            endingAt: endingAt,
            planID: planID,
            planName: planName,
            entries: entries
        )
    }

    private func rowSet(_ reps: Int, lb: Double? = nil, kg: Double? = nil) -> WorkoutRecordEntry {
        PersonaFixtures.entry(PersonaFixtures.rows, sets: [PersonaFixtures.set(reps, lb: lb, kg: kg)])
    }

    private func skippedRecords(count: Int) -> [WorkoutRecord] {
        (0..<count).map { index in
            makeRecord(
                id: 100 + index,
                daysAgo: count - 1 - index,
                entries: [PersonaFixtures.skipped(PersonaFixtures.rows)]
            )
        }
    }

    private func decliningRecords(counts: [Int]) -> [WorkoutRecord] {
        let weekDays = [[20, 21, 22, 23, 24, 25, 26], [13, 14, 15, 16, 17, 18, 19], [6, 7, 8, 9, 10, 11, 12]]
        return counts.enumerated().flatMap { week, count in
            (0..<count).map { index in
                makeRecord(id: 300 + week * 10 + index, daysAgo: weekDays[week][index])
            }
        }
    }

    private func assessment(date: Date, value: Double = 4, isBaseline: Bool = false) -> PostureAssessment {
        let fixture = PersonaFixtures.assessment(date: date, isBaseline: isBaseline, measurements: [(.shoulderLineAngle, value)])
        let measurement = PostureMeasurement(
            id: .shoulderLineAngle,
            name: "Shoulder Line Angle",
            value: value,
            unit: "°",
            landmarksUsed: [],
            confidence: 0.95,
            explanation: "Geometric observation."
        )
        return PostureAssessment(
            date: date,
            imageRelativePath: "fixture.jpg",
            view: fixture.view,
            pose: fixture.pose,
            measurements: [measurement],
            isBaseline: isBaseline
        )
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    }

    private func identifier(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }
}
