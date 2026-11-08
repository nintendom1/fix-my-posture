#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)" || {
    echo "mutate: cannot resolve repository root from the current directory." >&2
    exit 2
}
printf 'Repository root: %s\n' "$ROOT"
export FMP_MUTATE_ROOT_ANNOUNCED=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/mutate.py" "$@"
