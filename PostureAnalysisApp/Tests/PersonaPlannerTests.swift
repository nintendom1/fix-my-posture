import XCTest
@testable import PostureAnalysisApp

final class PersonaPlannerTests: XCTestCase {
    private var now: Date { PersonaFixtures.date(day: 16, hour: 9) }

    func testInactiveContextReturnsEmptyPlan() {
        let context = makeContext(trigger: .workoutSaved(record()), extraPersonableEnabled: false)
        let plan = makePlan(context: context, immediate: [observation(.achievement, "milestone", salience: .high)])
        XCTAssertEqual(plan, PersonaPlan.empty)
    }

    func testAcknowledgmentFoldsReplaceAndAppendWithoutUsingTheCap() {
        let fullCapState = PersonaTraceState(sent: [
            trace(observation(.pattern, "weekday", subject: "1", salience: .high), fireDate: now.addingTimeInterval(-3_600), delivery: .active),
            trace(observation(.pattern, "weekday", subject: "2", salience: .high), fireDate: now.addingTimeInterval(-7_200), delivery: .passive),
        ])
        let cases: [(PersonaSalience, PersonaDelivery, Bool)] = [
            (.high, .foldedReplace, true),
            (.medium, .foldedReplace, true),
            (.low, .foldedAppend, false),
        ]

        for (salience, expectedDelivery, replaces) in cases {
            let candidate = observation(.posture, "returned", salience: salience)
            let context = makeContext(
                trigger: .workoutSaved(record()),
                traceState: fullCapState,
                acknowledgmentWillFire: true
            )
            let plan = makePlan(context: context, immediate: [candidate])
            XCTAssertTrue(plan.scheduled.isEmpty)
            XCTAssertEqual(plan.traces.first?.delivery, expectedDelivery)
            switch plan.immediate {
            case .fold(.replace(let content)) where replaces:
                XCTAssertEqual(content.scenarioID, candidate.contentKey)
            case .fold(.append(let line)) where !replaces:
                XCTAssertTrue(line.contains(candidate.contentKey))
            default:
                XCTFail("Unexpected fold result for \(salience).")
            }
        }
    }

    func testImmediateHighAndMediumUseStandaloneRequestsAndLowStaysInApp() {
        let high = observation(.achievement, "milestone", subject: "high", salience: .high)
        let highPlan = makePlan(context: savedContext(), immediate: [high])
        guard case .standalone(let highRequest)? = highPlan.immediate else {
            return XCTFail("Expected immediate HIGH standalone request.")
        }
        XCTAssertEqual(highRequest.interruption, .active)
        XCTAssertEqual(highRequest.trigger, .after(seconds: 1))
        XCTAssertTrue(highRequest.identifier.hasPrefix(PersonaNotificationRequest.immediatePrefix))

        let medium = observation(.posture, "improved", subject: "medium", salience: .medium)
        let mediumPlan = makePlan(context: savedContext(), immediate: [medium])
        guard case .standalone(let mediumRequest)? = mediumPlan.immediate else {
            return XCTFail("Expected immediate MEDIUM standalone request.")
        }
        XCTAssertEqual(mediumRequest.interruption, .passive)

        let low = observation(.posture, "improved", subject: "low", salience: .low)
        let lowPlan = makePlan(context: savedContext(), immediate: [low])
        XCTAssertEqual(lowPlan.immediate, .inAppOnly)
        XCTAssertEqual(lowPlan.traces.first?.suppressionReason, .lowSalience)
        XCTAssertEqual(lowPlan.traces.first?.delivery, .inAppOnly)
    }

