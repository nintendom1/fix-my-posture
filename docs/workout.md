# Workout Coach (Beta)

Open **Workout Coach (Beta)** from the main menu. The first time, a short guide shows and describes the dumbbell shoulder press. Then prop the phone up in portrait, step back so the front camera can see both arms and your shoulders with room overhead, and follow the spoken setup. The coach counts reps for a standing dumbbell shoulder press (2 sets of 8–10), announces the target range and set completion, and keeps the screen awake while it is open.

Rep counts and framing checks are geometric heuristics from a 2D camera. They are not medical, injury, or performance assessments.

## Privacy

Everything runs on device. Apple Vision estimates the pose and `AVSpeechSynthesizer` speaks. Frames are processed in memory at 10 Hz and never recorded, saved, or transmitted. The workout has no networking or analytics.

## Architecture

- `Workout/Exercises`: `ExerciseCatalog.all` is the visible exercise list. Each `ExerciseDefinition` supplies a stable `ExerciseID` (for example `shoulder_press`), sets, target reps, required joints, overlay focus segments, the setup line, an `ExerciseGuide`, and an analyzer factory. To add an exercise, add one folder and one catalog line.
- `Workout/Analysis`: `PoseFrame` (reliable, unmirrored pixel pose plus capture timestamp), `ArmGeometry`, `HysteresisPhaseTracker`, `FramingEvaluator`, and the display-only `LandmarkSmoother` (One Euro filter).
- `Workout/Session`: `WorkoutSession` is a pure reducer, `handle(_ event:at:) -> [WorkoutEffect]`. `WorkoutCoachModel` is the main-actor orchestrator. It depends only on the `PoseFrameSource`, `ExerciseAnalyzing`, and `SpeechCoaching` protocols, so test fakes can be injected.
- `Workout/Camera`: `WorkoutCameraController` uses the shared `PortraitCameraSession` configuration, the same configuration as realtime posture correction. It has one serial queue, a 10 Hz gate on sample timestamps, synchronous `FramePoseEstimator` inference, and the existing 0.3 confidence filter. Frames reach the main actor through one lock-protected pending slot: at most one hop is in flight, newer frames replace older ones, and no buffers are retained. Vision code stays in `AppleVisionPoseEstimator`.
- `Voice`: `SpeechCoach` and `WorkoutAudioSession`.
- `Views/Workout`: `WorkoutCoachView`, `WorkoutHUDView`, `WorkoutJointOverlayView`, `ExerciseGuideView`, `ExerciseDemoFigureView`, and `WorkoutGuideOverlayView`.

## Guidance

The guide and the live overlay share one description of the movement. `ExerciseGuide` holds the steps, the read-aloud walkthrough, the start-position instruction, the counting-threshold lines, and an `ArmMotion`: looping keyframes of upper-arm and forearm elevation. `ArmMotion.place` turns those angles into elbow and wrist points, measuring "outward" as away from the other shoulder. That makes the same keyframes work for the canonical demo figure and for the user's own mirrored body.

- **First-time guide.** The guide sheet opens automatically the first time each exercise is shown, and before the camera starts, so the permission prompt never covers it. An animated front-view figure with two dumbbells (drawn with the posture `AlignmentReferenceOverlayView` silhouette) loops start → press → lower, and the matching step is highlighted. **Start Workout** (or swiping the sheet down) goes straight to setup. **Read Aloud** speaks the steps through `SpeechCoach`, so other audio is ducked and restored. With Reduce Motion, the start and top positions are shown side by side. The guide is remembered per exercise (`workoutCoach.guideSeen.<id>`), so returning users skip it.
- **On demand.** Tapping the exercise title in the HUD, or **How to Do It** in the exercise menu, reopens the guide. Like realtime Details, it stops capture while open. An active set pauses, and stays paused after **Back to Workout**.
- **Ghost demo.** While ready, translucent violet ghost arms with dumbbells loop the same motion. They're anchored to the user's smoothed shoulder dots and scaled to their smoothed, measured arm segments (typical proportions are used until measured). The status line reads "Hold the dumbbells just above your shoulders to begin".
- **Auto-start.** While ready, holding the start position (both arms confirmed at the bottom) for 1 s begins the set with "Set 1 of 2. Go." After a rest, this works only once the rest timer has ended. The Start button always works.
- **Threshold lines.** During a set, each arm gets a short **Start ↓** and **Top ↑** segment, drawn from the analyzer's own per-arm thresholds, so the user sees exactly what counts. A rep begins and ends at Start and turns around at Top. The checkpoint an arm is heading toward is bright and dashed, the other is dim, and a segment turns solid once that arm reaches it (cyan for Start, green for Top). The heights are locked at the start position for each rep (see the rep rule), so the segments hold still while you press.
- **Phone tilt.** `CoreMotionTiltMonitor` reads the phone's forward/back lean from gravity at 10 Hz while the camera runs. A lean of more than 15° for 1 s shows "Phone tilted: stand it upright" under the title and speaks a warning (at most every 30 s); it clears below 10°. A leaning phone squashes or stretches heights unevenly, more so up close. The warning is advisory and never blocks a set.
- **Show Measurements.** This exercise-menu toggle is off by default and remembered. It shows each arm's live height ratio, elbow angle, and zone (↓ bottom, ↑ top, ◌ between), for tuning thresholds on device.

