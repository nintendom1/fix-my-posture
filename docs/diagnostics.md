# Workout Session Recordings (Developer)

A developer recording stores analyzed camera-frame joints, analyzer and framing results, coach state, and spoken or heard events for debugging. It never includes camera images or audio.

## Recording

- **Settings › About › Developer diagnostics › Workout recordings.** The **Record workouts** toggle is on by default in Debug builds (what `make ios` installs) and off in Release builds (`dev.workoutRecordingEnabled`). `WorkoutCoachFactory` reads it when a workout starts, so a change applies to the next workout.
- While recording, a **REC** chip sits beside the microphone chip. Tapping it drops a **marker** at that moment: the chip shows "Marked 1:56" for 3 s and the coach says "Marked." (silently when the coach is muted). Mark the moment something went wrong, such as a rep that should have counted.
- **Voice markers.** While recording, "mark that" and "flag that" add a marker; continue speaking for a note, or start with "note". `MarkerPhraseParser` runs before commands. Everything after the trigger is note text until 1.5 s of quiet, including words such as "pause"; this survives recognition task restarts. When the coach speaks, recognition stops synchronously; marker delivery waits until the next main-loop turn so "Marked." queues behind the line starting. The recognizer's `onTaskStarted` callback carries note state across final-result, periodic refresh, and error-recovery restarts. Listening stopping also finalizes the note so far. Markers use the trigger time, notes are limited to 280 characters, and marker phrases appear in Voice Commands only while recording. If recording ends mid-note, the marker is dropped and recognition restarts so note words cannot run as commands. See [File format](#file-format-fmpworkout-session1) for marker fields.
- The page lists recordings newest first with their exercises, length, markers, and size. **Share** sends the file under a readable name such as `FMP Push-Up 2026-10-25 2119.json` (AirDrop, Files; it previews as text). **Copy report** copies a text report with the data needed to diagnose a problem (see below). Recordings can be deleted one at a time, or all those without markers.
- **Size and retention.** A recording takes about 0.9 MB a minute, so a 6-minute starter routine is about 5.5 MB. Each recording stops after 60 minutes (`WorkoutSessionRecorder.maximumDuration`; the workout carries on unrecorded and the REC chip disappears). The newest 20 recordings are kept (`FileWorkoutRecordingStore.maximumRecordings`): beyond that the oldest without markers are removed first, then the oldest with markers, so 20 starter routines take roughly 110 MB and the worst case is about 1.1 GB. The recording in progress is never pruned. A recording that never received a camera frame is deleted when it ends.
- **Crash recovery.** A summary says complete only after the writer confirms the end line reached the file. A recording without a complete summary (a crash, force-quit, or full disk) is counted from its file the next time recordings are listed, so its markers still protect it.
- **Pulling to a Mac.** `make diagnostics` copies every recording from the phone (the device and bundle identifier from `ios.local.env`, as for `make ios`) into `diagnostics/sessions/` and lists the newest. The phone must be connected or paired and unlocked. `make viewer` then replays them (see below).

## Replay viewer

`make viewer` starts a local server and opens the replay viewer at `http://127.0.0.1:4317` (`tools/session-replay/`, Node 20 or later, no dependencies). It shows the recordings in `diagnostics/sessions/`; drop a shared `FMP … .json` file on the page, or use **Open file…**, to import one.

