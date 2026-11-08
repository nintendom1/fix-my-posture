# Persistence & Baseline Comparison Architecture

## Persistence Strategy

The app utilizes **SwiftData** for local metadata storage and the app sandboxed `Documents/AssessmentImages/` directory for full-resolution JPEG image files managed via `ImageStore`.

### Versioned schema and migration

`Schema/SchemaV1.swift` is the immutable first snapshot. Its five models are `AssessmentEntity`, `LandmarkEntity`, `MeasurementEntity`, `SavedExerciseSetEntity`, and `WorkoutRecordEntity`. `Schema/SchemaV2.swift` is the current complete snapshot. It copies those models unchanged and adds `AdaptiveFactEntity` and `AdaptiveProfileCacheEntity`; the app's model typealiases point to V2. `WorkoutRecordEntity.planID` stays optional so records made outside a Saved Set have no routine identifier.

`AppMigrationPlan` includes both snapshots and a lightweight stage from V1 to V2. `SchemaMigrationTests` creates a V1 store directly, opens it through `AppModelContainer`, and checks that its workout, Saved Set, assessment, landmarks, and measurements survive without invoking the unreadable-store fallback. A fresh V2 store contains all seven models. Stores written before `SchemaV1` existed (the earlier unversioned container) are not migrated; that limitation predates V2.

If SwiftData cannot open a store, the app logs the failure, copies the store plus its SQLite `-shm` and `-wal` companions to `<store>.unreadable-<UTC yyyyMMdd-HHmmss>` (adding `-2`, `-3`, … rather than overwriting an earlier copy), removes the original files only after all copies succeed, and tries a fresh store. A valid V1 store must migrate instead of reaching this fallback. Assessment images are separate files; images left behind when a store is reset may remain orphaned.

To add another schema version:

1. Add `SchemaV<N>` as another complete `VersionedSchema` snapshot. Copy the model declarations from the current version and make the intended changes in the new one; never edit a version after it has shipped.
2. Set its identifier to the next version and include every current model in its `models`.
3. Append it to `AppMigrationPlan.schemas` and add an explicit `MigrationStage` from the previous version. Use a lightweight stage only when SwiftData can infer the change; use a custom stage for data transformations.
4. Point `AppModelContainer` and the model typealiases at the new version, and add tests that open a store of the previous version and a fresh store.

Do not use the unreadable-store fallback as a substitute for a migration that a release promises to perform.

### Repositories

`Repositories/` defines main-actor `WorkoutHistoryRepository`, `RoutineRepository`, and `AssessmentRepository` protocols with SwiftData implementations that receive a `ModelContext`. The repositories save explicitly, log failures, and expose value types for list operations. Views can retain `@Query` for reactive reads; assessment, Saved Set, and workout-history writes go through the repository container injected at the app root. `ImageStoring` wraps the shared `ImageStore` for photo save, load, and deletion.

- Workout history lists newest first, saves records, updates their entries when weights change, and deletes records.
- Routine storage lists, saves, duplicates using the existing `"Name Copy"` rule, and deletes user Saved Sets. `BuiltInRoutineRepository` decorates it with the read-only starter catalog, keeps starter ids out of base writes, and saves starter duplicates as user copies. Corrupt item JSON continues to decode as an empty list.
- Assessment storage maps domain landmarks and measurements to their SwiftData child models, keeps at most one baseline per posture view, and deletes assessments. Corrupt workout entry JSON continues to decode as an empty list.
- `SwiftDataAdaptiveTrainingRepository` stores prescriptions, evidence, calibrations, engagement, and settings as JSON payloads in `AdaptiveFactEntity`; it stores one cached interpretation in `AdaptiveProfileCacheEntity`. It skips and logs facts with an unknown kind or unreadable payload without deleting them, so a fact kind this version doesn't know is kept for a later version. Saving a calibration updates its own row in place and never overwrites another fact that shares its id.

## Preferences

`AppPreferencesStoring` centralizes app preferences. `UserDefaultsPreferences` preserves these existing keys and formats: `cameraTiltCompensationEnabled` (Bool, default `true`), `showHorizonLine` (Bool, default `true`), `feedbackRefreshRate` (Int, default `5`), `workoutCoach.showMeasurements` (Bool, default `false`), `workoutCoach.coachMuted` (Bool, default `false`), `workoutCoach.micMuted` (Bool, default `false`), `workoutCoach.voiceTipSpoken` (Bool, default `false`), `workoutCoach.guideSeen.<exerciseID>` (Bool, default `false`), and `workoutCoach.target.<exerciseID>` (JSON-encoded `ExerciseTarget` `Data`, default absent). These keys preserve settings written by earlier app versions.

Future workout settings use new namespaced keys: `settings.restPolicy` (JSON `Data`, default `exerciseDefault`, fixed seconds clamped to 30–120), `settings.weightUnit` (String `lb` or `kg`, default `lb`), `settings.tiltWarningsEnabled` (Bool, default `true`), `train.startByHolding` (Bool, default `true`), and `train.upNextOverride` (optional UUID string, default absent). Extra Personable uses `settings.extraPersonable` (Bool, default `true`), `persona.resetDate` (optional Double seconds since 1970, set by Reset Persona), and `persona.introCardDismissed` (Bool, default `false`); its decision traces and engagement events live in `persona-traces.json` in Application Support, not in SwiftData. When tilt warnings are disabled, the workout model does not surface phone tilt state or warning events.

### Entities

- `AssessmentEntity`: Stores assessment ID, date, view classification, app version, baseline status, and relationships to landmarks and measurements.
- Camera assessments may also store a nullable original-image horizon angle, its source, and whether compensation was applied. A missing field set identifies legacy/library records and keeps them uncompensated. Comparisons explicitly warn when only one side used compensation.
- `LandmarkEntity`: Stores landmark type, normalized coordinates, pixel coordinates, confidence, and manual edit flag.
- `MeasurementEntity`: Stores stable `measurementIDRawValue`, user display label, value, unit, confidence, explanation, and used landmarks.

## Baseline Matching Engine

`BaselineComparisonEngine` matches current assessment metrics with baseline metrics using stable `MeasurementID`s:

1. Assessments must share identical posture views (`PostureView`).
2. Measurements are mapped by `MeasurementID` (with automatic fallback mapping for legacy display names via `MeasurementID.fromLegacyName`).
3. Deltas are computed as `currentValue - baselineValue` and formatted with explicit +/- sign strings.
