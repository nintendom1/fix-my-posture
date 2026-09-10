# Persistence & Baseline Comparison Architecture

## Persistence Strategy

The app utilizes **SwiftData** for local metadata storage and the app sandboxed `Documents/AssessmentImages/` directory for full-resolution JPEG image files managed via `ImageStore`.

### Entities

- `AssessmentEntity`: Stores assessment ID, date, view classification, app version, baseline status, and relationships to landmarks and measurements.
- `LandmarkEntity`: Stores landmark type, normalized coordinates, pixel coordinates, confidence, and manual edit flag.
- `MeasurementEntity`: Stores stable `measurementIDRawValue`, user display label, value, unit, confidence, explanation, and used landmarks.

## Baseline Matching Engine

`BaselineComparisonEngine` matches current assessment metrics with baseline metrics using stable `MeasurementID`s:

1. Assessments must share identical posture views (`PostureView`).
2. Measurements are mapped by `MeasurementID` (with automatic fallback mapping for legacy display names via `MeasurementID.fromLegacyName`).
3. Deltas are computed as `currentValue - baselineValue` and formatted with explicit +/- sign strings.
