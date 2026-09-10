# Standing Posture Analysis iOS App

An iPhone 15 Pro native Swift/SwiftUI application for analyzing standing body posture from still photos.

## Key Features

- **On-Device Pose Detection**: Uses Apple Vision 2D body pose estimation without sending photos off-device.
- **Objective Geometry Metrics**: Measures head tilt, shoulder asymmetry, torso lateral deviation, forward-head angle, sagittal body lean, and knee alignment.
- **Aspect-Correct Coordinate Engine**: Aspect-ratio preserving transformations prevent angle distortion on non-square camera photos.
- **Manual Landmark Editing**: Interactive point dragging with touch feedback, reset point, and reset all options.
- **Local Persistence & Baseline Comparison**: SwiftData storage with image sandboxing and baseline comparison deltas (+/- degrees).
- **Developer Diagnostics**: Inspect raw normalized/pixel landmark coordinates, confidence ratings, and copy diagnostic logs.

## Requirements

- **Xcode**: 15.0 or later
- **Target OS**: iOS 17.0 or later (iPhone 15 Pro recommended)
- **Swift Version**: 5.9+

## How to Build & Run

For a physical iPhone, run from the repository directory:

```bash
make ios
```

This builds, signs, installs, and launches a Debug build using Xcode's command-line
tools. Full Xcode 15+ is required, with support for your phone's installed iOS
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

To check staged changes before committing:

```bash
gitleaks git . --pre-commit --staged --redact --exit-code=1
```

The history scan checks committed content; stage the changes you want to check
before running the staged scan. `--redact` hides secret values in output. A clean
scan exits with code 0; detected secrets cause exit code 1. Execution errors also
fail the command, so check the diagnostic output.

The [Gitleaks workflow](.github/workflows/gitleaks.yml) scans Git history on every
push and pull request using Gitleaks 8.30.1. Once the workflow is on the default
branch, you can also start it from **Actions > Gitleaks > Run workflow** on GitHub.
It requires no Gitleaks license secret. Secret scanning runs separately from
`./scripts/validate.sh`, which builds the app and runs simulator tests.

## Known Limitations & Design Boundary

- **Non-Diagnostic**: The app produces objective geometric metrics and is not a medical device or diagnostic tool for spinal/musculoskeletal disorders.
- **Still Images**: Designed for still standing photos rather than live video stream pose tracking.
