#!/usr/bin/env bash
# Compile check for agents that share one working tree. One build runs at a time (a directory lock), each agent
# uses its own derived data, and no simulator is needed. Agents never run tests; the orchestrator runs
# ./scripts/validate.sh. Usage: scripts/agent-build.sh <agent-name> [--tests]
#   --tests  also compiles the unit-test target (build-for-testing) without running it.
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:?usage: scripts/agent-build.sh <agent-name> [--tests]}"
action="build"
if [[ "${2:-}" == "--tests" ]]; then action="build-for-testing"; fi
lock="build/agents/build.lock"
mkdir -p build/agents
until mkdir "$lock" 2>/dev/null; do sleep 5; done
trap 'rmdir "$lock"' EXIT
log="build/agents/$name.log"
if xcodebuild "$action" -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "build/agents/$name" \
    CODE_SIGNING_ALLOWED=NO >"$log" 2>&1; then
    echo "BUILD SUCCEEDED ($action). Log: $log"
else
    grep -E "error:|warning: .*Persona" "$log" | sort -u | head -60
    echo "BUILD FAILED ($action). Full log: $log"
    exit 1
fi
