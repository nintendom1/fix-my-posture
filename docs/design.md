# Design layout gate

`make design-reference` extracts the 21 `#t2` frames from the untracked local bundle, renders them in Playwright WebKit, and commits updated `Design/Metrics/design-metrics.json`. It also writes reference PNGs and a Google Fonts cache under ignored `build/design/`. The bundle must be present at `fix-my-posture-mobile-app-design/project/`; it stays local and is never modified or committed.

`scripts/design/anchors.mjs` maps each stable frame ID to text or structural locators. Anchor names use `<screen>.<element>` (for example, `train.hero.cta` and `camera.repCount`). `box` anchors tolerate 1 pt and `text` anchors tolerate 2 pt. A screen implementation adds a SwiftUI fixture, attaches `.designAnchor("same.name")` to its elements, adds the frame ID to the fixture set, and removes it from `PendingFrames`.

`make design-snapshots` runs the snapshot harness with a fixed 390×844 window and writes images to `build/design/actual/`. `make design-diff` writes heatmaps, side-by-side images, and a mismatch summary to `build/design/diff/`; it masks the status bar, rounded corners, the native tab-bar strip, camera preview, and progress charts. Diff output is a local review aid, not a CI pass/fail gate. Use `swift scripts/design/diff.swift --tolerance 2` to allow two levels of per-channel pixel variation.

Run `make design-check` to regenerate references and metrics, run the design harness, and produce the available pixel diffs.

## SwiftUI design system

`PostureAnalysisApp/DesignSystem/` is the dark-first foundation for the redesign. This phase adds tokens and preview components without changing existing screens; screens adopt them in Phase 3.

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
| `drag_indicator` | `line.3.horizontal` | `edit` | `pencil` | `expand_less` | `chevron.up` |
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

`Components/` contains previewed, value-driven building blocks: `PrimaryButton` (gradient or white, 56/58 pt, 18 pt Black label and 24 pt icon), `CapsuleButton`, `FilterChip`, `StatusChip`, `SectionHeader`, `ProgressBar`, and `EmptyStateTile`. Interactive chips keep a 44 pt hit target. The filter pill is 36 pt high, uses 14 pt Heavy text and the HTML's selected/unselected colors; the status chip is 24 pt high with a 12 pt Heavy label and green/red text tint. The HUD toggle button is 44 pt. The progress bar is 10 pt high with a 5 pt rounded end, 16% white track, and a gradient fill. The gallery preview shows the tokens, type ramp, icon map, and all base components together.

### Assumptions

- The design system block does not show a light palette, so `.light` currently falls back to dark.
- The `aura` table has no Settings row, so Settings uses Train's aura colors.
- The HTML names EmptyStateTile but does not render an example; its surface uses the shared 20 pt card treatment, 16 pt padding, and semantic card colors.
- The HTML provides the CapsuleButton in its component list but no single canonical size; its visible pill is 40 pt with a 44 pt hit target.
- The eyebrow role is not specified in the type ramp; it uses 11 pt Heavy with 1 pt tracking, matching the compact uppercase section labels.
- Caption 1 uses 13 pt Bold and Caption 2 uses 12 pt Semibold, selecting from the HTML's 12–13 pt caption range.
