# Posture Analysis App (iOS Native)

A native Swift and SwiftUI iOS application designed for iPhone 15 Pro that analyzes standing posture from still photos on-device using Apple Vision framework.

## Project Architecture & Tech Stack

- **Target OS**: iOS 17.0+
- **Frameworks**: SwiftUI, Apple Vision (`VNDetectHumanBodyPoseRequest`), SwiftData, AVFoundation, PhotosUI
- **Privacy & Execution**: 100% on-device processing. Zero networking, backend, or cloud dependencies.

## Key Directory Structure Map

```text
PostureAnalysisApp/
├── App/                         # Composition root, routes, four-tab shell, tab style, sticky CTA
├── Models/                      # Estimator-independent posture and measurement models
├── Preferences/                 # AppPreferencesStoring, UserDefaults/in-memory stores, SwiftUI environment
├── DesignSystem/
│   ├── Tokens/                  # Colors, gradients, typography, radius, spacing, and sizes
│   └── Components/              # Shared buttons, chips, headers, workout HUD, and other components
├── Features/<Screen>/           # Screen state, intents, view models, and feature-specific SwiftUI views
│   ├── Assessment/              # Saved photo assessment and developer diagnostics
│   ├── ExerciseDetail/          # Exercise details and target editing
│   ├── History/                 # Workout history and weight editing
│   ├── Library/                 # Exercise library
│   ├── NotificationPreview/     # Developer page that sends any character notification after a delay
│   ├── PhotoAssessment/         # Camera/library import and photo assessment flow
│   ├── PostureHome/             # Posture tab and saved assessment history
│   ├── Progress/                # Workout progress and stats
│   ├── RealtimePosture/         # Live camera check, capture model, and posture overlays
│   ├── Routines/                # Routine list and detail
│   ├── RoutineEditor/           # Routine creation, editing, and exercise picker
│   ├── Settings/                # Settings and acknowledgements
│   ├── Train/                   # Train tab
│   ├── VoiceCommands/           # Voice command help shared by Settings and workout
│   ├── WorkoutCamera/           # Workout camera, HUD, guide, chooser, and overlays
│   └── WorkoutComplete/         # Saved workout summary
├── PoseEstimation/              # PoseEstimator protocol and AppleVisionPoseEstimator
├── PostureAnalysis/             # PostureAnalyzer, PostureAssessmentService, and measurement presentation
├── ImageImport/                 # PhotoValidator and ViewClassifier
├── Notifications/               # Character notification scenarios, content building, and delivery adapters
│   ├── Domain/                  # Foundation-only scenario models, catalog, templates, and content builder
│   └── Delivery/                # Attachment creation and UserNotifications adapters
├── Persistence/
│   ├── Schema/                  # Versioned SwiftData schema and migration plan
│   └── Repositories/            # Assessment, routine, workout-history, and image-store boundaries
├── Workout/                     # Workout Coach domain and camera infrastructure
│   ├── Exercises/               # Catalog, definitions, guidance, analyzers, and per-exercise folders
│   ├── Analysis/                # Pose frames, geometry, tracking, smoothing, and framing
│   ├── Session/                 # Pure reducer, plan, model, intents, and factory
│   ├── Presentation/            # Foundation-only workout state and presenters
│   ├── Coaching/                # Cue scheduling and tip layout
│   └── Camera/                  # Camera source/controller, permissions, and phone tilt
├── Voice/                       # Speech, audio session, command parsing, and microphone services
├── LandmarkEditing/             # Manual posture landmark adjustment
├── Utilities/                   # Coordinate conversion, camera setup, image normalization, geometry
├── Views/                       # Shared, still-used views reused across feature folders
├── Assets.xcassets/             # App icon, notification art, and exercise-photo assets
└── Tests/
    ├── Support/                 # Snapshot host, fixtures, fixed clock, and shared test support
    ├── Fakes/                   # Test fakes
    └── Design/                  # Metrics, anchors, frame coverage, and pending frames
scripts/design/                  # Reference extraction/rendering, anchors, masks, and pixel diff
Design/Metrics/                  # Committed metrics generated from the local design bundle
Design/AppIcon/                  # App icon SVG source, export script, and notices
Design/NotificationCharacter/    # Chibi source PSD, characters.json, notification-scenarios.json, and the PNG renderer
```

## Architecture

- Feature screens receive state and send intents to view models. View-model protocols define screen-facing contracts where injection is useful; implementations use `@MainActor` and `@Observable`. Camera, persistence, preferences, speech, and scheduling services sit behind protocols where tests need substitutes.
- `AppEnvironment` is the composition root. It creates the router, preferences, SwiftData container, repositories, catalogs, factories, and long-lived view models; `AppShellView` provides them to the four tab stacks and their presentations.
- `WorkoutSession` is a pure reducer. `WorkoutFramePipeline` coordinates frame analysis, and `Workout/Presentation` derives display values without UI frameworks. Repositories in `Persistence/Repositories` own storage access for assessments, routines, workout history, and images.

## Critical Invariants

1. **Aspect-Correct Geometry**: Angle and deviation calculations MUST be computed using pixel coordinates or aspect-fit normalized coordinates (`CoordinateConverter`) to prevent angular distortion on non-square images.
2. **Decoupled Pose Estimator**: All Apple Vision code MUST remain inside `AppleVisionPoseEstimator`. Domain models use estimator-agnostic `BodyPose` and `Landmark`.
3. **Stable Measurement Identity**: Every metric must maintain a stable `MeasurementID` string key (e.g. `front.shoulder_line_angle`) separate from user-facing display names.
4. **Non-Diagnostic Framing**: Avoid medical claims (e.g., scoliosis). Measurements are geometric observations relative to baseline.

## Adding a Workout Exercise

Every new Workout Coach exercise ships with full guidance (guide, ghost demo, threshold lines, hold ring, coaching cues, docs, and checklist items) even when a request only names the exercise. Follow the *Adding an exercise* checklist in `docs/workout.md`.

## Exercise Photography

Exercise thumbnails use vetted real photography. Never replace them with an unvetted source or AI-generated or generatively altered imagery. Only crop and resize approved photographs; preserve instructional/form visuals such as `ExerciseDemoFigureView`.

Whenever an exercise thumbnail is added, replaced, removed, renamed, or materially changed, update as applicable: its asset-catalog entry, `PostureAnalysisApp/Assets.xcassets/ExerciseThumbnails/SOURCES.md`, `THIRD_PARTY_NOTICES.md`, and the in-app Exercise Photography acknowledgements (backed by `ExercisePhotography`). Keep exercise IDs, asset names, exact original-source links, photographer credits, license/status, and processing notes synchronized. Keep only final cropped/resized derivatives in the repository. If a source, provenance, or usable crop cannot be verified, stop and report the problem rather than substituting another image.

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
- Workout reminders: `docs/reminders.md`
- Notification character scenarios (generated table of every state, art, and copy line): `docs/notification-scenarios.md`
- Character notification planner and selection rules: `docs/notifications.md`
- Commit and PR conventions: `docs/commit-and-pr.md`
- App icon source & export: `Design/AppIcon/README.md`
- Exercise photography sources & crop records: `PostureAnalysisApp/Assets.xcassets/ExerciseThumbnails/SOURCES.md`
- Notification character art pipeline and scenario data: `Design/NotificationCharacter/README.md`
