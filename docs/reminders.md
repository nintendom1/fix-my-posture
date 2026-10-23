# Workout reminders

Workout reminders are one optional on-device schedule configured from Settings → Workout reminders. The app stores the enabled state, recurrence, local hour and minute, Every Other Day start date, and selected Weekly weekdays in the existing preferences store. Notification permission is requested only when the user turns reminders on. Authorized and provisional permission schedules normally; denied permission leaves the setting enabled, clears pending requests, and offers an iOS Settings link.

## Scheduling and recommendations

Daily uses one repeating calendar trigger. Weekly uses one repeating calendar trigger per selected weekday. Every Other Day uses dated, non-repeating calendar triggers at the selected local time, every two calendar days from the start date. The app keeps a rolling batch of 16 upcoming occurrences and replaces requests with the `fixMyPosture.workoutReminder.` identifier prefix during reconciliation. It does not use elapsed 24 or 48 hour intervals. Trigger components carry no time zone, so reminders follow the device's local wall clock after travel or a daylight-saving change. Switching the recurrence to Every Other Day resets its start date to today; the user can then pick another date.

The Train screen and reminders share `CurrentUpNextRoutine.select`, which filters out saved routines without a valid workout plan and delegates ordering and the one-time override to `RoutineRotation.upNext`. If no startable routine remains, `WorkoutReminderRecommendationSelector` checks exercises in catalog order. It first chooses an exercise with no completed-set history, then chooses the exercise with the oldest most-recent performed entry. Entries saved as skipped do not count; exercises performed within a saved routine do count. Equal history dates keep catalog order.

Notification copy uses the routine duration estimate or the exercise's saved target where available. Each notification carries `workoutReminder.targetType` and `workoutReminder.targetID`, identifying the exact advertised routine UUID or stable exercise ID.

## Taps and reconciliation

`WorkoutReminderAppDelegate` installs the notification-center delegate in `application(_:didFinishLaunchingWithOptions:)`. A small `WorkoutReminderNotificationBridge` buffers the decoded target until `AppEnvironment` installs its handler. The coordinator validates and routes a still-valid advertised target through `AppRouter`; stale targets fall back to the current routine recommendation, then the exercise recommendation, then the Routines tab or the Library. An active workout route ignores the tap so the current session remains intact.

`WorkoutReminderCoordinator` runs reconciliations one at a time, so overlapping triggers can't interleave the remove and add steps. Reminder requests are reconciled from these existing callbacks:

- Settings changes: `SettingsViewModel.workoutReminderSettings.didSet` and `WorkoutReminderCoordinator.enable()`.
- App launch and activation: `AppShellView` `.task` and `onChange(of: scenePhase)`.
- Up Next override changes: `TrainHomeViewModel.send(_:)`, `.selectRoutine`.
- Routine create, edit, duplicate, and delete: successful mutation paths in `RoutineEditorViewModel.send(_:)`, `RoutinesViewModel.send(_:)`, and `RoutineDetailViewModel.send(_:)`.
- Workout history save: `WorkoutCoachView.saveHistory()` after `WorkoutHistorySaver.save` succeeds.

The app does not request background refresh solely to replenish the Every Other Day batch. The next app launch or activation restores its 16-occurrence horizon. If permission is denied or there is no startable routine or exercise, no reminder is scheduled; the saved preference remains enabled so a later reconciliation can resume scheduling. A notification tap during an active workout is ignored.

## Character notification scenarios and the developer preview

Every state the notification character can be in, with its art, title and copy, is described by `Design/NotificationCharacter/notification-scenarios.json`. `make notification-character` generates the 27 portrait images in `Assets.xcassets/NotificationCharacter`, the `NotificationScenarios` data set the app loads, and `docs/notification-scenarios.md`; see the character README for how to change them. `NotificationScenarioCatalog` decodes the data set, `NotificationTemplate` fills the `{streak}`, `{record}`, `{remaining}`, `{days}`, and `{suggestion}` placeholders, and `NotificationContentBuilder` picks the art and copy line for a variant. These types are Foundation-only and have no scheduling logic yet; the reminders above still use their fixed copy.

iOS hides a local notification's banner while the app is open unless the notification-center delegate implements `willPresent`. `WorkoutReminderAppDelegate` does, and it opts in only for the `fixMyPosture.character.acknowledgment` category, so a message sent after a workout is saved can appear over the summary. Reminders (`fixMyPosture.character.nudge`) stay hidden while the app is open and appear once the user leaves it.

Settings → Developer diagnostics → Notification preview sends any scenario to this iPhone. It lists every scenario with its image, shows the exact title, body, and art, and steps through copy variants. The delay stepper runs from 1 to 20 seconds (iOS needs at least one), defaults to 5, and is saved in the preferences store. Send builds the notification with the same content builder, category, and image attachment as a real one, asks for notification permission if it has not been requested, and schedules a time-interval trigger. Lock the phone or press Home during the countdown to see the real banner. Preview requests use the `fixMyPosture.devPreview.` identifier prefix, so reminder reconciliation never removes them, and they carry no workout target, so tapping one only opens the app. The page is available in every build.
