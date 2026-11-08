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

## Evidence, state, and policy

_Lands in the next PRs of the stack (facts and persistence, then the V1 recommendation policy)._
