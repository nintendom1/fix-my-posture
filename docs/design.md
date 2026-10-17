# Design system and screen layout reference

The local, read-only design bundle is the reference for the redesigned screens. `make design-reference` extracts its 21 `#t2` frames, renders them in Playwright WebKit, and writes updated `Design/Metrics/design-metrics.json`. Reference PNGs and the Google Fonts cache go under ignored `build/design/`. The bundle must be present at `fix-my-posture-mobile-app-design/project/Fix My Posture Redesign.dc.html`; these commands do not modify it.

`scripts/design/anchors.mjs` maps each stable frame ID to text or structural locators. Anchor names use `<screen>.<element>` (for example, `train.hero.cta` and `camera.repCount`). `box` anchors tolerate 1 pt and `text` anchors tolerate 2 pt. Every design frame currently has a fixture; `PendingFrames.ids` is empty.

`make design-snapshots` runs the snapshot harness with a fixed 390×844 window and writes images to `build/design/actual/`. `make design-diff` writes heatmaps, side-by-side images, and a mismatch summary to `build/design/diff/`; it masks the status bar, rounded corners, native tab-bar strip, camera preview, and progress charts. Pixel diffs are a local review aid. The XCTest anchor checks are the layout gate. Use `swift scripts/design/diff.swift --tolerance 2` to allow two levels of per-channel pixel variation.

Run `make design-reference` to regenerate the committed metrics and local references. Run `make design-check` to regenerate references, run the fixed-window XCTest snapshots and anchor checks, and produce available pixel diffs. The design bundle and a bootable iOS simulator are required for the complete check.

## Screen, frame, and feature map

| Screen | Design frame IDs | Feature folder |
|---|---|---|
| Train home | `train` | `Features/Train/` |
| Routines list and detail | `routines`, `routine` | `Features/Routines/` |
| Routine editor | `editor`, `editor-picker`, `editor-new` | `Features/RoutineEditor/` |
| Exercise library | `library` | `Features/Library/` |
| Exercise detail | `exercise` | `Features/ExerciseDetail/` |
| Workout camera | `camera-ready`, `camera-active`, `camera-paused`, `camera-tip`, `camera-rest-coach-muted`, `camera-lost-mic-off`, `camera-tilt` | `Features/WorkoutCamera/` |
| Workout completion | `complete` | `Features/WorkoutComplete/` |
| Progress | `progress` | `Features/Progress/` |
| Workout history | `history` | `Features/History/` |
| Posture home | `posture` | `Features/PostureHome/` |
| Saved posture assessment | `assessment` | `Features/Assessment/` |
| Settings | `settings` | `Features/Settings/` |

These fixtures cover all 21 frames. Realtime posture, photo import, and voice-command help are additional routes without a frame in the current bundle.

## SwiftUI design system

`PostureAnalysisApp/DesignSystem/` is the dark-first design system used by the redesigned screens. Feature screens use its semantic tokens, motion policy, anchors, and reusable components.

### Colors

`ColorTokens.palette(for:)` defines the semantic dark palette once. `.light` intentionally returns the dark palette until a light design is specified. `Color(hex:)` accepts 3, 4, 6, and 8 digit RGB(A) hex strings, including `#` and `0x` prefixes. The eight digit form is CSS `RRGGBBAA`.

| Role | Value |
|---|---|
| Brand | `#7C4DFF` |
| Accent | `#FF7F9E` |
| Success | `#6EE7B7` |
| Warning | `#FFC46B` |
| Danger | `#FF7B8A` |
| Rest / info | `#6FD6FF` |
| Primary background | `#0E0B16` |
| Card / card border | white at 6% / white at 7% |
| Primary / secondary text | `#F6F3FB` / `#B9B0CC` |
| Muted / subtle text | `#A49CB8` / `#8A82A0` |
| Active / Posture active / inactive tab | `#C9B3FF` / `#9FB0FF` / `#7D758C` |
| HUD toggle off | `rgba(255,90,110,.55)` |
| Selected filter chip background / text | `#F6F3FB` / `#1A1226` |
| Unselected filter chip background / text | white at 8% / `#E4DDF0` |

