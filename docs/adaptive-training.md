# Adaptive Training

Adaptive training finds a comfortable starting point for each movement and moves the dose or variant up or down
from the user's own Too Hard / Okay / Easy feedback. This document grows with each PR in the adaptive-training stack
(#99–#114); sections that have not landed yet are marked as such.

## Where it lives

The engine is a local Swift package, `Packages/AdaptiveTraining`, linked into the app target. It imports only
Foundation, so it can never reach SwiftUI, SwiftData, the camera, or app types such as `WorkoutRecord` or
`ExerciseID`; it names exercises by their stable string IDs. Its tests run on the Mac in seconds:

```bash
swift test --package-path Packages/AdaptiveTraining
```

`./scripts/validate.sh` (and so CI) runs those tests before the simulator tests.

App code reaches the package through adapters in `PostureAnalysisApp/AdaptiveTraining/`:

- `ExerciseVariantBridge` maps a ladder rung to the coach's `ExerciseDefinition` and tells the engine which rungs
  the app can offer (`Availability`: the exercises that exist, limited by the user's equipment). Its
  `notYetBuilt` list names ladder exercises that the app hasn't added yet; each exercise PR removes its ID, and
  `ExerciseVariantBridgeTests` fails if the list and the catalog disagree.
- `AdaptiveTrainingCoordinator` is the one app object that calls the engine, besides the debug provider. It reports
  Today's Session, prepares it as a workout plan, answers which rung an exercise is, and records evidence.
- `WorkoutOutcomeAdapter` is a pure mapping from a finished workout item and the effort card's answer to
  `AdaptiveEvidence`. `FinishedItemDetector` finds finished items by comparing the workout session before and after
  an input.

Dependencies point one way: the app imports the package, never the reverse, so package code can't name app types.
`PackageBoundaryTests` fails if any package source imports anything but Foundation. The policy, projection, and
planning code that later PRs add stays `internal` to the package, exposed only through the engine's public entry
point, so screens can read recommendations but never compute them.

## Progression ladders

A `MovementFamily` is an ordered ladder of `ProgressionRung`s, easiest first. Each rung has a stable `VariantID`
(`<family>.<exercise>[.<modifier>]`), the app exercise it runs, optional `PrescriptionModifier`s
(`reducedRange`, `supported`), a `DoseRange` in reps or seconds, and the equipment it needs. The first rung is the
family's explicit floor (`isFloor`): where the policy goes when one rep of anything harder is too hard. A floor never
needs equipment.

`ProgressionCatalog` answers, for any variant, the nearest available `easier(than:)` and `harder(than:)` rung and a
family's `floor(of:)` and `floorPrescription(of:)` (the floor at its minimum dose). Rungs the app hasn't built, or
that need equipment the user lacks, are skipped. A family whose floor isn't available can't be offered, because
there would be nowhere safe to regress. `problems` checks the structure: exactly one floor, first, with no
equipment; unique IDs; and every variant prefixed by its family.

V1 ladders (`ProgressionCatalog.v1`, version `ladders-1`; `*` marks the floor):

| Family | Ladder | Dose ranges |
|---|---|---|
| push | shallow wall push-up* → wall push-up → incline push-up → push-up | 1–8, 1–12, 1–12, 1–15 reps |
| squat | partial sit-to-stand* → sit-to-stand → air squat | 1–8, 1–12, 1–20 reps |
| row | seated scapular squeeze* → dumbbell row (dumbbells) | 1–12, 1–12 reps |
| overhead | partial supported wall slide* → supported wall slide → shoulder press (dumbbells) | 1–8, 1–12, 1–12 reps |
| hinge | supported shallow hip hinge* → hip hinge → stiff-leg deadlift (dumbbells) | 1–8, 1–12, 1–12 reps |
| glute | glute squeeze hold* → glute bridge | 5–30 s, 1–15 reps |
| lunge | supported weight shift* → weight shift → rear lunge (dumbbells) | 1–10, 1–12, 1–10 reps |
| neck | gentle chin tuck* (dose only) | 1–12 reps |
| core | abdominal brace* (dose only) | 5–45 s |

"Shallow", "partial", and "supported" rungs are modifiers on one exercise, not separate exercises. Hold doses step by
5 seconds; rep doses by 1. Variant IDs and family IDs are persisted in evidence and exports: never rename one. A
ladder change bumps the catalog `version`.

## Evidence and facts

The engine's source of truth is five kinds of facts, stored in SwiftData through the package's
`AdaptiveTrainingStoring` protocol (`SwiftDataAdaptiveTrainingRepository` in the app,
`InMemoryAdaptiveTrainingStore` for tests and previews):

- **Prescription**: what the app asked for, saved when the user starts it, with its policy and ladder versions.
- **Evidence** (`AdaptiveEvidence`): what happened on one rung. It keeps three amounts apart: what was asked
  (`prescribed`, a `Dose`), what the user confirmed (`confirmed`, a `WorkAmount`, with its `ConfirmationSource`), and
  what the tracker saw (`TrackerObservation`). It also records effort (Too Hard / Okay / Easy), a mid-set Too Hard,
  an optional bonus, how the item ended, and its source (calibration, adaptive, manual, recalibration).
- **Calibration** (`CalibrationSessionRecord`): one attempt's status, families, equipment answer, and the starting
  points accepted at commit.
- **Engagement**: a notification opened or dismissed, or an explicit skip.
- **Settings**: an equipment change or a removed family.

A `Dose` (a prescription) is always at least 1. A `WorkAmount` (work done or seen) may be zero, so "the user confirmed
zero reps" and "nobody confirmed anything" (`confirmed == nil`, confirmation `none`) stay different facts, and so do
"the tracker counted zero" and "the tracker didn't run". Evidence normalizes itself on creation and on decoding: no
confirmation means no confirmed amount and no confirmed sets; a declined bonus carries no work or rating; a
`notTracked` observation carries no count.

Semantics the policy relies on: tracking failure is never capacity evidence (`tracked`, `lowConfidence`, `lost`, and
`notTracked` are explicit, and a tracker count never stands in for the user's confirmation); declining a bonus or a
harder probe is neutral; completing the prescribed reps and rating them Too Hard is both a completion and negative
difficulty evidence; engagement facts may change confidence or copy, never capacity.

Identity: fact ids are one namespace across all five kinds. Recording an id that is already stored as the same kind
does nothing (facts are append-only); an id stored as another kind is refused. A calibration is the only fact updated
in place, and only while it is in progress; a committed or abandoned attempt never changes, and a new attempt needs a
new id. A failed write leaves nothing behind, so retrying it records the fact. Rows whose payload can't be read, whose
kind is unknown, or whose payload names a different id are skipped and kept, never deleted.

`AdaptiveFacts` always holds its facts in replay order (time, then id), including after decoding. Its `watermark`
counts append-only facts by id and calibrations by their full contents, so any change to what was stored changes it.
A cached profile is valid only for the policy version, the ladders and built exercises, and the watermark it was built
from; otherwise the engine replays the facts.

## Policy V1

`AdaptiveReplay.profile` rebuilds the profile from facts. It does not depend on input array order. Evidence, settings,
engagement, and calibration commits replay by their effective time, then fact UUID. A calibration uses its end time, or
its start time when it has no end time. Prescriptions provide item roles and targets but do not produce transitions.
Each capacity or engagement fact gets a transition that records the decision and its rationale.

Equipment in force starts empty. A committed calibration or `equipmentChanged` setting replaces it. Availability is the
built exercise set plus the equipment in force at that point in the replay. A family's floor must be available before
it can be offered.

### Evidence decisions

V1 checks evidence in this order. `TrackerObservation` is never read for capacity. An accepted tracker count matters
only because the app records a separate confirmation source and confirmed amount.

| Condition | Decision | Capacity effect |
|---|---|---|
| Evidence belongs to a calibration | `calibrationProbe` or `calibrationNotCommitted` | A committed probe updates comfortable dose and performance time only. An uncommitted probe has no effect. |
| Variant is outside its family, family is not started, or family was removed | `familyInactive` | None. |
| Item was not attempted | `notAttempted`; a declined harder sample also gets `harderSampleDeclined` | None. The sample remains due. |
| No effort rating | `unrated`; also `trackingOnly` when confirmation is `none` | None. Performance time still updates for an active family. |
| Okay/Easy without confirmed work | `unconfirmedRating` or `nothingCompleted` for confirmed zero | None. |
| Okay/Easy on an easier swap | `easierSwapRecorded` | Comfortable dose only. |
| Okay on the main item | `okayHold` | Hold current dose, clear the Easy streak, and raise confidence. |
| Easy below the full prescribed amount, stopped early, or ended during the item | `stoppedEarlyHold` | Hold current dose and clear the Easy streak. |
| Easy on the main item | `easyOnceHold` or `easyStreakIncrease` | Two Easy ratings on different days within the recency window add one dose step. Same-day Easy does not increment the streak. |
| Easy at the top of the dose range | `topOfRangeSampleOffered` | Offer the next available rung as an optional sample. |
| Okay/Easy on a harder sample | `harderSampleAccepted` | Move to that rung at its minimum dose. |
| Too Hard on a harder sample | `harderSampleTooHard` | Keep current dose, clear the due flag and the Easy streak, and block samples for the cooldown. |

An Easy streak requires different calendar days in the supplied calendar. A stale prior Easy starts a new streak and
adds `staleHistoryIgnored`. An Okay, stopped attempt, Too Hard decision, calibration start, or capacity change clears
the streak. A bonus adds `bonusRecordedOnly`; its acceptance and completion never change capacity.

Too Hard is authoritative, including when the item was completed. The policy checks the branches in order:

| Branch | Result |
|---|---|
| A recent comfortable dose on the performed rung is lower than the Too Hard dose | Use it (`tooHardBackToComfortable`). |
| The dose is above the rung minimum | Reduce by at least one step, rounding the configured reduction up to a full step (`tooHardReducedDose`). |
| The dose is at the minimum and an easier rung is available | Use its recent comfortable dose or its minimum (`tooHardEasierRung`). |
| No easier rung is available | Keep the performed rung at its minimum (`tooHardAtFloor`). |

Too Hard clears the Easy streak and pending harder sample, lowers confidence, and removes comfortable doses on the
performed rung that are at or above the Too Hard dose. At the floor minimum confidence is low. Too Hard on something
harder than `current` (a harder rung, or a higher dose on the same rung, such as an older prescription) is recorded
without moving capacity, whatever its source. A manual Too Hard with no positive work uses the performed rung's minimum
as its dose.

Manual Okay/Easy work on a harder rung advances by one available rung only, and never past the rung performed. On the
current rung, manual work at or above the current dose follows the main-item rules (Okay holds, Easy counts toward the
streak); less than the current dose is recorded without changing the streak. Manual work on an easier rung records a
comfortable dose only.

The first Okay or Easy after `absenceDays` or more without performing the family holds, clears the Easy streak, sets
confidence to medium, and adds `returnedAfterAbsence`. This applies to main, manual, and harder-sample evidence. Too
Hard still applies after an absence.

V1 defaults (`PolicyParameters.standard`): two Easy ratings on different days to add a step, a 25% Too Hard reduction
rounded up to a full step, a 28-day recency window, a 14-day absence threshold, and a 7-day harder-sample cooldown.

### Replay invariants

- The same facts, catalog, built exercises, parameters, and calendar produce the same encoded profile.
- Tracking loss, tracker counts, and tracking signals do not imply physical failure or completion.
- Time passing alone does not make a transition or change a prescription. Query-time confidence can become low after
  the absence threshold.
- Declining a bonus or harder sample is neutral. A declined sample remains due.
- Session context changes only the returned session. A tiny context does not write facts or change the profile.
- Calibration probes are applied at the calibration commit time before starting points. They change comfort and
  performance time only, ordered by each probe's own time: an older probe never replaces a newer comfortable dose or
  moves `lastPerformedAt` back, and a Too Hard probe removes comfortable doses rated before it. A committed
  recalibration replaces `current` and keeps prior comfortable doses.
- One manual fact can advance at most one rung.
- Every rationale names the family, stable variant ID, dose, and a short reason. A streak increase includes every
  distinct-day Easy fact that supports it.

### Today's Session

No states means `.needsCalibration`. States with no active family means `.nothingOffered`. Otherwise the planner
chooses the active family with the oldest `lastPerformedAt`; a never-performed family comes first, and ties follow
catalog order. Skipped days do not change the rotation. A completed main item from a Today Session prescription on
the current calendar day returns `.completedToday` with the family that would rotate next.

The main item uses `current`, clamped to the rung's dose range. If that rung is unavailable, the planner uses the
nearest easier available rung at its minimum. A tiny context uses the main rung minimum and omits a harder sample.
Otherwise a due sample is offered at the next available rung's minimum when its cooldown has expired. Main items offer
a bonus. `isTiny` is true when the main dose is the rung minimum. Confidence is read as of the requested time.

Estimated time is 45 seconds plus four seconds per rep, or the hold duration in seconds, plus 25 seconds when a sample
is offered. The rationale is the family's latest non-record-only transition, or its calibration starting point.

### Semantic events

`AdaptiveEventDeriver` derives events from facts and transitions, oldest first. Ties use the fact UUID and then
`AdaptiveEventKind.allCases` order. Starts from an initial or add-family calibration produce one
`calibrationCompleted`; recalibration produces one `recalibrationCompleted`. Increases and harder samples produce
`progressed`; decreases and easier variants produce `regressed`. Rated evidence produces an effort event unless it is
a calibration probe. Completed adaptive main items produce `sessionCompleted`. Bonus facts produce `bonusOffered` and
either `bonusAccepted` or `bonusDeclined`. A transition after absence produces `returnedAfterAbsence`.
`tinySessionPrescribed` is raised by the app from `TodaySession.isTiny`, not from replay.

### Cache

The engine checks its in-memory profile, then the stored cache, then replays all facts. A stored payload is reusable
only when the policy version, interpretation key, and fact watermark match. The interpretation key covers catalog
version, built exercise IDs, policy parameters, and calendar time zone. The watermark changes when an append-only fact
is added or a calibration's contents change. Cache timestamps come from the newest fact, not the current clock.

## Today's Session flow

The app never decides what is easier or harder. It runs what the engine returns and records the facts of what happened.

- **Starting.** `AdaptiveTrainingCoordinator.start(asOf:)` works only while the engine's status is `.ready`. It saves the
  prescription with `issue(...)`, with a new id for the prescription, the main item, and the sample item, and prepares a
  `TodaySessionLaunch`: the prescription, a `WorkoutPlan`, and one `AdaptivePlanItem` per plan item (item id, role,
  family, `RungDose`, exercise, and reduced range). `AppRoute.todaySession` (Train tab, full screen) reads the prepared
  launch from the coordinator, so the route carries no plan.
- **Developer entry point.** Settings › Developer diagnostics › Adaptive training has **Start Today's Session**
  (`adaptiveDebugStartTodayButton`). It is enabled only for `.ready`. The Train hero arrives in PR 14.
- **Plan shape.** The plan is named "Today's Session" and has the fixed id `AdaptiveTrainingCoordinator.todaySessionPlanID`
  (`70DA0000-0000-4000-8000-000000000001`). The main item is one set whose `targetReps` is the dose, in seconds for a
  timed dose. An optional harder sample is one set at its dose, labeled "Optional: <name>" wherever the plan shows item
  names. A plan item's id is its prescription item's id.
- **Reduced range.** `WorkoutPlanItem.reducedRange` runs the exercise's smaller-range variant, so a shallow floor and its
  full-range sample can share one exercise id in one plan. When the next occurrence is the same exercise from the same
  camera view, the session keeps its framing instead of resetting it, because the camera reports framing only when it
  changes and counting would otherwise stay off for the whole next set.
- **Saved names.** A saved entry is named from the plan occurrence it ran: "Shallow Wall Push-Up" for a reduced-range
  main item, and "Optional: <name>" for the harder sample. The completion stats add "Optional: " only to an older entry
  that lacks it.
- **When a session can't start.** If the main rung has no exercise, or its exercise counts a different unit than the dose,
  `start` returns nil and saves nothing. The debug page shows why. A sample the coach can't run is left out of the
  prescription as well, so nothing is recorded that was never offered.
- **Not a routine.** Today's Session saves a normal `WorkoutRecord` with `planID = todaySessionPlanID` and
  `planName = "Today's Session"`. The plan id matches no routine, so `RoutineRotation` never counts it, and
  `WorkoutHistorySaver` does not clear the Up Next override for it. A one-rep session saves and shows in History and
  Progress like any workout.
- **Completion screen.** For Today's Session the title is "Today's session complete" and the subtitle never says "every
  set done". A session under a minute shows its actual length ("40 s"), or "Done" under one second, instead of "<1m". A
  skipped optional sample reads "Optional, skipped". Other workouts keep their copy. There is no survey after the effort
  cards.

## Effort card

After a prescribed item the coach asks "How was that?" with Too Hard, Okay, and Easy. The question is about the amount,
not about whether the user was able to do it.

- **When it appears.** Whenever an eligible item finishes. The coach detects that from `WorkoutSession` changes (plan
  records, progress, and phase) in `WorkoutCoachModel.dispatch`; the reducer is unaware of the card.
  - A Today's Session plan item that completed, stopped early, or was skipped.
  - In any other workout, an exercise that is the current rung of an **active** family.
    `AdaptiveTrainingCoordinator.activeRung(for:reducedRange:)` answers from the profile and compares the exercise and
    its reduced range with the rung's modifiers. The app never compares difficulty. A routine exercise skipped before
    any work asks nothing.
  - An exercise outside a plan finishes with its last set. A routine or Today's Session item finishes with its record.
  - **Skipping after work keeps the work.** The session record keeps only finished sets, so the detector reads the set
    being skipped from the session before the skip: counted reps for a camera exercise, seconds held for a timed hold.
    A self-reported rep set that nobody marked done adds nothing. Skipping before any work is still `.notAttempted`.
- **What it shows.** A large card over the camera, clear of the bottom controls: the title, the amount ("3 reps" or
  "20 s") with − and + (reps by 1, seconds by 5, never below 0), three buttons (`effortTooHardButton`,
  `effortOkayButton`, `effortEasyButton`) with VoiceOver labels and hints, and a small **Skip** (`effortSkipButton`).
  With several sets the amount reads "each set".
- **Default amount.** Counted reps for camera items, the recorded amount for self-reported items, the seconds recorded
  for timed holds, and 0 for a skipped item.
- **Never blocks.** Rest keeps running under the card. Starting the next set, or ending the workout, closes it unrated
  and records that. A second finished item closes the first card unrated. Closing the screen records an open card
  unrated. When the last item finishes, the completion screen waits until the card is answered or skipped. If the
  workout ends during an item, nothing is asked: the item is recorded as ended.
- **Work that never finished.** When the workout ends, or its screen closes, an eligible exercise that has finished
  sets but not all of them (the first of two, then End during rest) is recorded once as `.endedWorkout`, unrated, with
  the sets it has. The coach remembers which items it has reported, so ending and then closing records once.
- **Voice.** While the card is open, `WorkoutVoiceController` asks `EffortPhraseParser` before the command parser. It
  maps "too hard", "too difficult", "that was too hard", "okay", "ok", "fine", "good", "that was okay", "easy",
  "too easy", and "that was easy". The longest phrase wins. The only other words allowed are polite fillers ("please",
  "um", "so", "yeah", "coach", "it was", "really", and "okay" itself), so a phrase that carries a command ("okay
  start", "okay end workout") or a negation ("not easy") is not an answer and reaches the command parser instead. The
  effort parser sees the raw transcript first because "okay" is a filler word to the command parser. An effort phrase
  never runs as a command, and "skip" is not an effort phrase.
- **Streaming speech.** A partial transcript that parses as an answer waits: it answers once the transcript is final or
  has stayed unchanged for 0.6 s. If more words arrive first ("okay" becomes "okay start"), nothing is answered and the
  normal parser handles the whole phrase.
- **Recording.** `WorkoutOutcomeAdapter.evidence(...)` builds the evidence, and `AdaptiveTrainingCoordinator.record(_:)`
  saves it. The model reaches the coordinator through `AdaptiveEvidenceRecording`, which the factory injects. It is nil
  for workouts with no engine, which never ask. A failed save is logged and never reaches the workout.

### Evidence mapping

`WorkoutOutcomeAdapter` is pure and decides nothing about difficulty. Rejection reasons stay empty because the session
doesn't keep the analyzer's rep rejections. `midSetTooHard` is false and `bonus` is nil until later PRs.

| Field | Value |
|---|---|
| `source` | `.adaptive` for Today's Session items, `.manual` for anything else. |
| `prescriptionID`, `prescriptionItemID`, `prescribed` | Today's Session items only. |
| `workoutID` | The coach's `workoutID`, which is also the saved workout's id. |
| `family`, `variant` | The prescription item's, or the active rung's for manual work. |
| `confirmation` `.user` | The user changed the amount, or the item is self-reported or a timed hold. |
| `confirmation` `.trackerAccepted` | A camera count that was rated and not changed, with tracking not lost. |
| `confirmation` `.none` | A camera count that was unrated and unchanged, or tracking was lost and the amount was not changed, or the item was not attempted. `confirmed` is nil. |
| `confirmed`, `setAmounts` | The card's amount. An item with several sets confirms its smallest set; a changed amount applies to each set. |
| `tracker` `.tracked` | Camera items, with `observed` set to the counted reps. |
| `tracker` `.lost` | A camera item that finished while tracking was lost; the count is kept as `observed`. |
| `tracker` `.notTracked` | Self-reported or timed items, and camera items skipped before any work. |
| `effort` | The card's answer; nil when skipped or closed unrated. |
| `completion` `.completed` | Every set done at or above the target (the card's amount counts if the user changed it). |
| `completion` `.stoppedEarly` | Done with less than the target, or skipped after some work (the counted reps or seconds held, read from before the skip). |
| `completion` `.endedWorkout` | The workout ended during the item. |
| `completion` `.notAttempted` | Skipped before any work, such as a declined harder sample. |

## Debug view and export

Settings › Developer diagnostics › Adaptive training shows the same read-only `AdaptiveSnapshot` that the developer
export encodes. It includes each state's current prescription and rationale, bounded recent evidence, counts, today's
session status, the replayed profile and semantic events, and the facts needed to interpret the result. It contains no
photos, frames, device identifiers, or account identifiers. Dates use ISO-8601 UTC with nine fractional digits, so
they survive a round trip exactly: decoding an export and encoding it again gives the same bytes, and replaying it
gives the engine's decisions even for facts less than a millisecond apart. Decoding also accepts fewer fractional
digits or none. JSON keys are sorted for repeatable exports. The page encodes and writes the export off the main
thread, so a long history doesn't stall it.

Use `make adaptive-replay FILE="export.json"` to replay an export under its recorded parameters. Add
`PARAMS="parameters.json"` to compare a candidate `PolicyParameters` value. The report lists changed prescriptions
and transitions, matched by fact id, family, and occurrence: a transition only the replay makes shows as
`none → <decision>`, and one it no longer makes shows as `<decision> → none`. It does not write facts or modify the
export.
