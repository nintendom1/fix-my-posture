# Persistence & Baseline Comparison Architecture

## Persistence Strategy

The app utilizes **SwiftData** for local metadata storage and the app sandboxed `Documents/AssessmentImages/` directory for full-resolution JPEG image files managed via `ImageStore`.

## Preferences

`AppPreferencesStoring` centralizes app preferences. `UserDefaultsPreferences` preserves these existing keys and formats: `cameraTiltCompensationEnabled` (Bool, default `true`), `showHorizonLine` (Bool, default `true`), `feedbackRefreshRate` (Int, default `5`), `workoutCoach.showMeasurements` (Bool, default `false`), `workoutCoach.coachMuted` (Bool, default `false`), `workoutCoach.micMuted` (Bool, default `false`), `workoutCoach.voiceTipSpoken` (Bool, default `false`), `workoutCoach.guideSeen.<exerciseID>` (Bool, default `false`), and `workoutCoach.target.<exerciseID>` (JSON-encoded `ExerciseTarget` `Data`, default absent). These keys preserve settings written by earlier app versions.

Future workout settings use new namespaced keys: `settings.restPolicy` (JSON `Data`, default `exerciseDefault`, fixed seconds clamped to 30–120), `settings.weightUnit` (String `lb` or `kg`, default `lb`), `train.startByHolding` (Bool, default `true`), and `train.upNextOverride` (optional UUID string, default absent).

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
