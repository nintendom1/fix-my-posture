# Workout Coach (Beta)

Open **Workout Coach (Beta)** from the main menu. Prop the phone up in portrait, step back so the front camera can see you from the hips up with room overhead, and follow the spoken setup. The coach counts reps for a standing dumbbell shoulder press (2 sets of 8–10), announces the target range and set completion, and keeps the screen awake while it is open.

Rep counts and framing checks are geometric heuristics from a 2D camera. They are not medical, injury, or performance assessments.

## Privacy

Everything runs on device. Apple Vision estimates the pose and `AVSpeechSynthesizer` speaks. Frames are processed in memory at 10 Hz and never recorded, saved, or transmitted. The workout has no networking or analytics.

## Architecture

- `Workout/Exercises`: `ExerciseCatalog.all` is the visible exercise list. Each `ExerciseDefinition` supplies a stable `ExerciseID` (for example `shoulder_press`), sets, target reps, required joints, overlay focus segments, the setup line, and an analyzer factory. To add an exercise, add one folder and one catalog line.
- `Workout/Analysis`: `PoseFrame` (reliable, unmirrored pixel pose plus capture timestamp), `ArmGeometry`, `HysteresisPhaseTracker`, `FramingEvaluator`, and the display-only `LandmarkSmoother` (One Euro filter).
- `Workout/Session`: `WorkoutSession` is a pure reducer, `handle(_ event:at:) -> [WorkoutEffect]`. `WorkoutCoachModel` is the main-actor orchestrator. It depends only on the `PoseFrameSource`, `ExerciseAnalyzing`, and `SpeechCoaching` protocols, so test fakes can be injected.
- `Workout/Camera`: `WorkoutCameraController` uses the shared `PortraitCameraSession` configuration, the same configuration as realtime posture correction. It has one serial queue, a 10 Hz gate on sample timestamps, synchronous `FramePoseEstimator` inference, and the existing 0.3 confidence filter. Frames reach the main actor through one lock-protected pending slot: at most one hop is in flight, newer frames replace older ones, and no buffers are retained. Vision code stays in `AppleVisionPoseEstimator`.
- `Voice`: `SpeechCoach` and `WorkoutAudioSession`.
- `Views/Workout`: `WorkoutCoachView`, `WorkoutHUDView`, and `WorkoutJointOverlayView`.

Analysis always uses the original unmirrored pixel geometry. Only the overlay is mirrored for the selfie preview, then smoothed. Overlay and preview share aspect-fit bounds through `CoordinateConverter`.

## Session state machine

Phases: `choosingExercise`, `framing`, `ready`, `exercising`, `paused(user | background | interruption)`, `resting`, `changingExercise(previous)`, `exerciseComplete`, and `ended`. With one exercise, the coach opens in `framing` with shoulder press selected.

Tracking reliability is a separate input. While exercising and unreliable, counting is suspended without changing phase. Framing guidance is spoken once per loss, and counting resumes automatically.

| Command | Behavior |
|---|---|
| Start | From framing or ready, begins the set; counting still waits for reliable tracking. From paused, resumes. From resting, starts the next set. |
| Pause | Pauses only while exercising. Elsewhere it changes nothing and gives a short spoken hint. |
| Resume | Acts only from paused. Harmless while exercising. |
| Restart set | Resets the current set's reps and starts a fresh analyzer. Nothing else changes. |
| Next set | While exercising or paused, completes the set and rests. From resting, starts the next set. After the last set, the exercise is complete. |
| Exercise menu | Selecting another exercise discards an in-progress set (finished sets are kept per exercise) and clears the analyzer, smoothing, and feedback. |
| End | Asks for confirmation when tapped. Then stops the camera, restores other audio, and shows a summary with a Done button. |

Backgrounding the app or locking the phone pauses an active set with the matching reason and stops the camera. On return the set stays paused, and the coach says "Paused. Tap Resume when ready." Camera and audio-session interruptions pause the same way.

Stale events are dropped. Every analyzer instance carries an epoch, and the session ignores reps from replaced analyzers. Camera events carry a generation, so results from an old capture start are discarded.

## Framing

`FramingEvaluator` uses each exercise's required joints. For shoulder press those are shoulders, elbows, wrists, and hips at confidence ≥ 0.4.

- Tracking becomes reliable after the required joints stay visible for 0.6 s. It becomes unreliable after they are missing for 0.3 s.
- Guidance, in order: step into view; step back until shoulders, elbows, wrists, and hips are visible; leave room above the hands; move a little left or right.
- Headroom for the press: the top shoulder's y minus 1.05 × the longer measured arm length (upper arm + forearm, in pixels) must stay at least 2% of the image height inside the frame.
- Left/right guidance is worded relative to the user. It is derived from unmirrored x, where the front camera's x grows toward the user's left, with a ±17% center tolerance.
- Guidance is spoken after it holds for 1 s. The same line repeats at most every 20 s.

## Shoulder press rep rule

The press is filmed from the front, using pixel geometry and an independent hysteresis tracker per arm. All thresholds live in `ShoulderPressConfiguration` and are prototype heuristics to tune on device.

- Signals: `h` = wrist height above the shoulder ÷ torso length (shoulder midpoint to hip midpoint), and the 2D elbow angle.
- Bottom when `h ≤ 0.25` and elbow ≤ 115°. Top when `h ≥ 0.55` and elbow ≥ 140°. Each end position needs 2 consecutive 10 Hz samples. Samples between the thresholds never change the confirmed end.
- A rep counts when both arms reach the top within one cycle and both return to the bottom, and the cycle took at least 0.8 s.
- A gap longer than 0.28 s between complete samples (two dropped samples at the 100–133 ms cadence) invalidates the cycle, so a fresh bottom is required. Movement done out of view never counts. Pausing or losing tracking has the same effect.
- The set announces "You're in the target range" at 8 and completes automatically at 10. Other reps are not spoken.

## Overlay and HUD

- The overlay draws only the focus segments (each shoulder→elbow→wrist chain plus thin shoulder and hip lines) and their joints. Joints are cyan when tracked and green while that arm holds the counted top position. Joints missing for up to 0.3 s turn muted gray, then disappear. The overlay never uses red.
- The top HUD stays small to preserve overhead room: close, exercise name, and status. The bottom HUD shows the rep count against the target, set progress, a rest countdown (90 s for the press), and controls: start/pause/resume, restart set, next set, exercise menu, and end. Both HUD regions publish their frames for later layout work.
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

1. Open the coach, grant camera access, and follow the framing guidance. Verify the headroom prompt when standing too close, and the left/right prompts.
2. Do 10 presses and check that the count is exactly 10, with no double counts when pausing near either threshold. A half press must not count, and neither must a rep finished after stepping out of view mid-rep.
3. Background the app or lock the phone mid-set. The set must be paused on return, with no added reps. Then resume.
4. Leave the screen idle for longer than the auto-lock interval and confirm it never locks.
5. With Spotify or Music playing, the music must lower only while the coach speaks and must never stay lowered, including after ending the workout or closing the screen mid-sentence.
6. Afterward, confirm realtime posture correction still works.

These checks remain manual; a passing simulator run does not imply they were performed.
