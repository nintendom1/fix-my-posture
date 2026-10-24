# Workout Coach (Beta)

Start **Workout Coach (Beta)** from a Train quick-start tile, an exercise detail page, or a routine. The first time an exercise opens, a short guide shows before the camera starts. Then prop the phone up in portrait, step back so the front camera can see the required joints with room to move, and follow the spoken setup. The coach counts reps for a standing dumbbell shoulder press (2 sets of 8–10) hammer curls (2 sets of 10), an overhead band triceps extension filmed side-on (2 sets of 10), air squats with the whole body in view (2 sets of 15), one-arm dumbbell rows filmed side-on (2 sets of 8–10 each arm), and push-ups with the phone on the floor (2 sets of 10), announces the target range and set completion, gives occasional form tips, and keeps the screen awake while it is open. After the permission prompts, the whole workout can run by voice: say "start", "pause", "next set", and so on.

Rep counts, framing checks, and form tips are geometric heuristics from a 2D camera. They are not medical, injury, or performance assessments.

## Privacy

Everything runs on device. Apple Vision estimates the pose, `AVSpeechSynthesizer` speaks, and the Speech framework recognizes commands with `requiresOnDeviceRecognition`. Frames and microphone audio are processed in memory and never recorded, saved, or transmitted. The workout has no networking or analytics.

## Architecture

- `Workout/Exercises`: `ExerciseCatalog.all` is the visible exercise list. Each `ExerciseDefinition` supplies a stable `ExerciseID` (for example `shoulder_press`), sets, target reps, required joints, overlay focus segments, the setup line, an `ExerciseGuide`, and an analyzer factory. Exercise definitions, guidance, presentation metadata, and analyzers live here, with one subfolder per exercise.
- `Workout/Analysis`: `PoseFrame` (reliable, unmirrored pixel pose plus capture timestamp), `ArmGeometry`, `HysteresisPhaseTracker`, `FramingEvaluator`, and the display-only `LandmarkSmoother` (One Euro filter).
- `Workout/Session`: `WorkoutSession` is a pure reducer, `handle(_ event:at:) -> [WorkoutEffect]`. `WorkoutFramePipeline` owns framing, analyzer updates, overlay smoothing, guide measurements, and tilt debounce. `WorkoutCoachModel` is the main-actor `@Observable` orchestrator behind `WorkoutCoachViewModeling`; its camera, permission, speech, audio, voice, clock, and scheduling dependencies are protocols, so tests can inject fakes without constructing AVFoundation or speech services. `AppEnvironment` creates `WorkoutCoachFactory`, which wires the on-device implementations when a workout starts.
- `Workout/Presentation`: `WorkoutVisualState` and `WorkoutHUDPresenter` derive camera screen state and copy as Foundation-only values. `Features/WorkoutCamera/WorkoutCameraScreen` receives one `WorkoutHUDViewState` and sends `WorkoutIntent` values through the view model.
- `Workout/Coaching`: `CoachingCue` (stable `CoachingCueID` keys such as `press.full_extension`, separate from the wording), the pure `CoachingCueScheduler` (owned by `WorkoutSession`), and the pure `WorkoutTipLayout` with each exercise's `MotionEnvelope`. `Utilities/ProtectedBodyGeometry` supplies the body areas that both posture callouts and workout tips avoid.
- `Workout/Camera`: `WorkoutCameraController` uses the shared `PortraitCameraSession` configuration, the same configuration as realtime posture correction. It has one serial queue, a 10 Hz gate on sample timestamps, synchronous `FramePoseEstimator` inference, and the existing 0.3 confidence filter. Frames reach the main actor through one lock-protected pending slot: at most one hop is in flight, newer frames replace older ones, and no buffers are retained. Vision code stays in `AppleVisionPoseEstimator`.
- `Voice`: `SpeechCoach`, `WorkoutAudioSession`, command parsing, and the on-device recognizer.
- `Features/WorkoutCamera`: `WorkoutCoachView` composes the camera preview and reducer; `WorkoutCameraScreen` owns camera chrome and confirmation UI, and its controls map to `WorkoutIntent`. The in-camera chooser, joint/ghost/threshold overlays, completion card, hold ring, and form tips are feature-specific views here. `EdgeToolbarVisibilityController` owns the three-second toolbar window and keeps it visible while VoiceOver is running.
- `Features/VoiceCommands`: `VoiceCommandsHelpView` and `VoiceStatusPresentation` are shared by the Settings and workout help sheets.
- `Features/WorkoutComplete`: the saved workout summary screen and its view model.
- `Features/ExerciseDetail`: exercise details and target editing.
- `DesignSystem/Components`: shared `HUDPill`, `HUDIconButton`, `EdgeToolbar`, `RepCounter`, and `EdgeGlow` components.
- `Views/`: only shared views remain here, including `ExerciseGuideView` and `ExerciseDemoFigureView` (used by exercise detail and the workout camera), posture report/measurement views, and overlays reused by multiple posture flows.

## Workout settings

The Settings screen stores rest policy, preferred weight unit, and start-by-holding in `AppPreferencesStoring`. `WorkoutCoachFactory` snapshots them when a workout starts, so changes apply to the next workout. The reducer receives those values through `WorkoutSettings` and remains independent of `UserDefaults`.

- **Rest between sets.** Exercise default uses each exercise's duration (90 seconds for shoulder press; 60 seconds for the others). A fixed choice from 30 to 120 seconds applies to every exercise. One-arm exercises still switch arms without resting, then rest after both sides. The HUD countdown and progress bar use the selected duration. The existing **Skip rest** action still starts the next set immediately.
- **Weight units.** New History weight entries and spoken mass phrases without a unit use the preferred unit. A spoken unit such as pounds or kilograms takes precedence. Saved weights retain their recorded units and are displayed as recorded; changing this setting never converts existing records.
- **Start by holding position.** Automatic start is enabled only when the global setting and the exercise both allow it. With it off, the start position never starts a set; the user can tap play or say "start". The ready status names those choices, and exercises such as air squats that already opt out keep their existing behavior.
- **Camera & framing.** Camera tilt compensation, the horizon line, alignment targets, and feedback refresh rate use the same preferences in Settings and the live-check gear menu.

## Guidance

The guide and the live overlay share one description of the movement. `ExerciseGuide` holds the steps, the read-aloud walkthrough, the start-position instruction, the counting-threshold lines, and an `ArmMotion`: looping keyframes of upper-arm and forearm elevation. `ArmMotion.place` turns those angles into elbow and wrist points, measuring "outward" as away from the other shoulder. That makes the same keyframes work for the canonical demo figure and for the user's own mirrored body.