Analysis always uses the original unmirrored pixel geometry. Only the overlay is mirrored for the selfie preview, then smoothed. Overlay and preview share aspect-fit bounds through `CoordinateConverter`.

## Session state machine

Phases: `choosingExercise`, `framing`, `ready`, `exercising`, `paused(user | background | interruption)`, `resting`, `changingExercise(previous)`, `exerciseComplete`, and `ended`. With one exercise, the coach opens in `framing` with shoulder press selected.

Tracking reliability is a separate input. While exercising and unreliable, counting is suspended without changing phase. Framing guidance is spoken once per loss, and counting resumes automatically.

| Command | Behavior |
|---|---|
| Start | From framing or ready, begins the set; counting still waits for reliable tracking. From paused, resumes. From resting, starts the next set. Holding the start position for 1 s does the same while ready, and after rest once the timer ends. |
| Pause | Pauses only while exercising. Elsewhere it changes nothing and gives a short spoken hint. |
| Resume | Acts only from paused. Harmless while exercising. |
| Restart set | Resets the current set's reps and starts a fresh analyzer. Nothing else changes. |
| Next set | While exercising or paused, completes the set and rests. From resting, starts the next set. After the last set, the exercise is complete. |
| Exercise menu | Selecting another exercise discards an in-progress set (finished sets are kept per exercise) and clears the analyzer, smoothing, and feedback. |
| End | Asks for confirmation when tapped. Then stops the camera, restores other audio, and shows a summary with a Done button. |

Backgrounding the app or locking the phone pauses an active set with the matching reason and stops the camera. On return the set stays paused, and the coach says "Paused. Tap Resume when ready." Camera and audio-session interruptions pause the same way.

Stale events are dropped. Every analyzer instance carries an epoch, and the session ignores reps from replaced analyzers. Camera events carry a generation, so results from an old capture start are discarded.

## Framing

`FramingEvaluator` uses each exercise's required joints. For shoulder press those are both shoulders, elbows, and wrists at confidence ≥ 0.4. Hips aren't required, so users can stand closer for steadier tracking; when visible, they still help center the left/right guidance.

- Tracking becomes reliable after the required joints stay visible for 0.6 s. It becomes unreliable after they are missing for 0.3 s.
- Guidance, in order: step into view; step back until both arms and shoulders are visible; leave room above the hands; move a little left or right.
- Headroom for the press: the top shoulder's y minus 1.05 × the longer measured arm length (upper arm + forearm, in pixels) must stay at least 2% of the image height inside the frame.
- Left/right guidance is worded relative to the user. It is derived from unmirrored x, where the front camera's x grows toward the user's left, with a ±17% center tolerance.
- Guidance is spoken after it holds for 1 s. The same line repeats at most every 20 s.

## Shoulder press rep rule

The press is filmed from the front, using pixel geometry and an independent hysteresis tracker per arm. All thresholds live in `ShoulderPressConfiguration` and are prototype heuristics to tune on device.

- Signals: `h` = wrist height above the shoulder in that arm's own length (upper arm + forearm), and the 2D elbow angle.
- The ruler is the moving arm itself, so the rule is the same at any distance and for any body proportions, and it never needs the hips. Each arm's ruler is its longest measured length over the last second, which resists momentary foreshortening when an arm points toward the camera.
- Start when `h ≤ 0.6`, elbow ≤ 115°, and the forearm points up (wrist above elbow). Top when `h ≥ 0.8` and elbow ≥ 140°. For a straight arm `h` is the sine of its elevation, so the top needs a straight arm at least about 53° above horizontal and side raises don't count. Each checkpoint needs 2 consecutive 10 Hz samples. Samples between the thresholds never change the confirmed checkpoint.
- Locked reference: while an arm sits at the start, its smoothed shoulder height and ruler are refreshed. Once the arm leaves the start, they're locked until it returns, so shoulders lifting during the press don't move the target. Stepping closer or farther between reps re-measures at the next start. A lock held longer than 6 s is dropped, and so are locks after a tracking gap.
- History: the first prototype measured `h` in torso lengths (shoulder midpoint to hip midpoint), with thresholds of 0.25 and 0.55. The standard start never registered as the bottom, and the torso ruler depended on hip detection and drifted with the shoulders. It was retuned and then replaced by the arm ruler.
- Self-checks (simulated, at 10 Hz): the guide's own demonstration reads `h` 0.38 / 82° at the start and 0.96 / 164° at the top, and counts exactly one rep per loop. Readings are identical at ½×, 2×, and 3× scale. Long-upper-arm, long-forearm, and short-arm proportions all count every rep, as does a pose with no hips. With the shoulders lifting 15% of an arm length at the top, the locked Top line doesn't move.
- A rep counts when both arms reach the top within one cycle and both return to the bottom, and the cycle took at least 0.8 s.
- A gap longer than 0.28 s between complete samples (two dropped samples at the 100–133 ms cadence) invalidates the cycle, so a fresh start is required. Movement done out of view never counts. Pausing or losing tracking has the same effect.
- The set announces "You're in the target range" at 8 and completes automatically at 10. Other reps are not spoken.