`ColorTokens.workoutColors(for:)` translates `WorkoutVisualState` into UI tint and glow values. `WorkoutVisualState` remains Foundation-only. Ready and active use `#B9A2FF` with `rgba(124,77,255,.5)` and `.45` glows; paused uses `#D8D0E8` and `rgba(200,190,230,.25)`; tips and tilt use warning, rest uses rest/info, lost tracking uses danger, and completion uses success. Their tint and glow values match the `S` state table in `FMP App.dc.html`.

### Gradients and aura

| Token | CSS definition |
|---|---|
| `trainHero` | `135deg, #6A3DF0, #A64BE0 55%, #FF7F9E` |
| `workoutActive` | `135deg, #7C4DFF, #C04BD8` |
| `workoutAttention` | `135deg, #FF9F43, #FFC46B` |
| `workoutLost` | `135deg, #FF5A6E, #FF9A8A` |
| `progress` | `150deg, #4A2BD8, #7C4DFF 50%, #2FB8A0 130%` |
| `posture` | `150deg, #3B4FD8, #6A6CF0 55%, #56B8D8 120%` |
| `success` | `135deg, #22C38E, #7BE0B4` |
| `rest` | `135deg, #3A8DFF, #6FD6FF` |

`GradientTokens.linearGradient(from:)` converts an exercise's CSS angle and color stops into a SwiftUI `LinearGradient`. CSS angles follow CSS direction semantics: `135deg` runs top-left to bottom-right, and `90deg` runs left to right. Stops beyond 100% extend the gradient line past the view bounds, then normalize stop locations to that extended line; this preserves the intended `120%` and `130%` endpoints.

`AuraBackground` uses 440 pt and 400 pt radial blobs at the HTML offsets. Train, Routines, Progress, Posture, and Complete use the `aura` table in `FMP App.dc.html`; Settings falls back to Train. Tab changes animate over 0.5 seconds, and `motionPolicy == .reduced` disables the color transition.

### Metrics and type

`Metrics.Radius` uses 9 pt icon tiles, 14 pt thumbnails, 20 pt rows/cards, 28 pt hero cards, and capsule shapes. `Metrics.Spacing` provides 4, 8, 12, 16, 20 pt screen margin, and 24 pt values. `Metrics.Size` includes 44 pt minimum hit targets, 56 pt primary and 58 pt sticky CTAs, 84 pt camera primary button, 96 pt rep counter, 10 pt progress bar, 86 pt tab bar, 44 pt HUD icon button, 24 pt listening chip, and a 36 pt filter-chip visual inside a 44 pt hit target.

`Typography` builds SF Pro Rounded `UIFont` values with `UIFontMetrics` and provides corresponding SwiftUI `Font` values. `.textStyle(_:)` applies tracking and maps the eyebrow to uppercase; the rep counter uses monospaced digits.

| Style | Base size / weight | Dynamic Type text style |
|---|---|---|
| Large Title | 34 pt Black | `.largeTitle` |
| Title | 30 pt Black | `.title1` |
| Title 2 | 21 pt Black | `.title2` |
| Headline | 16 pt Heavy | `.headline` |
| Body | 15 pt Bold | `.body` |
| Caption 1 | 13 pt Bold | `.caption1` |
| Caption 2 | 12 pt Semibold | `.caption2` |
| Eyebrow | 11 pt Heavy, uppercase, 1 pt tracking | `.caption2` |
| Rep counter | 96 pt Heavy, −3 pt tracking, monospaced digits | `.largeTitle` |

### Material icon map

The 60 Material Symbols names from `Design/Metrics/design-metrics.json` map one-to-one to SF Symbols available on iOS 17. `Image(material:)` uses this map.

