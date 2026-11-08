# Behaviour baseline

## Status

This is the current-state inventory for #132 (Refactor: behaviour-preserving foundations, phases 0–3). It records
what the app does today, which tests pin it, and the gates every invisible PR for it must pass. It describes only code
on `main` as of 2026-11-07. Plans for game-style UI, audio, companion, and narrative features (phases 4–6) belong to
#138 (Feature: game-style UI, audio, companion and narrative integration), not here. Update this file in the same PR whenever a baseline fact changes.

## Test environment

`./scripts/validate.sh` is the one validation entry point. It runs, in order:

1. Python helper tests: `python3 -m unittest discover -s scripts/tests -q`.
2. Session replay viewer tests: `node --test tools/session-replay/test/*.test.mjs` (Node 20 or later).
3. Xcode project registration: `python3 scripts/pbxproj.py check`.
4. AdaptiveTraining package tests: `swift test --package-path Packages/AdaptiveTraining --quiet`.
5. Toolchain checks: full Xcode (`xcodebuild -version`) and `simctl`.
6. Simulator choice: `SIMULATOR_DESTINATION` when set (it must start with `platform=iOS Simulator,`). Otherwise the
   available iPhone simulator on the newest iOS 17+ runtime, preferring iPhone 15 Pro within that runtime.
7. `xcodebuild test` of the `PostureAnalysisApp` scheme with `-derivedDataPath build/validation`,
   `-parallel-testing-enabled NO`, and `CODE_SIGNING_ALLOWED=NO`. This runs the whole app test bundle, including the
   design anchor checks in `Tests/Design`. `WorkoutSessionReplayTests.testLocalRecordingsReplayToWhatThePhoneCounted`
   skips unless a recordings folder is named.

CI (`.github/workflows/ci.yml`) runs `./scripts/validate.sh` for pushes to `main` and pull requests against any base branch, on `macos-15` with Xcode 16.4 and no
`SIMULATOR_DESTINATION`. GitHub's runners use UTC, so date-string tests must pin a time zone; reproduce locally with
`TEST_RUNNER_TZ=UTC ./scripts/validate.sh`. CI skips a push or pull request when every changed file is `*.md`,
`*.mdx`, or `*.txt`. A separate Gitleaks workflow scans full history on every push and pull request.

These `make` targets validate things `validate.sh` does not:

- `make design-check`: `design-reference` (renders the local design bundle; skipped when the bundle is absent),
  `design-snapshots` (fixed 390×844 snapshots and anchor checks on `iPhone 15 Pro`), and `design-diff` (local pixel
  diff, a review aid). See [design.md](design.md).
- `make replay-sessions`: replays pulled recordings in `diagnostics/sessions` (or `SESSION_DIR`) and fails when one
  no longer reproduces the phone's reps. Recordings stay local; see [diagnostics.md](diagnostics.md).
- `make notification-character-check`: re-renders the notification art in a pinned venv, checks it against the
  committed assets, and runs the Python helper tests.
- `make adaptive-replay FILE="export.json"`: replays an adaptive training export, optionally under `PARAMS`.

Every commit first passes `gitleaks git . --pre-commit --staged --redact --exit-code=1` on the staged snapshot
([commit-and-pr.md](commit-and-pr.md)). Device builds use `make ios`. `docs/validation.md` describes photo validation
rules, not test running.

## Behaviour inventory

### Navigation and routes

`AppRoute` has 20 cases, each owned by one of four tabs (Train, Routines, Progress, Posture). `AppRouter.open` selects
the owning tab and either pushes onto its `NavigationStack` path or, for `settings`, `workout`, `todaySession`,
`calibration`, and `livePostureCheck`, sets the one full-screen cover. `present` shows a cover without switching tabs.
Reselecting the active tab pops it to its root. `workoutComplete` has only a placeholder destination; the summary
shows inside the workout flow. Today's Session opens from Settings › Developer diagnostics › Adaptive training;
calibration opens from that page and from Settings › Adaptive Training. When the store cannot open at all, the app
shows `PersistenceUnavailableView` instead of the tabs.

