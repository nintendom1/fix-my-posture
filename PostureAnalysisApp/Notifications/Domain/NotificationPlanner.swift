import Foundation

/// A notification request before it is handed to the local notification delivery adapter.
struct PlannedNotification: Equatable {
    let identifier: String
    let fireDate: DateComponents
    let slot: NotificationSlot
    let scenarioID: String
    let content: CharacterNotificationContent
}

/// Projects reminder decisions over a bounded range of planned calendar days.
enum NotificationPlanner {
    /// Plans local character notifications from saved records and current reminder settings.
    static func plan(
        records: [WorkoutRecord], settings: WorkoutReminderSettings, now: Date, calendar: Calendar,
        suggestion: String?, isFirstEverNotification: Bool, catalog: NotificationScenarioCatalog,
        policy: NotificationPolicy = .standard
    ) -> [PlannedNotification] {
        guard settings.enabled else { return [] }
        let today = calendar.startOfDay(for: now)
        var plannedDaysConsidered = 0
        var firstReminderSeen = false
        var result: [PlannedNotification] = []
        var day = today
        while plannedDaysConsidered < policy.planningHorizonPlannedDays,
              result.count < policy.maximumRequests {
            if PlannedDays.isPlanned(day, settings: settings, calendar: calendar) {
                plannedDaysConsidered += 1
                let summary = PlannedDaysStreak.summarize(
                    records: records, settings: settings, asOf: day, calendar: calendar
                )
                if summary.daysSinceLastWorkout.map({ $0 >= policy.stopAfterDaysWithoutWorkout }) == true {
                    break
                }
                if !isCompletedToday(day, today: today, records: records, now: now, calendar: calendar) {
                    appendNotifications(
                        for: day, records: records, settings: settings, now: now,
                        calendar: calendar, suggestion: suggestion,
                        firstEver: isFirstEverNotification, firstReminderSeen: &firstReminderSeen,
                        catalog: catalog, policy: policy, to: &result
                    )
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.sorted { fireDate($0, calendar: calendar) < fireDate($1, calendar: calendar) }
    }

    /// Adds eligible slot requests for one planned day.
    private static func appendNotifications(
        for day: Date, records: [WorkoutRecord], settings: WorkoutReminderSettings,
        now: Date, calendar: Calendar, suggestion: String?, firstEver: Bool,
        firstReminderSeen: inout Bool, catalog: NotificationScenarioCatalog,
        policy: NotificationPolicy, to result: inout [PlannedNotification]
    ) {
        let summary = PlannedDaysStreak.summarize(
            records: records, settings: settings, asOf: day, calendar: calendar
        )
        let slots = NotificationSlotSchedule.slots(
            day: day, settings: settings, calendar: calendar, policy: policy
        )
        let hasRecentHistory = summary.daysSinceLastWorkout.map { $0 <= policy.recentHistoryDays } ?? false
        var eligibleSlots = hasRecentHistory ? slots : Array(slots.prefix(1))
        if summary.consecutiveMissedPlannedDays >= policy.taperAfterMissedPlannedDays {
            eligibleSlots = Array(eligibleSlots.prefix(1))
        }
        for scheduledSlot in eligibleSlots where scheduledSlot.time > now {
            let isFirstReminder = scheduledSlot.slot == .reminder && !firstReminderSeen
            if scheduledSlot.slot == .reminder { firstReminderSeen = true }
            let facts = NotificationScenarioSelector.nudgeFacts(
                day: day, slot: scheduledSlot.slot, slotTime: scheduledSlot.time,
                records: records, settings: settings,
                isFirstEverNotification: firstEver && isFirstReminder,
                calendar: calendar, policy: policy
            )
            guard let planned = makeNotification(
                day: day, slot: scheduledSlot.slot, slotTime: scheduledSlot.time,
                facts: facts, suggestion: suggestion, catalog: catalog,
                calendar: calendar, policy: policy
            ) else { continue }
            result.append(planned)
            if result.count >= policy.maximumRequests { return }
        }
    }

    /// Builds rendered content and stable identifiers for a selected slot.
    private static func makeNotification(
        day: Date, slot: NotificationSlot, slotTime: Date, facts: NudgeFacts,
        suggestion: String?, catalog: NotificationScenarioCatalog, calendar: Calendar,
        policy: NotificationPolicy
    ) -> PlannedNotification? {
        let selection = NotificationScenarioSelector.select(nudge: facts, policy: policy)
        guard let scenario = catalog.scenario(id: selection.scenarioID) else { return nil }
        var values = selection.values
        if let suggestion { values[.suggestion] = suggestion }
        let variant = NotificationCopyPicker.variant(
            scenarioID: scenario.id, dayNumber: facts.dayNumber, slotIndex: slot.rawValue
        )
        guard let content = NotificationContentBuilder.make(
            scenario: scenario, variant: variant, values: values
        ) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let identifier = WorkoutReminderScheduleBuilder.identifierPrefix
            + "character.\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0).\(slot.rawValue)"
        return PlannedNotification(
            identifier: identifier, fireDate: fireComponents(day: day, time: slotTime, calendar: calendar),
            slot: slot, scenarioID: scenario.id, content: content
        )
    }

    /// Makes local date components without a time zone for wall-clock delivery.
    private static func fireComponents(day: Date, time: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = calendar.component(.hour, from: time)
        components.minute = calendar.component(.minute, from: time)
        components.timeZone = nil
        return components
    }

    /// Checks completion using all records on the calendar day, independent of projection's as-of time.
    private static func isCompletedToday(
        _ day: Date, today: Date, records: [WorkoutRecord], now: Date, calendar: Calendar
    ) -> Bool {
        calendar.isDate(day, inSameDayAs: today)
            && records.contains { $0.endedAt <= now && calendar.isDate($0.endedAt, inSameDayAs: day) }
    }

    /// Reconstructs a request's local fire time for sorting.
    private static func fireDate(_ notification: PlannedNotification, calendar: Calendar) -> Date {
        calendar.date(from: notification.fireDate) ?? .distantPast
    }
}
