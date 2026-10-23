# Standing Posture Analysis iOS App

An iPhone 15 Pro native Swift/SwiftUI application for analyzing standing body posture from still photos and a live camera preview.

## Key Features

- **Four-tab app**: Train, Routines, Progress, and Posture, with settings for workout, camera, and posture preferences.
- **Workouts and routines**: Quick-start six guided exercises, save and reorder routines, and review rep and weight history.
- **Exercise library**: Search and filter exercises, review movement guidance, and adjust set and rep targets.
- **Progress and history**: See weekly workout stats and trends, open completed workouts, and edit logged weights.
- **On-device posture checks**: Analyze photos or use the live camera for geometric measurements, baseline comparisons, and manual landmark adjustment. Photos and frames stay on the device.

## Requirements

- **Xcode**: 16.4 or later
- **Target OS**: iOS 17.0 or later (iPhone 15 Pro recommended)
- **Swift Version**: 5.9+

## How to Build & Run

For a physical iPhone, run from the repository directory:

```bash
make ios
```

This builds, signs, installs, and launches a Debug build using Xcode's command-line
tools. Full Xcode 16.4+ is required, with support for your phone's installed iOS
version. No Node or npm installation is needed.

**First-time setup:**

1. Connect your unlocked iPhone by USB and accept **Trust This Computer**.
   Enable **Settings > Privacy & Security > Developer Mode** on the phone and
   follow the restart prompts. Pair the phone in Xcode's **Window > Devices and
   Simulators** if necessary.
2. Open `PostureAnalysisApp.xcodeproj` in Xcode. Add your Apple account in
   **Xcode > Settings > Accounts**. Select the app target's **Signing & Capabilities**,
   enable automatic signing, select your team (a Personal Team can be used), and
   choose a unique bundle identifier, such as `com.yourname.PostureAnalysisApp`.
3. For an initial run from Xcode, override the app target's **Build Settings > Code
   Signing Allowed** to **Yes** and **Code Signing Identity** to **Apple Development**
   for Debug. The project defaults disable signing for local simulator validation;
   `make ios` supplies these overrides automatically. Select your physical iPhone
   and press **Cmd + R** once to establish signing and device registration.
4. Run `make ios-devices` to find your phone's name or identifier, then:

   ```bash
   cp ios.local.env.example ios.local.env
   ```

   Edit `ios.local.env`: set `IOS_DEVICE`, `IOS_TEAM_ID` (the 10-character team ID),
   and `IOS_BUNDLE_ID` to match your signing setup. The team ID is the
   `DEVELOPMENT_TEAM` value in `PostureAnalysisApp.xcodeproj/project.pbxproj` after
   selecting your team in Xcode. This local configuration is ignored by git.
5. Run `make ios` whenever you want to test changes. Keep the phone unlocked during
   installation and launch. Reusing the bundle identifier preserves the existing
   app's stored assessments during normal updates.

Signing may contact Apple to obtain provisioning assets; posture processing in
the app remains entirely on-device. If signing expires, rerun the command;
account or provisioning errors may require revisiting Xcode's signing settings.

Alternatively, run `bash scripts/run-ios.sh` directly. For a simulator, open the
project in Xcode, select an iOS 17+ simulator, and press **Cmd + R**.

## How to Run Tests

Run automated tests via Xcode (`Cmd + U`) or from the terminal:

```bash
./scripts/validate.sh
```

The script builds the app and runs XCTest on an automatically selected installed
iPhone simulator (iOS 17+). No physical device, signing team, or `ios.local.env`
is needed. Full Xcode and an iOS simulator runtime are required; missing
prerequisites cause validation to fail rather than skip tests. Build output and
test results are stored in `build/validation`.

To choose a specific installed simulator:

```bash
SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' ./scripts/validate.sh
```

Or directly using xcodebuild (adjust the simulator name to one installed locally):

```bash
xcodebuild test -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

## How to Run Gitleaks

Install [Gitleaks](https://github.com/gitleaks/gitleaks) on macOS with Homebrew:

```bash
brew install gitleaks
```

From the repository root, scan all locally available Git history using the same
options as CI:

```bash
gitleaks git . --log-opts="--all" --redact --exit-code=1
```

Every commit requires a staged scan. Stage the intended changes, run this
command, and commit only when it exits successfully:

```bash
gitleaks git . --pre-commit --staged --redact --exit-code=1
```

The history scan checks committed content. The required pre-commit scan checks
the exact staged snapshot. `--redact` hides secret values in output. A clean scan
exits with code 0; detected secrets cause exit code 1. Execution errors also fail
the command and must be resolved rather than bypassed.

The [Gitleaks workflow](.github/workflows/gitleaks.yml) scans Git history on every
push and pull request using Gitleaks 8.30.1. Once the workflow is on the default
branch, you can also start it from **Actions > Gitleaks > Run workflow** on GitHub.
It requires no Gitleaks license secret. Secret scanning runs separately from
`./scripts/validate.sh`, which builds the app and runs simulator tests.

## App Icon & Third-Party Notices

The app icon is exported from a hand-written SVG in `Design/AppIcon/`; see
[Design/AppIcon/README.md](Design/AppIcon/README.md) to change or re-export it. Its glyph is a
modified Tabler Icons `body-scan` (MIT). The license is in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and in the app under **gear → Acknowledgements**.

Notification character portraits are rendered from a third-party chibi PSD by a script in
`Design/NotificationCharacter/`; see [its README](Design/NotificationCharacter/README.md) to render or change a
character. The artwork's credits and terms are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Known Limitations & Design Boundary

- **Non-Diagnostic**: The app produces objective geometric metrics and is not a medical device or diagnostic tool for spinal/musculoskeletal disorders.
- **Workout Voice Commands**: English only, and they need on-device speech recognition support. Recognition can mishear in noisy rooms or with music from the phone's speaker; headphones help. The coach doesn't listen while it's speaking, and touch controls always remain.
- **Live Tracking**: Requires a physical camera and sufficient lighting/body visibility. Low-confidence landmarks are excluded and uncertain measurements are labeled. Live measurements are not saved or compared with stored baselines. See [realtime validation and architecture](docs/realtime.md).