| Material | SF Symbol | Material | SF Symbol | Material | SF Symbol |
|---|---|---|---|---|---|
| `accessibility_new` | `figure.stand` | `add` | `plus` | `add_circle` | `plus.circle.fill` |
| `arrow_downward` | `arrow.down` | `arrow_upward` | `arrow.up` | `battery_full` | `battery.100percent` |
| `check` | `checkmark` | `check_circle` | `checkmark.circle.fill` | `chevron_left` | `chevron.left` |
| `chevron_right` | `chevron.right` | `close` | `xmark` | `code` | `chevron.left.forwardslash.chevron.right` |
| `content_copy` | `doc.on.doc` | `delete` | `trash` | `description` | `doc.text.fill` |
| `drag_indicator` | `circle.grid.2x2.fill` | `edit` | `pencil` | `expand_less` | `chevron.up` |
| `favorite` | `heart.fill` | `fitness_center` | `dumbbell.fill` | `format_list_numbered` | `list.number` |
| `graphic_eq` | `waveform` | `help` | `questionmark.circle.fill` | `info` | `info.circle.fill` |
| `ios_share` | `square.and.arrow.up` | `lock` | `lock.fill` | `menu_book` | `book.closed.fill` |
| `mic` | `mic.fill` | `mic_off` | `mic.slash.fill` | `monitoring` | `chart.xyaxis.line` |
| `more_horiz` | `ellipsis` | `notifications` | `bell.fill` | `pause` | `pause.fill` |
| `pause_circle` | `pause.circle.fill` | `photo_camera` | `camera.fill` | `photo_camera_front` | `camera.rotate` |
| `photo_library` | `photo.stack.fill` | `play_arrow` | `play.fill` | `play_circle` | `play.circle.fill` |
| `record_voice_over` | `person.wave.2.fill` | `remove` | `minus` | `restart_alt` | `arrow.counterclockwise` |
| `scale` | `scalemass.fill` | `screen_rotation` | `rotate.right` | `search` | `magnifyingglass` |
| `self_improvement` | `figure.mind.and.body` | `settings` | `gearshape.fill` | `signal_cellular_alt` | `antenna.radiowaves.left.and.right` |
| `skip_next` | `forward.end.fill` | `straighten` | `ruler` | `swap_horiz` | `arrow.left.arrow.right` |
| `timer` | `timer` | `tips_and_updates` | `lightbulb.max.fill` | `tune` | `slider.horizontal.3` |
| `videocam` | `video.fill` | `visibility` | `eye.fill` | `visibility_off` | `eye.slash.fill` |
| `volume_off` | `speaker.slash.fill` | `volume_up` | `speaker.wave.2.fill` | `wifi` | `wifi` |

### Base components

`Components/` contains previewed, value-driven building blocks: `PrimaryButton` (gradient or white, 56/58 pt, 18 pt Black label and 24 pt icon), `CapsuleButton`, `FilterChip`, `StatusChip`, `SectionHeader`, `ProgressBar`, `EmptyStateTile`, `SettingsRow`, and `TabRootHeader`. Workout camera components are `HUDPill`, `HUDIconButton`, `EdgeToolbar`, `RepCounter`, and `EdgeGlow`. Interactive chips keep a 44 pt hit target. The filter pill is 36 pt high, uses 14 pt Heavy text and the HTML's selected/unselected colors; the status chip is 24 pt high with a 12 pt Heavy label and green/red text tint. The HUD toggle button is 44 pt. The progress bar is 10 pt high with a 5 pt rounded end, 16% white track, and a gradient fill. The gallery preview shows the tokens, type ramp, icon map, and base components.

## Anchors and exemptions

SwiftUI fixtures attach `.designAnchor("screen.element")` to the element measured against its metric in `Design/Metrics/design-metrics.json`. The design test requires every non-exempt anchor to exist and compares its position and size using the tolerance for its kind: 1 pt for `box`, 2 pt for `text`. Keep anchor names stable when moving a view between files.

`DesignMetricsTests.exemptions` records the anchors the screen cannot own or that belong to deferred UI. The status bar is supplied by the snapshot window. The native tab bar is owned by `TabView` or covered by an editor sheet. The current deferred or intentionally absent anchors are routine action anchors (`routine.actions.remind`, `routine.actions.duplicate`, `routine.actions.delete`), the exercise favourite (`exercise.favorite`), assessment sharing (`assessment.share`), and the settings reminder value (`settings.reminders.value`). Camera frames exempt only the host-owned status bar. Each exemption has its reason beside the key in the test.

## Adding a screen

Use the feature-folder pattern:

