#!/usr/bin/env bash
# Compile check for agents that share one working tree. One build runs at a time (a kernel lock), each agent
# uses its own derived data, and no simulator is needed. Agents never run tests; the orchestrator runs
# ./scripts/validate.sh. Usage: scripts/agent-build.sh <agent-name> [--tests]
#   --tests  also compiles the unit-test target (build-for-testing) without running it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
lock="build/agents/build.lock"
if [[ "${1:-}" == "__with_kernel_lock" \
    && "${FMP_WITH_LOCK_PARENT_PID:-}" == "$PPID" ]]; then
    shift
else
    exec python3 "$ROOT/scripts/orchestrate/with-lock.py" "$lock" -- \
        "$ROOT/scripts/agent-build.sh" __with_kernel_lock "$@"
fi

name="${1:?usage: scripts/agent-build.sh <agent-name> [--tests]}"
action="build"
if [[ "${2:-}" == "--tests" ]]; then action="build-for-testing"; fi
log="build/agents/$name.log"
if xcodebuild "$action" -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "build/agents/$name" \
    CODE_SIGNING_ALLOWED=NO >"$log" 2>&1; then
    echo "BUILD SUCCEEDED ($action). Log: $log"
else
    grep -E "error:|warning: .*Persona" "$log" | sort -u | head -60
    if ! grep -qE "\.swift:[0-9]+:[0-9]+: error:" "$log" && grep -qiE "CoreSimulator|no available .*runtime|actool" "$log"; then
        echo "NOTE: no Swift errors; the asset-catalog step needs CoreSimulator, which a sandbox may block."
        echo "Ask for approval to run this script outside the sandbox, or report it and let the orchestrator compile."
    fi
    echo "BUILD FAILED ($action). Full log: $log"
    exit 1
fi
