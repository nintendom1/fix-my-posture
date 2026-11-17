# Standing Posture Analysis iOS App

Native SwiftUI app for iPhone. It analyzes posture from still photos and a live camera preview using on-device Apple Vision. The app has Train, Routines, Progress, and Posture tabs. Photos and camera frames stay on the device.

## Features

- Camera-guided workouts, saved routines, exercise guidance, and workout history.
- Geometric posture measurements, baseline comparisons, and manual landmark editing.
- Optional on-device workout reminders, including a notification character.
- Live posture feedback from the front or rear camera.

## Requirements

- Xcode 16.4 or later with an iOS 17 or later simulator runtime.
- An iPhone running iOS 17 or later for device installation.

## Build and run on iPhone

Connect and unlock the phone, trust the Mac, enable Developer Mode, and pair the phone in Xcode if prompted. Then run:

```bash
make ios-devices
cp ios.local.env.example ios.local.env
```

Set `IOS_DEVICE`, `IOS_TEAM_ID` (your 10-character Apple development team ID), and a unique `IOS_BUNDLE_ID` in the ignored `ios.local.env`. Run `make ios` to build, sign, install, and launch the Debug app. Keep the bundle ID the same when updating the app so it uses the existing app container. Signing may contact Apple for provisioning assets; posture processing stays on-device. `bash scripts/run-ios.sh` runs the same installer directly.

## Validate

```bash
./scripts/validate.sh
```

This runs the Python, Node, Swift package, project-registration, and app simulator tests. It selects an installed iPhone simulator on the newest iOS 17+ runtime; set `SIMULATOR_DESTINATION`, for example `platform=iOS Simulator,name=iPhone 15 Pro,OS=18.6`, to choose one. Full Xcode and an installed simulator runtime are required. No physical phone or signing team is needed. Results go under `build/validation/`.

## Movement Lab

The Movement Lab runs deterministic synthetic pose scenarios through the workout counting pipeline. Use it to check analyzer changes without a person or physical phone; it still needs Xcode and an installed iOS simulator.

From the repository root:

```bash
node tools/session-replay/lab.mjs presets
node tools/session-replay/lab.mjs run --preset <id>
make viewer
```

`presets` accepts `--exercise ID` and `--sim ID`; `run` accepts `--sim ID` and `--mode pipeline|coach` (default `pipeline`). Both CLI commands run XCTest on an iOS simulator, using the default ID in `tools/session-replay/lib/lab/runner.mjs`; pass `--sim ID` to select an installed simulator on your machine. `make viewer` starts the local Runs and Scenario coverage dashboards; it requires Node 20 or later and no Node packages, but no simulator. See [Workout Session Recordings and Movement Lab](docs/diagnostics.md) for details.

## Gitleaks

Install Gitleaks with `brew install gitleaks`. Before every commit, scan the staged snapshot:

```bash
gitleaks git . --pre-commit --staged --redact --exit-code=1
```

To scan all locally available Git history:

```bash
gitleaks git . --log-opts="--all" --redact --exit-code=1
```

The [Gitleaks workflow](.github/workflows/gitleaks.yml) scans full history on pushes and pull requests. `./scripts/validate.sh` does not run Gitleaks.

## Assets and acknowledgements

See [Design/AppIcon/README.md](Design/AppIcon/README.md) to export the app icon and [Design/NotificationCharacter/README.md](Design/NotificationCharacter/README.md) to render notification portraits. Credits and licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and in the app under **Settings → Acknowledgements**.

## Limits

The posture measurements are geometric observations, not medical advice or diagnoses. Live tracking needs a physical camera, adequate lighting, and a visible body. Live measurements are not saved or compared with stored baselines; see [Realtime posture check](docs/realtime.md).

## Agent workflow index

Project-local skills load on demand. Codex reads `.agents/skills/`; Claude Code reads matching copies in `.claude/skills/`.

- [Herdr orchestration](.agents/skills/herdr-orchestration/SKILL.md)
- [Implementer workflow](.agents/skills/implementer-workflow/SKILL.md)
- [Mutation checks](.agents/skills/mutation-checks/SKILL.md)
- [Review workflow](.agents/skills/review-workflow/SKILL.md)
- [PR handoff](.agents/skills/pr-handoff/SKILL.md)
