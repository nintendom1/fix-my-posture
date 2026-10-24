import Foundation

/// The single pure decision function for Extra Personable. Given a context it returns what to do now and
/// which persona notifications to schedule for the coming days, plus a trace for every candidate considered.
enum PersonaPlanner {
    typealias Detect = (_ context: PersonaContext, _ asOf: Date, _ projected: Bool) -> [PersonaObservation]
    typealias Compose = (_ catalog: PersonaContentCatalog, _ contentKey: String, _ tone: PersonaTone,
                         _ familiarity: PersonaFamiliarity, _ values: [String: String], _ variant: Int,
                         _ intro: Bool) -> PersonaComposition?

    /// Uses the registered detectors and the shared copy composer unless a caller supplies a detector.
    static func plan(
        context: PersonaContext,
        quietHours: any QuietHoursProviding,
        catalog: PersonaContentCatalog,
        policy: PersonaPolicy = .standard,
        detect: Detect? = nil
    ) -> PersonaPlan {
        let detector = detect ?? { context, asOf, projected in
            PersonaDetectors.observations(context, asOf: asOf, projected: projected, policy: policy)
        }
        return plan(
            context: context,
            quietHours: quietHours,
            catalog: catalog,
            policy: policy,
            detect: detector,
            compose: PersonaCopyComposer.compose
        )
    }

    /// Composition seam for deterministic planner tests and alternate internal composition behavior.
    static func plan(
        context: PersonaContext,
        quietHours: any QuietHoursProviding,
        catalog: PersonaContentCatalog,
        policy: PersonaPolicy = .standard,
        detect: Detect,
        compose: @escaping Compose = PersonaCopyComposer.compose
    ) -> PersonaPlan {
        guard context.isActive else { return .empty }

        let now = context.now
        let calendar = context.calendar
        let fired = context.traceState.fired(asOf: now)
        let committed = context.traceState.committed(asOf: now)
        var state = PlanningState(
            usedKeys: Set(committed.map { $0.observation.key.string }),
            standaloneByDay: standaloneCounts(committed: committed, calendar: calendar),
            recentTones: context.traceState.recentTones(asOf: now, limit: policy.recentToneLimit),
            introAvailable: context.isIntro,
            dailyCap: policy.dailyStandaloneCap,
            cooling: PersonaCooling.level(
                engagement: context.traceState.engagement,
                sent: fired,
                now: now,
                policy: policy
            )
        )
        let decisionID = UUID()

        if context.trigger.savedRecord != nil {
            evaluate(
                detect(context, now, false),
                slot: now,
                isImmediate: true,
                recordSuppressed: true,
                decisionID: decisionID,
                context: context,
                quietHours: quietHours,
                catalog: catalog,
                policy: policy,
                fired: fired,
                compose: compose,
                state: &state
            )
        }

        let today = calendar.startOfDay(for: now)
        for offset in 0...max(0, policy.projectionHorizonDays) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let slot = projectedSlot(
                    on: day,
                    offset: offset,
                    now: now,
                    reminderSlots: context.reminderSlotTimes,
                    calendar: calendar,
                    policy: policy
                  ) else { continue }

            if quietHours.quietInterval(containing: slot, calendar: calendar) != nil { continue }

            let dayKey = calendar.startOfDay(for: day)
            if state.standaloneByDay[dayKey, default: 0] >= policy.dailyStandaloneCap { continue }
            guard policy.projectedPerDay > 0 else { continue }

            evaluate(
                detect(context, slot, true),
                slot: slot,
                isImmediate: false,
                recordSuppressed: offset == 0,
                decisionID: decisionID,
                context: context,
                quietHours: quietHours,
                catalog: catalog,
                policy: policy,
                fired: fired,
                compose: compose,
                state: &state
            )
        }