    func testDailyCapBlocksThirdStandaloneAndCountsPendingImmediateButNotProjected() {
        let candidate = observation(.posture, "returned", subject: "candidate", salience: .high)
        let firedState = PersonaTraceState(sent: [
            trace(observation(.pattern, "weekday", subject: "old1", salience: .high), fireDate: now.addingTimeInterval(-3_600), delivery: .active),
            trace(observation(.pattern, "weekday", subject: "old2", salience: .high), fireDate: now.addingTimeInterval(-7_200), delivery: .passive),
        ])
        let firedPlan = makePlan(context: savedContext(traceState: firedState), immediate: [candidate])
        XCTAssertNil(firedPlan.immediate)
        XCTAssertEqual(firedPlan.traces.first?.suppressionReason, .dailyCapReached)
        XCTAssertTrue(firedPlan.traces.first?.whyThisWon.contains("2/2") == true)

        let pendingProjected = PersonaTraceState(sent: [
            trace(observation(.pattern, "weekday", subject: "pending1", salience: .high), fireDate: now.addingTimeInterval(600), delivery: .active, identifier: PersonaNotificationRequest.projectedPrefix + "one"),
            trace(observation(.pattern, "weekday", subject: "pending2", salience: .high), fireDate: now.addingTimeInterval(900), delivery: .active, identifier: PersonaNotificationRequest.projectedPrefix + "two"),
        ])
        let projectedDoesNotCount = makePlan(context: savedContext(traceState: pendingProjected), immediate: [candidate])
        XCTAssertNotNil(projectedDoesNotCount.immediate)

        let pendingImmediate = PersonaTraceState(sent: [
            trace(observation(.pattern, "weekday", subject: "immediate1", salience: .high), fireDate: now.addingTimeInterval(600), delivery: .active, identifier: PersonaNotificationRequest.immediatePrefix + "one"),
            trace(observation(.pattern, "weekday", subject: "immediate2", salience: .high), fireDate: now.addingTimeInterval(900), delivery: .passive, identifier: PersonaNotificationRequest.immediatePrefix + "two"),
        ])
        let immediateCounts = makePlan(context: savedContext(traceState: pendingImmediate), immediate: [candidate])
        XCTAssertEqual(immediateCounts.traces.first?.suppressionReason, .dailyCapReached)
    }

    func testProjectedSlotsCoverTodayThroughSevenDaysAtElevenThirty() {
        let policy = PersonaPolicy.standard
        let context = makeContext()
        let plan = makePlan(context: context, policy: policy, projected: { [self] date in
            [observation(.pattern, "weekday", subject: dayString(date), period: dayString(date), salience: .high)]
        })

        XCTAssertEqual(plan.scheduled.count, 8)
        XCTAssertTrue(plan.scheduled.allSatisfy { $0.identifier.hasPrefix(PersonaNotificationRequest.projectedPrefix) })
        XCTAssertEqual(Set(plan.scheduled.compactMap { requestDay($0, calendar: context.calendar) }).count, 8)
        for request in plan.scheduled {
            guard case .at(let components) = request.trigger else {
                return XCTFail("Projected request must use local calendar components.")
            }
            XCTAssertEqual(components.hour, 11)
            XCTAssertEqual(components.minute, 30)
        }
    }

    func testProjectedSlotMovesPastReminderAndSkipsQuietHours() {
        var policy = PersonaPolicy.standard
        policy.projectionHorizonDays = 0
        let reminder = PersonaFixtures.date(day: 16, hour: 11, minute: 30)
        let movedContext = makeContext(reminderSlotTimes: [reminder])
        let movedPlan = makePlan(context: movedContext, policy: policy, projected: { [self] date in
            [observation(.pattern, "weekday", subject: dayString(date), salience: .high)]
        })
        guard case .at(let movedComponents)? = movedPlan.scheduled.first?.trigger else {
            return XCTFail("Expected a dated projected request.")
        }
        XCTAssertEqual(movedComponents.hour, 13)
        XCTAssertEqual(movedComponents.minute, 0)

        let quietPlan = makePlan(
            context: makeContext(),
            quietHours: FixedQuietHours(startHour: 10, endHour: 12),
            policy: policy,
            projected: { [self] date in
                [observation(.pattern, "weekday", subject: dayString(date), salience: .high)]
            }
        )
        XCTAssertTrue(quietPlan.scheduled.isEmpty)
        XCTAssertTrue(quietPlan.traces.isEmpty)
    }

    func testTodayFallbackMovesAfterElevenThirtyWhenSlotHasPassed() {
        var policy = PersonaPolicy.standard
        policy.projectionHorizonDays = 0
        let lateContext = makeContext(now: PersonaFixtures.date(day: 16, hour: 12))
        let plan = makePlan(context: lateContext, policy: policy, projected: { [self] date in
            [observation(.pattern, "weekday", subject: dayString(date), salience: .high)]
        })
        guard case .at(let components)? = plan.scheduled.first?.trigger else {
            return XCTFail("Expected a projected request for today's fallback slot.")
        }
        XCTAssertEqual(components.hour, 13)
        XCTAssertEqual(components.minute, 0)
    }