**Protected by:** `AppRouteTests`, `AppShellSmokeTests`, `TrainHomeViewModelTests`, `RoutinesViewModelTests`,
`RoutineDetailViewModelTests`, `LibraryViewModelTests`, `ExerciseDetailViewModelTests`, `PostureHomeViewModelTests`,
`SettingsViewModelTests`, `RouteParityTests`, `WorkoutRemindersTests` (reminder-tap routing), and `DesignMetricsTests` (21 frames).
**Gaps:** the route-to-screen mapping in `AppShellView.destination(for:)` and `fullScreenDestination(for:)` is tested
only by rendering the tab roots. No test renders a presented cover or opens the app without a store.

### Workouts

`ExerciseCatalog.all` lists 14 exercises. All are camera-tracked and count reps (`ExerciseTracking.camera`,
`ExerciseDoseUnit.reps`). The session, HUD, and adaptive adapters also support self-reported sets and timed holds;
today only test fixtures use them. `WorkoutSession` phases are `choosingExercise`, `framing`, `ready`, `exercising`,
`paused(reason)`, `resting`, `changingExercise(previous)`, `exerciseComplete`, and `ended`. A `WorkoutPlan` comes from a
Saved Set (user or `BuiltInRoutines`), Today's Session, or a calibration sample (`savesHistory: false`). Adaptive items
end with an effort card; an Easy answer can offer a bonus set; "Too hard?" offers an easier version mid-set.
`WorkoutCoachView.saveHistory()` saves once per presentation on End or Close, then tells reminders.

**Protected by:** `WorkoutSessionTests`, `WorkoutCoachModelTests`, `WorkoutIntentTests`, `WorkoutCameraIntentTests`,
`WorkoutSelfReportedTests`, the 14 `*AnalyzerTests`, `RepRejectionTests`, `WorkoutSessionReplayTests` (each catalog
demonstration recorded and replayed), `SavedExerciseSetTests`, `BuiltInRoutinesTests`, `RoutineEstimatorTests`,
`RoutineRotationTests`, `WorkoutHistoryTests`, `WorkoutCompletionStatsTests`, `WorkoutCompleteViewModelTests`,
`TodaySessionFlowTests`, `BonusRepsTests`, `TooHardOfferTests`, `CalibrationViewModelTests`, `CalibrationScreenTests`,
`ExerciseCatalogTests`, and `WorkoutGoldenTraceTests` (including per-side arm changes, rest, and the next set).
**Gaps:** effect order inside `WorkoutCoachModel.apply` is untested. The view's once-only `saveHistory` guard is
untested; only `WorkoutCoachHistory.save` itself is exercised (by `CalibrationViewModelTests`).

### Camera overlays

During setup and rest the full ghost figure loops at the ideal spot, glides onto the user after about 0.6 s of steady
tracking, and returns after about 1 s without it (`GhostCalibration`, `WorkoutGhostGeometry`). During a set, Start and
Top threshold segments come from the analyzer's own thresholds. The hold ring fills over 1 s
(`WorkoutSession.startHoldProgress`). `CoachingCueScheduler` picks tips and `WorkoutTipLayout` keeps them clear of the
body, motion envelope, and HUD; only corrective cues are spoken. `FramingEvaluator` gates counting on required
joints; `OffscreenJointEstimator` may estimate a focus joint past the edge during a set. A phone lean over 15° for 1 s
warns. The overlay never uses red.

**Protected by:** `ReadyGhostInvariantTests`, `GhostCalibrationTests`, `WorkoutGhostGeometryTests`,
`WorkoutVisualStateTests`, `WorkoutFramePipelineTests`, `WorkoutHUDPresenterTests`, `WorkoutJointOverlayColorTests`,
`CoachingCueSchedulerTests`, `WorkoutTipLayoutTests`, `OffscreenJointEstimatorTests`, `PhoneTiltDetectorTests`,
`EdgeToolbarVisibilityTests`, and the seven camera frames in `DesignMetricsTests`.
**Gaps:** drawing order, animation timing, and pixel content are not gated (anchor boxes only; pixel diff is local).
Vision accuracy and camera capture are device checklist only.

### Speech