- **Stage:** the skeleton at the playhead, mirrored like the phone by default (L and R stay the user's own sides). Focus joints are bold, joints under the framing confidence are amber, joints below the 0.3 floor are red rings, and joints estimated past the frame edge are dashed. Toggles add the app HUD (set, reps, and what the coach just said), elbow angles, the analyzer's Start and Top lines, joint names with confidence, and a motion trail.
- **Panel:** the phase, set, reps, and counting; checks at this frame (the weakest joint framing needs, using the strongest alternative set as framing does, against the framing confidence; framing; the camera gap between frames, from capture timestamps, against the analyzer's limit; phone pitch); analyzer readings, threshold lines, and form values; notes; every joint's confidence; and the event log with filters.
- **Timeline:** phase, tracking (reliable, lost, or not tracking, split where the framing guidance changes), reps, each side's main signal and angle, the weakest required joint's confidence against the 0.4 and 0.3 lines, issues (tracking losses, cues, tilt), accepted tracking gaps in the Info lane, and notes. The reps lane numbers the coach's displayed count; dots classify each analyzer rep as counted, completing the set, one-side-only, or not counted (for example, a stale analyzer or counting off). Click or drag to scrub, and shift-drag to select a range.
- **Keys:** Space plays, ←/→ step a frame, Shift steps a second, [ and ] jump between log events, N adds a note at the playhead (or across the selection), E opens the export, and Esc clears the selection.
- **Notes** are saved beside the recording as `<uuid>.notes.json` (schema `fmp.session-notes/1`), so pulling the recording again never overwrites them. Notes have an author, you or Claude.
- **Export for Claude:** a Markdown excerpt with the window, notes, the exercise's tuning, the state in force when the window starts (phase, exercise, set, reps, counting, framing), the events and pipeline controls in the window, and a frame table as CSV (with an exercise column, and every exercise's focus joints, when the window spans more than one). The window is fixed when the dialog opens, so what is copied, saved, or sent is exactly the preview. It has presets (*Rep counting*, *Tracking & framing*, *Form cue*, *Session flow*), a window (selection, around the playhead, the exercise, or everything), a rate (10, 5, 2, or 1 Hz, or events only), the joints to include (focus joints, all, or none), and channel toggles. It shows a live token estimate. **Copy** and **Save .md** keep it on the Mac; **Send to Claude** writes `diagnostics/outbox/latest.md` (and `latest.json`). Then tell Claude Code "look at what I sent"; it reads the excerpt with `fmp_viewer_selection` (see below), or from that file.
- **Links:** `?session=<id>&t=13.3&from=12.3&to=15.4&export=1` opens a recording at a time, with a range selected and the export open.
- **Server:** binds to 127.0.0.1 only, refuses other Host headers, and accepts writes only with its `X-FMP-Replay` header. Its API: `GET /api/sessions`, `GET /api/sessions/<id>/file`, `GET`/`POST /api/sessions/<id>/notes`, `POST /api/import`, `GET`/`POST /api/viewer/state` (the open recording, playhead, and selection), `GET`/`POST /api/viewer/sent`, `POST /api/viewer/command` (relays `{"command":"seek","sessionId":…,"t":…,"from":…,"to":…,"note":…}` to open viewers), and `GET /api/events` (a server-sent event stream).
- **Markup safety:** recordings and notes can come from anywhere, so every string goes through `views.mjs`, which escapes text and forces numbers before anything reaches the page. A test renders every view from a hostile recording. Note saves and other writes are serialized per file, so concurrent saves never lose each other.
- Tests: `node --test tools/session-replay/test/*.test.mjs`, run by `validate.sh` with synthetic recordings only.

## Movement Lab Runs dashboard

`make viewer` opens the **Runs** dashboard. It lists synthetic runs newest first with per-run outcome totals; timestamped run IDs supply the run time and the plan's creation time remains separate. Open a run and scenario for synchronized reference and modified playback. The timeline shows phase, rep, rejection, framing, and counting; failed assertions link to their time. **Session recordings** opens the recording viewer.

Labels distinguish **planned** (no result yet), **executed** (a result exists), **passed**, **failed**, **inconclusive**, **invalid**, and **not tested** (the runner returned `notRun`). The reference is canonical guide motion on the scenario's seeded timeline. Dashboard artifact routes are read-only and expose only plans, summaries, results, and allowlisted recordings beneath `diagnostics/movement-lab/runs/`.

## Claude link (MCP)

`.mcp.json` registers `fmp-replay`, a stdio MCP server in `tools/session-replay/mcp.mjs` (Node 20+, no dependencies). Claude Code asks to approve the project's server once; `/mcp` shows its status after restart. Recording tools read `diagnostics/sessions/`; live viewer calls use the local server, started by `fmp_open_viewer` when needed.

| Tool | What it does | Limits and checks |
|---|---|---|
| `fmp_pull_device` | Runs `make diagnostics`. | Pulls serialize; `pull.sh` rejects a concurrent `diagnostics/.pull.lock` and stages each pull separately. |
| `fmp_list_sessions`, `fmp_session_overview` | List recordings or summarize one without frame data (about 1k tokens). The overview includes tuning, phase and rep events, tracking losses, bridged gaps, markers, notes, and suggested query windows. | Overview accepts an id, its first 8 characters, or `latest`. |
| `fmp_query`, `fmp_events` | Return a viewer-style Markdown/CSV window or selected timeline events. | More than 300 frame rows or about 17k tokens requires `allowLarge`; ordinary excerpts cap at 60,000 characters. The MCP message cap is 2 MiB. |
| `fmp_viewer_selection`, `fmp_viewer_seek`, `fmp_add_note`, `fmp_open_viewer` | Inspect the user's latest sent selection, seek the open viewer, add a note, or open a recording and range. | Live calls require a viewer that reports this checkout and time out after 2 s. Note writes use a per-file lock, taken over after 10 s. |
| `fmp_lab_manifest` | Return the exercises, scenario categories, mutation bounds, and preset IDs. | — |
| `fmp_lab_run` | Run a preset or validated plan in `pipeline` or `coach` mode; returns one bounded line per non-passing scenario and totals. Plans and scenarios are marked agent-authored; each scenario gets an intent from its intent or purpose. | Plan ≤1 MiB; intent ≤1,000 characters; invalid plans return at most 20 issues within 8 KiB. Optional `parentRunID` and `followUpReason` must appear together; the reason is ≤500 characters. Runs serialize in one MCP process. |
| `fmp_lab_inspect` | Inspect a run or scenario, optionally within a time window. | Safe run ID must match `YYYYMMDD-HHMMSS-<4–12 alphanumeric>`; ordinary output ≤60 lines, full trace ≤256 KiB. |
| `fmp_lab_open` | Open the viewer at a run, scenario, and keyframe, then select and seek the scenario. | Uses the same safe run ID validation. |

Times are seconds or `m:ss.s`. A follow-up reason is also added to the plan purpose shown in the run panel. Tool schemas reject invalid arguments. MCP tools cannot approve or write fixtures; approval and promotion are human-only in the dashboard. Recording data is a real person's body data. The test `tools/session-replay/test/mcp.test.mjs` drives the server over stdio against a temporary folder.

## Replay

`make replay-sessions` (or `make replay-sessions SESSION_DIR=<folder>`) replays every pulled recording through the strict pipeline in the simulator. `make replay-sessions CURRENT=1` runs current-build mode against today's catalog definitions and thresholds. The `FMP_REPLAY_CURRENT` and `TEST_RUNNER_FMP_REPLAY_CURRENT` flags select that mode in the test process. It ignores the exercise configuration and framing requirements recorded on the phone, so per-frame differences are expected; replay errors still fail the command. Both modes write `build/replay-report.txt` locally.

- **Reading:** `WorkoutSessionReplayTests` reads each file with `WorkoutSessionFile`. Only an unclosed array or a cut-off last record (a crash mid-write) is tolerated; a bad record anywhere else is an error.
- **Rebuilding:** strict mode rebuilds the pipeline with the recorded framing and off-edge settings, and each exercise from its recorded configuration. It checks the recorded required and any-of-required joints against the catalog. Current-build mode uses catalog exercises and reduced-range variants as they are today, without applying recorded exercise configurations or checking framing drift. Both modes apply `pipe` controls and analyze every frame the phone analyzed (`p: true`) in file order. A malformed replay, unknown exercise, view, control, or phase, an analyzed frame before any exercise, or a missing joint order or image size is an error.
- **Fidelity:** strict mode requires each analyzed frame to match what counting depends on: rep events (timestamp, epoch, sides), framing reliability, the counting flag, and whether the start position is held. Guidance wording isn't compared. Current-build mode measures changes and does not fail for frame differences.
- **Report:** `build/replay-report.txt` (local, gitignored) shows the first differing frames and every attempt the analyzers let go, with the reason. In current-build mode it starts with a mode label and lists phone and replayed counts per exercise for every recording. It's rewritten on every run; replay errors and an empty folder fail either mode.

Use the report to test a fix: change an analyzer or a configuration, replay, and compare the counts. Without a session folder, the local test skips. `testRecordedWorkoutsReplayToTheSameReps` records every catalog exercise's demonstration through the coach and replays it, so CI covers the format without personal data.

## Data rule

Recordings are measurements of a real person's body, and this repository is public.

- `diagnostics/`, shared copies (`FMP *.json`), and the older `*.jsonl` and `*.fmpsession` files are gitignored. Never commit a real recording, and never paste one into an issue, pull request, or other public place unless the developer explicitly asks.
- To keep a fix from regressing, commit a synthetic test (for example the guide demonstration with the failing values) rather than the recording.

## Architecture

`WorkoutCoachModel.dispatch` records reducer inputs with their resulting state; `applyControl` records a pipeline control only when it changes. `WorkoutFramePipeline.collectsDiagnostics` adds framing, counting, and analyzer output only when a recorder is attached. `WorkoutCameraController` records accepted-frame sequence numbers and landmarks below the 0.3 confidence floor, which analysis ignores. Recording IDs match saved `WorkoutRecord` IDs; a workout with no finished set has no history entry. The recorder, line writer, store, and configuration serializer live in `Workout/Diagnostics/`. On device, each recording is `Application Support/Diagnostics/Workouts/<uuid>.json` with `<uuid>.summary.json` beside it; the folder is excluded from backups. Legacy `.jsonl` and `.fmpsession` files convert when listed or pulled. Shared copies are hard links in the temporary folder.

## Movement Lab scenarios

Movement Lab plans use `schemaVersion: 1`. Plan and scenario IDs are 1–64 lowercase ASCII letters, digits, `_`, or `-`; a plan has at most 200 scenarios. Each scenario names a registered exercise, category (`canonical`, `depth_rom`, `alignment`, `timing`, `tracking`, `session_framing`), purpose, guide revision, seed, 1–120 repetitions, mode (`constrained` or `raw`), mutations, assertions, and revision lineage. Plan authors are `agent` or `developer`. Unknown schema versions and mutation/assertion kinds are rejected; field validation runs before materialization. A generated timeline is at most 120 seconds.

### Local command-line runs

```sh
node tools/session-replay/lab.mjs presets
node tools/session-replay/lab.mjs run --preset air_squat
node tools/session-replay/lab.mjs presets --exercise push_up
node tools/session-replay/lab.mjs run --preset push_up
node tools/session-replay/lab.mjs run /path/to/plan.json --mode pipeline --sim <simulator-id>
node tools/session-replay/lab.mjs inspect <run-id> --scenario canonical --window 1-6
make lab PLAN=/path/to/plan.json SIM=<simulator-id>
```

The preset list comes from the Swift `MovementLabTests` manifest. The CLI validates plan JSON and field paths, invokes a fixed `xcodebuild` argument list, and times out after 20 minutes. Preset listing and runs require an iOS simulator; `--sim` chooses its UUID. A `spokenCue` assertion in pipeline mode is inconclusive because only coach mode captures speech. Outcome labels are defined in [Runs dashboard](#movement-lab-runs-dashboard).

The built-in `push_up` plan is titled **Push-Up Movement Scenarios**. Its `canonical` scenario expects five counted repetitions. `shallow-depth` keeps both elbows above 110° and expects zero. `bottom-shoulder-dropout-0-3s` and `bottom-shoulder-dropout-0-7s` remove both shoulders at Down and each expect one counted repetition. `descent-shoulder-dropout` removes the same joints while lowering and expects zero repetitions plus a `trackingGap` rejection. The viewer's Runs and Scenario coverage views discover exercises and scenarios from stored plans, including Push-Up.

Each run is stored locally at `diagnostics/movement-lab/runs/<run-id>/`. `plan.json` preserves the plan input. `scenarios/<id>.json` is a workout-session recording array with processed pipeline fields, including `out`, `fr`, `rd`, `sig`, `rej`, and `cnt`, so the existing replay viewer can open it. `results.json` contains scenario outcomes and assertion details. `summary.json` contains execution mode, outcome totals, elapsed time, and revisions. `counting-changes.json` records counting transitions by scenario. The inspector prints one scenario by default, filters event records to a requested time window, and limits ordinary output to about 60 lines; `--full` prints the complete selected trace.

All generated poses and plans are synthetic. They test analyzer behavior for supplied coordinates, not Apple Vision camera accuracy. Exploratory plans and artifacts stay under git-ignored `diagnostics/`; do not commit them or use real recordings as substitutes.

### JSON contract

This schema-complete plan shows the required envelope and a representative scenario. Replace the abbreviated `canonicalRevision` value with the current guide hash before materializing it. Fields not shown in this scenario are documented in the tables below.

```json
{
  "schemaVersion": 1,
  "id": "air-squat-lab-v1",
  "title": "Air Squat lab",
  "purpose": "Exercise the guide-bottom knee edit.",
  "author": "developer",
  "createdAt": "2026-11-07T12:00:00Z",
  "scenarios": [
    {
      "id": "knees-at-bottom",
      "exercise": "air_squat",
      "category": "alignment",
      "purpose": "Move the knees inward at the first maximum hip drop.",
      "canonicalRevision": "guide-fnv1a-…",
      "seed": "9007199254740993",
      "reps": 5,
      "mode": "constrained",
      "mutations": [
        {
          "kind": "jointOffset",
          "joints": ["leftKnee"],
          "dx": -0.04,
          "dy": 0,
          "peak": 3.7,
          "rise": 0.35,
          "fall": 0.35,
          "strength": 1
        }
      ],
      "assertions": [
        {"kind": "repCount", "equals": 5},
        {"kind": "rejection", "reasonContains": "partialEnd", "countMin": 1},
        {"kind": "formSignal", "id": "squat.knees_in", "present": true},
        {"kind": "framing", "state": "reliable", "reached": true},
        {"kind": "spokenCue", "textContains": "stand tall", "present": true}
      ],
      "revision": 1
    }
  ]
}
```

`seed` is a base-10 unsigned 64-bit integer encoded as a JSON string. The decoder accepts decimal digits only and converts them to `UInt64`; this preserves values above JavaScript's exact integer range, including `UInt64.max`. `parentRevision` is omitted when absent, as are optional mutation `reps` selectors and absent `repCount` bounds. JSON `null` is not emitted for these absent values. All other keys in the example are required.

Mutation objects use `kind` as their discriminator. `joints` contains exact `LandmarkType.rawValue` names; `side` is `left` or `right`. A missing `reps` selector means every repetition; a supplied selector is a nonempty, duplicate-free list of one-based repetition numbers.

| `kind` | Required payload | Meaning |
|---|---|---|
| `jointOffset` | `joints`, `dx`, `dy`, `peak`, `rise`, `fall`, `strength` | Offset the named joints by `dx`/`dy` body-heights, shaped by the raised-cosine influence. |
| `depthScale` | `scale`; optional `reps` | Scale hip and knee travel from the standing pose on selected repetitions. |
| `asymmetry` | `side`, `amount` | Lower or raise one side of the hips as squat depth changes. |
| `tempo` | `scale`; optional `reps` | Multiply each selected guide cycle's duration. |
| `pause` | `at`, `duration` | Insert a hold at `at` on the pre-insertion, tempo-scaled clock. |
| `frameGap` | `at`, `duration` | Omit frames in a half-open output-clock interval. |
| `dropout` | `joints`, `from`, `to` | Remove the named landmarks in a half-open output-clock interval. |
| `confidence` | `joints`, `from`, `to`, `value` | Set confidence in a half-open output-clock interval. |
| `framing` | `scale`, `offsetX`, `offsetY` | Scale and translate the pose in the image. |

Assertion objects also use `kind` as their discriminator:

| `kind` | Required payload | Optional payload |
|---|---|---|
| `repCount` | At least one of `equals`, `min`, or `max` | `equals` is exclusive with `min`/`max`; a range can use either endpoint or both. |
| `rejection` | `reasonContains`, `countMin` | — |
| `formSignal` | `id`, `present` | — |
| `framing` | `state`, `reached` | — |
| `spokenCue` | `textContains`, `present` | — |

The reserved result object has `scenarioID`, `revision`, `outcome` (`passed`, `failed`, `inconclusive`, `invalid`, or `notRun`), `observed`, `assertionResults`, and `invalidReasons`. `observed` has optional `reps` and arrays `rejections`, `signals`, `framingChanges`, and `cues`. Each assertion result has its zero-based `assertionIndex`, `passed`, and `detail`. The runner evaluates frozen assertions against pipeline or coach observations. Generation failures are `invalid`; spoken-cue assertions in pipeline mode are `inconclusive`.

### Timeline, units, and generation order

`reps` is a count; times are seconds. Each scenario begins with a 1.5-second Ready hold, then repeats guide keyframe movements and holds. Tempo multiplies cycle durations; composite tempo factors apply in mutation-array order, normalize each duration and cumulative addition to the nearest nanosecond, and reject overflow or underflow. Repetition selectors are one-based. Total duration includes tempo and pauses and may not exceed 120 seconds.

There are two clocks. `pause.at` uses the tempo-scaled clock before pauses, inclusive from zero through its end. `jointOffset.peak`, `dropout.from/to`, `confidence.from/to`, and `frameGap.at` use the output clock after pauses. Clock positions are bounded by the 120-second scenario limit; dropout, confidence, and frame-gap intervals are `[start, end)`, and a frame-gap endpoint must not exceed sequence end. Joint-offset influence is zero at its rise/fall edges and one at `peak`; a zero-width side contributes only at the peak. Pause samples hold the guide pose at insertion.

Frames are sampled at `n / 30` seconds from zero through `ceil(duration × 30) / 30`; timestamps are `startingTimestamp + elapsed`. One body-height is the vertical pixel span (`maxY - minY`) of available joints in the depth-scaled rendered guide pose before jitter and other mutations. Offset, asymmetry, and framing translations use this scale. Inclusive numeric bounds: `jointOffset` dx/dy ±0.5 body-heights, peak 0–120 s, rise/fall 0–10 s, strength 0–1; depth/tempo scales 0.3–2; composite depth scale per selected repetition 1/16–16; asymmetry and framing offsets ±0.5 body-heights; framing scale 0.3–2; confidence 0–1; pause, frame-gap, dropout, and confidence intervals at most 10 s. Constrained joint offsets over 0.3 body-heights are invalid.

For selected Air Squat repetitions, depth scaling changes `LegPose.hipDrop`; for Push-Up it scales the arm angles from the straight-arm start. Stages run in order: seeded pixel jitter, asymmetry, local offsets, constrained projection, framing, confidence overrides and landmark dropout, then frame-gap omission. Mutations in a stage follow JSON order. Constrained projection targets bone lengths from the depth-mutated pose, keeps declared planted joints fixed (Air Squat ankles, Push-Up wrists), and rejects an offset if it cannot retain at least half of the nonzero requested displacement while each available connected bone stays within 3% of its reference. Offsets to planted joints are invalid. Asymmetry-modified hips resist projection; unaffected joints may compensate. Raw mode keeps requested displacements without projection. The caller supplies creation and frame-start timestamps; jitter uses the decimal `UInt64` seed. Identical inputs reproduce the same frames and recording lines.

Movement Lab landmarks are synthetic inputs. They can test analyzer behavior given those coordinates, but they never establish the accuracy of Apple Vision's camera-to-landmark estimates.

### Scenario coverage

The Movement Lab **Scenario coverage** view groups stored scenario revisions into an exercise-by-category matrix. Each cell shows the latest recorded outcome for each scenario id and revision; an empty cell is labeled **not tested**. This is scenario coverage, not code coverage. Filters narrow the matrix by exercise, category, and outcome. Open a populated cell to see its scenarios and stored keyframe comparisons.

Keyframes are selected from the saved recording. Joint offsets use their configured peak time; depth and asymmetry use the frame with the greatest hip drop or side difference; framing and canonical motion use a representative deepest pose. A depth mutation limited to selected repetitions searches only those cycles, locating their timing from reference poses or stored rep events. Pause uses its insertion boundary. Dropout and confidence use the start of their affected window, frame gaps use the first frame after the gap, and tempo uses a repetition boundary. Each thumbnail names the mutation type and time, highlights affected landmarks, and opens playback at that timestamp. A scenario without a materialized recording shows that its keyframe is unavailable rather than substituting a generic image.

### Hybrid movement editor

**Edit movement** opens a stored plan, recording, and reference sample from playback or coverage. Presets add supported mutations; dragging a joint adds a bounded `jointOffset` whose peak is the selected time. The editor supports constrained/raw generation modes, pipeline/coach execution, side-by-side/overlay/difference comparison, and one shared timeline for phase, reps, rejections, tracking, and cues.

The browser is only a preview of stored samples; it does not run the Swift generator, projection, or analyzer. **Save and rerun in Swift** writes `diagnostics/movement-lab/edits/<edit-id>/plan.json`, validates it with the shared schema, then uses the fixed-argument CLI runner to create a run under `diagnostics/movement-lab/runs/`. POSTs require the viewer's `x-fmp-replay` header and per-page nonce.

Each save keeps the scenario ID, increments its revision, records `parentRevision` and `editNote`, and copies assertions unchanged. Changing assertions requires an `assertionChangeReason`; the editor never rewrites them after seeing a run. Edit plans are unique and atomic; reruns serialize and use the CLI timeout and process-group termination.

## Movement Lab review and promotion

Review a materialized scenario in the Runs view after inspecting its expected assertions and observed result. Add a short review note, then choose **Approve**, **Reject**, **Keep exploratory**, or **Edit and rerun**. Approval is available only when the stored result passed every frozen assertion. The review status, note, timestamp, source run, and SHA-256 hash of the stored scenario definition are written atomically under the git-ignored `diagnostics/movement-lab/reviews/<run-id>/`. A new run or changed scenario content has separate review state; an edit does not carry approval forward.

**Promote approved fixture** appears only for an approved revision. The confirmation dialog names the output path and states that recording frames are excluded. After confirmation, the viewer server prints a one-time 6-digit code to its own stdout (the terminal running the viewer). The person must type that code into the browser prompt and submit it with the one-use token. The token and code expire after 60 seconds; the code is single-use, and five incorrect attempts require a fresh code. The code is never returned in an HTTP response or stored in API-served logs. Promotion rechecks the stored run, scenario content hash, execution mode, revision, passing assertions, approved status, and synthetic Movement Lab recording marker. The fixture contains the execution mode, plan with that scenario, frozen assertions, observed results, and approval provenance. It contains no recording or frame data. Existing fixture paths are immutable; approve a newer scenario revision to create a separate `.r<revision>.json` file. Only the explicit browser review workflow exposes promotion; the CLI and MCP entry points do not.

This code proves that a person at the viewer's terminal supplied the code. Any local process with file access could still write a fixture directly. Fixtures reach CI only through a reviewed commit.

`MovementLabRegressionTests` reads every JSON fixture under `PostureAnalysisApp/Tests/Fixtures/MovementScenarios/approved/` relative to its source file, regenerates it with `MovementGenerator`, and runs it through `MovementLabRunner` using the fixture's stored `pipeline` or `coach` execution mode. It compares the generated observations and assertion results with the reviewed result. A checkout without approved fixtures passes this test without adding bundle resources. Review fixture assertions and observations when updating an exercise guide or analyzer; keep exploratory run artifacts in ignored diagnostics storage.

## Copy report

`WorkoutRecordingReport` turns a recording into plain text sized for a chat (a few to about 15 KB). It reads the file twice: once for everything but frames, then only the frames it shows.

- A header line: title, start time, length, frames (and frames that never reached the coach), and how it ended. Then the coordinate space and the framing rules, and for each exercise its required joints, effective framing grace, and full tuning.
- **Timeline:** commands (with their source and heard phrase), phase and rep-count changes, tracking lost (with the framing guidance) and back, bridged bottom dropouts, tips, everything the coach said, camera, app, and audio events, and markers.
- **Windows:** every tracking loss, from 1 s before to 1 s after it ends (at most 3 s of the loss), and every marker, from 8 s before to 2 s after. Overlapping windows merge. Each row, at 5 Hz plus any frame where framing changes or a rep is counted, shows the time, framing, the counting flag, each focus joint as confidence then x,y (`lo.28` below the floor, `--` not seen, `est` estimated), and the analyzer readings.

## File format: `fmp.workout-session/1`

A JSON array (`.json`) with one record per line, appended as the workout runs; each record is an object with its kind in `k`. A serial utility queue writes buffered lines every second, past 256 KB, and on markers and end; backgrounding waits for pending writes. Each comma is written before the next record, so a closed file is valid JSON. A crash can lose at most the last second and leave `]` missing; no `end` record means incomplete. Readers skip brackets, remove trailing commas, ignore unknown kinds, and tolerate a cut-off last line. Older JSON Lines files read the same way.

```json
[
{"k":"header","schema":"fmp.workout-session/1",...},
{"k":"pipe","t":0.36,"control":"exercise","exercise":"push_up",...},
{"k":"f","t":13.07,"ts":383167.75,"j":[[749.4,882.1,0.35],null,...],...},
{"k":"end","t":57.9,"reason":"workoutEnded",...}
]
```

Times: `t` is seconds since the recording began, on the coach's clock. Frame lines also carry `ts`, the camera timestamp that analyzers and rep events use; never mix the two. Joints are unmirrored image pixels with the origin at the top left (the analysis space), written exactly; derived values are rounded to 4 decimal places.

| `k` | When | Fields |
|---|---|---|
| `header` | First line | `schema`, `kind` (`workout`), `id`, `startedAt` (with offset), `timeZone`, `app`, `device`, `camera` (`analysisHz`, coordinate space, `previewMirrored`), `jointOrder` (19 names; frame joints use this order), `confidenceFloor`, `settings`, `plan` (per item: `id`, `exercise`, `sets`, `reps`, and `reducedRange`, `optional`, `bonus`, and `easierSwap` only when true, so a plan without them runs the full range and is required; the header's plan is written before any bonus or easier version is inserted), `exercises` (per id: name, camera view, sets and reps, required, any-of-required, focus, and planted joints, room checks, flags, the full `configuration`, and every cue; a plan that runs a smaller-range variant adds `<id>.reducedRange` with that variant's own entry), `framing`, `offscreen`, `cueScheduler`, `constants` |
| `pipe` | A pipeline control that changed something | `control` (`sessionPhase`, `exercise`, `resetAnalyzer`, `counting`, `resetTracking`) and its values. An `exercise` control for a smaller-range variant adds `variant: "reducedRange"`; replay then runs that variant's own recorded configuration, and a control without `variant` runs the full range |
| `f` | Every frame the coach received | `ts`, `seq`, `delay` (seconds the frame waited between pose estimation and reaching the coach; long after a main-thread stall; the coach placed the frame at `t − delay`), `p` (false when nothing analyzed it: no exercise was selected, or the frame was captured before the latest Start, Resume, or analyzer change), `cnt` (counting flag), `wh` (image size, when it changes), `j` (`[x, y, confidence]` or null per joint), `lo` (`[index, x, y, confidence]` for joints below the floor), `est` (`[index, x, y]` for joints estimated past the edge), `pitch`, `fr` (framing `ok` and guidance `g`), `out` (this frame's pipeline events: `rep`, `framing`, `start`), `rd` (per-side `signal`, `elbow`, `zone`), `th` (per-side Start and Top lines `[x1, y1, x2, y2]`, `locked`, `confirmed`), `sig` (continuous form signals), `forms` (rep attempts judged), `fv` (form readings), `end` (sides at the counted end), `start` (start position held), `rej` (attempts the analyzer let go on this frame: `ts`, `side` when the exercise counts sides separately, `reason` `tooFast` (`duration`, `minimum`), `partialEnd` (`reached`), `trackingGap` (`seconds`, `maximum`, `stage`), `countingStopped`, `sideSwitched`, or `referenceExpired` (`stage`: `moving` or `reachedEnd`)) |
| `state` | After any reducer input or coach change, only when different | `phase`, `ex`, `planIndex`, `set`, `side`, `reps`, `sideReps`, `counting`, `epoch`, `framing`, `restEnds`, `tilted`, `tip`, `speaking`, `mic`, `coachMuted`, `micMuted`, `camera` |
| `e` | A discrete event | `type`: `command` (`command`, `source` voice or touch, heard `phrase`), `speak` (`text`, `muted`), `repeatLast`, `tip` (`cue`, `kind`, `text`), `tip.cleared`, `clearFeedback`, `rep`, `framing`, `startPosition`, `tilt`, `opened`, `bonus` (`id`, `after`, `amount`: a bonus set was inserted), `easierSwap` (`id`, `after`, `exercise`, `reducedRange` only when true, `amount`: the easier version of an item was inserted after it; the `command` event for "Too hard?" reads `tooHard`, and "Stop here" on a standalone exercise reads `stopItem`), `app.background`, `app.foreground`, `interruptionBegan`, `interruptionEnded`, `voiceControl`, `camera.running`, `camera.interrupted` (`reason`: the numeric `AVCaptureSession` interruption reason when supplied), `camera.failed`, `audio.interruptionBegan`, `audio.interruptionEnded`, `audio.interruption` (`interruption`, numeric `reason` when supplied, `wasSuspended`, and `shouldResume` when ended), `audio.route` (`reason`: numeric `AVAudioSession` route-change reason, `outputs` and `inputs`: current port types), `audio.session` (`operation`: `setCategory` or `setActive`, current category, mode and options, plus `isOtherAudioPlaying` and `secondaryAudioShouldBeSilenced`; `active` and `activeOptions` apply to `setActive`), `audio.work` (`step`, `ms`: measured elapsed audio-step duration, and `execution` (`main` or `worker`); the viewer warns for main-thread work of 100 ms or more, labels worker work as "Audio session work", and preserves the old warning behavior for recordings without `execution`), `ui.guide`, `ui.help`, `ui.measurements` |
| `marker` | A marker | `t` (recorded), `heardAt` (when its trigger was heard, if different), `id`, `source` (`tap` or `voice`), `text`, `ctx` (the latest `state` line and the last 20 events) |
| `note` | A later note on a marker | `id`, `markerID`, `text`; the newest note for a marker wins |
| `end` | Last line | `endedAt`, `reason` (`workoutEnded`, `closed`, or `timeLimit`), `frames`, `seqGaps` (frames the camera produced that never reached the coach), `workoutRecordID` |

Recordings may include `framing` on each exercise entry, with its effective framing configuration after any exercise override. Older recordings omit it; readers use the session-level `framing` values. Frame records may include `info`, an array of informational analyzer events. `bottomDropoutBridged` carries `level: "info"`, capture timestamp `ts`, gap length `seconds`, and the allowed `maximum`. These optional fields extend schema version 1; recordings without them keep their previous behavior.

A frame line is about 1.5 KB (the 19 exact joints are about 1 KB of it): roughly 0.9 MB per minute at 10 Hz.