- **First-time guide.** The guide sheet opens automatically the first time each exercise is shown, and before the camera starts, so the permission prompt never covers it. An animated front-view figure with two dumbbells (drawn with the posture `AlignmentReferenceOverlayView` silhouette) loops start → press → lower, and the matching step is highlighted. **Start Workout** (or swiping the sheet down) goes straight to setup. **Read Aloud** speaks the steps through `SpeechCoach`, so other audio is ducked and restored. With Reduce Motion, the start and top positions are shown side by side. The guide is remembered per exercise (`workoutCoach.guideSeen.<id>`), so returning users skip it.
- **On demand.** **Exercise guide** in the camera edge toolbar reopens the guide. Like realtime Details, it stops capture while open. An active set pauses, and stays paused after **Back to Workout**.
- **Ghost demo.** While ready, translucent violet ghost arms with dumbbells loop the same motion. They're anchored to the user's smoothed shoulder dots and scaled to their smoothed, measured arm segments (typical proportions are used until measured). Leg ghosts are sized from your own hips, knees, and ankles and need no arm measurements. From the side, arms are sized against shoulder-to-hip torso length, or against the visible upper arm when the hip is out of view. The status line reads "Hold the dumbbells just above your shoulders to begin". Every exercise must show its alignment ghost whenever the workout reaches `.ready`; `WorkoutGhostGeometry` alone decides what the ghost draws. Ghost sizing uses joints Ready guarantees (`requiredJoints` plus any one `anyOfRequiredJoints` set) or a fallback, and optional landmarks may refine sizing but must never suppress the ghost.
- **Auto-start.** While ready, holding the start position (both arms confirmed at the bottom) for 1 s begins the set with "Set 1 of 2. Go." After a rest, this works only once the rest timer has ended. Saying "start" or tapping Start always works.
- **Hold ring.** While a hold is being timed, a ring labeled "Hold" fills over the second (`WorkoutSession.startHoldProgress`). It floats beside the body at chest height, just outside the widest visible joint on whichever side has more room, and is separate from the HUD. Letting go hides it. The set starts on the frame where the ring fills.
- **Threshold lines.** During a set, each arm gets a short **Start ↓** and **Top ↑** segment, drawn from the analyzer's own per-arm thresholds, so the user sees exactly what counts. A rep begins and ends at Start and turns around at Top. The checkpoint an arm is heading toward is bright and dashed, the other is dim, and a segment turns solid once that arm reaches it (cyan for Start, green for Top). The heights are locked at the start position for each rep (see the rep rule), so the segments hold still while you press.
- **Phone tilt.** `CoreMotionTiltMonitor` reads the phone's forward/back lean from gravity at 10 Hz while the camera runs. A lean of more than 15° for 1 s shows "Phone tilted: stand it upright" under the title and speaks a warning (at most every 30 s); it clears below 10°. A leaning phone squashes or stretches heights unevenly, more so up close. The warning is advisory and never blocks a set.
- **Show Measurements.** This exercise-menu toggle is off by default and remembered. It shows each arm's live height ratio, elbow angle, and zone (↓ bottom, ↑ top, ◌ between), for tuning thresholds on device. A second line shows the last rep's form values for tuning the coaching thresholds: `↓` Top-to-Start lowering time, `Δt` Top-line timing gap, `Δh` largest height gap on the way up, `ext` the lower peak elbow angle, and `torso` the live sideways drift from the set's start.

Analysis always uses the original unmirrored pixel geometry. Only the overlay is mirrored for the selfie preview, then smoothed. Overlay and preview share aspect-fit bounds through `CoordinateConverter`.

## Saved Sets

A **Saved Set** is an ordered sequence of exercises, each occurrence with its own sets and reps, for example "Upper Body: Floor Press 2 × 10, Row 2 × 10 each arm, Shoulder Press 2 × 8–10". In the app, "set" still means a group of reps within an exercise.