1. Add `Features/<Screen>/` with a view-model protocol, an `@MainActor @Observable` implementation, an Equatable screen state, and an intent enum. The screen renders state and sends intents; service work goes through injectable protocols.
2. Add deterministic fixtures under `Tests/Support/` and a fixed-window design test for each supplied frame.
3. Add stable frame IDs to `ImplementedDesignFixtures`, and add stable `<screen>.<element>` locators to `scripts/design/anchors.mjs`. Attach matching `.designAnchor` modifiers in the screen.
4. Add the frame ID to `PendingFrames.ids` while its fixture and design test are not ready. Once the fixture and required anchors are covered, remove the ID. A frame with a fixture still has to pass its anchor assertions. `PendingFrames` is empty today.

## Deferred features

The current design coverage defers richer progress charts, workout reminders, exercise favourites, sharing posture assessments, URL deep links, and exercise photos. `DesignMetricsTests` records the frame-anchor exemptions that exist today, including the reminder value, favourite, share, and routine action anchors. URL deep links and exercise photos have no frame in this bundle.

## Navigation and routes

`PostureAnalysisApp/App/` owns the composition root and the app shell. `AppEnvironment` constructs the router, preferences, SwiftData container and repositories, exercise catalog, and workout factory once, then provides them through SwiftUI's environment. `PostureAnalysisApp` starts at `AppShellView`.

The native `TabView` order is Train, Routines, Progress, Posture. Each tab owns a `NavigationStack` and an `[AppRoute]` path managed by the Foundation-only `AppRouter`. Selecting a different tab preserves its path; selecting the active tab again returns it to its root. `AppRoute` is Codable and Hashable so route state can be tested without rendering SwiftUI. Settings and the workout camera use a full-screen presentation over the tabs; the remaining routes push into their owning stack.

| Route | Tab or presentation | Current entry point |
|---|---|---|
| `train`, `library`, `exercise(id)` | Train stack | Train quick-start or routine CTA; **All Exercises** opens Library, then an exercise detail page |
| `routines`, `routine(id)`, `routineEditor(id?)` | Routines stack | Saved Sets tab and its create/edit controls |
| `progress`, `history` | Progress stack | Progress opens Workout History; Train's History control opens the same route |
| `posture`, `postureHistory`, `assessment(id)` | Posture stack | Posture home and saved assessment history/details |
| `livePostureCheck`, `photoAssessment(view)` | Posture flow | Live-check card and photo actions on the Posture home |
| `settings` | Full-screen over Train | Train gear; SettingsScreen groups coach, workout, camera and posture, and about preferences. Done dismisses the cover. |
| `workout(exerciseID?, routineID?)`, `workoutComplete` | Full-screen workout flow | Train quick-start, exercise detail, or routine; completion appears within the workout flow |

Workout history and posture assessment history are distinct: `.history` is workout history with weight editing under Progress, while `.postureHistory` is the saved assessment list with baseline selection under Posture. The report's Developer Diagnostics button and assessment landmark editor remain in the Posture assessment flow.

The tab bar uses a dark material blur with `rgba(18,14,28,.84)`, a white 6% top hairline, inactive `#7D758C` icons and labels, and 11 pt rounded Heavy labels. The selected tint is `#C9B3FF` for Train, Routines, and Progress, and `#9FB0FF` for Posture. `TabBarStyle` holds the testable values; `TabBarAppearance` applies the UIKit appearance once at launch.

`View.stickyCTA { ... }` reserves a 58 pt button, 16 pt horizontal insets, and bottom spacing through a safe-area inset. Routine detail and exercise detail use it; `StickyCTALayoutFixture` also exercises the layout in DEBUG snapshots.

### Assumptions

- The design system block does not show a light palette, so `.light` currently falls back to dark.
- The `aura` table has no Settings row, so Settings uses Train's aura colors.
- The HTML names EmptyStateTile but does not render an example; its surface uses the shared 20 pt card treatment, 16 pt padding, and semantic card colors.
- The HTML provides the CapsuleButton in its component list but no single canonical size; its visible pill is 40 pt with a 44 pt hit target.
- The eyebrow role is not specified in the type ramp; it uses 11 pt Heavy with 1 pt tracking, matching the compact uppercase section labels.
- Caption 1 uses 13 pt Bold and Caption 2 uses 12 pt Semibold, selecting from the HTML's 12–13 pt caption range.
- Assessment history and workout history remain separate: the tested `.history` route belongs to Progress, so Posture uses the additional `.postureHistory` route.
