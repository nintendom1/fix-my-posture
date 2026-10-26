#!/usr/bin/env bash
# Copies developer workout recordings from the iPhone into diagnostics/sessions/ (gitignored), using the same
# device and bundle identifier as `make ios`. Recordings stay on this Mac; never commit them.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "Error: $*" >&2; exit 1; }

if [[ -f ios.local.env ]]; then
    # User-owned shell configuration, excluded from git.
    source ios.local.env
fi

xcrun --find devicectl >/dev/null 2>&1 || fail "Install Xcode 16.4+ and select it with xcode-select."
[[ -n "${IOS_DEVICE:-}" ]] || fail "Set IOS_DEVICE in ios.local.env (see 'make ios-devices')."
[[ -n "${IOS_BUNDLE_ID:-}" ]] || fail "Set IOS_BUNDLE_ID in ios.local.env to the identifier 'make ios' installs."

sessions="diagnostics/sessions"
mkdir -p "$sessions"
# One pull at a time (Claude's MCP tool and a manual `make diagnostics` can overlap); a lock left by a killed pull is
# taken over once its process is gone.
lock="diagnostics/.pull.lock"
until mkdir "$lock" 2>/dev/null; do
    holder="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
        rm -rf "$lock"
        continue
    fi
    fail "Another pull is running. Try again when it finishes."
done
echo $$ > "$lock/pid"
inbox="$(mktemp -d diagnostics/inbox.XXXXXX)"
trap 'rm -rf "$lock" "$inbox"' EXIT

echo "Copying workout recordings from $IOS_DEVICE..."
xcrun devicectl device copy from --device "$IOS_DEVICE" \
    --domain-type appDataContainer --domain-identifier "$IOS_BUNDLE_ID" \
    --source "Library/Application Support/Diagnostics/Workouts" \
    --destination "$inbox" --timeout 120 --quiet \
    || fail "Copy failed. Connect and unlock the iPhone, and make sure the app has recorded a workout (Settings > Developer diagnostics > Workout recordings)."

# Newer copies replace older ones; viewer notes live in separate *.notes.json files and are never touched.
copied=0
while IFS= read -r -d '' file; do
    mv -f "$file" "$sessions/"
    copied=$((copied + 1))
done < <(find "$inbox" -type f \( -name '*.json' -o -name '*.jsonl' -o -name '*.fmpsession' \) -print0)
rm -rf "$inbox"

# Older recordings were JSON Lines; rewrite them as a JSON array, one record per line, like current ones.
python3 - "$sessions" <<'PY'
import pathlib, sys
folder = pathlib.Path(sys.argv[1])
for legacy in list(folder.glob("*.jsonl")) + list(folder.glob("*.fmpsession")):
    records = [line.strip().strip(",") for line in legacy.read_text().splitlines()]
    records = [r for r in records if r.startswith("{")]
    (folder / (legacy.stem + ".json")).write_text("[\n" + ",\n".join(records) + ("\n]\n" if records else "]\n"))
    legacy.unlink()
PY

[[ $copied -gt 0 ]] || { echo "No recordings on the iPhone yet."; exit 0; }

python3 - "$sessions" <<'PY'
import datetime, json, pathlib, sys
folder = pathlib.Path(sys.argv[1])

def local(stamp):
    # Summaries store UTC; show this Mac's local time.
    try:
        return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return stamp[:16]

rows = []
for summary in folder.glob("*.summary.json"):
    try:
        data = json.loads(summary.read_text())
    except ValueError:
        continue
    session = folder / (summary.name.removesuffix(".summary.json") + ".json")
    if session.exists():
        rows.append((data.get("startedAt", ""), data, session))
for started, data, session in sorted(rows, key=lambda row: row[0], reverse=True)[:10]:
    markers = data.get("markerCount", 0)
    state = "" if data.get("isComplete") else " (incomplete)"
    print(f"{local(started)}  {data.get('title', 'Workout')}  "
          f"{markers} marker{'s' if markers != 1 else ''}{state}\n    {session}")
PY