`SpeechCoach` speaks `Utterance` values through `AVSpeechSynthesizer` with the best-quality voice for the current
English locale, or en-US. An interrupting utterance clears the queue and stops the current line. At most 2 lines wait;
older ones drop. Instruction lines are kept for "repeat that" ("Nothing to repeat yet." before any). Each line calls
`beginDucking` first; `onActivityChanged(true)` fires before the first line and `false` after the queue drains. A
watchdog stops a line after `max(1, words / 2.5) + 5` seconds, re-armed when playback starts. Utterances come from
`WorkoutSession` `.speak` and `.repeatLastInstruction` effects, plus three direct lines in `WorkoutCoachModel`: guide
Read Aloud (interrupts, plays even when muted), the one-time voice tip, and the recording "Marked." confirmation.
Otherwise a muted coach records each line as muted and speaks nothing. No other screen speaks. Apart from notification sounds (reminders, acknowledgments, previews, and active persona
notifications use the default sound; passive persona notifications are silent while the app is open), the app plays
no other sound or haptic.

**Protected by:** `WorkoutSessionTests` (utterance text per event), `WorkoutCoachModelTests` and `WorkoutIntentTests`
(what the model asks a `FakeSpeechCoach` to say), `WorkoutCoachModelRecordingTests` (recorded `speak` events),
`SpeechActivityTraceTests` (fake coach activity and the model's listening response), and `AudioWorkTimingTests`.
**Gaps:** the real `SpeechCoach` queue (max 2 queued, interrupt, watchdog, repeat) is untested. The real
`SpeechCoach.speakNext` activity callback and ducking order is unpinned until phase 2 provides a synthesizer seam.
The audio-facade PR must add a production trace through that seam before changing this behavior. Voice selection and
speech timing are device checklist only.

### Listening

`WorkoutVoiceController` asks for microphone, then speech-recognition permission, enables recording, and starts
`OnDeviceSpeechRecognizer`. It is half-duplex: `setCoachSpeaking(true)` stops recognition, discarding the partial
transcript, before the session reconfigures for ducking, and `false` restarts it when listening is still wanted. A
transcript goes first to `EffortPhraseParser` while an effort card is open, then to `BonusPhraseParser` while a bonus
offer is open, then to `VoiceCommandParser`. A match that could still grow waits for a final result or its settle time
(0.6 s by default, 1.0 s for the weight sound-alike "wait", `VoiceCommandParser.weightSoundAlikeSettleTime`); 1.2 s of unchanged transcript restarts the task. `WeightPhraseParser` reads spoken weights. Route changes
reconfigure input, a media-services reset rebuilds the recognizer, and a late reactivation restarts listening.

**Protected by:** `VoiceCommandParserTests`, `EffortPhraseParserTests` (including controller routing),
`BonusRepsTests` and `TooHardOfferTests` (controller routing), `WorkoutCoachModelTests` with `FakeVoiceController`,
`VoiceListeningParityTests`, and `SpeechActivityTraceTests` (model audio-event routing and controller response to
supplied coach-speaking state).
**Gaps:** the real recognizer's automatic error back-off uses non-injected timers and remains untested. Recognition
accuracy and actual OS permission prompts are device checklist only.

### Audio session

`WorkoutAudioSession` uses `.playback` with `.mixWithOthers`, or with voice control `.playAndRecord` with
`.mixWithOthers`, `.defaultToSpeaker`, and `.allowBluetoothA2DP`. Ducking deactivates an active session, sets
`.duckOthers`, and reactivates. `endDucking` deactivates with `.notifyOthersOnDeactivation`, restores the base
category, reactivates for listening when needed, and retries a busy deactivation every 0.25 s up to 4 attempts. An
interruption stops voice (status paused) and speech and pauses an active set; when it ends, voice resumes only if the
system says so, capture can run, and the microphone is unmuted. Only new or removed devices count as route changes.
Backgrounding pauses the set, stops capture and speech, and flushes the recorder; leaving the screen also deactivates
the session.

**Protected by:** `WorkoutCoachModelRecordingTests` (notification translation and observers on the shared session),
`AudioSessionParityTests` (category, option bits, activation, ducking, deactivation, notification events, and failure
paths), `SpeechActivityTraceTests` (model event routing and controller/audio-session response to supplied
coach-speaking state), and `WorkoutCoachModelTests` (an interruption pauses the session).
**Gaps:** the ordering between the real `SpeechCoach.speakNext` activity callback and ducking, and `finishActivity`
restore and callback, is unpinned until phase 2 provides a synthesizer seam. The audio-facade PR must add a production
trace through that seam before changing this behavior. Completion of the restore retry sequence is untested because
its dispatch timer is not injectable. Real routes (Bluetooth, AirPlay, calls, Siri) are device checklist only.

### Reminders and character notifications

`WorkoutReminderCoordinator` reconciles one optional schedule (Plain or Character) on launch, activation, settings,
routine, Up Next, and history-save changes, one reconciliation at a time. Character style plans copy and art from
`NotificationScenarioCatalog` and acknowledges the first saved workout of a day. Extra Personable adds persona
observations behind `settings.extraPersonable`, with cooling and traces in `persona-traces.json`. A notification tap
routes to its still-valid workout, and is ignored during an active workout. See [reminders.md](reminders.md),
[notifications.md](notifications.md), and [persona.md](persona.md).

**Protected by:** `WorkoutRemindersTests`, `RouteParityTests`, `CharacterReminderCoordinatorTests`, `WorkoutRemindersSettingsPageTests`,
the `Notification*Tests`, the `Persona*Tests`, and `make notification-character-check`.
**Gaps:** foreground presentation options, dismissal registration and translation, and persona presentation options
are pinned by `NotificationContentBuilderTests` and `PersonaCoordinatorTests`; actual OS banner rendering, OS delivery
of dismissal callbacks, and delivery timing are device checklist only.

### Persistence

`AppModelContainer` opens `SchemaV2` (seven models) through `AppMigrationPlan`, with a lightweight stage from
`SchemaV1` (five models). Repositories in `Persistence/Repositories` own reads and writes. If a store cannot open, its
files are copied to `<store>.unreadable-<UTC stamp>`, the originals are removed, and a fresh store opens; a failed copy
leaves the originals and the open fails. After a failed open, or if the fresh store also fails, the app runs without
repositories and shows `PersistenceUnavailableView`. Preferences live in `UserDefaults`; persona traces, the notification event log,
assessment images, and developer recordings are separate files. See [persistence.md](persistence.md).

**Protected by:** `SchemaMigrationTests`, `AppModelContainerTests`, `PersistenceRepositoryTests`,
`AdaptiveTrainingRepositoryTests`, `BuiltInRoutineRepositoryTests`, `PreferencesStoreTests`, `PersonaTraceStoreTests`,
and `WorkoutRecordingStoreTests`.
**Gaps:** nothing tells the user a store was moved aside, and nothing recovers it; that is a separate recovery-UX
concern outside the behaviour-preserving refactor. The `PersistenceUnavailableView` path is untested.

### Adaptive training

`Packages/AdaptiveTraining` decides every prescription, imports only Foundation, and names exercises by stable string
IDs. App code reaches it only through `PostureAnalysisApp/AdaptiveTraining/`; `AdaptiveTrainingCoordinator` is the one
app caller besides the debug provider. The engine's `record`, `save`, `commit`, `abandon`, `removeFamily`, and
`changeEquipment` return `[AdaptiveEvent]` from `AdaptiveEventDeriver`. The coordinator discards them; events appear
only in the developer snapshot and export. `tinySessionPrescribed` is defined but never derived or emitted.

**Protected by:** the package tests (including `AdaptiveEventTests`, `PackageBoundaryTests`, `ReplayInvariantTests`,
and `TodaySessionPlannerTests`), `AdaptiveTrainingCoordinatorTests`, `AdaptiveTrainingRepositoryTests`,
`WorkoutOutcomeAdapterTests`, `ExerciseVariantBridgeTests`, `TodaySessionFlowTests`, the `AdaptiveDebug*Tests`, and
the `AdaptiveTrainingSettings*Tests`.
**Gaps:** events are derived but no app code consumes them, and no test pins that nothing reacts to them.

## Docs inventory

Status comes from a keyword and section review on 2026-11-07, not a line-by-line audit.

| File | Covers | Status |
|---|---|---|
| `README.md` | Features, build, tests, Gitleaks, notices, limits | Current |
| `AGENTS.md` | Structure map, architecture, invariants, commands | Current |
| `docs/adaptive-training.md` | Package boundary, ladders, facts, policy, Today's Session, effort, bonus, Too Hard, calibration, debug | Current; "The Train hero arrives in PR 14" (Today's Session flow, Calibration › In the app) is planned |
| `docs/agent-orchestration.md` | Agent roles, panes, briefs, build lock, review | Current (process) |
| `docs/baseline.md` | This inventory | Current |
| `docs/commit-and-pr.md` | Gitleaks gate, commit and PR format | Current |
| `docs/debugging.md` | Developer diagnostics view and links | Current |
| `docs/design.md` | Design bundle, metrics, tokens, components, anchors, routes | Current; "Deferred features" lists deferred work |
| `docs/diagnostics.md` | Workout recordings, viewer, MCP, replay, file format | Current |
| `docs/geometry.md` | Coordinate systems, aspect rule, reference geometry, horizon | Current |
| `docs/notification-scenarios.md` | Generated scenario table | Current (generated) |
| `docs/notifications.md` | Character notification planner | Current |
| `docs/persistence.md` | Schema, migration, move-aside, repositories, preferences, baseline matching | Current |
| `docs/persona-content.md` | Generated persona copy and art | Current (generated) |
| `docs/persona.md` | Extra Personable gating, planner, cooling, debug | Current; "Extending" and the reserved `{name}` token describe later work |
| `docs/realtime.md` | Live posture check | Current |
| `docs/reminders.md` | Reminder scheduling, taps, developer preview | Current |
| `docs/validation.md` | Photo validation rules (not CI) | Current |
| `docs/workout.md` | Workout Coach behaviour, rep rules, coaching, speech, voice, tests, device checklist | Current; "Future options" is future work |
| `Design/AppIcon/README.md` | Icon source and export | Current |
| `Design/NotificationCharacter/README.md` | Character art pipeline and scenario data | Current |