    func testQuietHoursDeferInactiveImmediateAndAllowActiveAppDelivery() {
        let late = PersonaFixtures.date(day: 16, hour: 23)
        var policy = PersonaPolicy.standard
        policy.projectionHorizonDays = 0
        let candidate = observation(.achievement, "milestone", salience: .high)
        let deferred = makePlan(
            context: savedContext(now: late, appIsActive: false),
            policy: policy,
            immediate: [candidate]
        )
        guard case .standalone(let request)? = deferred.immediate,
              case .at(let components) = request.trigger else {
            return XCTFail("Expected quiet-hours deferral to the next morning.")
        }
        XCTAssertEqual(components.day, 17)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(deferred.traces.first?.quietDeferred, true)

        let active = makePlan(
            context: savedContext(now: late, appIsActive: true),
            policy: policy,
            immediate: [candidate]
        )
        guard case .standalone(let activeRequest)? = active.immediate else {
            return XCTFail("Expected an immediate request while the app is active.")
        }
        XCTAssertEqual(activeRequest.trigger, .after(seconds: 1))
        XCTAssertEqual(active.traces.first?.quietDeferred, false)
    }

    func testRecentlySentAndSimilarDowngradeSuppressions() {
        let same = observation(.posture, "returned", subject: "same", salience: .high)
        let recentlySentState = PersonaTraceState(sent: [
            trace(same, fireDate: now.addingTimeInterval(-60), delivery: .active, identifier: PersonaNotificationRequest.immediatePrefix + "same")
        ])
        let recentlySent = makePlan(context: savedContext(traceState: recentlySentState), immediate: [same])
        XCTAssertEqual(recentlySent.traces.first?.suppressionReason, .recentlySent)

        let medium = observation(.pattern, "weekday", subject: "today", salience: .medium)
        let similarState = PersonaTraceState(sent: [
            trace(observation(.pattern, "weekday", subject: "old1", salience: .high), fireDate: now.addingTimeInterval(-86_400), delivery: .foldedReplace),
            trace(observation(.pattern, "weekday", subject: "old2", salience: .high), fireDate: now.addingTimeInterval(-2 * 86_400), delivery: .foldedReplace),
        ])
        let similar = makePlan(context: savedContext(traceState: similarState), immediate: [medium])
        XCTAssertEqual(similar.traces.first?.salience, .low)
        XCTAssertEqual(similar.traces.first?.suppressionReason, .similarDowngrade)
        XCTAssertEqual(similar.traces.first?.recentSimilarCount, 2)

        let alreadyLow = observation(.pattern, "weekday", subject: "already-low", salience: .low)
        let lowPlan = makePlan(context: savedContext(traceState: similarState), immediate: [alreadyLow])
        XCTAssertEqual(lowPlan.traces.first?.suppressionReason, .lowSalience)
    }

    func testStrongCoolingDropsPatternAndKeepsHighPersonalRecord() {
        let patternTraces = (0..<3).map { index in
            trace(
                observation(.pattern, "weekday", subject: "old\(index)", salience: .high),
                // Standalone messages on earlier days: only they can be dismissed, and they leave today's cap free.
                fireDate: now.addingTimeInterval(TimeInterval(-index - 1) * 86_400),
                delivery: .passive
            )
        }
        let events = patternTraces.map { event(for: $0, kind: .dismissed) }
        let state = PersonaTraceState(sent: patternTraces, engagement: events)
        let pattern = observation(.pattern, "routineRepeat", salience: .high)
        let dropped = makePlan(context: savedContext(traceState: state), immediate: [pattern])
        XCTAssertEqual(dropped.traces.first?.cooling, .strong)
        XCTAssertEqual(dropped.traces.first?.suppressionReason, .cooling)

        let pr = observation(.achievement, "pr.weight", subject: "new-pr", salience: .high)
        let kept = makePlan(context: savedContext(traceState: state), immediate: [pr])
        XCTAssertEqual(kept.traces.first?.cooling, .strong)
        XCTAssertEqual(kept.traces.first?.salience, .high)
        XCTAssertEqual(kept.traces.first?.delivery, .active)
    }

    func testNegativeObservationIsCappedAtMedium() {
        let lapse = observation(.lapse, "skippedExercise", salience: .high, strength: 5)
        let plan = makePlan(context: savedContext(familiarity: .established), immediate: [lapse])
        XCTAssertEqual(plan.traces.first?.salience, .medium)
        XCTAssertEqual(plan.traces.first?.delivery, .passive)
    }

