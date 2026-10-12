# Workout Coach (Beta)

Open **Workout Coach (Beta)** from the main menu. The first time, a short guide shows and describes the dumbbell shoulder press. Then prop the phone up in portrait, step back so the front camera can see both arms and your shoulders with room overhead, and follow the spoken setup. The coach counts reps for a standing dumbbell shoulder press (2 sets of 8–10), announces the target range and set completion, and keeps the screen awake while it is open. After the permission prompts, the whole workout can run by voice: say "start", "pause", "next set", and so on.

Rep counts and framing checks are geometric heuristics from a 2D camera. They are not medical, injury, or performance assessments.

## Privacy

Everything runs on device. Apple Vision estimates the pose, `AVSpeechSynthesizer` speaks, and the Speech framework recognizes commands with `requiresOnDeviceRecognition`. Frames and microphone audio are processed in memory and never recorded, saved, or transmitted. The workout has no networking or analytics.

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
- **Auto-start.** While ready, holding the start position (both arms confirmed at the bottom) for 1 s begins the set with "Set 1 of 2. Go." After a rest, this works only once the rest timer has ended. Saying "start" or tapping Start always works.
- **Hold ring.** While a hold is being timed, a ring labeled "Hold" fills over the second (`WorkoutSession.startHoldProgress`). It floats beside the body at chest height, just outside the widest visible joint on whichever side has more room, and is separate from the HUD. Letting go hides it. The set starts on the frame where the ring fills.
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

Backgrounding the app or locking the phone pauses an active set with the matching reason and stops the camera and microphone. On return the set stays paused, and the coach says "Paused. Say resume when ready." (or "Tap Resume" without voice control). Camera and audio-session interruptions pause the same way.

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
- The guide's own demonstration reads `h` 0.38 / 82° at the start and 0.96 / 164° at the top. `ShoulderPressAnalyzerTests` checks this rule end to end (see [Automated validation](#automated-validation)).
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
- `WorkoutAudioSession` mixes with other audio, so music keeps playing. With voice control it uses `.playAndRecord` with `.mixWithOthers`, `.defaultToSpeaker`, and `.allowBluetoothA2DP` (Bluetooth headphones keep high-quality music while the built-in mic listens), and stays active between utterances. Without it, `.playback` with `.mixWithOthers`.
- Ducking only takes effect when the session activates, and other audio only returns when it deactivates. So before speaking, listening stops, the session is cycled with `.duckOthers`, and the coach speaks. When the queue drains, `endDucking()` deactivates with `.notifyOthersOnDeactivation`, restores the non-ducking category, and re-activates for listening. It retries briefly if deactivation reports busy.
- `endDucking()` is idempotent and runs on every exit path: speech finished or cancelled, the watchdog, activation errors, interruptions, backgrounding, leaving the screen, and ending the workout. If the app crashes, iOS releases its audio session, which restores other audio.

## Voice control

The microphone and speech-recognition prompts follow the camera prompt, in that order. Without voice, the touch controls keep working and prompts say "Tap" instead of "Say".

