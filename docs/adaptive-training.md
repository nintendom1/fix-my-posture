# Adaptive Training

Adaptive training finds a comfortable starting point for each movement and adjusts dose or variant from the user's Too Hard / Okay / Easy feedback.

## Where it lives

`Packages/AdaptiveTraining` is a Foundation-only Swift package. It owns progression policy and cannot import SwiftUI, SwiftData, camera code, or app types. Its package tests run on the Mac:

```bash
swift test --package-path Packages/AdaptiveTraining
```

`PostureAnalysisApp/AdaptiveTraining/` adapts app exercise IDs and outcomes to the package. `ExerciseVariantBridge` maps rungs to `ExerciseDefinition` and reports built exercises and equipment; its `notYetBuilt` list is checked against the app catalog. App callers are `AdaptiveTrainingCoordinator` and the debug provider; screens read recommendations and never compute progression. The coordinator handles prescriptions, evidence, easier swaps, and calibration; `WorkoutOutcomeAdapter` maps finished items to evidence. Policy, projection, and planning stay internal to the package. `./scripts/validate.sh` runs package tests before simulator tests.

## Progression ladders

Each `MovementFamily` is an easiest-first ladder of `ProgressionRung`s. Every rung has a stable `VariantID` (`<family>.<exercise>[.<modifier>]`), app exercise, optional `reducedRange` or `supported` modifier, dose range, and equipment. `MovementFamilyID` and `VariantID` are persisted in evidence and exports; never rename them. The first rung is the explicit floor (`isFloor`), used when the minimum of a harder rung is too hard; a floor needs no equipment.

`ProgressionCatalog` finds the nearest built, equipped easier or harder rung and each family's floor and minimum floor prescription. Unbuilt or unequipped rungs are skipped; a family without an available floor cannot be offered. Validation requires exactly one first, equipment-free floor, unique IDs, and variant IDs prefixed by their family.

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

"Shallow", "partial", and "supported" are modifiers on an exercise, not separate exercises. Rep doses step by 1 and hold doses by 5 seconds. A ladder change bumps the catalog version.

## Evidence and facts

The engine replays five fact types through `AdaptiveTrainingStoring` (SwiftData in the app, in-memory in tests/previews):

- **Prescription:** the requested plan with policy and ladder versions.
- **Evidence (`AdaptiveEvidence`):** prescribed `Dose`, user-confirmed `WorkAmount` and `ConfirmationSource`, separate tracker observation, effort, mid-set Too Hard, optional bonus, completion, and source.
- **Calibration (`CalibrationSessionRecord`):** status, families, equipment, and starting points accepted at commit.
- **Engagement:** notification opened/dismissed or explicit skip.
- **Settings:** equipment change or removed family.

A prescribed `Dose` is at least 1; a `WorkAmount` may be zero. Thus confirmed zero differs from no confirmation (`confirmed == nil`, source `none`), and tracker zero differs from no tracker. Evidence normalization on creation and decode clears confirmed amount/sets without confirmation, clears work/rating on declined bonuses, and removes counts from `notTracked` observations.

Policy invariants: tracking failure is never capacity evidence and tracker counts never replace user confirmation; declining a bonus or harder probe is neutral; completing the prescription and rating it Too Hard is both completion and negative difficulty evidence; engagement can affect confidence or copy, never capacity.

Fact IDs share one namespace: a duplicate ID of the same kind is a no-op; another kind is refused. Only an in-progress calibration can change in place. Committed or abandoned calibrations are immutable and a new attempt needs a new ID. Failed writes store nothing; unreadable, unknown-kind, or mismatched-ID rows are skipped but kept. `AdaptiveFacts` orders replay by time then ID. Its watermark changes with append-only fact IDs or any calibration content, and cached profiles are reusable only for the same policy, catalog/built exercises, and watermark.

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
| Easy below the full prescribed amount, stopped early, switched to an easier version, or ended during the item | `stoppedEarlyHold` | Hold current dose and clear the Easy streak. |
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