    func testCandidateOrderingAndLowerPriorityTrace() {
        let posture = observation(.posture, "improved", salience: .high, strength: 5)
        let pattern = observation(.pattern, "weekday", salience: .high, strength: 5)
        let achievement = observation(.achievement, "milestone", salience: .high, strength: 1)
        let plan = makePlan(context: savedContext(), immediate: [posture, pattern, achievement])

        XCTAssertEqual(plan.traces.first?.observation.family, .achievement)
        XCTAssertEqual(plan.traces.first?.observation.evidence.strength, 1)
        XCTAssertEqual(plan.traces.filter { $0.suppressionReason == .lowerPriorityThanSelected }.count, 2)
        XCTAssertTrue(plan.traces.dropFirst().allSatisfy { $0.whyThisWon.contains("achievement.milestone") })
    }

    func testIntroAndToneRotateAcrossWinnersWithinOnePlan() {
        var policy = PersonaPolicy.standard
        policy.projectionHorizonDays = 1
        let first = observation(.achievement, "pr.weight", subject: "first", salience: .high)
        let second = observation(.achievement, "pr.weight", subject: "second", salience: .high)
        var introValues: [Bool] = []
        let composer: PersonaPlanner.Compose = { catalog, key, tone, familiarity, values, variant, intro in
            introValues.append(intro)
            return self.fakeComposition(key: key, tone: tone, intro: intro)
        }
        let context = savedContext(familiarity: .new)
        let plan = makePlan(
            context: context,
            policy: policy,
            immediate: [first],
            projected: { [self] date in
                self.dayString(date) == self.dayString(self.now) ? [second] : []
            },
            compose: composer
        )

        XCTAssertEqual(introValues, [true, false])
        XCTAssertEqual(plan.traces.filter { $0.outcome.isSent }.compactMap(\.tone), [.proud, .pleased])
        XCTAssertEqual(plan.scheduled.count, 1)

        let previouslyIntroduced = PersonaTraceState(sent: [
            trace(observation(.posture, "improved", subject: "old", salience: .high), fireDate: now.addingTimeInterval(-60), delivery: .foldedReplace)
        ])
        let noIntroContext = savedContext(traceState: previouslyIntroduced)
        var noIntroValue = true
        let noIntroComposer: PersonaPlanner.Compose = { catalog, key, tone, familiarity, values, variant, intro in
            noIntroValue = intro
            return self.fakeComposition(key: key, tone: tone, intro: intro)
        }
        _ = makePlan(context: noIntroContext, immediate: [first], compose: noIntroComposer)
        XCTAssertFalse(noIntroValue)
    }

    func testSuggestionAddsRoutineTargetPayload() {
        let routineID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let candidate = observation(
            .lapse, "comeback", salience: .high,
            suggestion: .routine(id: routineID, name: "Quick Upper")
        )
        let plan = makePlan(context: savedContext(), immediate: [candidate])
        guard case .standalone(let request)? = plan.immediate else {
            return XCTFail("Expected a standalone suggestion notification.")
        }
        XCTAssertEqual(request.userInfo["workoutReminder.targetType"], "routine")
        XCTAssertEqual(request.userInfo["workoutReminder.targetID"], routineID.uuidString)
        XCTAssertEqual(request.userInfo[PersonaNotificationRequest.UserInfoKey.observationKey], candidate.key.string)
        XCTAssertEqual(request.categoryIdentifier, NotificationCategory.persona)
    }

    func testSuppressedTracesAreRecordedOnlyForImmediateAndTodaysProjection() {
        var policy = PersonaPolicy.standard
        policy.projectionHorizonDays = 2
        let context = makeContext()
        let immediate = observation(.posture, "improved", subject: "immediate", salience: .low)
        let plan = makePlan(context: savedContext(), policy: policy, immediate: [immediate], projected: { [self] date in
            [observation(.pattern, "weekday", subject: dayString(date), salience: .low)]
        })
        XCTAssertEqual(plan.traces.count, 2)
        XCTAssertTrue(plan.traces.allSatisfy { $0.suppressionReason == .lowSalience && $0.delivery == .inAppOnly })
    }

    private func makePlan(
        context: PersonaContext,
        quietHours: any QuietHoursProviding = FixedQuietHours(startHour: 22, endHour: 8),
        policy: PersonaPolicy = PersonaPolicy.standard,
        immediate: [PersonaObservation] = [],
        projected: @escaping (Date) -> [PersonaObservation] = { _ in [] },
        compose: PersonaPlanner.Compose? = nil
    ) -> PersonaPlan {
        let detect: PersonaPlanner.Detect = { _, asOf, isProjected in
            isProjected ? projected(asOf) : immediate
        }
        let composer = compose ?? { [self] _, key, tone, _, _, _, intro in
            self.fakeComposition(key: key, tone: tone, intro: intro)
        }
        return PersonaPlanner.plan(
            context: context,
            quietHours: quietHours,
            catalog: PersonaFixtures.catalog(),
            policy: policy,
            detect: detect,
            compose: composer
        )
    }