## Invisible-PR parity checklist

Copy this list into the body of every #132 (behaviour-preserving foundations) PR and check each item, or explain why
it does not apply:

- [ ] No new or changed UI, sound, haptic, route, notification, or preference key.
- [ ] No `@Model` or schema change, asset change, or exercise-definition change.
- [ ] Golden traces (utterances, effects, reps) and committed design metrics unchanged.
- [ ] Existing tests unchanged; only additions.
- [ ] SwiftData move-aside recovery path unchanged.
- [ ] New observers and adapters default to none (no-op) in production.
- [ ] Docs updated in this PR, or a no-change rationale given (Docs impacted / Docs reviewed / No-change rationale).

## Documentation update matrix

| Change | Update in the same PR |
|---|---|
| Workout, coach, or workout event | `docs/workout.md` |
| Adaptive training | `docs/adaptive-training.md` |
| Voice or audio | `docs/workout.md` (Speech and audio, Voice control); add `docs/audio.md` only when a real audio boundary is implemented |
| Navigation or design | `docs/design.md` (frame and fixture map, routes), `Design/Metrics`, anchors |
| Persistence | `docs/persistence.md`, including migration and recovery guidance |
| Persona or notifications | `docs/persona.md`, `docs/persona-content.md`, `docs/notifications.md`, `docs/notification-scenarios.md`, `docs/reminders.md` as relevant |
| Replay or diagnostics | `docs/diagnostics.md` |
| User-visible capability or setup | `README.md` |
| Assets | `THIRD_PARTY_NOTICES.md`, asset source manifests, in-app acknowledgements |
| New directory or responsibility | `AGENTS.md` |
| Tests or validation steps | The doc that names them, with real invocations; never `docs/validation.md` |
| Dormant internal interfaces | Label them dormant/internal wherever they are documented |
| A fact recorded here | `docs/baseline.md` |

## Known limits

Parity tests run on the simulator with fakes for the camera, speech, recognizer, audio session, and clock. They cannot
prove behaviour on real audio routes (Bluetooth, AirPlay, calls, Siri, media-services resets), Vision pose accuracy,
real speech and recognition timing, permission prompts, or notification delivery. A change that touches any of
these needs explicit review and the relevant items from the physical-device checklists in [workout.md](workout.md)
and [realtime.md](realtime.md), run on an iPhone with `make ios`.