        let scheduled = state.scheduled.sorted { lhs, rhs in
            let leftDate = fireDate(for: lhs.trigger, calendar: calendar, relativeTo: now)
            let rightDate = fireDate(for: rhs.trigger, calendar: calendar, relativeTo: now)
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.identifier < rhs.identifier
        }
        return PersonaPlan(immediate: state.immediate, scheduled: scheduled, traces: state.traces)
    }

    private struct PlanningState {
        var traces: [PersonaDecisionTrace] = []
        var scheduled: [PersonaNotificationRequest] = []
        var immediate: PersonaImmediate?
        var usedKeys: Set<String>
        var standaloneByDay: [Date: Int]
        var recentTones: [PersonaTone]
        var introAvailable: Bool
        let dailyCap: Int
        let cooling: PersonaCoolingLevel
    }

    private static func standaloneCounts(
        committed: [PersonaDecisionTrace],
        calendar: Calendar
    ) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for trace in committed where trace.delivery.isStandalone {
            guard let fireDate = trace.fireDate else { continue }
            result[calendar.startOfDay(for: fireDate), default: 0] += 1
        }
        return result
    }

    private static func projectedSlot(
        on day: Date,
        offset: Int,
        now: Date,
        reminderSlots: [Date],
        calendar: Calendar,
        policy: PersonaPolicy
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = policy.projectedHour
        components.minute = policy.projectedMinute
        guard var slot = calendar.date(from: components) else { return nil }

        if offset == 0 && slot <= now {
            slot = now.addingTimeInterval(TimeInterval(policy.todayFallbackDelayMinutes) * 60)
            guard calendar.isDate(slot, inSameDayAs: day) else { return nil }
        }

        let minimumDistance = TimeInterval(policy.minimumMinutesFromReminderSlot) * 60
        let orderedReminders = reminderSlots.sorted()
        for _ in 0..<2 {
            guard let collision = orderedReminders.first(where: {
                calendar.isDate($0, inSameDayAs: day) && abs($0.timeIntervalSince(slot)) < minimumDistance
            }) else { break }
            slot = collision.addingTimeInterval(minimumDistance)
        }
        return calendar.isDate(slot, inSameDayAs: day) ? slot : nil
    }

    private static func evaluate(
        _ candidates: [PersonaObservation],
        slot: Date,
        isImmediate: Bool,
        recordSuppressed: Bool,
        decisionID: UUID,
        context: PersonaContext,
        quietHours: any QuietHoursProviding,
        catalog: PersonaContentCatalog,
        policy: PersonaPolicy,
        fired: [PersonaDecisionTrace],
        compose: Compose,
        state: inout PlanningState
    ) {
        let calendar = context.calendar
        let slotDay = calendar.startOfDay(for: slot)
        let standaloneCountToday = state.standaloneByDay[slotDay, default: 0]
        let sorted = candidates.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element
            if left.salience != right.salience { return left.salience > right.salience }
            if left.family.priority != right.family.priority { return left.family.priority > right.family.priority }
            if left.evidence.strength != right.evidence.strength { return left.evidence.strength > right.evidence.strength }
            if left.key.string != right.key.string { return left.key.string < right.key.string }
            return lhs.offset < rhs.offset
        }.map { $0.element }

        for (index, candidate) in sorted.enumerated() {
            var salience = candidate.isNegative ? min(candidate.salience, .medium) : candidate.salience
            let similarCount = recentSimilarCount(for: candidate, fired: fired, now: context.now, calendar: calendar, policy: policy)
            if candidate.isNegative && candidate.evidence.strength < policy.negativeMinimumStrength {
                appendSuppressed(
                    candidate, salience: salience, reason: .lowSalience, delivery: .none,
                    tone: nil, recentSimilarCount: similarCount, standaloneCountToday: standaloneCountToday,
                    quietDeferred: false, decisionID: decisionID, context: context,
                    recordSuppressed: recordSuppressed, state: &state
                )
                continue
            }

            if state.usedKeys.contains(candidate.key.string) {
                appendSuppressed(
                    candidate, salience: salience, reason: .recentlySent, delivery: .none,
                    tone: nil, recentSimilarCount: similarCount, standaloneCountToday: standaloneCountToday,
                    quietDeferred: false, decisionID: decisionID, context: context,
                    recordSuppressed: recordSuppressed, state: &state
                )
                continue
            }

            let similarLowered = similarCount >= policy.similarDowngradeCount
            let wasLoweredBySimilarRule = similarLowered && salience > .low
            if similarLowered { salience = salience.lowered }

            guard let adjusted = PersonaCooling.adjusted(salience, for: candidate, level: state.cooling) else {
                appendSuppressed(
                    candidate, salience: salience, reason: .cooling, delivery: .none,
                    tone: nil, recentSimilarCount: similarCount, standaloneCountToday: standaloneCountToday,
                    quietDeferred: false, decisionID: decisionID, context: context,
                    recordSuppressed: recordSuppressed, state: &state
                )
                continue
            }
            salience = adjusted

            let delivery: PersonaDelivery
            if isImmediate && context.acknowledgmentWillFire {
                delivery = salience == .low ? .foldedAppend : .foldedReplace
            } else {
                switch salience {
                case .high: delivery = .active
                case .medium: delivery = .passive
                case .low:
                    let reason: PersonaSuppressionReason = wasLoweredBySimilarRule ? .similarDowngrade : .lowSalience
                    appendSuppressed(
                        candidate, salience: salience, reason: reason, delivery: .inAppOnly,
                        tone: nil, recentSimilarCount: similarCount, standaloneCountToday: standaloneCountToday,
                        quietDeferred: false, decisionID: decisionID, context: context,
                        recordSuppressed: recordSuppressed, state: &state
                    )
                    if isImmediate { state.immediate = .inAppOnly }
                    continue
                }
            }

            let fireDateAndTrigger = plannedFire(
                delivery: delivery,
                slot: slot,
                isImmediate: isImmediate,
                context: context,
                quietHours: quietHours,
                policy: policy
            )
            let fireDate = fireDateAndTrigger.fireDate
            let quietDeferred = fireDateAndTrigger.quietDeferred
            if delivery.isStandalone {
                let fireDay = calendar.startOfDay(for: fireDate)
                let alreadyPlanned = state.standaloneByDay[fireDay, default: 0]
                if alreadyPlanned >= policy.dailyStandaloneCap {
                    appendSuppressed(
                        candidate, salience: salience, reason: .dailyCapReached, delivery: delivery,
                        tone: nil, recentSimilarCount: similarCount, standaloneCountToday: standaloneCountToday,
                        quietDeferred: quietDeferred, decisionID: decisionID, context: context,
                        recordSuppressed: recordSuppressed, state: &state,
                        why: suppressionExplanation(.dailyCapReached, count: alreadyPlanned, cap: policy.dailyStandaloneCap)
                    )
                    continue
                }
            }

            let tone = PersonaToneSelector.tone(
                for: candidate,
                familiarity: context.familiarity,
                trajectory: context.trajectory,
                recentTones: state.recentTones,
                policy: policy
            )
            let variant = NotificationCopyPicker.variant(
                scenarioID: candidate.key.string,
                dayNumber: NotificationCopyPicker.dayNumber(for: fireDate, calendar: calendar),
                slotIndex: 0
            )
            guard let composition = compose(
                catalog, candidate.contentKey, tone, context.familiarity,
                candidate.values, variant, state.introAvailable
            ) else {
                appendSuppressed(
                    candidate, salience: salience, reason: .noContent, delivery: delivery,
                    tone: tone, recentSimilarCount: similarCount, standaloneCountToday: standaloneCountToday,
                    quietDeferred: quietDeferred, decisionID: decisionID, context: context,
                    recordSuppressed: recordSuppressed, state: &state
                )
                continue
            }

            let winnerTraceID = UUID()
            var identifier: String?
            switch delivery {
            case .foldedReplace:
                state.immediate = .fold(.replace(composition.content))
            case .foldedAppend:
                state.immediate = .fold(.append(line: composition.content.body))
            case .active, .passive:
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: fireDate)
                let projected = !isImmediate
                let requestID = PersonaNotificationRequest.identifier(
                    day: dateComponents,
                    observationKey: candidate.key.string,
                    projected: projected
                )
                identifier = requestID
                let request = makeRequest(
                    identifier: requestID,
                    observation: candidate,
                    composition: composition,
                    delivery: delivery,
                    trigger: fireDateAndTrigger.trigger,
                    traceID: winnerTraceID
                )
                if isImmediate {
                    state.immediate = .standalone(request)
                } else {
                    state.scheduled.append(request)
                }
            case .inAppOnly, .none:
                continue
            }

            if case .active = delivery { state.standaloneByDay[calendar.startOfDay(for: fireDate), default: 0] += 1 }
            if case .passive = delivery { state.standaloneByDay[calendar.startOfDay(for: fireDate), default: 0] += 1 }
            state.usedKeys.insert(candidate.key.string)
            state.recentTones.insert(tone, at: 0)
            state.recentTones = Array(state.recentTones.prefix(max(0, policy.recentToneLimit)))
            state.introAvailable = false

            let why = winnerExplanation(
                observation: candidate,
                salience: salience,
                otherCandidateCount: max(0, sorted.count - 1),
                standaloneCountToday: standaloneCountToday,
                cap: policy.dailyStandaloneCap,
                tone: tone,
                familiarity: context.familiarity
            )
            state.traces.append(PersonaDecisionTrace(
                id: winnerTraceID,
                decisionID: decisionID,
                decidedAt: context.now,
                observation: candidate,
                salience: salience,
                delivery: delivery,
                tone: tone,
                familiarity: context.familiarity,
                trajectory: context.trajectory,
                templateID: composition.templateID,
                title: composition.content.title,
                body: composition.content.body,
                standaloneCountToday: standaloneCountToday,
                quietDeferred: quietDeferred,
                cooling: state.cooling,
                recentSimilarCount: similarCount,
                whyThisWon: why,
                outcome: .sent(fireDate: fireDate, identifier: identifier)
            ))

            for lowerCandidate in sorted.dropFirst(index + 1) {
                let lowerSalience = lowerCandidate.isNegative ? min(lowerCandidate.salience, .medium) : lowerCandidate.salience
                let lowerSimilarCount = recentSimilarCount(
                    for: lowerCandidate,
                    fired: fired,
                    now: context.now,
                    calendar: calendar,
                    policy: policy
                )
                appendSuppressed(
                    lowerCandidate,
                    salience: lowerSalience,
                    reason: .lowerPriorityThanSelected,
                    delivery: .none,
                    tone: nil,
                    recentSimilarCount: lowerSimilarCount,
                    standaloneCountToday: standaloneCountToday,
                    quietDeferred: false,
                    decisionID: decisionID,
                    context: context,
                    recordSuppressed: recordSuppressed,
                    state: &state,
                    why: "Lower priority than \(candidate.contentKey)."
                )
            }
            return
        }
    }

    private static func recentSimilarCount(
        for candidate: PersonaObservation,
        fired: [PersonaDecisionTrace],
        now: Date,
        calendar: Calendar,
        policy: PersonaPolicy
    ) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -max(0, policy.similarWindowDays), to: now) ?? now
        return fired.filter { trace in
            guard trace.observation.key.familyKind == candidate.key.familyKind,
                  let fireDate = trace.fireDate else { return false }
            return fireDate >= cutoff && fireDate <= now
        }.count
    }

    private static func plannedFire(
        delivery: PersonaDelivery,
        slot: Date,
        isImmediate: Bool,
        context: PersonaContext,
        quietHours: any QuietHoursProviding,
        policy: PersonaPolicy
    ) -> (fireDate: Date, trigger: PersonaNotificationRequest.Trigger, quietDeferred: Bool) {
        let calendar = context.calendar
        if delivery.isStandalone && isImmediate,
           !context.appIsActive,
           let interval = quietHours.quietInterval(containing: context.now, calendar: calendar) {
            return (interval.end, .at(dateComponents(for: interval.end, calendar: calendar)), true)
        }
        if isImmediate {
            let date = context.now.addingTimeInterval(TimeInterval(policy.immediateDelaySeconds))
            return (date, .after(seconds: policy.immediateDelaySeconds), false)
        }
        return (slot, .at(dateComponents(for: slot, calendar: calendar)), false)
    }

    private static func dateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private static func makeRequest(
        identifier: String,
        observation: PersonaObservation,
        composition: PersonaComposition,
        delivery: PersonaDelivery,
        trigger: PersonaNotificationRequest.Trigger,
        traceID: UUID
    ) -> PersonaNotificationRequest {
        var userInfo = [
            PersonaNotificationRequest.UserInfoKey.traceID: traceID.uuidString,
            PersonaNotificationRequest.UserInfoKey.observationKey: observation.key.string,
        ]
        if let suggestion = observation.suggestion {
            let target: WorkoutReminderTarget
            switch suggestion {
            case .routine(let id, _): target = .routine(id)
            case .exercise(let id, _): target = .exercise(id)
            }
            userInfo.merge(target.payload) { _, new in new }
        }
        return PersonaNotificationRequest(
            identifier: identifier,
            title: composition.content.title,
            body: composition.content.body,
            imageAssetName: composition.content.imageAssetName,
            categoryIdentifier: NotificationCategory.persona,
            interruption: delivery == .active ? .active : .passive,
            trigger: trigger,
            userInfo: userInfo
        )
    }

    private static func appendSuppressed(
        _ observation: PersonaObservation,
        salience: PersonaSalience,
        reason: PersonaSuppressionReason,
        delivery: PersonaDelivery,
        tone: PersonaTone?,
        recentSimilarCount: Int,
        standaloneCountToday: Int,
        quietDeferred: Bool,
        decisionID: UUID,
        context: PersonaContext,
        recordSuppressed: Bool,
        state: inout PlanningState,
        why: String? = nil
    ) {
        guard recordSuppressed else { return }
        state.traces.append(PersonaDecisionTrace(
            id: UUID(),
            decisionID: decisionID,
            decidedAt: context.now,
            observation: observation,
            salience: salience,
            delivery: delivery,
            tone: tone,
            familiarity: context.familiarity,
            trajectory: context.trajectory,
            templateID: nil,
            title: nil,
            body: nil,
            standaloneCountToday: standaloneCountToday,
            quietDeferred: quietDeferred,
            cooling: state.cooling,
            recentSimilarCount: recentSimilarCount,
            whyThisWon: why ?? suppressionExplanation(reason, count: standaloneCountToday, cap: state.dailyCap),
            outcome: .suppressed(reason)
        ))
    }

    private static func suppressionExplanation(
        _ reason: PersonaSuppressionReason,
        count: Int,
        cap: Int
    ) -> String {
        switch reason {
        case .disabled: "Suppressed: Extra Personable is disabled."
        case .recentlySent: "Suppressed: this observation was recently sent."
        case .similarDowngrade: "Suppressed: similar observations lowered salience below the delivery bar."
        case .cooling: "Suppressed: cooling removed this observation."
        case .dailyCapReached: "Suppressed: daily cap reached (\(count)/\(cap))."
        case .quietHours: "Suppressed: the slot falls in quiet hours."
        case .lowSalience: "Suppressed: low salience has no acknowledgment to ride on."
        case .noContent: "Suppressed: no eligible content was available."
        case .lowerPriorityThanSelected: "Suppressed: a higher-priority observation was selected."
        }
    }

    private static func winnerExplanation(
        observation: PersonaObservation,
        salience: PersonaSalience,
        otherCandidateCount: Int,
        standaloneCountToday: Int,
        cap: Int,
        tone: PersonaTone,
        familiarity: PersonaFamiliarity
    ) -> String {
        let candidateWord = otherCandidateCount == 1 ? "candidate" : "candidates"
        return "\(salience.rawValue.uppercased()) \(observation.contentKey) beat \(otherCandidateCount) other \(candidateWord); \(standaloneCountToday)/\(cap) standalone that day; tone \(tone.rawValue) at \(familiarity.rawValue)."
    }

    private static func fireDate(
        for trigger: PersonaNotificationRequest.Trigger,
        calendar: Calendar,
        relativeTo now: Date
    ) -> Date {
        switch trigger {
        case .after(let seconds): now.addingTimeInterval(TimeInterval(seconds))
        case .at(let components): calendar.date(from: components) ?? .distantFuture
        }
    }
}