- **Storage.** `SavedExerciseSet` and `SavedExerciseSetItem` are pure Codable types. Each item has its own UUID, so the same exercise can appear more than once. Items store the exercise by stable `ExerciseID`, not its name. `SavedExerciseSetEntity` (SwiftData, in the app's model container) stores the items as JSON, which keeps their order, so Saved Sets survive restarts. If an exercise is no longer available, the set shows "Needs attention" and runs the rest; nothing is removed silently.
- **List.** Saved Sets show their exercise count and a ✎ edit button. **Create Saved Set** opens the editor.
- **Editor** (`Features/RoutineEditor/RoutineEditorScreen`): name; add, remove, and drag to reorder exercises; steppers for each occurrence's sets and rep range; Save, Duplicate ("<name> Copy" with fresh ids), and Delete with confirmation. These overrides apply only in that Saved Set, for that workout.
- **Running one.** The session follows a `WorkoutPlan`, where each occurrence overrides the exercise's sets and reps (`ExerciseDefinition.withTarget`).
  - The HUD shows "Exercise 3 of 5".
  - Finishing an occurrence's last set records it as completed and starts the normal rest with the next exercise already selected: "Shoulder press complete. Up next: hammer curl, 2 sets of 10. Rest up." The HUD shows "Up next: Hammer Curl · 2 sets × 10 reps".
  - When rest ends, the next exercise's setup and framing begin. Counting waits for "start", Start, or holding its start position. The first time an exercise appears, its guide opens.
  - An exercise that appears again later counts its own sets.
- **Skipping.** Long-press **Next set** in the camera edge toolbar for **Skip to Next Exercise**, or say "next exercise", "skip exercise", or "skip this exercise" (destructive, so it must be said on its own) to move to the next occurrence. Any sets finished there are kept, and the occurrence is recorded as skipped rather than completed.
- **Changing exercise.** **Change exercise** in the camera edge toolbar opens the existing chooser, which warns that choosing another exercise leaves the Saved Set and skips the rest of it. Naming an exercise directly mid-set asks you to use "next exercise" or "change exercise" instead.
- **Completion.** After the last occurrence, the completion card lists each occurrence: its sets and reps, "Skipped" (with any sets done first), or "Not reached". **Another Round** runs the whole Saved Set again, and the end-of-workout summary lists the same.

## Workout history

Ending a workout saves it automatically: End Workout on the completion card, End and then Done, or closing the camera screen after finishing a set. A workout with no finished set saves nothing.

- **Storage.** `WorkoutRecord` (pure Codable, built from the session by `WorkoutRecord(session:startedAt:endedAt:)`) is stored by `WorkoutRecordEntity` (SwiftData, entries as JSON). Workouts run from a Saved Set also store that set's UUID as `planID`; individual exercise workouts leave it nil.
  - The record has the start and end time and, for a Saved Set, its name.
  - Each entry is one exercise (or one Saved Set occurrence, marked completed or skipped) with its sets: reps, the arm for one-arm exercises, and the weight.
  - The exercise's name is copied, so history still reads well if the exercise changes.
- **Weights by voice.** Mid-set, say "my weights are 17.5 pounds", "add weight seventeen point five pounds", "weight 8 kilograms", or for bands "using the red band" (red, yellow, green, blue, black, purple, orange, gray, light, medium, or heavy).
  - The coach confirms out loud ("17.5 pounds."), the Heard chip shows "Weight 17.5 lb", and the HUD shows the weight beside the set count.
  - The weight applies to the current set and carries to the next ones until changed. Bodyweight exercises reply that they don't use weights.
  - `WeightPhraseParser` reads digits ("17.5") and number words ("seventeen point five", "twenty two and a half"). A mass needs a unit and "weight", "weights", or "using" before the number, with only number words between, so other numbers never set a weight.
  - Speech recognition often writes "weight" as "wait", so "wait", "weigh", and their forms count as weight words too ("wait 17.5 pounds" sets a weight). While a number follows "wait" with no unit yet, nothing runs. "Wait" on its own pauses only after 1 s of quiet (`VoiceCommandParser.weightSoundAlikeSettleTime`), in case a weight is coming. Pausing longer than that between "weight" and the number still pauses the set. A spoken weight waits for the transcript to settle, so "17" doesn't fire before "point five".
- **Weights** (`WorkoutWeight`) are per dumbbell and per set: a value in the unit given (shown as lb or kg), or a band's name for band exercises (`ExerciseDefinition.equipment`). Bodyweight exercises (squats, push-ups) take no weight.
  - During a workout, the weight in use is recorded with each finished set and carries to the next sets of that exercise until changed. The HUD shows it beside the set count.
- **History screen.** Open Workout History from Progress or the recent-workout card on Train. Workouts appear newest first; swipe to delete.
  - Each workout shows its sets. Tap a set's weight (or **Add weight**) to enter or change it per dumbbell in lb or kg, or name the band.
  - **Also for the later sets** copies it to the rest of that exercise. **Remove Weight** clears it.

## Session state machine

Phases: `choosingExercise`, `framing`, `ready`, `exercising`, `paused(user | background | interruption)`, `resting`, `changingExercise(previous)`, `exerciseComplete`, and `ended`.

- **Entry.** Train quick-start tiles, Library exercise details, and routine details start the camera with the selected exercise or plan. Exercise detail lets the user adjust sets and reps; the values are remembered on this phone (`ExerciseTargetStore`, with Reset to Default; the built-in definition never changes). `choosingExercise` remains for a session started without an exercise.
- **Completion.** When a standalone exercise's last set finishes, a card fades in over the camera (instantly with Reduce Motion). It shows "<Exercise> complete", this round's reps per set and in total, and anything else done in the workout. Its buttons are **Another Round**, **Choose Exercise** (shown when there are other exercises), and **End Workout**. The coach says the same choices: "Say another round, change exercise, or end workout", or "Tap Another Round, Choose Exercise, or End Workout" without voice. A completed Saved Set shows the full workout summary screen.
- **Changing exercise.** Saying "change exercise" or tapping **Change exercise** in the edge toolbar enters `changingExercise` and shows an exercise chooser over the camera, with each exercise's sets and how many are done. Pick one by voice or tap, or cancel to return to where you were. Picking another one mid-set asks "Discard this set's N reps?" when the set has reps.

Tracking reliability is a separate input. While exercising and unreliable, counting is suspended without changing phase. Framing guidance is spoken once per loss, and counting resumes automatically.

| Command | Behavior |
|---|---|
| Start | From framing or ready, begins the set; counting still waits for reliable tracking. From paused, resumes. From resting, starts the next set. Holding the start position for 1 s does the same while ready, and after rest once the timer ends. |
| Pause | Pauses only while exercising. Elsewhere it changes nothing and gives a short spoken hint. |
| Resume | Acts only from paused. Harmless while exercising. |
| Restart set | Resets the current set's reps and starts a fresh analyzer. Nothing else changes. |
| Next set | While exercising or paused, completes the set and rests. From resting, starts the next set. After the last set, the exercise is complete. |
| Change exercise | The edge-toolbar chooser selects another exercise. It discards an in-progress set (finished sets are kept per exercise; returning picks up at the next set) and clears the analyzer, smoothing, threshold lines, readings, and feedback, including any tip and the coaching history. The first time an exercise is chosen, its guide opens. |
| Another round | After the last set, does the same exercise again from set 1. Earlier rounds stay in the summary. Elsewhere it changes nothing and gives a short hint. |
| End | Asks for confirmation when tapped mid-workout. Then stops the camera, restores other audio, and shows a summary with Done and View History actions. From a standalone exercise's completion card, End Workout returns to Train because the card already showed the results. |

Backgrounding the app or locking the phone pauses an active set with the matching reason and stops the camera and microphone. On return the set stays paused, and the coach says "Paused. Say resume when ready." (or "Tap Resume" without voice control). Camera and audio-session interruptions pause the same way.

Stale events are dropped. Every analyzer instance carries an epoch, and the session ignores reps from replaced analyzers. Camera events carry a generation, so results from an old capture start are discarded.

## Framing

`FramingEvaluator` uses each exercise's required joints. For shoulder press and hammer curls those are both shoulders, elbows, and wrists at confidence ≥ 0.4. Hips aren't required, so users can stand closer for steadier tracking; when visible, they still help center the left/right guidance.

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

## Hammer curl rep rule

Hammer curls are filmed from the front. Each arm counts on its own with its own hysteresis tracker, so curls can alternate or move together. The displayed count is the number of reps both arms have done, and the HUD also shows "L 6 · R 7". Thresholds live in `HammerCurlConfiguration`.

- Signal: `r` = the wrist's height above its elbow, in that arm's upper-arm length. From the front, the upper arm hangs nearly vertical, so it's a steady ruler at any distance, while the forearm swings toward the camera and looks shorter. The ruler is the longest upper arm over the last second.
- Start when `r ≤ −0.6` (hanging straight). Top when `r ≥ 0.25` (wrist well above the elbow). Each checkpoint needs 2 consecutive 10 Hz samples.
- Locked reference: while an arm hangs at the start, its smoothed elbow height and ruler are refreshed; once it curls, they're locked until it hangs straight again (dropped after 6 s, or after a tracking gap).
- An arm earns a rep when it hangs straight, reaches the Top, and hangs straight again within a cycle of at least 0.8 s. An arm that curls up again without hanging straight doesn't count; that raises "Straighten at the bottom."
- Validation: the guide's own demonstration reads about −0.88 hanging and 0.83 at the top. It counts exactly one rep per arm per loop at ½× and 2× scale, with upper arm or forearm ±15%. The weakest case, a forearm 15% shorter, still reads −0.75 and 0.71. `HammerCurlAnalyzerTests` also cover alternating arms, a half curl, and curling again from midway.
- The set completes automatically at 10. There's no target-range announcement, since the target is exactly 10.
- The demonstration's forearm moves in the sagittal plane (`ArmMotion.forearmPlane = .sagittal`): toward the camera, so in the guide and the ghost it rises straight up in front of the elbow, as it does on camera.

## Band triceps extension rep rule

The overhead triceps extension is filmed from the side, because from the front the hands hide behind the head at the start. Stand side-on to the phone, facing either way. The arm nearer the phone is tracked: the most confident complete arm, kept until the other is clearly more confident (by 0.2). Both arms move with one band, so each rep counts for both. Thresholds live in `TricepsExtensionConfiguration`.

- Signal: `s` = the wrist's height above its elbow in forearm lengths, plus the 2D elbow angle. From the side, the forearm swings in the image plane, so its longest length over the last second is a full ruler at any distance and for any proportions.
- Start when `s ≤ −0.25` and the elbow is at most 100° (hands lowered just below horizontal behind the head, so the start registers before they're hidden). Top when `s ≥ 0.75` and the elbow is at least 140° (straight overhead). The elbow height and ruler are locked at the start, as with curls.
- **Hands hidden behind the head.** Folded behind the head, the hands often drop out of view.
  - Framing needs only a shoulder and elbow (`anyOfRequiredJoints`), so tracking stays reliable.
  - While the tracked arm's elbow stays raised (at least half an upper arm above the shoulder) and the hand was last seen on its way down (below 0.5), a hidden hand counts as folded at the start. The same applies before any hand has been seen, so holding the start with hidden hands still starts the set.
  - A hand last seen overhead is never taken for the start.
  - Joints count down to the live 0.3 confidence floor, since hands behind the head track with low confidence.
  - Device feedback on #20 prompted this change.
- A rep is Start → Top → Start within at least 0.8 s.
- Validation: the guide's side-view demonstration reads −0.71 at 40° and 1.00 at 177°. It counts exactly one rep per loop facing either way, with either arm, at ½× and 2× scale, and with either arm segment ±15%.
- **Side-view support**:
  - `ExerciseDefinition.cameraView = .side` gives a profile guide figure and a ghost arm on the nearer shoulder, facing the way the user faces (from the nose).
  - Framing (`anyOfRequiredJoints`) accepts either arm and asks you to "Step into view, standing side-on to the phone."
  - The hold ring, tip placement, and arm measurements work with one shoulder; from the side, measurements are checked against torso length.
  - `ArmMotion.holdsDumbbells = false` hides the dumbbells for band exercises.

## Air squat rep rule

Air squats are filmed from the front with the whole body in view (hips, knees, and ankles are required; framing asks you to "Step back until your whole body is in view, head to feet"). Thresholds live in `AirSquatConfiguration`.

- Signal: `d` = how far the hips sit above the knees, in thigh lengths, averaged over both legs. Standing, the thigh is vertical and `d` ≈ 1. Squatting, the thigh points toward the camera, so on screen the hips sink to the knees' height and `d` falls toward 0. The thigh is its own ruler (the longest recent hip-to-knee length, locked while standing), so the rule is the same at any distance and for any build.
- Standing is the start when `d ≥ 0.85`. The squat is the counted end when `d ≤ 0.45`. A rep is stand → squat → stand within at least 1 s. The lines are drawn across the hips as **Stand ↑** and **Squat ↓**.
- Validation: the guide's demonstration reads 1.00 standing and 0.19 at the bottom, for any thigh length. It counts exactly one rep per loop at ½×/2× scale and with thigh or shin ±15%. A half-depth squat reads about 0.59 and doesn't count.
- **No hold-to-start** (`ExerciseDefinition.startsByHolding = false`): standing is the start position, so holding it would start sets by accident. Say "start" or tap Start. The status line and prompts say so.
- **Lower-body demonstrations**: keyframes carry a `LegPose` (hip drop and knee spread). The guide figure squats, and the ghost draws legs standing on your own ankles, scaled to your leg length, showing how low to go. Leg joints turn green at the counted squat, since only joints of the moving limbs turn green.

## One-arm dumbbell row rep rule

The row is filmed from the side, with the rowing arm nearer the phone, bent forward with the other hand on a bench. The arm nearer the phone is tracked (`NearArmSelector`, shared with the triceps extension). Thresholds live in `DumbbellRowConfiguration`.

- Signal: `e` = the elbow's height above its shoulder in upper-arm lengths, plus the 2D elbow angle. Hanging straight reads about −1, and pulled up past the back about −0.2. The upper arm swings in the image plane, so its longest recent length is a full ruler.
- Start when `e ≤ −0.85` and the elbow is at least 150° (hanging straight). Top when `e ≥ −0.35`. The shoulder height and ruler are locked while the arm hangs. A rep needs at least 0.8 s.
- **One arm at a time** (`ExerciseDefinition.perSide`):
  - Each set is the left arm, then the right, then rest.
  - After the left arm the coach says "Left arm done, N reps. Switch to your right arm." There's no rest timer: hold the start position or say "start". Turn around so the right arm is nearer the phone; the ghost follows the way you face.
  - The HUD shows "Set 1 of 2 · Left arm". Each arm's reps are recorded as their own entry ("Set 1 L", "Set 1 R").
- Validation: the guide's bent-over demonstration (torso pitched 50°, `ArmMotion.torsoPitch`) reads −1.00 hanging and −0.17 pulled. It counts exactly one rep per loop facing either way, with either arm, at ½×/2×, and with either segment ±15%.

## Push-up rep rule

Push-ups are filmed by a phone lying on the floor a step in front of the hands, tilted up to face the head (`ExerciseCameraView.floor`). The hands sit near the bottom of the frame and the shoulders rise and fall above them. Thresholds live in `PushUpConfiguration`.

- Signal: `h` = how far the shoulders sit above the planted hands, in arm lengths (upper arm + forearm), averaged over both arms, plus the average 2D elbow angle. The arms stand roughly upright in the image, so the longest recent arm length, locked at the top, is a full ruler at any distance.
- Up (the start) when `h ≥ 0.8` and the elbows are at least 150°. Down (the counted end) when `h ≤ 0.5` and the elbows are at most 110°. A rep is up → down → up within at least 0.8 s. The lines are drawn across the shoulders as **Up ↑** and **Down ↓**.
- Validation: the guide's floor-view demonstration reads 1.00 at 180° up and 0.42 at 50° down, whatever the arm proportions. It counts exactly one rep per loop at ½×/2×, mirrored, and with either segment ±15%.
- **Floor-view support**:
  - The guide figure plants its hands on a floor line, with the shoulders above them by the arm pose.
  - The ghost arms rise from your own hands to show where your shoulders go.
  - Framing asks you to "Get into a plank facing the phone".
  - The tilt warning is off (`ExerciseDefinition.warnsAboutTilt = false`), since the phone leans back on purpose.
  - Holding the plank with straight arms for a second starts the set.

## Form coaching

While counting, the coach watches how each rep is done and offers a short tip now and then. Corrective cues are spoken and shown as a tip; reminders are only shown. Cues describe movement relative to the user's own set. They never mention grip, wrist rotation, dumbbell orientation, or injury, and they never make medical claims.

**Signals.** `ShoulderPressFormMonitor` only observes; counting never depends on it. It uses the analyzer's own units (wrist height in that arm's length, with the locked shoulder), so readings are the same at any distance. The times when a wrist crosses the drawn Top and Start lines are interpolated between samples, so they don't jump with the 10 Hz cadence. An *attempt* begins once both arms settle at the Start and a wrist rises 0.2 above where it rested, and it ends when both settle again. Attempts that don't count, such as a half press, are judged too, so the coach can say why. All values are prototype heuristics in `ShoulderPressConfiguration`, and the guide's own demonstration raises none of them.

| Cue (priority) | Raised when | Guide demo |
|---|---|---|
| "Press all the way up." (50) | An attempt ends with an arm that never reached the Top, or with a peak 2D elbow angle under 155°. | peak 173° |
| "Lower to just above your shoulders." (40) | After the Top, a wrist dips at least 0.2 below its peak and presses back to the Top without reaching the Start. | never |
| "Lower with control." (30) | A wrist takes less than 0.15 s from the Top line down to the Start line, a full lowering faster than about 0.8 s. | 0.29 s for a 1.5 s lowering |
| "Keep your torso centered." (20, continuous) | The shoulder midpoint's sideways offset from the hip midpoint drifts more than 0.12 arm lengths from where it was at the start of the set (the mean of 5 samples at the Start). Skipped while hips aren't visible. | 0 |
| "Press both arms evenly." (10) | The wrists cross the Top line more than 0.3 s apart, or differ in height by more than 0.25 on the way up. | 0 s / 0 |

Reminders, visual only: "Brace your core.", "Breathe out as you press.", "Keep your ribs down."

Hammer curls (`HammerCurlFormMonitor`) judge each arm's attempts separately. An attempt begins once an arm settles hanging straight and its wrist rises 0.5 above where it hung.

| Cue (priority) | Raised when | Guide demo |
|---|---|---|
| "Curl all the way up." (50) | An arm's attempt ends without reaching the Top. | never |
| "Straighten at the bottom." (40) | After the Top, a wrist dips at least 0.4 and curls up again without hanging straight. | never |
| "Keep your elbows by your sides." (20, continuous) | An elbow's sideways distance from its shoulder grows by more than 0.25 shoulder widths compared with the start of the set. | 0 |
| "Keep your body still." (10, continuous) | The shoulder midpoint moves more than 0.35 upper-arm lengths relative to the hip midpoint compared with the start of the set. Skipped while hips aren't visible. | 0 |

Triceps extension (drafted wording, for review): "Straighten both arms fully." (50: Top missed or peak elbow under 155°), "Lower behind your head." (40: extended again after dipping 0.5 without reaching the Start), "Lower with control." (30: Top line to Start line in under 0.3 s; the demo's 1.5 s lowering reads 0.49 s), "Keep your elbows pointing up." (20, continuous: the upper arm tips more than 25° from where it pointed at the start of the set). Reminders: "Keep your ribs down.", "Elbows close to your head.", "Breathe out as you extend."

Air squat (drafted wording, for review):
- "Squat a little deeper." (50): an attempt that dropped at least 0.3 but never reached the Squat line.
- "Stand all the way up." (40): after the squat, rose at least 0.3 and squatted again without standing.
- "Keep your knees in line with your toes." (20, continuous, while squatting below 0.6): a knee moved inside its ankle by more than 0.25 hip widths compared with standing.
- "Keep your chest up." (10, continuous, while squatting below 0.6): the shoulders-to-hips height shrank below 75% of standing, which is a forward lean seen from the front. Needs shoulders.

Reminders: "Weight in your heels.", "Brace your core.", "Breathe in on the way down."

One-arm row (drafted wording, for review):
- "Pull your elbow up past your back." (50): an attempt that rose at least 0.3 but missed the Top.
- "Lower all the way down." (40): after the Top, dipped at least 0.35 and pulled again without hanging straight.
- "Lower with control." (30): Top line to Start line in under 0.25 s. The demo's 1.5 s lowering reads about 0.5 s.
- "Keep your back still." (20, continuous): the shoulder-to-hip line tipped more than 15° from the start of the set. Needs the hip.

Reminders: "Squeeze your shoulder blade.", "Keep your neck neutral.", "Brace your core."

Push-up (drafted wording, for review):
- "Go a little lower." (50): an attempt that dropped at least 0.2 but missed the Down line.
- "Push all the way up." (40): after the bottom, rose at least 0.2 and went down again without straightening.
- "Lower with control." (30): Up line to Down line in under 0.2 s. The demo's 1.5 s lowering reads 0.43 s.

Reminders: "Brace your core.", "Hands under your shoulders.", "Breathe out as you push."

Curl reminders: "Elbows stay close.", "Lower slowly.", "Stand tall." The curl's motion envelope runs from the shoulders down past the hanging dumbbells, and out past them to the sides. Its "Last rep" line shows each arm's last top and hanging heights, plus the live flare and sway drift.

**Scheduling.** `CoachingCueScheduler` keeps cues sparse:

- A continuous signal must hold for 0.5 s. A per-rep cue needs the newest attempt and 2 of the last 3 attempts to raise it.
- Each cue waits 10 s before it can repeat. Cues start at least 4 s apart, unless a higher-priority cue replaces the one on screen.
- One tip shows at a time, for 3 s. A higher-priority cue replaces a lower one immediately; a lower one waits.
- A corrective cue doesn't start while the coach is speaking, so the tip and its spoken line stay together and cues never pile up in the speech queue. Cues never interrupt speech, and they go through the normal speech path, so coach mute, half-duplex listening, and ducking apply. "Repeat that" can repeat a cue.
- Reminders: one at set start, then one after 25 s without any cue, rotating through the list across sets.
- Pausing or losing tracking clears signals in progress. Restarting, finishing, or switching clears everything, including the tip.

**Tips.** `WorkoutTipLayout.placement(size:container:protected:reserved:previous:)` keeps a tip clear of three areas:

- the body (`ProtectedBodyGeometry`);
- the exercise's motion envelope (for the press, from the shoulders up one arm length overhead, 0.75 arm lengths out to each side, and 0.3 below);
- both HUD regions (`WorkoutHUDRects`).

It keeps the current slot while it stays valid. Otherwise it tries these slots in order:

1. below the top HUD (center, left, right);
2. above the bottom HUD (center, left, right);
3. the left and right gutters, scanning from mid-height outward.

The tip is measured on one line (up to 320 pt) and as a compact, wrapped tip (up to 120 pt), which fits beside the hips when the user stands close. At typical distances the tip sits under the top HUD. When the body fills the frame from head to ankles, there's no room, so a corrective cue is only spoken and a reminder is skipped. Tips fade in and out over 0.25 s, instantly with Reduce Motion. A muted coach still shows tips, silently.

**Emphasis.** While a corrective tip shows, the joints it refers to are drawn amber: elbows and wrists for the arm cues, and shoulders and hips (with their lines) for the torso cue. Amber takes precedence over the green end position. Gray for missing joints still takes precedence. The overlay never uses red.

## Overlay and HUD

- The ghost demo (ready) and threshold lines (during a set) are drawn beneath the joints. See [Guidance](#guidance).
- The overlay draws only the focus segments (each shoulder→elbow→wrist chain plus thin shoulder and hip lines) and their joints. Joints are cyan when tracked, green while that arm holds the counted top position, and amber while a form tip refers to them. Joints missing for up to 0.3 s turn muted gray, then disappear. The overlay never uses red.
- The camera HUD keeps its state-colored instruction pill and edge glow above the preview, with the title, plan subtitle, speaker and microphone toggles in the top row. Rep count, primary action, progress, set summary, and next line stay at the bottom; five controls sit in the right-edge toolbar. Long-press **Next set** in a Saved Set for **Skip to Next Exercise**. Long-press the microphone for Voice Commands and mic mute controls. The HUD regions publish their frames (`WorkoutHUDRects`), and form tips keep clear of them.
- The idle timer is disabled while the screen is open.

## Speech and audio

- `SpeechCoach` keeps a short utterance queue: at most 2 pending lines, older ones dropped. It remembers the last instruction for "repeat that". Delegate callbacks (start, finish, cancel) advance the queue. A watchdog stops any utterance that runs past its estimated duration + 5 s.
- `WorkoutAudioSession` mixes with other audio, so music keeps playing. With voice control it uses `.playAndRecord` with `.mixWithOthers`, `.defaultToSpeaker`, and `.allowBluetoothA2DP` (Bluetooth headphones keep high-quality music while the built-in mic listens), and stays active between utterances. Without it, `.playback` with `.mixWithOthers`.
- Ducking only takes effect when the session activates, and other audio only returns when it deactivates. So before speaking, listening stops, the session is cycled with `.duckOthers`, and the coach speaks. When the queue drains, `endDucking()` deactivates with `.notifyOthersOnDeactivation`, restores the non-ducking category, and re-activates for listening. It retries briefly if deactivation reports busy.
- `endDucking()` is idempotent and runs on every exit path: speech finished or cancelled, the watchdog, activation errors, interruptions, backgrounding, leaving the screen, and ending the workout. If the app crashes, iOS releases its audio session, which restores other audio.

## Voice control

The microphone and speech-recognition prompts follow the camera prompt, in that order. Without voice, the touch controls keep working and prompts say "Tap" instead of "Say".

- **Commands.** Start ("begin", "let's go"). Pause ("stop", "hold on", "wait"; "stop workout" also pauses; "wait" alone runs after 1 s, in case it was "weight"). Resume ("continue", "keep going"). Start over ("restart set", "reset set"). Next set ("finish set", "end set"). Change exercise ("switch exercise"), or name one ("switch to shoulder press", "dumbbell press instead"; aliases come from `ExerciseDefinition.voiceAliases`). Cancel ("never mind"). How many reps. Which set. Repeat that ("say that again"). Voice commands ("what can I say", "help", "show commands"). Close ("done", "go back"). Mute ("mute coach", "be quiet") and unmute ("talk to me") the coach. Weights ("my weights are 17.5 pounds", "add weight seventeen point five pounds", "weight 8 kilograms", "using the red band"). Stop listening ("mute microphone"). End workout ("finish workout", "quit workout").
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
    - A muted coach is fully silent: no announcements, replies, or spoken tips, and no music ducking. Form tips still appear on screen. The guide's Read Aloud still plays, because it's an explicit tap.
- **Heard chip.** A "Heard: …" chip confirms each recognized command for 1.5 s.
- **Voice Commands help.** A full-height sheet with large type, readable from across the room. It opens by voice ("what can I say", "help", "voice commands") or by long-pressing the microphone and choosing **Voice Commands**.
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

- `ReadyGhostInvariantTests` start each catalog exercise from its guide position with every joint and with only the joints framing requires (plus any third landmark framing needs to see a body). Each pose must reach Ready and draw ghost geometry for every guide keyframe; no known gaps remain.
- `WorkoutFramePipelineTests` check side-view sizing from a visible upper arm when the hip is out of view and preserve torso-based sizing when the hip is visible. `WorkoutGhostGeometryTests` check leg sizing without arm metrics and arm/floor metric requirements.
- `ShoulderPressAnalyzerTests` sample the guide's own demonstration (`ExerciseDemoFigureView.pose` driven by `ArmMotion`) at 10 Hz:
  - one rep per loop;
  - identical readings, including form readings, at ½× and 2× scale;
  - counting with no hips in view;
  - no count for a half press;
  - a locked Top threshold that stays put while the shoulders lift mid-press;
  - no form cues for the demonstration itself;
  - "Press all the way up" for a half press, "Lower with control" for a 0.5 s lowering, "Press both arms evenly" for one arm 0.4 s late, and "Lower to just above your shoulders" for re-pressing from midway;
  - the torso signal for a sideways lean, never without hips, and never affecting the count.
- `HammerCurlAnalyzerTests` run the curl guide's own demonstration (forearm moving toward the camera) at 10 Hz:
  - one rep per arm per loop, at ½× and 2× scale and with either segment ±15%;
  - alternating arms each count;
  - curling again from midway counts once and asks to straighten;
  - a half curl doesn't count and asks to curl all the way up;
  - flared elbows and sway raise their signals, and sway needs hips.
- `TricepsExtensionAnalyzerTests` run the side-view demonstration facing either way, with either arm, at ½×/2× scale and with either segment ±15%. They also check that a half extension asks to straighten, a fast lowering asks for control, extending again from midway asks to lower behind the head, and tipped elbows raise their signal. Hands hidden behind the head still count, while a hand hidden overhead never counts as the start. Side-on framing accepts either arm, keeps tracking with the hand hidden, and asks you to stand side-on.
- `AirSquatAnalyzerTests` run the squat demonstration at ½×/2× scale and with thigh or shin ±15%. They also check that a shallow squat asks to go deeper, squatting again without standing asks to stand up, caving knees and a forward lean raise their signals only at depth, and the lean check needs shoulders.
- `DumbbellRowAnalyzerTests` run the bent-over side demonstration facing either way, with either arm, at ½×/2× and with either segment ±15%. They also check that a half pull asks to pull higher, a fast lowering asks for control, pulling again from midway asks to lower all the way, and a tipping back raises its signal only with the hip visible.
- `PushUpAnalyzerTests` run the floor-view demonstration at ½×/2×, mirrored, and with either segment ±15%. They also check that a shallow push-up asks to go lower, a fast lowering asks for control, and going back down without straightening asks to push all the way up.
- `SavedExerciseSetTests` check that order, ids, and repeated exercises survive storage; that unavailable exercises need attention without being removed; that duplicates get fresh ids; and that remembered targets apply without changing the defaults.
- `WorkoutHistoryTests` check that weights carry to later sets until changed (and are confirmed out loud), that bodyweight exercises take no weight, that Saved Set occurrences are recorded with their outcome and survive storage, that one-arm sets are labeled by arm, and that a workout with no sets saves nothing.
- `CoachingCueSchedulerTests` check the 0.5 s hold, 2 of the last 3 attempts, the 10 s cooldown and 4 s gap, replacement by priority only upward, waiting while the coach speaks, and reminders at set start and after 25 s quiet.
- `WorkoutTipLayoutTests` check the preferred slot, keeping a still-valid slot, speak-only when nothing fits, and that press tips at typical and close distances never touch the arms, body, envelope, or HUD.
- `WorkoutSessionTests` drive the reducer:
  - holding the start position for 1 s auto-starts the set;
  - rest is never skipped before its timer ends;
  - stale-epoch reps are ignored;
  - the target range is announced at 8 and the set completes at 10;
  - the tilt warning is rate-limited;
  - the hold ring's progress fills over 1 s and disappears when you let go;
  - the "Right now" suggestions follow the phase;
  - set start shows a reminder tip without speaking it;
  - a corrective cue is spoken and shown, and only for the current analyzer;
  - restarting a set forgets its coaching history, and pausing restarts a continuous cue's hold;
  - the last set offers another round (earlier rounds kept), and ending from the completion card skips the summary;
  - one-arm-at-a-time sets switch arms without rest, then rest after both, recording an entry per arm;
  - a Saved Set rests, then selects the next exercise without counting; skipping records skipped occurrences; a repeated exercise counts its own sets; and switching away needs the chooser;
  - switching mid-set keeps finished sets, restarts the set in progress, clears feedback, and starts a fresh analyzer; curl arms count separately, and the count is what both arms have done.
- `VoiceCommandParserTests` cover spoken weights (digits, number words, halves, kilograms, bands, settling, and ignoring unrelated numbers), "wait" heard for "weight" (a weight, held while the number is said, or a pause after 1 s), fillers, longest-phrase matching, the whole-utterance rule for destructive commands, prefix ambiguity, exercise names, and opening and closing help by voice. They also check that every recognized phrase appears exactly once in the Voice Commands help.
- `PhoneTiltDetectorTests` check the 1 s settle time, the 15°/10° hysteresis, and that missing motion data never warns.

## Adding an exercise

Every new exercise ships with full guidance, even when the request only names it:

1. One folder under `Workout/Exercises` (definition, configuration, analyzer) and one line in `ExerciseCatalog`.
2. Guide: steps, the Read Aloud walkthrough, the start-position instruction, and `ArmMotion` keyframes whose first keyframe is the start position. These drive the guide sheet, the first-time display, the ghost, and the hold ring.
3. Ready-state ghost: a pose with only the joints framing requires must reach Ready and still produce ghost geometry for every guide keyframe (`ReadyGhostInvariantTests` checks every catalog exercise). Don't tighten framing to make the ghost render; add a sizing fallback in `WorkoutFramePipeline.metricsReference` or `WorkoutGhostGeometry` instead.
4. Threshold lines that match the movement's direction. Don't assume "top" means higher wrists.
5. Validate the thresholds by running the guide's own demonstration through the analyzer. Expect exactly one rep per loop at any scale and proportions, with a scale-invariant ruler such as arm length. Report any deviation from the planned thresholds.
6. Coaching: corrective cues with stable `CoachingCueID`s, priorities, and emphasized joints; visual-only reminders; and a `MotionEnvelope`. The demonstration should raise no cues.
7. Voice aliases (`ExerciseDefinition.voiceAliases`); the parser, the help list, and the every-phrase test pick them up.
8. Docs: the rep rule section, the coaching cues, and physical-device checklist items.
9. Presentation: add the short name, muscles, filter groups, gradient token, SF Symbol, equipment and camera-setup lines, plus watch items keyed to the exercise's own cue IDs in `Workout/Exercises/ExercisePresentation.swift` (`ExerciseCatalogTests` enforces this).
10. Non-diagnostic wording: never comment on grip, wrist rotation, dumbbell orientation, or injury.

## Future options

- `VNDetectHumanBodyPose3DRequest` (iOS 17) could reduce front-view foreshortening of elbow angles.
- RTMPose would need a bundled model, a person detector, and Core ML conversion. That is a lot of added work for little gain on front-view arm joints.

## Physical-device checklist

Simulator tests cannot validate the camera, Vision detections, speech, or audio ducking. On an iPhone 15 Pro (`make ios`):


### Guide, setup, and camera behavior

- [ ] **1.** On a fresh install (deleting the app resets the guide), opening the coach shows the guide before any permission prompt. Read Aloud lowers your music and then restores it. Start Workout leads to the camera. Reopening the coach skips the guide. The ⓘ title reopens it, and doing so mid-set pauses the set.
- [ ] **2.** Grant camera access and follow the framing guidance. Verify the headroom prompt when standing too close, and the left/right prompts.
- [ ] **3.** For every exercise, the alignment ghost appears as soon as the status reads "Get in position" and lines up with you, including when you stand as close as framing allows. For shoulder press, holding the dumbbells just above your shoulders shows the Hold ring beside you, filling over about 1 s, and then starts the set. Letting go early hides the ring. During rest it never starts before the timer ends.
- [ ] **4.** Turn on Show Measurements. At the start position, each arm should read below 0.6 and 115° (↓). At the top, above 0.8 and 140° (↑). Do the same press close to the phone and far from it: the readings should be about the same. Each arm's Start segment turns solid at the start, and its Top segment turns solid green only once the wrist passes it with the arm nearly straight. The segments shouldn't drift while you press.
- [ ] **5.** Lean the phone back more than 15°: after about a second, the tilt warning appears and is spoken. Stand it upright and the warning clears.
- [ ] **6.** Do 10 presses and check that the count is exactly 10, with no double counts when pausing near either threshold. A half press must not count, and neither must a rep finished after stepping out of view mid-rep.
- [ ] **7.** Background the app or lock the phone mid-set. The set must be paused on return, with no added reps. Then resume.
- [ ] **8.** Leave the screen idle for longer than the auto-lock interval and confirm it never locks.

### Voice, audio, and permissions

- [ ] **9.** With Spotify or Music playing, the music must lower only while the coach speaks and must never stay lowered, including after ending the workout or closing the screen mid-sentence.
- [ ] **10.** Voice, for a whole set without touching the phone: allow the microphone and speech prompts (they follow the camera prompt). Then say "start", "how many reps", "pause", "resume", "next set", and "end workout". Each one shows a "Heard" chip.
- [ ] **11.** The coach never reacts to its own speech, and "stop" pauses rather than ending. Chatting in sentences such as "I might end workout later today" doesn't end the workout.
- [ ] **12.** Turn on airplane mode: voice commands still work, because recognition is on-device.
- [ ] **13.** Deny the microphone or speech permission. The microphone shows "permission needed", tapping it offers Settings, and the buttons still work. Grant it in Settings and return.
- [ ] **14.** During a set, take a phone call or invoke Siri. The set pauses and music isn't left lowered. Afterward voice resumes, and saying "resume" continues the set.
- [ ] **15.** With AirPods playing music, voice commands still work and the music stays in the headphones.
- [ ] **16.** Voice Commands help:
    - Mid-set, say "what can I say". The sheet opens, the coach explains it, and reps keep counting; the header's count updates.
    - "How many reps" answers with the sheet still open. "Close" dismisses it. Reopen it and say "pause": it closes and the set pauses.
    - It also opens by long-pressing the microphone and choosing **Voice Commands**.
    - With the microphone or speech permission denied, the sheet shows Open Settings.
- [ ] **17.** On a fresh install:
    - the coach says the "what can I say" tip once after its intro, and not on later opens;
    - while ready, the status line alternates with the commands hint;
    - the guide's **Show Voice Commands** button closes the guide and opens the help.
- [ ] **18.** Sound and microphone:
    - While the coach speaks, 🎙 stays a microphone (dimmed).
    - Tap 🔊 mid-sentence: speech stops and music returns to full volume immediately. Nothing more is spoken until you tap 🔊 again or say "unmute", which replies "Coach voice on."
    - Say "mute" between lines to mute the coach by voice.
    - Tap 🎙 while it's listening: it turns red, and prompts switch to "Tap". Tap again to resume listening.
    - Say "stop listening": the mic mutes. Long-press 🎙 and choose Voice Commands.
    - Close and reopen the coach: both mutes are remembered, and a muted mic doesn't start listening (no orange recording dot).

### Form coaching and overlays

- [ ] **19.** Form tips (turn on Show Measurements to see the "Last rep" values):
    - Do a few half presses: after the second, the coach says and shows "Press all the way up." with your elbows and wrists amber.
    - Drop the weights quickly from the top for a few reps: "Lower with control."
    - Press with one arm clearly behind the other: "Press both arms evenly."
    - From the top, lower only to forehead height and press again, twice: "Lower to just above your shoulders."
    - With your hips in view, lean sideways for a second: "Keep your torso centered." With hips out of view, it never appears.
    - Ten clean reps at the guide's pace bring no corrective cues.
- [ ] **20.** No cue repeats within 10 s. Cues start at least 4 s apart, except when a more important cue replaces the one on screen. A cue never cuts off a voice reply or announcement.
- [ ] **21.** Tips never cover your arms or the HUD during the press, at the bottom or the top of the rep, standing far or close. Standing so close that your body fills the screen, cues are spoken without a tip.
- [ ] **22.** A reminder (for example "Brace your core.") appears at set start, isn't spoken, and another appears about every 25 s while reps stay clean.
- [ ] **23.** Mute the coach: tips still appear, silently. With Reduce Motion on, tips appear and disappear without fading.
- [ ] **24.** Voice commands keep working mid-set while cues are spoken. Saying "repeat that" right after a cue repeats it.
- [ ] **25.** Restarting the set, finishing it, or switching exercise clears the tip and the amber joints immediately.

### Exercise, routine, and history coverage

- [ ] **26.** Exercise launch: start shoulder press from Train quick start and confirm the camera opens after its guide. Open Library, choose hammer curl, and verify the first-use guide appears before the camera prompt. Closing the camera returns to the screen that launched it.
- [ ] **27.** Hammer curls, simultaneous: with both arms hanging straight, the Hold ring fills and the set starts. Curl both arms together 10 times; the count reaches 10 and the set completes. The HUD shows "L · R" counts, and each arm's Start line sits below its elbow and its Top line above it, with labels clear of the arms.
- [ ] **28.** Hammer curls, alternating: curl left, then right, and so on. The count goes up once both arms have done a rep ("L 3 · R 2" shows 2). Curling one arm up again from halfway, without hanging straight, doesn't count; after two of those, "Straighten at the bottom." plays. Half curls get "Curl all the way up."
- [ ] **29.** Switching mid-set: during a press set with a few reps, tap **Change exercise** in the edge toolbar and choose Hammer Curl. It asks to discard the reps; confirm, and the curl guide (first time) or setup line follows, with no leftover tip, amber joints, or press lines. Say "change exercise", then "cancel": you're back where you were. Switch back to the press: it resumes at its next set.
- [ ] **30.** Completion: finish both sets of a standalone exercise. The completion card fades in with each set's reps and the total, and the coach names the buttons (no more "push end").
    - **Another Round** (or say "another round") starts set 1 again.
    - **Choose Exercise** (or "change exercise") opens the chooser; Cancel returns to the card.
    - **End Workout** (or "end workout") returns to Train without a duplicate summary. Finish a Saved Set and confirm its full workout summary appears, with Done returning to Train.
    - Ending mid-set with the stop button still asks for confirmation and shows the summary.
- [ ] **31.** Band triceps extension, side-on:
    - Stand side-on with the band under your feet. Framing asks you to stand side-on until one arm is in view.
    - The ghost arm appears on your nearer shoulder, facing your way, with no dumbbells.
    - Stand close with your hips out of frame and your hands behind your head: the ghost arm still appears.
    - Holding your hands behind your head fills the Hold ring. Ten extensions count exactly 10.
    - Turn to face the other way between sets: tracking follows the nearer arm.
    - Folding your hands fully behind your head (where the camera can't see them) still counts. The coach doesn't say it can't see you, and the next rep starts.
    - Half extensions get "Straighten both arms fully."
    - Letting the elbows drift forward gets "Keep your elbows pointing up."
- [ ] **32.** Air squats:
    - Step back until framing stops asking to see your whole body. Standing still doesn't start the set; the status says to say "start".
    - The ghost legs show how low to go.
    - Lower the phone until your head and shoulders are cropped: the ghost legs still appear.
    - Fifteen squats to thighs-level count exactly 15, and half squats don't count ("Squat a little deeper.").
    - Squatting again from halfway gets "Stand all the way up."
    - Letting the knees cave in gets "Keep your knees in line with your toes."
- [ ] **33.** One-arm row:
    - Stand side-on with your left arm nearer the phone, bent forward with a hand on a bench. Holding the dumbbell straight down fills the Hold ring and starts "Set 1 of 2 · Left arm".
    - Keep your hip out of frame: the ghost arm still appears.
    - Row 8–10; at 10 (or "next set") the coach says to switch to your right arm, with no rest timer.
    - Turn around; the ghost turns with you, and the right arm's set starts the same way. After both arms, rest starts.
    - Half pulls get "Pull your elbow up past your back."
    - The summary and completion card list "Set 1 L", "Set 1 R", and so on.
- [ ] **34.** Push-ups:
    - Lay the phone on the floor a step in front of your hands, propped to lean back, and get into a plank facing it. No tilt warning appears.
    - The ghost arms rise from your hands. Holding the plank fills the Hold ring.
    - Ten push-ups to the Down line count exactly 10. Shallow ones get "Go a little lower."
    - Dropping fast gets "Lower with control."
- [ ] **35.** Saved Sets:
    - Create "Upper Body" with shoulder press 2 × 8–10, hammer curl 2 × 10, and shoulder press again 1 × 12. Reorder by dragging, save, quit the app, and reopen: it's still there in order. Duplicate it and delete the copy.
    - Start it: the HUD shows "Exercise 1 of 3".
    - After the last press set, rest begins with "Up next: Hammer Curl"; when rest ends, curls are set up, and nothing counts until you start.
    - Say "next exercise" mid-curl: it skips to the second press, which starts at set 1 of 1.
    - The final card lists the press as completed, curls as skipped, and the last press.
    - In Library, open Hammer Curl and adjust it to 3 × 12, start it, and confirm the set completes at 12. Reset to Default restores 2 × 10.
- [ ] **36.** History:
    - Finish two press sets and end the workout. Workout History from Progress shows it, newest first.
    - Open it, add 17.5 lb to set 1 with "Also for the later sets", and set 2 shows 17.5 lb too. Change set 2 to 8 kg and remove it again.
    - Band triceps take a band name, and push-ups and squats show no weight control.
    - Closing the coach after a finished set (without ending) still saves it. Opening and closing without a set saves nothing. Swipe to delete a workout.
- [ ] **37.** Weights by voice:
    - Mid-set, say "my weights are seventeen point five pounds". The coach says "17.5 pounds.", the Heard chip shows it, and the HUD shows 17.5 lb.
    - The next set keeps 17.5 lb. Say "weight 8 kilograms" mid-set, and the history shows 17.5 lb for set 1 and 8 kg for set 2.
    - With band triceps, say "using the red band".
    - With music playing, saying "I lost five pounds" in conversation sets nothing.
    - Mid-set, say "weight 17.5 pounds" (often heard as "wait"): the set doesn't pause, the coach says "17.5 pounds.", and the HUD shows 17.5 lb.
    - Say "wait" on its own: the set pauses after about a second. "Pause" and "stop" still pause right away.

### Posture camera and settings

- [ ] **38.** Afterward, confirm realtime posture correction still works.
- [ ] **39.** In realtime posture correction, open the gear menu labeled **Feedback settings**. Check Camera tilt compensation, Horizon line, Alignment targets, and the 2 / 5 / 10 per second refresh rate. Change each value in the menu and in Settings → Camera & framing; both places should show the same value.
- [ ] **40.** Set Rest between sets to **Exercise default** and confirm shoulder press rests for 90 seconds and hammer curls for 60. Set it to **45 seconds** and confirm both exercises show a 45-second countdown and matching progress bar. One-arm rows switch sides without a rest, then rest after the second arm. **Skip rest** still starts the next set immediately.
- [ ] **41.** Set Weight units to **kg**. A new History weight entry starts with kg selected, and saying "my weights are twenty" records 20 kg. Saying "my weights are twenty pounds" records 20 lb. Existing history entries keep their recorded unit and value.
- [ ] **42.** Turn **Start by holding position** off. Holding the shoulder press start position does not begin a set; tapping play and saying "start" do. The ready status says "Tap play to start" without voice and "Say ‘start’ or tap play" when voice is available. Air squats still require an explicit start.
- [ ] **43.** Restore defaults and confirm **Exercise default**, **lb**, and Start by holding on. Verify press rests for 90 seconds and curls for 60 seconds, and holding the press start position still starts the set.

These checks remain manual; a passing simulator run does not imply they were performed.
