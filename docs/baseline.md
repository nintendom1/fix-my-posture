# Behaviour baseline

This file records current behaviour and coverage for behaviour-preserving changes. Update it when a listed guarantee or gap changes. Detailed rules belong in the linked owner docs.

## Test environment

`./scripts/validate.sh` is the full validation entry point. It runs:

1. `python3 -m unittest discover -s scripts/tests -q`.
2. `node --test tools/session-replay/test/*.test.mjs` (Node 20 or later).
3. `python3 scripts/pbxproj.py check`.
4. `swift test --package-path Packages/AdaptiveTraining --quiet` and `swift test --package-path Packages/Narrative --quiet`.
5. Full Xcode and `simctl` checks.
6. App XCTest via `xcodebuild test -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp -destination '<simulator>' -derivedDataPath build/validation -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`.

`SIMULATOR_DESTINATION` must start with `platform=iOS Simulator,` and name an installed simulator. When unset, the script selects an available iPhone on the newest iOS 17+ runtime, preferring iPhone 15 Pro within that runtime. `WorkoutSessionReplayTests.testLocalRecordingsReplayToWhatThePhoneCounted` skips unless `FMP_SESSION_DIR` or `TEST_RUNNER_FMP_SESSION_DIR` names a recordings folder. CI uses Xcode 16.4 on `macos-15` and skips markdown-only changes. GitHub's runners use UTC, so date-string tests must pin a time zone; reproduce locally with `TEST_RUNNER_TZ=UTC ./scripts/validate.sh` (xcodebuild passes `TEST_RUNNER_`-prefixed variables to the test process without the prefix).

Other checks:

- `make design-check` refreshes available references, runs fixed-window snapshots and anchor checks, and writes local pixel diffs. See [design.md](design.md).
- `make replay-sessions` replays local recordings in `diagnostics/sessions` or `SESSION_DIR`. See [diagnostics.md](diagnostics.md); recordings stay local.
- `make notification-character-check` checks generated character assets and runs their Python tests.
- `make adaptive-replay FILE="export.json"` replays an adaptive-training export; optional parameters use `PARAMS`.
- Every commit requires `gitleaks git . --pre-commit --staged --redact --exit-code=1`. See [commit-and-pr.md](commit-and-pr.md).

Device builds use `make ios`. [validation.md](validation.md) documents photo warnings, not test execution.

## Behaviour and coverage

| Area | Current guarantee | Coverage and remaining gap |
|---|---|---|
| Navigation | Four tabs keep independent navigation paths. Settings, workouts, Today's Session, calibration, and Live Posture Check use full-screen presentation. See [design.md](design.md). | Route and shell tests cover route ownership and tab roots; presented covers and the no-store screen are not rendered by tests. |
| Workout Coach | `WorkoutSession` is a reducer. Analyzers, framing, coaching, speech, and recording feed its value-based effects. See [workout.md](workout.md). | Session, analyzer, replay, and golden-trace tests cover behaviour. The SwiftUI history-saved lifecycle guard remains untested. |
| Speech and audio | `SpeechCoach` uses system text-to-speech. `WorkoutAudioSession` is the only workout `AVAudioSession` owner. Other audio contracts are marked Dormant and internal. See [audio.md](audio.md) and [workout.md](workout.md). | Queue and audio parity tests use fakes. Real speech timing, recognition, audio routes, and OS interruptions require device checks. |
| Posture analysis | Geometry uses aspect-correct pixel coordinates. Live camera results are generation-checked and remain local. See [geometry.md](geometry.md) and [realtime.md](realtime.md). | Geometry and camera lifecycle tests use synthetic poses and injected capture. Vision accuracy, camera capture, and latency require a device. |
| Reminders and persona | Reminders and character messages are local notifications. Persona state and traces are local files. See [reminders.md](reminders.md), [notifications.md](notifications.md), and [persona.md](persona.md). | Planner and routing tests cover decisions; actual notification delivery and banner presentation require a device. |
| Persistence | Versioned SwiftData stores migrate V1 to V2. Repository writes are explicit; assessment photos are separate files. See [persistence.md](persistence.md). | Migration, repository, and preference tests cover storage. The persistence-unavailable screen is untested. |
| Adaptive training | `Packages/AdaptiveTraining` is Foundation-only and owns progression decisions. App integration stays behind adapters in `PostureAnalysisApp/AdaptiveTraining/`. The app coordinator forwards derived events, including `tinySessionPrescribed`, to the production `WorkoutReminderCoordinator`. It buffers workout-bound events until a saved workout and evaluates calibration events immediately when reminder settings and authorization allow. See [adaptive-training.md](adaptive-training.md) and [persona.md](persona.md). | Package, adapter, and persona tests cover decisions and delivery. |
| Narrative | `Packages/Narrative` is a Foundation-only runtime and is not linked into the app. See [narrative.md](narrative.md). | Package tests cover the runtime and the app-project boundary. |

