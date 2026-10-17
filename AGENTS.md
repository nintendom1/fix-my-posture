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
├── Preferences/         # Typed AppPreferencesStoring boundary, UserDefaults and in-memory stores, SwiftUI environment key
├── DesignSystem/        # Dark-first SwiftUI tokens, type, icons, aura, components, DEBUG gallery, layout anchors, and motion policy
│   ├── Tokens/          # Semantic colors, gradients, and shared radius/spacing/size metrics
│   └── Components/      # PrimaryButton, CapsuleButton, FilterChip, StatusChip, SectionHeader, ProgressBar, EmptyStateTile
├── PoseEstimation/      # PoseEstimator protocol & AppleVisionPoseEstimator implementation
├── PostureAnalysis/    # PostureAnalyzer geometry calculation engine
├── ImageImport/         # PhotoValidator & ViewClassifier
├── Persistence/         # Saved Set, exercise-target & workout-history models, ImageStore, BaselineComparisonEngine
│   ├── Schema/          # Versioned SwiftData models (SchemaV1) and AppMigrationPlan
│   └── Repositories/    # Assessment, routine, and workout-history repositories; image-store boundary
├── Views/               # SwiftUI views (ContentView, HistoryView, LandmarkOverlayView, AssessmentDetailView, DeveloperDebugView, AcknowledgementsView, PosturePreviews)
│   └── Workout/         # WorkoutCoachView, WorkoutHUDView, WorkoutJointOverlayView, ExerciseGuideView, WorkoutGhostOverlayView, RepThresholdOverlayView, HoldProgressRingView, MicrophoneStatusView, VoiceCommandsHelpView, WorkoutTipView (coaching tips), WorkoutSelectionView (Saved Sets & exercise list, in-camera chooser), SavedSetEditorView, WorkoutHistoryView (history & weight editing), ExerciseCompleteCard
├── Workout/             # Workout Coach (Beta)
│   ├── Exercises/       # ExerciseCatalog, ExerciseDefinition, ExerciseAnalyzing, ExerciseGuide; one folder per exercise (ShoulderPress/, HammerCurl/, TricepsExtension/, AirSquat/, DumbbellRow/, PushUp/)
│   ├── Analysis/        # PoseFrame, ArmGeometry, HysteresisPhaseTracker, FramingEvaluator, LandmarkSmoother, NearArmSelector
│   ├── Session/         # WorkoutSession (pure reducer), WorkoutPlan (ordered exercise occurrences) & WorkoutCoachModel (main-actor orchestrator)
│   ├── Presentation/    # WorkoutVisualState and WorkoutHUDPresenter (Foundation-only display derivation)
│   ├── Coaching/        # CoachingCue, CoachingCueScheduler (pure), WorkoutTipLayout & MotionEnvelope (pure tip placement)
│   └── Camera/          # PoseFrameSource protocol, WorkoutCameraController, PhoneTiltMonitor
├── Voice/               # SpeechCoach & WorkoutAudioSession (speech, ducking); VoiceCommandParsing, VoiceCommandParser, VoiceCommandHelp, OnDeviceSpeechRecognizer, WorkoutVoiceController, VoicePermissions (hands-free commands)
├── LandmarkEditing/     # LandmarkEditingView (manual point repositioning)
├── Utilities/           # CoordinateConverter (aspect-correct image pixel transform), PortraitCameraSession, ProtectedBodyGeometry (body areas overlays avoid)
├── Assets.xcassets/     # AppIcon (exported from Design/AppIcon; don't edit the PNG by hand)
└── Tests/               # XCTest suite for geometry, analyzers, the session reducer, and related behavior
    ├── Support/         # Fixed-window SwiftUI snapshot host and fixed clock
    └── Design/          # Design metrics, anchor tolerances, coverage, and pending frames
scripts/                 # validate.sh, run-ios.sh, pbxproj.py, and design-reference/diff helpers
scripts/design/          # HTML frame extraction, WebKit reference rendering, anchor locators, masks, and pixel diff
Design/Metrics/          # Committed layout metrics generated from the local design bundle
Design/AppIcon/          # App icon SVG source, export script, Tabler license (see THIRD_PARTY_NOTICES.md)
```

## Critical Invariants

1. **Aspect-Correct Geometry**: Angle and deviation calculations MUST be computed using pixel coordinates or aspect-fit normalized coordinates (`CoordinateConverter`) to prevent angular distortion on non-square images.
2. **Decoupled Pose Estimator**: All Apple Vision code MUST remain inside `AppleVisionPoseEstimator`. Domain models use estimator-agnostic `BodyPose` and `Landmark`.
3. **Stable Measurement Identity**: Every metric must maintain a stable `MeasurementID` string key (e.g. `front.shoulder_line_angle`) separate from user-facing display names.
4. **Non-Diagnostic Framing**: Avoid medical claims (e.g., scoliosis). Measurements are geometric observations relative to baseline.

## Adding a Workout Exercise

Every new Workout Coach exercise ships with full guidance (guide, ghost demo, threshold lines, hold ring, coaching cues, docs, and checklist items) even when a request only names the exercise. Follow the *Adding an exercise* checklist in `docs/workout.md`.

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
- Register new or renamed Swift files with `python3 scripts/pbxproj.py add|rename`; `validate.sh` runs `check`.
- **Required Before Every Commit** (run after staging changes):
  ```bash
  gitleaks git . --pre-commit --staged --redact --exit-code=1
  ```
  Do not create a commit unless this scan completes successfully. Installing
  Gitleaks is a prerequisite for committing; do not skip the scan when the
  executable is unavailable.

## Documentation Reference
- Geometry & Coordinate Math: `docs/geometry.md`
- Persistence & Baseline Comparison: `docs/persistence.md`
- Photo Validation: `docs/validation.md`
- Developer Diagnostics: `docs/debugging.md`
- Workout Coach (Beta): `docs/workout.md`
- Design snapshot and layout gate: `docs/design.md`
- Realtime posture: `docs/realtime.md`
- Commit and PR conventions: `docs/commit-and-pr.md`
- App icon source & export: `Design/AppIcon/README.md`