- **Commands.** Start ("begin", "let's go"). Pause ("stop", "hold on", "wait"; "stop workout" also pauses). Resume ("continue", "keep going"). Start over ("restart set", "reset set"). Next set ("finish set", "end set"). Change exercise ("switch exercise"), or name one ("switch to shoulder press", "dumbbell press instead"; aliases come from `ExerciseDefinition.voiceAliases`). Cancel ("never mind"). How many reps. Which set. Repeat that ("say that again"). Voice commands ("what can I say", "help", "show commands"). Close ("done", "go back"). Mute ("mute coach", "be quiet") and unmute ("talk to me") the coach. Stop listening ("mute microphone"). End workout ("finish workout", "quit workout").
- **Parsing.** `VoiceCommandParser` lowercases and strips punctuation and apostrophes, then takes the longest known phrase (the most recent on ties). Destructive commands (end workout, restart set, next set, change or select exercise) count only when they're nearly the whole utterance: at most 2 extra words, not counting fillers such as "please", "okay", "coach", and "let's". A match that could still become a different command ("start" → "start over") waits for a final result or for the transcript to settle for 0.6 s; anything else runs immediately.
- **Listening.** `OnDeviceSpeechRecognizer` uses `SFSpeechRecognizer` for the current locale if it's English, or en-US otherwise. It requires on-device support; without it the microphone shows unavailable and touch controls remain. Requests set `requiresOnDeviceRecognition`, partial results, `contextualStrings` from the parser's vocabulary, and no punctuation. Tasks restart after every command and final result, after 1.2 s of unchanged transcript (so old words can't combine with new ones), and every 50 s. Errors back off 0.5–4 s; after 5 in a row, voice reports unavailable until the microphone is tapped.
- **Half-duplex.** `WorkoutVoiceController` stops recognition, discarding any partial transcript, before the coach speaks, and resumes once the speech queue drains. The coach never hears itself.
- **Sound and microphone.** Two stable toggles sit at the top right; their icons never swap. Both settings are remembered between workouts (`workoutCoach.micMuted`, `workoutCoach.coachMuted`).
  - **🎙 Microphone.** Green while listening. The same mic, dimmed, while the coach speaks; listening resumes afterward. A red disc when muted, gray when paused by the system, and orange when it needs permission or is unavailable.
    - Tap to mute or unmute, or to retry after a system pause. In a problem state, tapping opens Voice Commands, with Open Settings or Try Again.
    - Long-press for **Voice Commands** and **Mute/Unmute Microphone**.
    - Say "stop listening" to mute it (said on its own). Unmuting is touch-only, since a muted microphone can't hear.
    - While it's muted, nothing listens, no permission is requested, and prompts say "Tap".
  - **🔊 Coach voice.** Tap to mute or unmute; a red disc shows it's muted. Muting cuts the current line.
    - By voice: "mute" or "be quiet" (said on its own) to mute, and "unmute" or "talk to me" to unmute. Unmuting replies "Coach voice on." The coach can't hear while it's talking, so mute by voice between lines, or tap anytime.
    - A muted coach is fully silent: no announcements, replies, or tips, and no music ducking. The guide's Read Aloud still plays, because it's an explicit tap.
- **Heard chip.** A "Heard: …" chip confirms each recognized command for 1.5 s.
- **Voice Commands help.** A full-height sheet with large type, readable from across the room. It opens by voice ("what can I say", "help", "voice commands"), from **Voice Commands** in the ☰ menu, or by tapping the microphone.
  - **Content:** `VoiceCommandHelp` generates every command from the parser's alias table, grouped as Sets, Exercises, Info, and Finish. Each shows its main phrase, a short description, and its alternates, and destructive commands are marked "Say it on its own". Because the list comes from the same table the parser uses, it always matches what's recognized.
  - **Header:** a "Right now" section shows the commands that fit the current phase (`WorkoutSession.suggestedCommands`). The header also shows the microphone state, with Open Settings or Try Again when needed, and live set progress.
  - **Toggles:** the header repeats both sound toggles, and shows an Unmute Microphone banner while muted.
  - **Behavior:** the workout keeps counting behind the sheet. "Close", "done", "go back", or "cancel" dismiss it. Info and sound commands (how many reps, which set, repeat that, mute, unmute) keep it open. Any command that changes the workout closes it and then runs. Opened by voice, the coach also says, "Here's everything you can say. Try start, pause, or how many reps. Say close when you're done."
- **Discovery.**
  - The first time voice works on this install, the coach says once after its intro: "Say 'what can I say' anytime to see voice commands" (`workoutCoach.voiceTipSpoken`).
  - While ready, the status line alternates every 4 s with "Say 'what can I say' for commands".
  - The how-to guide has a voice-commands row with a **Show Voice Commands** button.
- **Interruptions.** Calls and Siri pause the workout, stop listening, and restore other audio. Voice resumes when the system says to; the workout stays paused. Headphone route changes reinstall the microphone tap. A media-services reset rebuilds the audio engine.
- **Limits.** English only. Recognition can mishear in noisy rooms or with music from the phone's speaker; headphones help. Non-destructive commands such as "pause" are recognized anywhere in a sentence.

## Automated validation

`./scripts/validate.sh` runs these alongside the existing suite. They use pure types only, with no camera, speech, or motion hardware.

- `ShoulderPressAnalyzerTests` sample the guide's own demonstration (`ExerciseDemoFigureView.pose` driven by `ArmMotion`) at 10 Hz:
  - one rep per loop;
  - identical readings at ½× and 2× scale;
  - counting with no hips in view;
  - no count for a half press;
  - a locked Top threshold that stays put while the shoulders lift mid-press.
- `WorkoutSessionTests` drive the reducer:
  - holding the start position for 1 s auto-starts the set;
  - rest is never skipped before its timer ends;
  - stale-epoch reps are ignored;
  - the target range is announced at 8 and the set completes at 10;
  - the tilt warning is rate-limited;
  - the hold ring's progress fills over 1 s and disappears when you let go;
  - the "Right now" suggestions follow the phase.
- `VoiceCommandParserTests` cover fillers, longest-phrase matching, the whole-utterance rule for destructive commands, prefix ambiguity, exercise names, and opening and closing help by voice. They also check that every recognized phrase appears exactly once in the Voice Commands help.
- `PhoneTiltDetectorTests` check the 1 s settle time, the 15°/10° hysteresis, and that missing motion data never warns.

## Future options

- `VNDetectHumanBodyPose3DRequest` (iOS 17) could reduce front-view foreshortening of elbow angles.
- RTMPose would need a bundled model, a person detector, and Core ML conversion. That is a lot of added work for little gain on front-view arm joints.

## Physical-device checklist

Simulator tests cannot validate the camera, Vision detections, speech, or audio ducking. On an iPhone 15 Pro (`make ios`):

1. On a fresh install (deleting the app resets the guide), opening the coach shows the guide before any permission prompt. Read Aloud lowers your music and then restores it. Start Workout leads to the camera. Reopening the coach skips the guide. The ⓘ title reopens it, and doing so mid-set pauses the set.
2. Grant camera access and follow the framing guidance. Verify the headroom prompt when standing too close, and the left/right prompts.
3. When ready, the violet ghost arms line up with your shoulders and roughly match your arm length. Holding the dumbbells just above your shoulders shows the Hold ring beside you, filling over about 1 s, and then starts the set. Letting go early hides the ring. During rest it never starts before the timer ends.
4. Turn on Show Measurements. At the start position, each arm should read below 0.6 and 115° (↓). At the top, above 0.8 and 140° (↑). Do the same press close to the phone and far from it: the readings should be about the same. Each arm's Start segment turns solid at the start, and its Top segment turns solid green only once the wrist passes it with the arm nearly straight. The segments shouldn't drift while you press.
5. Lean the phone back more than 15°: after about a second, the tilt warning appears and is spoken. Stand it upright and the warning clears.
6. Do 10 presses and check that the count is exactly 10, with no double counts when pausing near either threshold. A half press must not count, and neither must a rep finished after stepping out of view mid-rep.
7. Background the app or lock the phone mid-set. The set must be paused on return, with no added reps. Then resume.
8. Leave the screen idle for longer than the auto-lock interval and confirm it never locks.
9. With Spotify or Music playing, the music must lower only while the coach speaks and must never stay lowered, including after ending the workout or closing the screen mid-sentence.
10. Voice, for a whole set without touching the phone: allow the microphone and speech prompts (they follow the camera prompt). Then say "start", "how many reps", "pause", "resume", "next set", and "end workout". Each one shows a "Heard" chip.
11. The coach never reacts to its own speech, and "stop" pauses rather than ending. Chatting in sentences such as "I might end workout later today" doesn't end the workout.
12. Turn on airplane mode: voice commands still work, because recognition is on-device.
13. Deny the microphone or speech permission. The microphone shows "permission needed", tapping it offers Settings, and the buttons still work. Grant it in Settings and return.
14. During a set, take a phone call or invoke Siri. The set pauses and music isn't left lowered. Afterward voice resumes, and saying "resume" continues the set.
15. With AirPods playing music, voice commands still work and the music stays in the headphones.
16. Voice Commands help:
    - Mid-set, say "what can I say". The sheet opens, the coach explains it, and reps keep counting; the header's count updates.
    - "How many reps" answers with the sheet still open. "Close" dismisses it. Reopen it and say "pause": it closes and the set pauses.
    - It also opens from **Voice Commands** in the ☰ menu and by long-pressing the microphone.
    - With the microphone or speech permission denied, the sheet shows Open Settings.
17. On a fresh install:
    - the coach says the "what can I say" tip once after its intro, and not on later opens;
    - while ready, the status line alternates with the commands hint;
    - the guide's **Show Voice Commands** button closes the guide and opens the help.
18. Sound and microphone:
    - While the coach speaks, 🎙 stays a microphone (dimmed).
    - Tap 🔊 mid-sentence: speech stops and music returns to full volume immediately. Nothing more is spoken until you tap 🔊 again or say "unmute", which replies "Coach voice on."
    - Say "mute" between lines to mute the coach by voice.
    - Tap 🎙 while it's listening: it turns red, and prompts switch to "Tap". Tap again to resume listening.
    - Say "stop listening": the mic mutes. Long-press 🎙 and choose Voice Commands.
    - Close and reopen the coach: both mutes are remembered, and a muted mic doesn't start listening (no orange recording dot).
19. Afterward, confirm realtime posture correction still works.

These checks remain manual; a passing simulator run does not imply they were performed.
