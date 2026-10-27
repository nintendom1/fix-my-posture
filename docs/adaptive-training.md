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

## Policy

The V1 recommendation policy lands in the next PR.
