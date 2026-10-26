# Workout Session Recordings (Developer)

A developer recording captures one workout in detail, so a problem can be described with data instead of from memory: every analyzed camera frame's joints, what the analyzer and framing decided, the coach's state, and everything it said and heard. Recordings are for developing the app. They never include camera images.

## Recording

- **Settings › About › Developer diagnostics › Workout recordings.** The **Record workouts** toggle is on by default in Debug builds (what `make ios` installs) and off in Release builds (`dev.workoutRecordingEnabled`). `WorkoutCoachFactory` reads it when a workout starts, so a change applies to the next workout.
- While recording, a **REC** chip sits beside the microphone chip. Tapping it drops a **marker** at that moment: the chip shows "Marked 1:56" for 3 s and the coach says "Marked." (silently when the coach is muted). Mark the moment something went wrong, such as a rep that should have counted.
- The page lists recordings newest first with their exercises, length, markers, and size. **Share** sends the file under a readable name such as `FMP Push-Up 2026-10-25 2119.json` (AirDrop, Files; it previews as text). **Copy report** copies a text report with the data needed to diagnose a problem (see below). Recordings can be deleted one at a time, or all those without markers.
- **Size and retention.** A recording takes about 0.9 MB a minute, so a 6-minute starter routine is about 5.5 MB. Each recording stops after 60 minutes (`WorkoutSessionRecorder.maximumDuration`; the workout carries on unrecorded and the REC chip disappears). The newest 20 recordings are kept (`FileWorkoutRecordingStore.maximumRecordings`): beyond that the oldest without markers are removed first, then the oldest with markers, so 20 starter routines take roughly 110 MB and the worst case is about 1.1 GB. The recording in progress is never pruned. A recording that never received a camera frame is deleted when it ends.
- **Crash recovery.** A summary says complete only after the writer confirms the end line reached the file. A recording without a complete summary (a crash, force-quit, or full disk) is counted from its file the next time recordings are listed, so its markers still protect it.
- **Pulling to a Mac.** `make diagnostics` copies every recording from the phone (the device and bundle identifier from `ios.local.env`, as for `make ios`) into `diagnostics/sessions/` and lists the newest. The phone must be connected or paired and unlocked.

## Data rule

Recordings are measurements of a real person's body, and this repository is public.

- `diagnostics/`, shared copies (`FMP *.json`), and the older `*.jsonl` and `*.fmpsession` files are gitignored. Never commit a real recording, and never paste one into an issue, pull request, or other public place unless the developer explicitly asks.
- To keep a fix from regressing, commit a synthetic test (for example the guide demonstration with the failing values) rather than the recording.

## Architecture