The mid-item "Easier version" asks the same table. `AdaptiveTrainingEngine.easierSwap(for:asOf:)` (and the pure
`AdaptiveReplay.easierSwap`) runs these branches on the item's own rung and dose, and returns where Too Hard on that
item would go. It reuses the policy's internal Too Hard computation, so the answer and a Too Hard rating on the same item
always agree. It returns nil for any role but the day's main item, for a family that isn't active, for a rung outside
its family, when the item is already at the floor's minimum, and when nothing easier is available. The easier rung can
count a different unit (a glute bridge's easier rung is a timed hold). `issueEasierSwap(replacing:target:prescriptionID:itemID:at:)`
saves a `todaySession` prescription with one `easierSwap` item for the same family, with caller-provided ids; a target
outside the item's family throws `AdaptiveTrainingEngineError.easierSwapOutsideFamily`. The swap item never offers a bonus.

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

### Events and cache

`AdaptiveEventDeriver` derives replayable events from facts and transitions, oldest first; ties use fact UUID then `AdaptiveEventKind.allCases` order. Calibration commits emit `calibrationCompleted` or `recalibrationCompleted`; increases/harder samples emit `progressed`; decreases/easier variants emit `regressed`; rated non-calibration evidence emits an effort event; completed, stopped-early, or easier-swapped Today's Session main items emit `sessionCompleted`; bonus facts emit `bonusOffered` and accepted/declined; and an absence transition emits `returnedAfterAbsence`.

Successful engine operations return derived events, which `AdaptiveTrainingCoordinator` forwards in order to its observer. Production attaches `WorkoutReminderCoordinator` in `AppEnvironment`. Calibration milestones are evaluated immediately behind reminder-enabled and notification-authorization gates. Workout-bound events wait for a saved record and match its time interval. A live `tinySessionPrescribed` is forwarded only after a successful tiny-session issue; it may precede the saved workout by up to 5 s and must match a Today's Session record. A newer unsaved tiny-session prescription replaces the earlier buffered one. `returnedAfterAbsence` is excluded from the buffered workout events. Unmatched buffered events are discarded after save. Replay-derived events appear in the debug export; the live tiny-session event does not. Persona delivery cannot change adaptive state.

The engine checks its in-memory profile, then the stored cache, then replays all facts. A cached payload is valid only for the policy version, interpretation key (catalog version, built exercise IDs, parameters, calendar time zone), and fact watermark. Cache timestamps use the newest fact rather than the current clock.

## Today's Session flow

The coordinator saves the engine's prescription and prepares its workout plan; the workout screen reports what happened. The app does not decide which rung or dose is easier or harder. See [Workout Coach](workout.md) for the plan, effort card, voice phrases, and saved-workout flow.

## Train and the invitation

When the coordinator is available, Train reads `TodaySessionStatus` and formats that answer for the hero. The app does
not choose a family, variant, or dose. A ready session shows its area, exercise, dose, estimate, and **Start**. A session
already completed today says **Done for today** and names the next area when one is offered. The user's routine remains
available from the card. When setup is needed, the hero links to calibration. When nothing is offered, the normal
routine hero remains.

On launch and when the app becomes active, a small sheet invites a user with `.needsCalibration` to find a starting
point. It stays hidden while a full-screen route is presented. **Find your starting point** closes the sheet before
opening calibration and does not count as a dismissal. **Not now** and a swipe down snooze the sheet for seven days and
increment its saved dismissal count. It stops appearing after the third dismissal. Leaving calibration without saving
allows the invitation to appear at the next app activation unless it is still snoozed.

## Effort card

The screen and voice flow are documented in [Workout Coach](workout.md). WorkoutOutcomeAdapter maps the user's answer and work observed by the coach into evidence; the app reports outcomes, while the package decides progression.

### Evidence mapping

midSetTooHard records the user's explicit flag separately from tracker data. It does not itself choose a prescription; policy decisions use the effort, confirmed work, and completion facts. Bonus evidence records the offered dose (one rep or five seconds), acceptance, completed amount, and optional rating. The policy adds bonusRecordedOnly; a bonus never changes capacity.

| Field | Value |
|---|---|
| source | .adaptive for Today's Session items, .manual otherwise. |
| prescriptionID, prescriptionItemID, prescribed | Today's Session items only. |
| workoutID | The coach's workoutID, also used by the saved workout. |
| family, variant | The prescription item's or the active rung's for manual work. |
| confirmation .user | The user changed the amount, or the item is self-reported or timed. |
| confirmation .trackerAccepted | A rated, unchanged camera count with tracking maintained. |
| confirmation .none | An unchanged, unrated camera count, lost tracking without an amount correction, or an unattempted item; confirmed is nil. |
| confirmed, setAmounts | The card amount. Multiple sets confirm the smallest set; a changed amount applies to each. |
| tracker .tracked | Camera items, with observed equal to counted reps. |
| tracker .lost | A camera item completed while tracking was lost; the count remains observed. |
| tracker .notTracked | Self-reported/timed items, or camera items skipped before work. |
| effort | The card answer; nil when skipped or closed unrated. |
| completion .completed | Every set met or exceeded its target, using the corrected card amount if changed. |
| completion .stoppedEarly | Below target, skipped after work, or stopped with "Stop here, it counts". |
| completion .switchedToEasier | The easier version was taken; the item ends with its work. |
| completion .endedWorkout | The workout ended during the item. |
| midSetTooHard | True only after the user flags Too hard?; it never changes tracker data. |
| completion .notAttempted | Skipped before work, such as a declined harder sample. |
| bonus | Present only when an item was offered a bonus; see above. |

## Bonus reps

Only a Today's Session main item marked to offer a bonus can add bonus evidence. The offer follows a full-dose Easy rating; declining is neutral. The app records accepted/declined status, completed work, and any bonus rating, but V1 never uses those facts to move capacity. See [Workout Coach](workout.md) for the offer, timing, voice phrases, and saved entry.

## Mid-set Too hard

The user's flag is kept as midSetTooHard, regardless of what happens next or what the tracker reports. The set continues unless the user chooses an option. Stopping early can produce .stoppedEarly; taking an easier version records .switchedToEasier. In either case, the workout adapter reports the resulting facts and the package applies its Too Hard policy. See [Workout Coach](workout.md) for the button, choices, and phrase precedence.

## Calibration

The first calibration finds a comfortable starting point for each movement area. It is never a test, a score, or a
label. The screen opens with "Let's find a comfortable starting point. A few tiny samples, no tests." and never says
"score", "level", or "beginner", or uses a medical word. Every rule lives in the package's `CalibrationFlow` (invariant
6). The app shows the step the flow returns and reports what happened.