    private func makeContext(
        now: Date? = nil,
        trigger: PersonaTrigger = .reconcile,
        appIsActive: Bool = false,
        extraPersonableEnabled: Bool = true,
        familiarity: PersonaFamiliarity = .new,
        trajectory: PersonaTrajectory = .stable,
        reminderSlotTimes: [Date] = [],
        traceState: PersonaTraceState = .empty,
        acknowledgmentWillFire: Bool = false
    ) -> PersonaContext {
        let contextNow = now ?? self.now
        let settings = PersonaFixtures.reminderSettings
        return PersonaContext(
            now: contextNow,
            calendar: PersonaFixtures.calendar,
            trigger: trigger,
            appIsActive: appIsActive,
            settings: settings,
            extraPersonableEnabled: extraPersonableEnabled,
            personaResetDate: nil,
            familiarity: familiarity,
            trajectory: trajectory,
            streak: PlannedDaysStreak.summarize(
                records: [], settings: settings, asOf: contextNow, calendar: PersonaFixtures.calendar
            ),
            records: [],
            relationshipRecords: [],
            assessments: [],
            routineNames: [:],
            routineMinutes: [:],
            exerciseNames: [:],
            reminderSlotTimes: reminderSlotTimes,
            traceState: traceState,
            acknowledgmentWillFire: acknowledgmentWillFire
        )
    }

    private func savedContext(
        now: Date? = nil,
        appIsActive: Bool = false,
        familiarity: PersonaFamiliarity = .new,
        traceState: PersonaTraceState = .empty,
        acknowledgmentWillFire: Bool = false
    ) -> PersonaContext {
        let contextNow = now ?? self.now
        return makeContext(
            now: contextNow,
            trigger: .workoutSaved(record(endingAt: contextNow)),
            appIsActive: appIsActive,
            familiarity: familiarity,
            traceState: traceState,
            acknowledgmentWillFire: acknowledgmentWillFire
        )
    }

    private func observation(
        _ family: ObservationFamily,
        _ kind: String,
        subject: String = "fixture",
        period: String = "2026-10-16",
        salience: PersonaSalience,
        strength: Int = 3,
        suggestion: PersonaSuggestion? = nil
    ) -> PersonaObservation {
        PersonaFixtures.observation(
            family, kind, subject: subject, period: period, salience: salience,
            strength: strength, suggestion: suggestion
        )
    }

    private func trace(
        _ observation: PersonaObservation,
        fireDate: Date,
        delivery: PersonaDelivery,
        identifier: String? = nil,
        tone: PersonaTone = .warm
    ) -> PersonaDecisionTrace {
        PersonaDecisionTrace(
            id: UUID(),
            decisionID: UUID(),
            decidedAt: fireDate,
            observation: observation,
            salience: observation.salience,
            delivery: delivery,
            tone: tone,
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
            outcome: .sent(fireDate: fireDate, identifier: identifier)
        )
    }

    private func event(for trace: PersonaDecisionTrace, kind: PersonaEngagementEvent.Kind) -> PersonaEngagementEvent {
        PersonaEngagementEvent(
            traceID: trace.id,
            observationKey: trace.observation.key.string,
            kind: kind,
            date: now.addingTimeInterval(-60)
        )
    }

    private func record(endingAt date: Date? = nil) -> WorkoutRecord {
        PersonaFixtures.record(endingAt: date ?? now)
    }

    private func dayString(_ date: Date) -> String {
        let parts = PersonaFixtures.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func requestDay(_ request: PersonaNotificationRequest, calendar: Calendar) -> Date? {
        guard case .at(let components) = request.trigger else { return nil }
        return calendar.date(from: components)
    }

    private func fakeComposition(key: String, tone: PersonaTone, intro: Bool) -> PersonaComposition {
        PersonaComposition(
            content: CharacterNotificationContent(
                scenarioID: key,
                kind: .persona,
                title: "T \(key) \(tone.rawValue)",
                body: "B \(key)\(intro ? " intro" : "")",
                imageAssetName: "NotificationCharacter/smile-hoodie-portrait",
                artLabel: "smile · hoodie · portrait"
            ),
            templateID: "\(key)#t0b0"
        )
    }
}

private extension PersonaDecisionTrace.Outcome {
    var isSent: Bool {
        if case .sent = self { return true }
        return false
    }
}
