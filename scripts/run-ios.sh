#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "Error: $*" >&2; exit 1; }

if [[ -f ios.local.env ]]; then
    # This is a user-owned shell configuration, excluded from git.
    source ios.local.env
fi

xcrun --find devicectl >/dev/null 2>&1 || fail "Install Xcode 15+ and select it with: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
[[ -n "${IOS_DEVICE:-}" ]] || fail "Copy ios.local.env.example to ios.local.env and set IOS_DEVICE using 'make ios-devices'."
[[ "${IOS_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || fail "Set IOS_TEAM_ID in ios.local.env to your 10-character Apple development team ID. See README.md for first-time signing setup."
[[ -n "${IOS_BUNDLE_ID:-}" && "$IOS_BUNDLE_ID" != com.yourname.PostureAnalysisApp ]] || fail "Set IOS_BUNDLE_ID in ios.local.env to a unique bundle identifier, such as com.yourname.PostureAnalysisApp (replace yourname)."

BUILD_DIR="$REPO_ROOT/build/ios-device"
APP_PATH="$BUILD_DIR/Build/Products/Debug-iphoneos/PostureAnalysisApp.app"

echo "Checking connection to $IOS_DEVICE..."
xcrun devicectl device info details --device "$IOS_DEVICE" --timeout 30 || fail "Connect and unlock your iPhone, trust this Mac, and enable Developer Mode. Check the device with 'make ios-devices'."

echo "Building and signing PostureAnalysisApp..."
if ! xcodebuild build \
    -project PostureAnalysisApp.xcodeproj \
    -scheme PostureAnalysisApp \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
    PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID"; then
    fail "Build failed; see the Xcode error above. For signing errors, complete the first-time Xcode setup in README.md using the same team and bundle identifier."
fi

[[ -d "$APP_PATH" ]] || fail "Build completed but the app is missing at $APP_PATH."
echo "Installing on $IOS_DEVICE..."
xcrun devicectl device install app --device "$IOS_DEVICE" "$APP_PATH" --timeout 120 || fail "Installation failed. Check that the phone is unlocked, paired, and registered for the signing team in Xcode."
echo "Launching PostureAnalysisApp..."
xcrun devicectl device process launch --device "$IOS_DEVICE" --terminate-existing "$IOS_BUNDLE_ID" --timeout 30 || fail "Launch failed. Unlock your iPhone and rerun 'make ios', or open the installed app on the phone. Enable Developer Mode and, if prompted, trust the developer under Settings > General > VPN & Device Management."
echo "PostureAnalysisApp is running on your iPhone."