- `Workout/Diagnostics/`: `WorkoutSessionRecording` (the protocol `WorkoutCoachModel` calls), `WorkoutSessionRecorder` (main-actor, cheap per call), `WorkoutSessionLines` (each line kind), `DiagnosticJSON` (an ordered, compact JSON writer whose numbers read back exactly), `FileWorkoutSessionWriter` (a serial `.utility` queue that buffers lines and appends them to the file every second, past 256 KB, and on markers and the end; backgrounding waits until everything is written), `FileWorkoutRecordingStore` (files, summaries, pruning), and `ExerciseDiagnostics` (each exercise's configuration as JSON, and a rebuild from a recorded configuration).
- `WorkoutCoachModel` sends every reducer input through one `dispatch`, so each recordable input is written with the state it led to, and every pipeline change through `applyControl`, which records a `WorkoutFramePipeline.Control` only when it changes the pipeline. A replay that applies the same controls in the same order rebuilds exactly the pipeline the phone had.
- `WorkoutFramePipeline.collectsDiagnostics` adds `FrameDiagnostics` to each output: the frame framing and the analyzer saw (with joints estimated past the edge), this frame's framing result, the counting flag, and the full `ExerciseAnalysis`. It is off unless a recorder is present, so an unrecorded workout does no extra work.
- `WorkoutCameraController` numbers accepted frames (`PoseFrame.sequence`) and keeps the joints the 0.3 confidence floor removed (`PoseFrame.lowConfidenceLandmarks`). Analysis never reads them.
- The recording's id is the saved `WorkoutRecord.id`, so a history entry and its recording match. A workout with no finished set saves no history entry.
- Files: `Application Support/Diagnostics/Workouts/<uuid>.json` with `<uuid>.summary.json`. The folder is excluded from backups. Older JSON Lines recordings (`.jsonl`, `.fmpsession`) are converted when listed or pulled. Shared copies are hard links under readable names in the temporary folder.

## Copy report

`WorkoutRecordingReport` turns a recording into plain text sized for a chat (a few to about 15 KB). It reads the file twice: once for everything but frames, then only the frames it shows.

- A header line: title, start time, length, frames (and frames that never reached the coach), and how it ended. Then the coordinate space and the framing rules, and for each exercise its required joints and full tuning.
- **Timeline:** commands (with their source and heard phrase), phase and rep-count changes, tracking lost (with the framing guidance) and back, tips, everything the coach said, camera, app, and audio events, and markers.
- **Windows:** every tracking loss, from 1 s before to 1 s after it ends (at most 3 s of the loss), and every marker, from 8 s before to 2 s after. Overlapping windows merge. Each row, at 5 Hz plus any frame where framing changes or a rep is counted, shows the time, framing, the counting flag, each focus joint as confidence then x,y (`lo.28` below the floor, `--` not seen, `est` estimated), and the analyzer readings.

## File format: `fmp.workout-session/1`

A JSON array (`.json`) with one record per line, appended as the workout runs; each record is an object with its kind in `k`. Each record's comma is written just before the next one, so a closed file is valid JSON. A crash loses at most the last second and leaves the closing `]` missing, and a file without an `end` record is incomplete. Readers take a file line by line: they skip the brackets, drop each line's trailing comma, ignore unknown kinds, and skip a last line cut short. Older JSON Lines recordings read the same way.

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
| `header` | First line | `schema`, `kind` (`workout`), `id`, `startedAt` (with offset), `timeZone`, `app`, `device`, `camera` (`analysisHz`, coordinate space, `previewMirrored`), `jointOrder` (19 names; frame joints use this order), `confidenceFloor`, `settings`, `plan`, `exercises` (per id: name, camera view, sets and reps, required, any-of-required, focus, and planted joints, room checks, flags, the full `configuration`, and every cue), `framing`, `offscreen`, `cueScheduler`, `constants` |
| `pipe` | A pipeline control that changed something | `control` (`sessionPhase`, `exercise`, `resetAnalyzer`, `counting`, `resetTracking`) and its values |
| `f` | Every frame the coach received | `ts`, `seq`, `p` (false when no exercise was selected, so nothing analyzed it), `cnt` (counting flag), `wh` (image size, when it changes), `j` (`[x, y, confidence]` or null per joint), `lo` (`[index, x, y, confidence]` for joints below the floor), `est` (`[index, x, y]` for joints estimated past the edge), `pitch`, `fr` (framing `ok` and guidance `g`), `out` (this frame's pipeline events: `rep`, `framing`, `start`), `rd` (per-side `signal`, `elbow`, `zone`), `th` (per-side Start and Top lines `[x1, y1, x2, y2]`, `locked`, `confirmed`), `sig` (continuous form signals), `forms` (rep attempts judged), `fv` (form readings), `end` (sides at the counted end), `start` (start position held) |
| `state` | After any reducer input or coach change, only when different | `phase`, `ex`, `planIndex`, `set`, `side`, `reps`, `sideReps`, `counting`, `epoch`, `framing`, `restEnds`, `tilted`, `tip`, `speaking`, `mic`, `coachMuted`, `micMuted`, `camera` |
| `e` | A discrete event | `type`: `command` (`command`, `source` voice or touch, heard `phrase`), `speak` (`text`, `muted`), `repeatLast`, `tip` (`cue`, `kind`, `text`), `tip.cleared`, `clearFeedback`, `rep`, `framing`, `startPosition`, `tilt`, `opened`, `app.background`, `app.foreground`, `interruptionBegan`, `interruptionEnded`, `voiceControl`, `camera.running`, `camera.interrupted`, `camera.failed`, `audio.interruptionBegan`, `audio.interruptionEnded`, `ui.guide`, `ui.help`, `ui.measurements` |
| `marker` | A marker | `t` (recorded), `heardAt` (when its trigger was heard, if different), `id`, `source` (`tap` or `voice`), `text`, `ctx` (the latest `state` line and the last 20 events) |
| `note` | A later note on a marker | `id`, `markerID`, `text`; the newest note for a marker wins |
| `end` | Last line | `endedAt`, `reason` (`workoutEnded`, `closed`, or `timeLimit`), `frames`, `seqGaps` (frames the camera produced that never reached the coach), `workoutRecordID` |

A frame line is about 1.5 KB (the 19 exact joints are about 1 KB of it): roughly 0.9 MB per minute at 10 Hz.