## Documentation update matrix

| Change | Update in the same PR |
|---|---|
| Workout, coach, or workout event | `docs/workout.md` |
| Adaptive training | `docs/adaptive-training.md` |
| Voice or audio | `docs/workout.md` and `docs/audio.md` |
| Navigation or design | `docs/design.md`, `Design/Metrics`, and anchor fixtures |
| Persistence | `docs/persistence.md`, including migration and recovery behaviour |
| Persona or notifications | Relevant files among `docs/persona.md`, `docs/persona-content.md`, `docs/notifications.md`, `docs/notification-scenarios.md`, and `docs/reminders.md` |
| Replay or diagnostics | `docs/diagnostics.md` |
| User-visible capability or setup | `README.md` |
| Assets | `THIRD_PARTY_NOTICES.md`, asset source manifests, and in-app acknowledgements |
| New directory or responsibility | `AGENTS.md` |
| Tests or validation steps | The doc that owns them, with runnable commands; never `docs/validation.md` |
| Dormant and internal interfaces | Label them Dormant and internal wherever documented |
| A fact recorded here | `docs/baseline.md` |

## Behaviour-preserving checklist

For a refactor that claims behaviour parity, check each item or explain why it does not apply:

- [ ] No new or changed UI, sound, haptic, route, notification, or preference key.
- [ ] No `@Model`, schema, asset, or exercise-definition change.
- [ ] Golden traces (utterances, effects, reps) and committed design metrics are unchanged.
- [ ] Existing tests are unchanged; only additions are made.
- [ ] SwiftData move-aside recovery behaviour is unchanged.
- [ ] Optional observer parameters default to nil; production wiring is explicit and tested.
- [ ] Docs are updated, or the PR explains why they are unchanged.

## Internal contracts

The speech seam supports existing behaviour. The workout model's observer is nil in production; the adaptive coordinator uses `WorkoutReminderCoordinator` for adaptive events. The presentation mapper remains test-only. Sound and narrative contracts below are dormant.

| Contract | Current guarantee | Required before activation |
|---|---|---|
| Workout observer and presentation events (`PostureAnalysisApp/Workout/Session/WorkoutObserving.swift`, `PostureAnalysisApp/Workout/Presentation/WorkoutPresentationEvent.swift`) | `WorkoutCoachModel` receives no observer in production. `AdaptiveTrainingCoordinator` sends adaptive events to `WorkoutReminderCoordinator`, which defers workout-bound events until history is saved and evaluates calibration milestones immediately. The semantic mapper is test-only. | Keep workout-model callbacks opt-in and preserve observer-free golden traces; test the production adaptive-event path and save correlation. |
| Audio coordinator (`PostureAnalysisApp/Voice/AudioCoordinating.swift`) | `WorkoutAudioCoordinator` forwards to its supplied owner; `WorkoutAudioSession` remains the only system owner. | Add explicit wiring and parity tests without adding another `AVAudioSession` owner. |
| Sound cues and music/effect contracts (`PostureAnalysisApp/Voice/SoundCue.swift`) | Stable vocabulary and policy labels only; no players or production callers. | Add policy-aware players, an opt-in switch, and audio-focus tests. |
| Narrative runtime and presentation (`Packages/Narrative/`) | Validates scripts and runs a pure value runtime. The app does not link or present it. | Define app, asset, audio, and persistence ownership; add opt-in integration and isolation tests. |

`SpeechSynthesizing` is the active backend seam. `SpeechCoach` defaults to the system wrapper, and its queue behaviour is tested through the injected synthesizer. A prerecorded backend must preserve queue, repeat, cancellation, callback order, and shared-session ownership; a sibling protocol may be needed because the seam accepts `AVSpeechUtterance`.

## Known limits

Simulator tests use fakes for camera, speech, recognition, audio sessions, and clocks. They cannot establish hardware behaviour. Physical-device checks in [workout.md](workout.md) and [realtime.md](realtime.md) cover camera, speech, audio routes, permissions, and notification delivery; run them on an iPhone with `make ios` when a change depends on those behaviours.