`CalibrationFlow` is a pure `Codable` value, advanced by inputs like `WorkoutSession`. An input that doesn't fit the
current step is ignored. `step` is one of:

| Step | Shown | Input that answers it |
|---|---|---|
| `.equipment` | Dumbbells and a band, both optional. Skipped when a profile already knows the equipment. | `setEquipment` |
| `.families` | The areas that can be offered, with push and squat preselected. | `setFamilies` (at least one) |
| `.closeness(family, options:)` | "Which feels closest to what you can do comfortably today?" with the family's available rungs, easiest first, and Not sure. Skipped for a family with one available rung. | `answerCloseness(family:variant:)`, nil for Not sure |
| `.probe(family, RungDose, isHarderOffer:)` | One tiny sample, run in the coach and rated Too Hard / Okay / Easy. | `probeResult`, or `declineHarderProbe` for a harder offer |
| `.summary([CalibrationStart])` | One plain line per area, Use these, and a way out. | `engine.commit` or `engine.abandon` |

`skipFamily` leaves one area out until it settles. Families that can't be offered (no available floor) never appear.
No rung that needs dumbbells is asked about or offered without them.

### Rules

- **Start rung.** Not sure starts at the family's floor. An answer starts at that rung, but no higher than the middle rung
  of the available ladder (the lower middle when the count is even). Push without equipment starts no higher than the
  wall push-up. The samples can climb from there.
- **Sample dose.** The first sample is 2 reps for a rep rung whose range allows it, otherwise the rung's minimum. A harder
  or easier sample is the rung's minimum.
- **Okay** settles at the sample's dose.
- **Easy** offers the next harder available rung at its minimum (`isHarderOffer`). If nothing is harder, the limit is
  reached, or a Too Hard was already seen in that family, it settles at the sample's dose. A single Easy never raises the
  starting dose.
