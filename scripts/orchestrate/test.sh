#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

lock="build/agents/build.lock"
if [[ "${1:-}" == "__with_kernel_lock" \
    && "${FMP_WITH_LOCK_PARENT_PID:-}" == "$PPID" ]]; then
    shift
else
    exec python3 "$ROOT/scripts/orchestrate/with-lock.py" "$lock" -- \
        "$ROOT/scripts/orchestrate/test.sh" __with_kernel_lock "$@"
fi

sim=""
name="orchestrator"
tests=()
while (($#)); do
    case "$1" in
        --sim)
            (($# >= 2)) || { echo "Error: --sim requires a simulator id." >&2; exit 2; }
            sim="$2"
            shift 2
            ;;
        --name)
            (($# >= 2)) || { echo "Error: --name requires an agent name." >&2; exit 2; }
            name="$2"
            shift 2
            ;;
        --*)
            echo "Error: unexpected option: $1" >&2
            exit 2
            ;;
        *)
            tests+=("$1")
            shift
            ;;
    esac
done
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "$name" == "." || "$name" == ".." ]]; then
    echo "Error: --name must be a simple agent name." >&2
    exit 2
fi
if ((${#tests[@]} == 0)); then
    echo "Error: provide at least one XCTest class or Class/method." >&2
    exit 2
fi
for test_case in "${tests[@]}"; do
    if [[ ! "$test_case" =~ ^[A-Za-z_][A-Za-z0-9_]*(/[A-Za-z_][A-Za-z0-9_]*)?$ ]]; then
        echo "Error: invalid XCTest selector: $test_case" >&2
        exit 2
    fi
done

destination=""
if [[ -n "$sim" ]]; then
    destination="platform=iOS Simulator,id=$sim"
else
    inventory="$(xcrun simctl list devices available -j)"
    simulator_id="$(printf '%s' "$inventory" | python3 -c '
import json, sys
inventory = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in inventory.items():
    if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
        continue
    version = tuple(int(part) for part in runtime.split("iOS-")[1].split("-") )
    if version < (17,):
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"] == "iPhone 15 Pro", device["name"], device["udid"]))
if not candidates:
    sys.exit("No available iPhone simulator with iOS 17+.")
print(max(candidates)[-1])
')"
    destination="platform=iOS Simulator,id=$simulator_id"
fi

agent_dir="build/agents/$name"
results_dir="$agent_dir/results"
mkdir -p "$results_dir"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
result_bundle="$results_dir/$timestamp.xcresult"
log="$agent_dir/test-$timestamp.log"
command=(
    xcodebuild test
    -project PostureAnalysisApp.xcodeproj
    -scheme PostureAnalysisApp
    -destination "$destination"
    -derivedDataPath "$agent_dir"
    -parallel-testing-enabled NO
    CODE_SIGNING_ALLOWED=NO
    -resultBundlePath "$result_bundle"
)
for test_case in "${tests[@]}"; do
    command+=("-only-testing:PostureAnalysisAppTests/$test_case")
done

xcode_status=0
if "${command[@]}" > "$log" 2>&1; then
    xcode_status=0
else
    xcode_status=$?
fi

summary=""
summary_status=2
if summary="$(python3 scripts/orchestrate/test-summary.py "$result_bundle" 2>&1)"; then
    summary_status=0
else
    summary_status=$?
fi
if [[ -n "$summary" ]]; then
    first_line="${summary%%$'\n'*}"
    printf '%s log=%s\n' "$first_line" "$log"
    if [[ "$summary" == *$'\n'* ]]; then
        printf '%s\n' "${summary#*$'\n'}"
    fi
else
    printf 'Error: test summary was empty. log=%s\n' "$log"
fi

if [[ "$xcode_status" -ne 0 || "$summary_status" -ne 0 ]]; then
    exit 1
fi
