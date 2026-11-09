#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)" || {
    echo "validate-both.sh: cannot resolve repository root from the current directory." >&2
    exit 2
}
printf 'Repository root: %s\n' "$ROOT"
cd "$ROOT"

if ! command -v python3 >/dev/null 2>&1; then
    echo "RUNNER_ERROR: python3 is not available." >&2
    exit 2
fi
for tool in node swift xcrun xcodebuild; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'RUNNER_ERROR: %s is not available.\n' "$tool" >&2
        exit 2
    fi
done
if [[ ! -r "$SCRIPT_DIR/with-lock.py" || ! -x "$SCRIPT_DIR/validate-both.sh" ]]; then
    echo "RUNNER_ERROR: validate-both.sh or its adjacent with-lock.py helper is missing or not runnable." >&2
    exit 2
fi
if [[ ! -r "$SCRIPT_DIR/test-summary.py" ]]; then
    echo "RUNNER_ERROR: adjacent test-summary.py helper is missing or unreadable." >&2
    exit 2
fi
if [[ ! -x "$ROOT/scripts/validate.sh" ]]; then
    echo "RUNNER_ERROR: scripts/validate.sh is missing or not executable in the caller's repository." >&2
    exit 2
fi

lock="build/orchestrate/validate.lock"
if [[ "${1:-}" == "__with_kernel_lock" \
    && "${FMP_WITH_LOCK_PARENT_PID:-}" == "$PPID" ]]; then
    shift
else
    exec python3 "$SCRIPT_DIR/with-lock.py" "$lock" -- \
        "$SCRIPT_DIR/validate-both.sh" __with_kernel_lock "$@"
fi

sim=""
only=""
while (($#)); do
    case "$1" in
        --sim)
            (($# >= 2)) || { echo "Error: --sim requires an id or device name." >&2; exit 2; }
            sim="$2"
            shift 2
            ;;
        --only)
            (($# >= 2)) || { echo "Error: --only requires local or utc." >&2; exit 2; }
            only="$2"
            shift 2
            ;;
        *)
            echo "Error: unexpected argument: $1" >&2
            exit 2
            ;;
    esac
done
if [[ -n "$only" && "$only" != "local" && "$only" != "utc" ]]; then
    echo "Error: --only must be local or utc." >&2
    exit 2
fi

destination=""
if [[ -n "$sim" ]]; then
    if [[ "$sim" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
        destination="platform=iOS Simulator,id=$sim"
    else
        destination="platform=iOS Simulator,name=$sim"
    fi
fi

baseline="$(mktemp "$ROOT/build/orchestrate/validation-results.XXXXXX")"
cleanup() {
    rm -f "$baseline"
}
trap cleanup EXIT

capture_result_baseline() {
    python3 - "$ROOT/build/validation/Logs/Test" > "$baseline" <<'PY'
import json
import sys
from pathlib import Path

results = Path(sys.argv[1])
print(json.dumps([path.name for path in results.glob("*.xcresult")]))
PY
}

new_result_bundle() {
    python3 - "$ROOT/build/validation/Logs/Test" "$baseline" <<'PY'
import json
import sys
from pathlib import Path

results = Path(sys.argv[1])
before = set(json.loads(Path(sys.argv[2]).read_text()))
candidates = [
    path for path in results.glob("*.xcresult")
    if path.is_dir() and (path / "Info.plist").is_file() and path.name not in before
]
if candidates:
    print(max(candidates, key=lambda path: path.stat().st_mtime_ns))
PY
}

relevant_failures() {
    local log="$1"
    grep -E '(^FAIL:|^ERROR:|Traceback|AssertionError|error:|Test Case .*failed|Failed tests|Testing failed|FAILED)' "$log" \
        | tail -n 15 || true
}

run_one() {
    local mode="$1"
    local log="build/validation-$mode.log"
    capture_result_baseline
    local validate_status=0
    if [[ "$mode" == "utc" ]]; then
        if SIMULATOR_DESTINATION="$destination" TEST_RUNNER_TZ=UTC ./scripts/validate.sh > "$log" 2>&1; then
            validate_status=0
        else
            validate_status=$?
        fi
    else
        unset TEST_RUNNER_TZ
        if SIMULATOR_DESTINATION="$destination" ./scripts/validate.sh > "$log" 2>&1; then
            validate_status=0
        else
            validate_status=$?
        fi
    fi

    local error_line
    if [[ "$validate_status" -ne 0 ]]; then
        if [[ "$validate_status" -eq 126 || "$validate_status" -eq 127 ]]; then
            printf 'RUNNER_ERROR: scripts/validate.sh could not be launched (status %s). log=%s\n' "$validate_status" "$log" >&2
            return 2
        fi
        error_line="$(grep -m 1 '^Error:' "$log" || true)"
        if [[ -n "$error_line" ]]; then
            printf '%s: %s log=%s\n' "$mode" "$error_line" "$log"
            relevant_failures "$log"
            return 1
        fi
    fi

    local bundle
    bundle="$(new_result_bundle)"
    if [[ -n "$bundle" ]]; then
        local summary summary_status header
        if summary="$(python3 "$SCRIPT_DIR/test-summary.py" "$bundle" 2>&1)"; then
            summary_status=0
        else
            summary_status=$?
        fi
        if [[ "$summary" == *"xcresulttool could not run:"* ]]; then
            printf 'RUNNER_ERROR: xcresulttool could not be launched. log=%s\n' "$log" >&2
            return 2
        fi
        if [[ "$summary_status" -le 1 ]]; then
            header="${summary%%$'\n'*}"
            printf '%s: %s log=%s\n' "$mode" "$header" "$log"
            if [[ "$validate_status" -ne 0 || "$summary_status" -ne 0 ]]; then
                return 1
            fi
            return 0
        fi
    fi

    error_line="$(grep -m 1 '^Error:' "$log" || true)"
    if [[ -z "$error_line" ]]; then
        error_line="Error: validation failed before XCTest."
    fi
    printf '%s: %s log=%s\n' "$mode" "$error_line" "$log"
    relevant_failures "$log"
    return 1
}

overall=0
if [[ -z "$only" || "$only" == "local" ]]; then
    if run_one local; then
        :
    else
        run_status=$?
        if [[ "$run_status" -eq 2 ]]; then exit 2; fi
        overall=1
    fi
fi
if [[ -z "$only" || "$only" == "utc" ]]; then
    if run_one utc; then
        :
    else
        run_status=$?
        if [[ "$run_status" -eq 2 ]]; then exit 2; fi
        overall=1
    fi
fi
exit "$overall"
