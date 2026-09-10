# Posture Analysis App (iOS Native)

A native Swift and SwiftUI iOS application designed for iPhone 15 Pro that analyzes standing posture from still photos on-device using Apple Vision framework.

## Project Architecture & Tech Stack

- **Target OS**: iOS 17.0+
- **Frameworks**: SwiftUI, Apple Vision (`VNDetectHumanBodyPoseRequest`), SwiftData, AVFoundation, PhotosUI
- **Privacy & Execution**: 100% on-device processing. Zero networking, backend, or cloud dependencies.

## Key Directory Structure Map

```text
PostureAnalysisApp/
├── Models/              # Domain models (BodyPose, Landmark, PostureMeasurement, MeasurementID, PostureAssessment)
├── PoseEstimation/      # PoseEstimator protocol & AppleVisionPoseEstimator implementation
├── PostureAnalysis/    # PostureAnalyzer geometry calculation engine
├── ImageImport/         # PhotoValidator & ViewClassifier
├── Persistence/         # SwiftData entities (AssessmentEntity), ImageStore, BaselineComparisonEngine
├── Views/               # SwiftUI views (ContentView, HistoryView, LandmarkOverlayView, AssessmentDetailView, DeveloperDebugView)
├── LandmarkEditing/     # LandmarkEditingView (manual point repositioning)
├── Utilities/           # CoordinateConverter (aspect-correct image pixel transform)
└── Tests/               # GeometryTests XCTest suite
```

## Critical Invariants

1. **Aspect-Correct Geometry**: Angle and deviation calculations MUST be computed using pixel coordinates or aspect-fit normalized coordinates (`CoordinateConverter`) to prevent angular distortion on non-square images.
2. **Decoupled Pose Estimator**: All Apple Vision code MUST remain inside `AppleVisionPoseEstimator`. Domain models use estimator-agnostic `BodyPose` and `Landmark`.
3. **Stable Measurement Identity**: Every metric must maintain a stable `MeasurementID` string key (e.g. `front.shoulder_line_angle`) separate from user-facing display names.
4. **Non-Diagnostic Framing**: Avoid medical claims (e.g., scoliosis). Measurements are geometric observations relative to baseline.

## Useful Validation & Build Commands

- **Build App Target**:
  ```bash
  xcodebuild build -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp -destination 'generic/platform=iOS Simulator'
  ```
- **Run Unit Tests**:
  ```bash
  xcodebuild test -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
  ```
- **Validation Entry Point**:
  ```bash
  ./scripts/validate.sh
  ```

## Documentation Reference
- Geometry & Coordinate Math: `docs/geometry.md`
- Persistence & Baseline Comparison: `docs/persistence.md`
- Photo Validation: `docs/validation.md`
- Developer Diagnostics: `docs/debugging.md`