## Overlay and HUD

- The ghost demo (ready) and threshold lines (during a set) are drawn beneath the joints. See [Guidance](#guidance).
- The overlay draws only the focus segments (each shoulder→elbow→wrist chain plus thin shoulder and hip lines) and their joints. Joints are cyan when tracked and green while that arm holds the counted top position. Joints missing for up to 0.3 s turn muted gray, then disappear. The overlay never uses red.
- The top HUD stays small to preserve overhead room: close, exercise name (tap for the guide), and status. The bottom HUD shows the rep count against the target (it pulses on each counted rep), set progress, a rest countdown (90 s for the press), optional measurements, and controls: start/pause/resume, restart set, next set, the exercise menu (exercises, How to Do It, Show Measurements), and end. Both HUD regions publish their frames for later layout work.
- The idle timer is disabled while the screen is open.

## Speech and audio

- `SpeechCoach` keeps a short utterance queue: at most 2 pending lines, older ones dropped. It remembers the last instruction for "repeat that". Delegate callbacks (start, finish, cancel) advance the queue. A watchdog stops any utterance that runs past its estimated duration + 5 s.
- `WorkoutAudioSession` uses `.playback` with `.mixWithOthers`, so music keeps playing. Before speaking, it adds `.duckOthers` and activates. When the queue drains, `endDucking()` deactivates with `.notifyOthersOnDeactivation` and restores the non-ducking category. It retries briefly if deactivation reports busy.
- `endDucking()` is idempotent and runs on every exit path: speech finished or cancelled, the watchdog, activation errors, interruptions, backgrounding, leaving the screen, and ending the workout. If the app crashes, iOS releases its audio session, which restores other audio.

## Future options

- `VNDetectHumanBodyPose3DRequest` (iOS 17) could reduce front-view foreshortening of elbow angles.
- RTMPose would need a bundled model, a person detector, and Core ML conversion. That is a lot of added work for little gain on front-view arm joints.

## Physical-device checklist

Simulator tests cannot validate the camera, Vision detections, speech, or audio ducking. On an iPhone 15 Pro (`make ios`):

1. On a fresh install (deleting the app resets the guide), opening the coach shows the guide before any permission prompt. Read Aloud lowers your music and then restores it. Start Workout leads to the camera. Reopening the coach skips the guide. The ⓘ title reopens it, and doing so mid-set pauses the set.
2. Grant camera access and follow the framing guidance. Verify the headroom prompt when standing too close, and the left/right prompts.
3. When ready, the violet ghost arms line up with your shoulders and roughly match your arm length. Holding the dumbbells just above your shoulders for about 1 s starts the set. During rest it never starts before the timer ends.
4. Turn on Show Measurements. At the start position, each arm should read below 0.6 and 115° (↓). At the top, above 0.8 and 140° (↑). Do the same press close to the phone and far from it: the readings should be about the same. Each arm's Start segment turns solid at the start, and its Top segment turns solid green only once the wrist passes it with the arm nearly straight. The segments shouldn't drift while you press.
5. Lean the phone back more than 15°: after about a second, the tilt warning appears and is spoken. Stand it upright and the warning clears.
6. Do 10 presses and check that the count is exactly 10, with no double counts when pausing near either threshold. A half press must not count, and neither must a rep finished after stepping out of view mid-rep.
7. Background the app or lock the phone mid-set. The set must be paused on return, with no added reps. Then resume.
8. Leave the screen idle for longer than the auto-lock interval and confirm it never locks.
9. With Spotify or Music playing, the music must lower only while the coach speaks and must never stay lowered, including after ending the workout or closing the screen mid-sentence.
10. Afterward, confirm realtime posture correction still works.

These checks remain manual; a passing simulator run does not imply they were performed.