- **Declining a harder offer** settles at the last Okay or Easy sample, at that sample's own dose. It is neutral: it adds
  no sample and no evidence.
- **Too Hard** is authoritative even when the work was finished. On a harder offer it settles at the last comfortable
  sample, because the easier rung was already comfortable. Otherwise it samples the next easier available rung at its
  minimum, or settles at the floor's minimum when there is none.
- **Nothing confirmed.** Okay or Easy with no confirmed work proves nothing, so the same sample is offered again and
  counts toward the limit.
- **Limit.** A family gets at most 3 samples. After the third it settles at its last comfortable sample, or the floor's
  minimum if none was.
- **Starting dose.** The starting dose is the settled sample's dose.
- **Recalibration.** The active areas are preselected and the user can add or drop areas. When a chosen area's current
  rung is still available, the flow skips closeness and samples that rung at its first-sample dose. A new area has no
  current rung, so it gets the closeness question. Equipment is already known and is not asked again.
- **Keep the current dose.** In recalibration, an Okay or Easy sample of the current rung with confirmed work settles
  at the greater of the sample dose and the current dose. Okay therefore keeps the prescription. Easy can offer the next
  rung; declining keeps the current dose. Too Hard steps down one available rung at its minimum. Other rungs settle at
  their sample dose. These rules do not change the initial calibration.
- **Add an area.** The flow offers only inactive families and preselects none. An already active family is dropped from
  the choice. The new family gets the usual closeness and sample steps; commit adds it to the rotation and leaves the
  existing families unchanged.

### Facts

The flow builds the `CalibrationSessionRecord`. `engine.startCalibration(kind:id:at:)` saves it in progress, which changes
no recommendation. `saveProgress` updates its families and equipment. `commit(_:at:)` saves it committed with
`startingPoints` and `equipment`; it throws `calibrationNotAtSummary` unless the flow is at a summary with at least one
starting point. `abandon(_:at:)` saves it abandoned with no starting points. All three go through `save(_:)`, so a
committed or abandoned attempt can't change again (`calibrationChangeNotAllowed`).

Each rated sample is `AdaptiveEvidence` with `source: .calibration` and the attempt's `calibrationID`, recorded by the
app through `record(_:)` as the coach finishes it. Replay applies a committed attempt's samples at commit time and
ignores an uncommitted attempt's, so abandoning changes nothing (invariant 7). A sample's prescription (kind
`calibrationProbe`) is built for the coach but never saved.

### In the app

- **Entry.** Settings › Adaptive Training offers initial, recalibration, and add-an-area flows. Settings › Developer diagnostics › Adaptive training also has **Find my starting point** for initial calibration. Reminder taps do not replace the open screen.
- **Samples.** The coordinator gives the coach a one-item "Finding your starting point" plan with no routine ID, bonus, or easier version. Its `CalibrationProbeRecorder` saves sample evidence as calibration evidence, but `savesHistory: false` prevents a workout-history entry or reminder. Closing or skipping before a rating changes no starting point; the same sample can be retried or the family skipped.
- **Commit and abandon.** **Use these** commits starting points from the summary. Leaving a started flow, or choosing **Leave without saving**, saves an abandoned calibration with no starting points and does not change recommendations.

## Settings

Settings shows setup status, active areas and their current exercise and dose, plus **Add an area**, **Recalibrate**, and dumbbell/band choices when available. Removal keeps history and is disabled for the last active area. Equipment changes availability and can move a current prescription to an available easier rung. If the profile cannot be read, controls are unavailable. Preference storage is covered in [Persistence](persistence.md).

## Debug view and export

The debug page and export contain a read-only `AdaptiveSnapshot`: current prescription and rationale, bounded recent evidence, counts, Today's Session status, replayed profile and events, and the facts needed to interpret them. Exports contain no photos, frames, device IDs, or account IDs. Dates use round-trip-safe ISO-8601 UTC with nine fractional digits; keys are sorted, and encoding and writing run off the main thread.

Run `make adaptive-replay FILE="export.json"` to replay recorded parameters. Add `PARAMS="parameters.json"` to compare candidate `PolicyParameters`. The report lists changed prescriptions and transitions by fact ID, family, and occurrence; it does not write facts or modify the export.
