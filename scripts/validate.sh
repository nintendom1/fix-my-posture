#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "Error: $*" >&2; exit 1; }

echo "=== Posture Analysis App Simulator Validation ==="
xcodebuild -version >/dev/null 2>&1 || fail "Install full Xcode and select it with xcode-select before running validation."
xcrun --find simctl >/dev/null 2>&1 || fail "The selected Xcode installation does not provide simctl."

DESTINATION="${SIMULATOR_DESTINATION:-}"
if [[ -z "$DESTINATION" ]]; then
    command -v python3 >/dev/null 2>&1 || fail "Python 3 is required to select an installed simulator."
    SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
inventory = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in inventory.items():
    if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
        continue
    version = tuple(int(part) for part in runtime.split("iOS-")[1].split("-"))
    if version < (17,):
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"] == "iPhone 15 Pro", device["name"], device["udid"]))
if not candidates:
    sys.exit("No available iPhone simulator with iOS 17+. Install an iOS runtime in Xcode Settings > Components and create an iPhone simulator in Devices and Simulators.")
print(max(candidates)[-1])
')" || fail "Could not select an iOS simulator. Check the diagnostic above."
    DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
fi

# Reject physical-device and generic destinations: tests need a concrete simulator.
case "$DESTINATION" in
    "platform=iOS Simulator,"*) ;;
    *) fail "SIMULATOR_DESTINATION must start with 'platform=iOS Simulator,' and identify a simulator by name or id." ;;
esac

echo "Building and running unit tests on $DESTINATION..."
# The test action builds both the app and test bundle before executing XCTest.
xcodebuild test \
    -project "$REPO_ROOT/PostureAnalysisApp.xcodeproj" \
    -scheme PostureAnalysisApp \
    -destination "$DESTINATION" \
    -derivedDataPath "$REPO_ROOT/build/validation" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO

echo "=== Validation Successful ==="
