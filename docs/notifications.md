# Character notification planner

The planner turns the workout reminder schedule and saved workout history into local character notifications. The decision engine is pure Foundation code; callers supply the current time, calendar, settings, records, and bundled scenario catalog.

## Vocabulary

- A **planned day** is a calendar day selected by the reminder recurrence: every day, selected weekdays, or every other calendar day from its anchor.
- A **workout day** contains at least one saved workout, using `endedAt` and the supplied calendar.
- A **streak** counts consecutive planned workout days through the latest completed planned day. A planned day today with no workout is pending and is excluded. Workouts on unplanned days do not change a streak. `priorRunLength` records the run before the missed stretch that preceded the current run; when there is no current run, it equals `brokenRunLength`.
- A **run** is a maximal sequence of planned workout days. The longest run is the record; previous record means the longest run other than the current run.
- A **missed planned day** is a planned day that was not completed, excluding a pending today.

## Nudge slots

| Slot | Time | Rules |
|---|---|---|
| Reminder | User's selected local time T | Always the first slot, when future. |
| Follow-up | T + 3 hours, capped at 21:00 | Requires recent history and at least 30 minutes after T. |
| Final warning | 21:30 | Requires recent history and at least 30 minutes after the previous slot. |

Recent history means the last workout was within 14 calendar days. `NotificationSlotSchedule.slots(day:settings:calendar:policy:)` is the shared source for reminder, follow-up, and final-warning dates; follow-up is computed from T + 3 elapsed hours and capped at local 21:00. It is used by the planner, nudge context, and acknowledgment context. Slot indexes are 0, 1, and 2; earlier same-day slots are treated as ignored. Late night begins at 21:00. Only the first future reminder slot in a plan can use `first-ever-notification`.

## Reminder selection

First matching rule wins.

| Order | Condition | Scenario id |
|---:|---|---|
| 1 | Never scheduled before | `first-ever-notification` |
| 2 | One missed day after a run of 5+ | `streak-broken` |
| 3 | Two missed days after a run of 5+ | `immediate-post-break` |
| 4 | Last workout 7+ days ago | `long-absence` |
| 5 | No workout history | `never-established-history` |
| 6 | Late night with recent history | `late-night-streak-at-risk` or `late-night-reminder` |
| 7 | Meaningful streak within 1–3 sessions of a 7+ record | `approaching-personal-best` |
| 8 | Streak is 6 | `almost-one-week` |
| 9 | Meaningful streak | `established-streak-reminder` |
| 10 | Streak is 2–4 | `early-streak-forming` |
| 11 | Streak <= 1 and 3 of 4 recent planned days completed | `neutral-check-in` |
| 12 | Reminder before 10:00 | `morning-reminder` |
| 13 | Saturday or Sunday | `weekend-reminder` |
| 14 | Otherwise | `ordinary-daily-reminder` |

## Follow-up selection

| Order | Condition | Scenario id |
|---:|---|---|
| 1 | Late night | `late-night-streak-at-risk` or `late-night-reminder` |
| 2 | High-value streak | `high-value-streak-at-risk` |
| 3 | Meaningful streak | `established-streak-at-risk` |
| 4 | Otherwise | `first-ignored-reminder` |

## Final-warning selection

| Order | Condition | Scenario id |
|---:|---|---|
| 1 | Meaningful streak 30+ and day number divisible by 5 | `rare-escalation` |
| 2 | Meaningful streak and habitual late completion | `strong-repeated-dismissal` |
| 3 | Meaningful streak | `final-streak-warning` |
| 4 | Otherwise | `repeated-ignored-reminder` |

## Acknowledgments

Only the first workout of a calendar day receives an acknowledgment. `NotificationScenarioSelector.acknowledgment(for:records:settings:calendar:policy:)` returns nil unless reminders are enabled and the record is the first workout that day. It builds the summary with the saved record included and `asOf` set to its `endedAt`, computes slot, gap, streak, week, and notification-free facts, then applies the rules below. Weeks use Monday as their first day.

| Order | Condition | Scenario id |
|---:|---|---|
| 1 | First workout day ever | `first-completed-session` |
| 2 | Beats a prior record of at least 7 | `new-personal-best-streak` |
| 3 | Major milestone (14, 30, 50, 100, then each 100) | `major-streak-milestone` |
| 4 | Seven-day streak | `one-week-milestone` |
| 5 | Returns after 7+ calendar days | `comeback-after-long-absence` |
| 6 | Restarts a 5+ run / second day after restart | `restart-after-broken-streak` / `second-day-after-restart` (using `priorRunLength` for the run before the break) |
| 7 | Planned day saved at/after 21:00 preserving meaningful streak | `streak-preserved-last-minute` |
| 8 | Completes every planned session in a week with 3+ planned days | `perfect-week` |
| 9 | Recovers by completing today and the previous planned day | `weekly-recovery` |
| 10 | At least one slot fired earlier that day | `session-completed-after-reminders` |
| 11 | Early completion, and 2 of previous 3 completions were also early | `notification-free-success` |
| 12 | Otherwise | `session-completed` |

## Projection and taper

The planner visits calendar days from today forward until it has considered 14 planned days or has made 60 requests. Each day is summarized using the same saved records and an `asOf` at that day's start, so future planned days project as misses. If today's planned session is already complete, no notification is scheduled today. After three consecutive missed planned days only the reminder slot remains. Once the last workout is 14 calendar days behind, planning stops for that day and every later day. Fire dates use local wall-clock components and are sorted chronologically.

All thresholds and limits live in `NotificationPolicy`. The scenario copy and art source is documented in [notification-scenarios.md](notification-scenarios.md).
