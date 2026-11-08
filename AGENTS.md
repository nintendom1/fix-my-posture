# Posture Analysis App (iOS Native)

Native SwiftUI app for iPhone 15 Pro, targeting iOS 17+. Still-photo posture analysis uses Apple Vision on device. No networking, backend, or cloud processing.

## Project Map

```text
PostureAnalysisApp/
  App/                         Composition root, routing, four-tab shell
  AdaptiveTraining/            Adapters to the progression package
  Models/ Preferences/          Domain models and preference stores
  DesignSystem/                 Tokens and shared components
  Features/<Screen>/            Screen state, intents, view models, and views
  PoseEstimation/               Estimator protocol and Apple Vision adapter
  PostureAnalysis/ ImageImport/  Measurement and photo validation services
  Notifications/{Domain,Persona,Delivery}/ Character notification systems
  Persistence/{Schema,Repositories}/ SwiftData schema and storage boundaries
  Workout/{Exercises,Analysis,Session,Presentation,Coaching,Diagnostics,Camera}/
                                Workout Coach domain and camera infrastructure
  Voice/ LandmarkEditing/ Utilities/ Views/ Tests/{Support,Fakes,Design}/
Packages/AdaptiveTraining/      Foundation-only progression engine (`swift test`)
Packages/Narrative/             Dormant Foundation-only script runtime (`swift test`)
scripts/design/                 Design reference extraction and pixel diff
scripts/diagnostics/            Local workout recording pull tools
tools/session-replay/           Replay viewer, Movement Lab (`make lab`), `fmp-replay` MCP
diagnostics/                    Gitignored recordings and Movement Lab runs
Design/                         App icon, notification character, and metrics sources
```

Feature screens exchange state and intents with view models. `AppEnvironment` composes app services. `WorkoutSession` is a pure reducer; `WorkoutFramePipeline` coordinates analysis. Storage access belongs to repositories in `Persistence/Repositories`.

## Critical Invariants

1. **Aspect-Correct Geometry**: Compute angles and deviations with pixel coordinates or aspect-fit normalized coordinates (`CoordinateConverter`) to avoid distortion on non-square images.
2. **Decoupled Pose Estimator**: Keep all Apple Vision code inside `AppleVisionPoseEstimator`. Domain models use estimator-independent `BodyPose` and `Landmark`.
3. **Stable Measurement Identity**: Give every metric a stable `MeasurementID` string key, such as `front.shoulder_line_angle`, separate from its display name.
4. **Non-Diagnostic Framing**: Make no medical claims (for example, scoliosis). Measurements are geometric observations relative to baseline.
5. **Recordings Stay Local**: Developer workout recordings in `diagnostics/` and shared `FMP … .json` files contain real human pose data. Never commit or paste them into issues or PRs unless the developer explicitly asks; use synthetic tests instead.
6. **Adaptive Engine Boundary**: `Packages/AdaptiveTraining` alone decides easier, harder, and next prescriptions. It remains Foundation-only with stable string IDs. Screens and view models encode no progression rules; app code uses `PostureAnalysisApp/AdaptiveTraining/` adapters. Never rename a `MovementFamilyID` or `VariantID`.

## Workout Exercise Guidance

Every new camera-tracked Workout Coach exercise includes a guide, ghost demo, threshold lines, hold ring, coaching cues, docs, and checklist items. Self-reported exercises use the lighter checklist in `docs/workout.md`.

The full ghost figure renders through setup, Ready, and rest, at an ideal spot until calibration. Every pose that can reach Ready calibrates it. Size the ghost only from joints guaranteed by Ready (`requiredJoints` plus one `anyOfRequiredJoints` set), or provide a fallback. Optional landmarks may refine sizing but must not suppress the ghost. Never add required joints just to render it. `ReadyGhostInvariantTests` checks this.

## Exercise Photography

Exercise thumbnails use vetted real photography. Do not use unvetted or AI-generated or generatively altered images. Crop and resize approved photos only; preserve instructional/form visuals such as `ExerciseDemoFigureView`.

For every thumbnail add, replacement, removal, rename, or material change, synchronize the asset catalog, `PostureAnalysisApp/Assets.xcassets/ExerciseThumbnails/SOURCES.md`, `THIRD_PARTY_NOTICES.md`, and in-app Exercise Photography acknowledgements backed by `ExercisePhotography`. Keep IDs, asset names, exact source links, credits, license/status, and processing notes aligned. Retain only final cropped/resized derivatives. If provenance or a usable crop cannot be verified, stop and report it.

## Build and Validation

- Build: `xcodebuild build -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp -destination 'generic/platform=iOS Simulator'`
- Unit tests: `xcodebuild test -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`
- Project validation entry point: `./scripts/validate.sh` (orchestrator only; agents use the focused workflow skill).
- Register Swift files with `python3 scripts/pbxproj.py add|rename`; validation runs `check`.
- The orchestrator runs `scripts/orchestrate/validate-both.sh` for local-time and UTC validation.

## Commit Gate

Before every commit, run after staging:

```bash
gitleaks git . --pre-commit --staged --redact --exit-code=1
```

Do not commit unless Gitleaks completes successfully. Install it if unavailable; never skip the scan.

## On-Demand Agent Workflows

- Herdr agents, pane layout, prefixes, briefs, and ownership: [herdr-orchestration](.agents/skills/herdr-orchestration/SKILL.md).
- Implementer compile, focused tests, and report: [implementer-workflow](.agents/skills/implementer-workflow/SKILL.md).
- Mutation testing and restoration: [mutation-checks](.agents/skills/mutation-checks/SKILL.md).
- Review request, collection, and confirmation: [review-workflow](.agents/skills/review-workflow/SKILL.md).
- Before/Now, Docs section, and stacked PR handoff: [pr-handoff](.agents/skills/pr-handoff/SKILL.md).
