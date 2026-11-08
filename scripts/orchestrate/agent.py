#!/usr/bin/env python3
"""Place, start, prompt, and close Herdr agents and long-running scripts."""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import math
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from pathlib import PurePosixPath
from typing import Any


NAME_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
NOTE_TOPIC_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
OVERFLOW_RE = re.compile(r"^Agent(?: (\d+))?$")
SCRIPT_TAB_RE = re.compile(r"^Scripts(?: (\d+))?$")
IMPLEMENTER_TOOLS = (
    "Bash(scripts/agent-build.sh:*) Bash(scripts/orchestrate/test.sh:*) Bash(swift test:*) Bash(swift build:*) "
    "Bash(xcodebuild:*) Bash(git diff:*) Bash(git status:*) Bash(git log:*) "
    "Bash(node --test:*) Bash(python3 -m unittest:*) "
    "Bash(scripts/orchestrate/agent.py note get:*) Bash(scripts/orchestrate/agent.py note add:*) "
    "Read Edit Write Glob Grep"
)
REVIEWER_TOOLS = (
    "Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*) "
    "Bash(scripts/orchestrate/agent.py note get:*) "
    "Read Glob Grep Write(build/reviews/**) Edit(build/reviews/**)"
)
RPC_TIMEOUT_SECONDS = 20.0
AGENT_REGISTRATION_TIMEOUT_SECONDS = 10.0
AGENT_REGISTRATION_POLL_SECONDS = 0.2
WAIT_DEFAULT_SECONDS = 3600.0
WAIT_TRANSPORT_MARGIN_SECONDS = 10.0
STATE_RELATIVE_PATH = Path("build/orchestrate/state.json")
STATE_LOCK_RELATIVE_PATH = Path("build/orchestrate/state.lock")
MIGRATED_STATE_FIELD = "migrated_legacy_states"
_MUTATION_EPOCH = 0


class OrchestrationError(Exception):
    """A user-facing command or Herdr error."""


def _result(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise OrchestrationError("Herdr returned invalid JSON")
    result = payload.get("result", payload)
    if not isinstance(result, dict):
        raise OrchestrationError("Herdr returned an unexpected response")
    return result


def _is_mutation(args: tuple[str, ...]) -> bool:
    return tuple(args[:2]) in {
        ("pane", "resize"), ("pane", "rename"), ("pane", "move"),
        ("pane", "split"), ("pane", "close"), ("pane", "run"),
        ("tab", "create"), ("tab", "close"), ("agent", "start"),
        ("agent", "prompt"), ("agent", "send-keys"),
    }


def _herdr_json(*args: str, timeout: float = RPC_TIMEOUT_SECONDS) -> dict[str, Any]:
    global _MUTATION_EPOCH
    if _is_mutation(args):
        _MUTATION_EPOCH += 1
    try:
        proc = subprocess.run(
            ["herdr", *args], capture_output=True, text=True, check=False, timeout=timeout
        )
    except subprocess.TimeoutExpired as exc:
        raise OrchestrationError(f"herdr {' '.join(args)} timed out") from exc
    except OSError as exc:
        raise OrchestrationError(f"could not run herdr: {exc}") from exc
    if proc.returncode:
        detail = (proc.stderr or proc.stdout).strip()
        if detail:
            try:
                body = json.loads(detail)
                error = body.get("error", {}) if isinstance(body, dict) else {}
                detail = error.get("message", detail) if isinstance(error, dict) else detail
            except json.JSONDecodeError:
                pass
        raise OrchestrationError(detail or f"herdr {' '.join(args)} failed")
    try:
        result = _result(json.loads(proc.stdout))
    except json.JSONDecodeError as exc:
        raise OrchestrationError(f"herdr {' '.join(args)} returned invalid JSON") from exc
    return result


def _herdr_text(*args: str) -> str:
    try:
        proc = subprocess.run(
            ["herdr", *args], capture_output=True, text=True, check=False,
            timeout=RPC_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        raise OrchestrationError(f"herdr {' '.join(args)} timed out") from exc
    except OSError as exc:
        raise OrchestrationError(f"could not run herdr: {exc}") from exc
    if proc.returncode:
        detail = (proc.stderr or proc.stdout).strip()
        raise OrchestrationError(detail or f"herdr {' '.join(args)} failed")
    return proc.stdout


def _repo_root() -> Path:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
            timeout=RPC_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        raise OrchestrationError("git repository lookup timed out") from exc
    except OSError as exc:
        raise OrchestrationError(f"could not run git: {exc}") from exc
    if proc.returncode:
        raise OrchestrationError("run this command from inside a git checkout")
    return Path(proc.stdout.strip()).resolve()


def _git_common_dir(root: Path) -> Path:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"], cwd=root,
            capture_output=True, text=True, check=False, timeout=RPC_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        raise OrchestrationError("git common directory lookup timed out") from exc
    except OSError as exc:
        raise OrchestrationError(f"could not run git: {exc}") from exc
    if proc.returncode:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise OrchestrationError(detail or "could not locate git common directory")
    common_dir = Path(proc.stdout.strip())
    if not common_dir.is_absolute():
        common_dir = root / common_dir
    return common_dir.resolve()


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds")


def _next_start_order(state: dict[str, Any]) -> int:
    values = [
        int(meta.get("start_order", 0))
        for section in (state.get("agents", {}), state.get("scripts", {}))
        for meta in section.values()
        if isinstance(meta, dict) and str(meta.get("start_order", "")).isdigit()
    ]
    return max(values, default=0) + 1


class StateFileLock:
    """A kernel lock for one shared orchestration artifact."""

    def __init__(self, path: Path, *, purpose: str = "shared agent state") -> None:
        self.path = path
        self.purpose = purpose
        self._stream = None

    def __enter__(self) -> StateFileLock:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self._stream = self.path.open("a", encoding="utf-8")
            fcntl.flock(self._stream.fileno(), fcntl.LOCK_EX)
        except OSError as exc:
            if self._stream:
                self._stream.close()
                self._stream = None
            raise OrchestrationError(f"cannot lock {self.purpose} {self.path}: {exc}") from exc
        return self

    def release(self) -> None:
        if self._stream is None:
            return
        try:
            fcntl.flock(self._stream.fileno(), fcntl.LOCK_UN)
        finally:
            self._stream.close()
            self._stream = None

    def __exit__(self, exc_type: Any, exc_value: Any, traceback: Any) -> None:
        self.release()


_PATH_CHAR_RANGES = ((1, 46), (48, 0x10FFFF))
_GlobToken = tuple[tuple[int, int], ...] | None


def _merge_ranges(ranges: list[tuple[int, int]]) -> tuple[tuple[int, int], ...]:
    merged: list[list[int]] = []
    for low, high in sorted(ranges):
        if not merged or low > merged[-1][1] + 1:
            merged.append([low, high])
        else:
            merged[-1][1] = max(merged[-1][1], high)
    return tuple((low, high) for low, high in merged)


def _complement_ranges(ranges: tuple[tuple[int, int], ...]) -> tuple[tuple[int, int], ...]:
    result: list[tuple[int, int]] = []
    for allowed_low, allowed_high in _PATH_CHAR_RANGES:
        cursor = allowed_low
        for low, high in ranges:
            if high < cursor or low > allowed_high:
                continue
            if low > cursor:
                result.append((cursor, min(allowed_high, low - 1)))
            cursor = max(cursor, high + 1)
            if cursor > allowed_high:
                break
        if cursor <= allowed_high:
            result.append((cursor, allowed_high))
    return tuple(result)


def _class_token(pattern: str, start: int) -> tuple[_GlobToken, int] | None:
    body_start = start + 1
    if body_start < len(pattern) and pattern[body_start] == "!":
        body_start += 1
    if body_start < len(pattern) and pattern[body_start] == "]":
        body_start += 1
    close = body_start
    while close < len(pattern) and pattern[close] != "]":
        close += 1
    if close == len(pattern):
        return None
    body = pattern[start + 1:close]
    negate = body.startswith("!")
    if negate:
        body = body[1:]
    ranges: list[tuple[int, int]] = []
    index = 0
    if body.startswith("]"):
        ranges.append((ord("]"), ord("]")))
        index = 1
    while index < len(body):
        low = ord(body[index])
        if index + 2 < len(body) and body[index + 1] == "-":
            high = ord(body[index + 2])
            if low <= high:
                ranges.append((low, high))
            else:
                ranges.extend(((low, low), (ord("-"), ord("-")), (high, high)))
            index += 3
        else:
            ranges.append((low, low))
            index += 1
    included = _merge_ranges(ranges)
    token = _complement_ranges(included) if negate else tuple(
        (max(low, allowed_low), min(high, allowed_high))
        for low, high in included
        for allowed_low, allowed_high in _PATH_CHAR_RANGES
        if max(low, allowed_low) <= min(high, allowed_high)
    )
    return token, close + 1


def _glob_tokens(pattern: str) -> tuple[_GlobToken, ...]:
    tokens: list[_GlobToken] = []
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "*":
            if not tokens or tokens[-1] is not None:
                tokens.append(None)
            index += 1
        elif char == "?":
            tokens.append(_PATH_CHAR_RANGES)
            index += 1
        elif char == "[" and (parsed := _class_token(pattern, index)) is not None:
            token, index = parsed
            tokens.append(token)
        else:
            codepoint = ord(char)
            if char not in {"/", "\x00"}:
                tokens.append(((codepoint, codepoint),))
            else:
                tokens.append(())
            index += 1
    return tuple(tokens)


def _ranges_overlap(first: tuple[tuple[int, int], ...], second: tuple[tuple[int, int], ...]) -> bool:
    return any(max(a, c) <= min(b, d) for a, b in first for c, d in second)


def _segment_globs_overlap(first: str, second: str) -> bool:
    first_tokens, second_tokens = _glob_tokens(first), _glob_tokens(second)

    def closure(tokens: tuple[_GlobToken, ...], positions: set[int]) -> frozenset[int]:
        result, pending = set(positions), list(positions)
        while pending:
            position = pending.pop()
            if position < len(tokens) and tokens[position] is None and position + 1 not in result:
                result.add(position + 1)
                pending.append(position + 1)
        return frozenset(result)

    initial = (closure(first_tokens, {0}), closure(second_tokens, {0}))
    pending_states, visited = [initial], {initial}
    while pending_states:
        first_state, second_state = pending_states.pop()
        if len(first_tokens) in first_state and len(second_tokens) in second_state:
            return True
        first_moves: list[tuple[int, tuple[tuple[int, int], ...]]] = []
        second_moves: list[tuple[int, tuple[tuple[int, int], ...]]] = []
        for position in first_state:
            if position < len(first_tokens):
                token = first_tokens[position]
                first_moves.append((position if token is None else position + 1,
                                    _PATH_CHAR_RANGES if token is None else token))
        for position in second_state:
            if position < len(second_tokens):
                token = second_tokens[position]
                second_moves.append((position if token is None else position + 1,
                                     _PATH_CHAR_RANGES if token is None else token))
        for next_first, first_range in first_moves:
            for next_second, second_range in second_moves:
                if not _ranges_overlap(first_range, second_range):
                    continue
                next_state = (
                    closure(first_tokens, {next_first}), closure(second_tokens, {next_second})
                )
                if next_state not in visited:
                    visited.add(next_state)
                    pending_states.append(next_state)
    return False


def _ownership_patterns(values: list[str] | None) -> list[str]:
    patterns: list[str] = []
    for value in values or []:
        for part in value.split(","):
            raw = part.strip()
            if not raw:
                raise OrchestrationError("--owns contains an empty file glob")
            path = PurePosixPath(raw)
            if path.is_absolute() or ".." in path.parts or "\\" in raw:
                raise OrchestrationError(f"--owns glob must stay inside the repository: {raw!r}")
            normalized = path.as_posix()
            if normalized == ".":
                raise OrchestrationError("--owns must name one or more repository file globs")
            if normalized not in patterns:
                patterns.append(normalized)
    return patterns


def _path_globs_overlap(first: str, second: str) -> bool:
    first_parts, second_parts = PurePosixPath(first).parts, PurePosixPath(second).parts
    def closure(parts: tuple[str, ...], positions: set[int]) -> frozenset[int]:
        result, pending = set(positions), list(positions)
        while pending:
            position = pending.pop()
            if position < len(parts) and parts[position] == "**" and position + 1 not in result:
                result.add(position + 1)
                pending.append(position + 1)
        return frozenset(result)

    initial = (closure(first_parts, {0}), closure(second_parts, {0}))
    pending_states, visited = [initial], {initial}
    while pending_states:
        first_state, second_state = pending_states.pop()
        if len(first_parts) in first_state and len(second_parts) in second_state:
            return True
        first_moves: list[tuple[int, str | None]] = []
        second_moves: list[tuple[int, str | None]] = []
        for position in first_state:
            if position < len(first_parts):
                part = first_parts[position]
                first_moves.append((position if part == "**" else position + 1,
                                    None if part == "**" else part))
        for position in second_state:
            if position < len(second_parts):
                part = second_parts[position]
                second_moves.append((position if part == "**" else position + 1,
                                     None if part == "**" else part))
        for next_first, first_part in first_moves:
            for next_second, second_part in second_moves:
                if first_part is None and second_part is None:
                    compatible = True
                elif first_part is None:
                    compatible = _segment_globs_overlap(str(second_part), "?*")
                elif second_part is None:
                    compatible = _segment_globs_overlap(first_part, "?*")
                else:
                    compatible = _segment_globs_overlap(first_part, second_part)
                if not compatible:
                    continue
                next_state = (
                    closure(first_parts, {next_first}), closure(second_parts, {next_second})
                )
                if next_state not in visited:
                    visited.add(next_state)
                    pending_states.append(next_state)
    return False


def _assert_ownership_available(ctx: Context, patterns: list[str], *, except_name: str | None = None) -> None:
    for existing_name, metadata in ctx.state["agents"].items():
        if existing_name == except_name or not isinstance(metadata, dict):
            continue
        existing = metadata.get("owns", [])
        if not isinstance(existing, list):
            continue
        for requested_glob in patterns:
            for existing_glob in existing:
                if isinstance(existing_glob, str) and _path_globs_overlap(requested_glob, existing_glob):
                    raise OrchestrationError(
                        f"refusing start: ownership conflict with agent {existing_name} "
                        f"({existing_glob} overlaps {requested_glob})"
                    )


def _empty_workspace_state() -> dict[str, Any]:
    return {"agents": {}, "orphaned_panes": {}, "scripts": {}, "managed_tabs": []}


def _validated_legacy_state(data: Any, path: Path) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise OrchestrationError(f"invalid state file: {path}")
    agents = data.setdefault("agents", {})
    scripts = data.setdefault("scripts", {})
    managed_tabs = data.setdefault("managed_tabs", [])
    if not isinstance(agents, dict) or not isinstance(scripts, dict) or not isinstance(managed_tabs, list):
        raise OrchestrationError(f"invalid state file: {path}")
    return data


def _legacy_bucket(source: str, payload: Any, path: Path) -> dict[str, Any]:
    legacy = _validated_legacy_state(payload, path)
    return {
        "source": source,
        "agents": legacy["agents"],
        "scripts": legacy["scripts"],
        "managed_tabs": legacy["managed_tabs"],
        "imported": {"agents": [], "scripts": [], "managed_tabs": []},
        "checked_workspaces": [],
    }


def _normalize_shared_state(data: Any, path: Path) -> tuple[dict[str, Any], bool]:
    if not isinstance(data, dict):
        raise OrchestrationError(f"invalid state file: {path}")
    changed = False
    if "workspaces" not in data:
        old_agents = data.pop("agents", {})
        old_scripts = data.pop("scripts", {})
        old_tabs = data.pop("managed_tabs", [])
        migrated_paths = data.get(MIGRATED_STATE_FIELD, [])
        legacy_payload = {"agents": old_agents, "scripts": old_scripts, "managed_tabs": old_tabs}
        buckets = data.get("legacy_buckets", [])
        if any(legacy_payload[key] for key in legacy_payload):
            buckets.append(_legacy_bucket("shared-unscoped", legacy_payload, path))
        data["workspaces"] = {}
        data["legacy_buckets"] = buckets
        data[MIGRATED_STATE_FIELD] = migrated_paths
        changed = True
    workspaces = data.setdefault("workspaces", {})
    if MIGRATED_STATE_FIELD not in data or "legacy_buckets" not in data:
        changed = True
    migrated_paths = data.setdefault(MIGRATED_STATE_FIELD, [])
    buckets = data.setdefault("legacy_buckets", [])
    if not isinstance(workspaces, dict) or not isinstance(migrated_paths, list) or not isinstance(buckets, list):
        raise OrchestrationError(f"invalid state file: {path}")
    for workspace_id, state in workspaces.items():
        if not isinstance(workspace_id, str) or not isinstance(state, dict):
            raise OrchestrationError(f"invalid workspace state in {path}")
        if any(key not in state for key in ("agents", "orphaned_panes", "scripts", "managed_tabs")):
            changed = True
        agents = state.setdefault("agents", {})
        orphaned_panes = state.setdefault("orphaned_panes", {})
        scripts = state.setdefault("scripts", {})
        tabs = state.setdefault("managed_tabs", [])
        if (not isinstance(agents, dict) or not isinstance(orphaned_panes, dict)
                or not isinstance(scripts, dict) or not isinstance(tabs, list)):
            raise OrchestrationError(f"invalid workspace state in {path}")
    for bucket in buckets:
        if not isinstance(bucket, dict):
            raise OrchestrationError(f"invalid legacy state archive in {path}")
        legacy = _validated_legacy_state(bucket, path)
        imported = bucket.setdefault("imported", {})
        checked = bucket.setdefault("checked_workspaces", [])
        if not isinstance(imported, dict) or not isinstance(checked, list):
            raise OrchestrationError(f"invalid legacy state archive in {path}")
        for section in ("agents", "scripts", "managed_tabs"):
            values = imported.setdefault(section, [])
            if not isinstance(values, list):
                raise OrchestrationError(f"invalid legacy state archive in {path}")
        bucket["agents"] = legacy["agents"]
        bucket["scripts"] = legacy["scripts"]
        bucket["managed_tabs"] = legacy["managed_tabs"]
    return data, changed


def _migration_snapshot(workspace_id: str) -> dict[str, Any]:
    panes = _herdr_json("pane", "list", "--workspace", workspace_id).get("panes", [])
    tabs = _herdr_json("tab", "list", "--workspace", workspace_id).get("tabs", [])
    agents = _herdr_json("agent", "list").get("agents", [])
    if not all(isinstance(items, list) for items in (panes, tabs, agents)):
        raise OrchestrationError("Herdr returned invalid data while migrating shared state")
    return {
        "panes": [pane for pane in panes if pane.get("workspace_id", workspace_id) == workspace_id],
        "tabs": [tab for tab in tabs if tab.get("workspace_id", workspace_id) == workspace_id],
        "agents": [agent for agent in agents if agent.get("workspace_id", workspace_id) == workspace_id],
    }


def _import_legacy_bucket(
    bucket: dict[str, Any], workspace_id: str, workspace_state: dict[str, Any],
    snapshot: dict[str, Any],
) -> None:
    imported = bucket["imported"]
    pane_ids = {str(pane.get("pane_id", "")) for pane in snapshot["panes"]}
    live_agents = {
        (str(agent.get("name", "")), str(agent.get("pane_id", "")))
        for agent in snapshot["agents"]
    }
    for name, metadata in bucket["agents"].items():
        pane_id = str(metadata.get("pane_id", "")) if isinstance(metadata, dict) else ""
        if name in imported["agents"] or not pane_id or pane_id not in pane_ids:
            continue
        if (str(name), pane_id) not in live_agents:
            continue
        workspace_state["agents"].setdefault(name, metadata)
        imported["agents"].append(name)
    for purpose, metadata in bucket["scripts"].items():
        pane_id = str(metadata.get("pane_id", "")) if isinstance(metadata, dict) else ""
        if purpose in imported["scripts"] or not pane_id or pane_id not in pane_ids:
            continue
        workspace_state["scripts"].setdefault(purpose, metadata)
        imported["scripts"].append(purpose)
    tab_ids = {str(tab.get("tab_id", "")) for tab in snapshot["tabs"]}
    for tab_id in bucket["managed_tabs"]:
        value = str(tab_id)
        if value in imported["managed_tabs"] or value not in tab_ids:
            continue
        workspace_state["managed_tabs"].append(value)
        imported["managed_tabs"].append(value)
    workspace_state["managed_tabs"] = sorted(set(workspace_state["managed_tabs"]))
    bucket["checked_workspaces"].append(workspace_id)


def _load_state(root: Path, path: Path, workspace_id: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any] | None]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        data = {}
    except (OSError, json.JSONDecodeError) as exc:
        raise OrchestrationError(f"cannot read {path}: {exc}") from exc
    data, changed = _normalize_shared_state(data, path)

    legacy_path = (root / STATE_RELATIVE_PATH).resolve()
    migrated = {str(item) for item in data[MIGRATED_STATE_FIELD]}
    legacy_key = str(legacy_path)
    if legacy_path != path.resolve() and legacy_key not in migrated:
        try:
            legacy_data = json.loads(legacy_path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            legacy_data = None
        except (OSError, json.JSONDecodeError) as exc:
            raise OrchestrationError(f"cannot migrate legacy state {legacy_path}: {exc}") from exc
        if legacy_data is not None:
            data["legacy_buckets"].append(_legacy_bucket(legacy_key, legacy_data, legacy_path))
            migrated.add(legacy_key)
            data[MIGRATED_STATE_FIELD] = sorted(migrated)
            changed = True

    workspaces = data["workspaces"]
    if workspace_id not in workspaces:
        workspace_state = _empty_workspace_state()
        workspaces[workspace_id] = workspace_state
        changed = True
    else:
        workspace_state = workspaces[workspace_id]
        if any(key not in workspace_state for key in ("agents", "orphaned_panes", "scripts", "managed_tabs")):
            changed = True
    agents = workspace_state.setdefault("agents", {})
    orphaned_panes = workspace_state.setdefault("orphaned_panes", {})
    scripts = workspace_state.setdefault("scripts", {})
    managed_tabs = workspace_state.setdefault("managed_tabs", [])
    if (not isinstance(agents, dict) or not isinstance(orphaned_panes, dict)
            or not isinstance(scripts, dict) or not isinstance(managed_tabs, list)):
        raise OrchestrationError(f"invalid workspace state for {workspace_id!r} in {path}")
    pending = [
        bucket for bucket in data["legacy_buckets"]
        if workspace_id not in {str(item) for item in bucket["checked_workspaces"]}
    ]
    migration_snapshot = _migration_snapshot(workspace_id) if pending else None
    if migration_snapshot is not None:
        for bucket in pending:
            _import_legacy_bucket(bucket, workspace_id, workspace_state, migration_snapshot)
            changed = True
    if changed:
        _save_state(path, data)
    return data, workspace_state, migration_snapshot


def _save_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".state-", delete=False
        ) as stream:
            temp_name = stream.name
            json.dump(state, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    except OSError as exc:
        if temp_name:
            try:
                os.unlink(temp_name)
            except OSError:
                pass
        raise OrchestrationError(f"cannot write {path}: {exc}") from exc


class Context:
    def __init__(self, root: Path, common_dir: Path, state_lock: StateFileLock) -> None:
        workspace = _workspace_from_environment()
        self.root = root
        self.workspace = workspace
        self.state_path = common_dir / STATE_RELATIVE_PATH
        self.state_lock = state_lock
        self.shared_state, self.state, migration_snapshot = _load_state(
            self.root, self.state_path, self.workspace
        )
        self._snapshot = migration_snapshot
        self._snapshot_epoch = _MUTATION_EPOCH if migration_snapshot is not None else -1

    def save_state(self) -> None:
        self.shared_state["workspaces"][self.workspace] = self.state
        _save_state(self.state_path, self.shared_state)

    def release_state_lock(self) -> None:
        self.state_lock.release()

    def snapshot(self, *, refresh: bool = False) -> dict[str, Any]:
        if not refresh and self._snapshot is not None and self._snapshot_epoch == _MUTATION_EPOCH:
            return self._snapshot
        panes = _herdr_json("pane", "list", "--workspace", self.workspace).get("panes", [])
        tabs = _herdr_json("tab", "list", "--workspace", self.workspace).get("tabs", [])
        agents = _herdr_json("agent", "list").get("agents", [])
        if not all(isinstance(items, list) for items in (panes, tabs, agents)):
            raise OrchestrationError("Herdr returned an invalid pane, tab, or agent list")
        panes = [p for p in panes if p.get("workspace_id", self.workspace) == self.workspace]
        tabs = [t for t in tabs if t.get("workspace_id", self.workspace) == self.workspace]
        agents = [a for a in agents if a.get("workspace_id", self.workspace) == self.workspace]
        self._snapshot = {"panes": panes, "tabs": tabs, "agents": agents}
        self._snapshot_epoch = _MUTATION_EPOCH
        return self._snapshot


def _workspace_from_environment() -> str:
    if os.environ.get("HERDR_ENV") != "1":
        raise OrchestrationError("run this command inside a Herdr-managed pane (HERDR_ENV=1)")
    workspace = os.environ.get("HERDR_WORKSPACE_ID")
    if not workspace:
        raise OrchestrationError("HERDR_WORKSPACE_ID is not set")
    return workspace


def _workspace_notes_directory(common_dir: Path, workspace: str) -> Path:
    workspace_key = hashlib.sha256(workspace.encode("utf-8")).hexdigest()[:24]
    return common_dir / "notes" / workspace_key


def _note_path(common_dir: Path, workspace: str, topic: str) -> Path:
    if not NOTE_TOPIC_RE.fullmatch(topic):
        raise OrchestrationError("note topic must contain only letters, digits, '.', '_' or '-' and be at most 64 characters")
    return _workspace_notes_directory(common_dir, workspace) / f"{topic}.json"


def _note_file_path(root: Path, value: str, *, must_exist: bool) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    try:
        resolved = path.resolve(strict=must_exist)
    except OSError as exc:
        raise OrchestrationError(f"note file does not exist: {value}") from exc
    try:
        resolved.relative_to(root.resolve())
    except ValueError as exc:
        raise OrchestrationError(f"note file must be inside the repository: {value}") from exc
    if must_exist and not resolved.is_file():
        raise OrchestrationError(f"note file is not a regular file: {value}")
    return resolved


def _head_commit(root: Path) -> str:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--verify", "HEAD^{commit}"], cwd=root,
            capture_output=True, text=True, check=False, timeout=RPC_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise OrchestrationError(f"could not determine note commit: {exc}") from exc
    if proc.returncode:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise OrchestrationError(detail or "could not determine note commit")
    return proc.stdout.strip()


def _save_note(path: Path, note: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".note-", delete=False
        ) as stream:
            temp_name = stream.name
            json.dump(note, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    except OSError as exc:
        if temp_name:
            try:
                os.unlink(temp_name)
            except OSError:
                pass
        raise OrchestrationError(f"cannot write investigation note {path}: {exc}") from exc


def _note_add(args: argparse.Namespace, root: Path, common_dir: Path, workspace: str) -> None:
    path = _note_path(common_dir, workspace, args.topic)
    source = _note_file_path(root, args.file, must_exist=True)
    relative = source.relative_to(root.resolve()).as_posix()
    summary = args.summary
    if summary is None:
        if sys.stdin.isatty():
            raise OrchestrationError("note add requires --summary or summary text on stdin")
        summary = sys.stdin.read()
    summary = summary.strip()
    if not summary:
        raise OrchestrationError("note summary cannot be empty")
    if len(summary.encode("utf-8")) > 4096:
        raise OrchestrationError("note summary must be 4096 bytes or fewer")
    line_refs = re.findall(r"(?<![A-Za-z0-9_])([\w./-]+):\d+(?:-\d+)?\b", summary)
    file_name = PurePosixPath(relative).name
    if not any(reference == relative or reference.endswith("/" + relative) or reference == file_name for reference in line_refs):
        raise OrchestrationError(f"note summary must include a {relative}:line reference")
    with StateFileLock(path.parent / ".notes.lock", purpose="investigation notes"):
        try:
            current = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            current = {"version": 1, "topic": args.topic, "workspace_id": workspace, "entries": {}}
        except (OSError, json.JSONDecodeError) as exc:
            raise OrchestrationError(f"cannot read investigation note {path}: {exc}") from exc
        if (not isinstance(current, dict) or current.get("version") != 1
                or current.get("workspace_id") != workspace or not isinstance(current.get("entries"), dict)):
            raise OrchestrationError(f"invalid investigation note {path}")
        commit = _head_commit(root)
        current["entries"][relative] = {
            "file": relative,
            "commit": commit,
            "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "summary": summary,
        }
        _save_note(path, current)
    print(f"note added topic={args.topic} file={relative} commit={commit}")


def _note_get(args: argparse.Namespace, root: Path, common_dir: Path, workspace: str) -> None:
    path = _note_path(common_dir, workspace, args.topic)
    try:
        note = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        print(f"no notes for topic={args.topic}")
        return
    except (OSError, json.JSONDecodeError) as exc:
        raise OrchestrationError(f"cannot read investigation note {path}: {exc}") from exc
    if (not isinstance(note, dict) or note.get("version") != 1
            or note.get("workspace_id") != workspace or not isinstance(note.get("entries"), dict)):
        raise OrchestrationError(f"invalid investigation note {path}")
    entries = note["entries"]
    if not entries:
        print(f"no notes for topic={args.topic}")
        return
    for file, entry in sorted(entries.items()):
        if not isinstance(entry, dict):
            raise OrchestrationError(f"invalid file note for topic {args.topic}")
        target = _note_file_path(root, str(file), must_exist=False)
        try:
            digest = hashlib.sha256(target.read_bytes()).hexdigest()
            stale = digest != str(entry.get("sha256", ""))
        except OSError:
            stale = True
        marker = "stale" if stale else "current"
        print(f"topic={args.topic} file={file} commit={entry.get('commit', '-')} state={marker}")
        print(str(entry.get("summary", "")))


def _tab_panes(snapshot: dict[str, Any], tab_id: str) -> list[dict[str, Any]]:
    return [pane for pane in snapshot["panes"] if pane.get("tab_id") == tab_id]


def _tab_by_label(snapshot: dict[str, Any], label: str) -> dict[str, Any] | None:
    return next((tab for tab in snapshot["tabs"] if tab.get("label") == label), None)


def _orchestrator_pane_id(snapshot: dict[str, Any]) -> str | None:
    main = _tab_by_label(snapshot, "Main")
    if not main:
        return None
    matches = [
        pane for pane in snapshot["panes"]
        if pane.get("tab_id") == main.get("tab_id") and pane.get("label") == "Orchestrator"
    ]
    if len(matches) != 1 or not matches[0].get("pane_id"):
        return None
    return str(matches[0]["pane_id"])


def _main(snapshot: dict[str, Any]) -> dict[str, Any]:
    tab = _tab_by_label(snapshot, "Main")
    if not tab:
        raise OrchestrationError("the current workspace has no Main tab")
    orchestrator_id = _orchestrator_pane_id(snapshot)
    if not orchestrator_id or not any(
        pane.get("pane_id") == orchestrator_id for pane in _tab_panes(snapshot, tab["tab_id"])
    ):
        raise OrchestrationError("Main has no Orchestrator pane")
    return tab


def _recorded_agent_panes(
    state: dict[str, Any], snapshot: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    pane_ids = {str(pane.get("pane_id", "")) for pane in snapshot["panes"]}
    orchestrator_id = _orchestrator_pane_id(snapshot)
    recorded = {}
    for agent in snapshot["agents"]:
        name = agent.get("name")
        pane_id = str(agent.get("pane_id", ""))
        meta = state.get("agents", {}).get(name) if name else None
        if not isinstance(meta, dict) or not pane_id or pane_id not in pane_ids:
            continue
        recorded_id = str(meta.get("pane_id", ""))
        if not recorded_id or recorded_id != pane_id or pane_id == orchestrator_id:
            continue
        recorded[pane_id] = agent
    return recorded


def _recorded_agent_ids(state: dict[str, Any], snapshot: dict[str, Any]) -> set[str]:
    pane_ids = {str(pane.get("pane_id", "")) for pane in snapshot["panes"]}
    active = {
        str(meta["pane_id"])
        for meta in state.get("agents", {}).values()
        if isinstance(meta, dict) and meta.get("pane_id") and str(meta["pane_id"]) in pane_ids
    }
    orphaned = {
        str(pane_id) for pane_id in state.get("orphaned_panes", {})
        if str(pane_id) in pane_ids
    }
    return active | orphaned


def _pane_agents(
    snapshot: dict[str, Any], state: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    safe_tabs = _managed_tab_ids(snapshot, state)
    tab_by_pane = {str(pane.get("pane_id")): str(pane.get("tab_id", "")) for pane in snapshot["panes"]}
    return {
        pane_id: agent
        for pane_id, agent in _recorded_agent_panes(state, snapshot).items()
        if tab_by_pane.get(pane_id) in safe_tabs
    }


def _managed_tab_ids(snapshot: dict[str, Any], state: dict[str, Any]) -> set[str]:
    orchestrator_id = _orchestrator_pane_id(snapshot)
    main = _tab_by_label(snapshot, "Main")
    safe_tabs = {str(main["tab_id"])} if main and orchestrator_id else set()
    agent_ids = _recorded_agent_ids(state, snapshot)
    pane_ids = {str(pane.get("pane_id", "")) for pane in snapshot["panes"]}
    script_ids = _script_pane_ids(state) & pane_ids
    known_ids = agent_ids | script_ids | ({orchestrator_id} if orchestrator_id else set())
    for tab in snapshot["tabs"]:
        tab_id = str(tab.get("tab_id", ""))
        if tab_id not in {str(value) for value in state.get("managed_tabs", [])}:
            continue
        label = str(tab.get("label", ""))
        if not OVERFLOW_RE.match(label) and not SCRIPT_TAB_RE.match(label):
            continue
        ids = {str(pane.get("pane_id", "")) for pane in _tab_panes(snapshot, str(tab.get("tab_id")))}
        if ids and ids <= known_ids and ids & (agent_ids | script_ids):
            safe_tabs.add(tab_id)
    return safe_tabs


def _register_managed_tab(ctx: Context, tab_id: str) -> None:
    managed_tabs = {str(value) for value in ctx.state.get("managed_tabs", [])}
    if tab_id not in managed_tabs:
        managed_tabs.add(tab_id)
        ctx.state["managed_tabs"] = sorted(managed_tabs)
        ctx.save_state()


def _managed_panes_in_tab(ctx: Context, snapshot: dict[str, Any], tab_id: str) -> list[dict[str, Any]]:
    if tab_id not in _managed_tab_ids(snapshot, ctx.state):
        return []
    managed_ids = _recorded_agent_ids(ctx.state, snapshot) | _script_pane_ids(ctx.state)
    orchestrator_id = _orchestrator_pane_id(snapshot)
    if orchestrator_id:
        managed_ids.add(orchestrator_id)
    return [
        pane for pane in _tab_panes(snapshot, tab_id)
        if str(pane.get("pane_id", "")) in managed_ids
    ]


def _managed_pane_ids(ctx: Context, snapshot: dict[str, Any]) -> set[str]:
    pane_ids = _recorded_agent_ids(ctx.state, snapshot) | _script_pane_ids(ctx.state)
    orchestrator_id = _orchestrator_pane_id(snapshot)
    if orchestrator_id:
        pane_ids.add(orchestrator_id)
    safe_tabs = _managed_tab_ids(snapshot, ctx.state)
    panes = {str(pane.get("pane_id", "")): pane for pane in snapshot["panes"]}
    return {
        pane_id for pane_id in pane_ids
        if pane_id in panes and str(panes[pane_id].get("tab_id", "")) in safe_tabs
    }


def _label(pane: dict[str, Any], snapshot: dict[str, Any], state: dict[str, Any]) -> str:
    name = _pane_agents(snapshot, state).get(str(pane.get("pane_id")), {}).get("name")
    if pane.get("label"):
        return str(pane["label"])
    if name:
        return str(name)
    return str(pane.get("terminal_title_stripped") or pane.get("terminal_title") or "Pane")


def _script_pane_ids(state: dict[str, Any]) -> set[str]:
    return {
        str(meta["pane_id"])
        for meta in state.get("scripts", {}).values()
        if isinstance(meta, dict) and meta.get("pane_id")
    }


def _main_agent_slots(ctx: Context, snapshot: dict[str, Any]) -> int:
    main = _main(snapshot)
    panes = _tab_panes(snapshot, str(main["tab_id"]))
    pane_ids = {str(pane.get("pane_id", "")) for pane in panes}
    agent_ids = set(_pane_agents(snapshot, ctx.state)) & pane_ids
    script_ids = _script_pane_ids(ctx.state) & pane_ids
    fixed_ids = pane_ids - agent_ids - script_ids
    return min(2, max(0, 3 - len(fixed_ids)))


def _assert_unique_purpose(
    ctx: Context, snapshot: dict[str, Any], purpose: str, *, except_pane_id: str | None = None
) -> None:
    if purpose.casefold() == "orchestrator":
        raise OrchestrationError("pane purpose 'Orchestrator' is reserved")
    used: dict[str, str] = {}
    for name, meta in ctx.state["agents"].items():
        if isinstance(meta, dict):
            existing = str(meta.get("purpose", "")).strip()
            pane_id = str(meta.get("pane_id", ""))
            if existing and pane_id != except_pane_id:
                used[existing.casefold()] = f"agent {name}"
    for existing, meta in ctx.state["scripts"].items():
        pane_id = str(meta.get("pane_id", "")) if isinstance(meta, dict) else ""
        if str(existing).strip() and pane_id != except_pane_id:
            used[str(existing).casefold()] = f"script {existing}"
    orchestrator_id = _orchestrator_pane_id(snapshot)
    owned_ids = _recorded_agent_ids(ctx.state, snapshot) | _script_pane_ids(ctx.state)
    orphaned_ids = {str(pane_id) for pane_id in ctx.state.get("orphaned_panes", {})}
    for pane in snapshot["panes"]:
        pane_id = str(pane.get("pane_id", ""))
        if (pane_id == except_pane_id or pane_id == orchestrator_id or pane_id not in owned_ids
                or pane_id in orphaned_ids):
            continue
        label = str(pane.get("label") or "").strip()
        if not label:
            continue
        used.setdefault(label.casefold(), f"pane {pane_id}")
    collision = used.get(purpose.casefold())
    if collision:
        raise OrchestrationError(f"pane purpose {purpose!r} is already used by {collision}")


def _reconcile_agent_records(ctx: Context, snapshot: dict[str, Any]) -> None:
    live = {
        (str(agent.get("name", "")), str(agent.get("pane_id", "")))
        for agent in snapshot["agents"]
        if agent.get("name") and agent.get("pane_id")
    }
    pane_ids = {str(pane.get("pane_id", "")) for pane in snapshot["panes"]}
    orphaned = ctx.state.setdefault("orphaned_panes", {})
    changed = False
    for name, meta in list(ctx.state["agents"].items()):
        pane_id = str(meta.get("pane_id", "")) if isinstance(meta, dict) else ""
        if pane_id and (name, pane_id) in live:
            continue
        if pane_id and pane_id in pane_ids:
            if isinstance(meta, dict) and meta.get("cleanup_pending"):
                continue
            record = dict(meta) if isinstance(meta, dict) else {}
            record["name"] = name
            record["agent_status"] = "not-running"
            orphaned[pane_id] = record
        ctx.state["agents"].pop(name, None)
        changed = True
    for pane_id in list(orphaned):
        if str(pane_id) not in pane_ids:
            orphaned.pop(pane_id, None)
            changed = True
    if changed:
        ctx.save_state()


def _wait_for_agent_registration(ctx: Context, name: str, pane_id: str) -> None:
    deadline = time.monotonic() + AGENT_REGISTRATION_TIMEOUT_SECONDS
    last_error = ""
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            result = _herdr_json(
                "agent", "list", timeout=min(RPC_TIMEOUT_SECONDS, remaining)
            )
            agents = result.get("agents", [])
            if isinstance(agents, list) and any(
                str(agent.get("name", "")) == name
                and str(agent.get("pane_id", "")) == pane_id
                and agent.get("workspace_id", ctx.workspace) == ctx.workspace
                for agent in agents if isinstance(agent, dict)
            ):
                return
        except OrchestrationError as exc:
            last_error = " ".join(str(exc).split())
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(AGENT_REGISTRATION_POLL_SECONDS, remaining))
    detail = f"; last Herdr error: {last_error}" if last_error else ""
    raise OrchestrationError(
        f"Herdr did not register agent {name} in pane {pane_id} "
        f"within {AGENT_REGISTRATION_TIMEOUT_SECONDS:g} seconds{detail}"
    )


def _rollback_agent_start(ctx: Context, name: str, pane_id: str, touched: set[str]) -> list[str]:
    errors: list[str] = []
    closed = False
    try:
        _herdr_json("pane", "close", pane_id)
        closed = True
    except OrchestrationError as exc:
        errors.append("close pane: " + " ".join(str(exc).split()))
    if closed:
        ctx.state["agents"].pop(name, None)
        ctx.state.setdefault("orphaned_panes", {}).pop(pane_id, None)
    else:
        record = ctx.state["agents"].setdefault(name, {"pane_id": pane_id})
        if not isinstance(record, dict):
            record = {"pane_id": pane_id}
            ctx.state["agents"][name] = record
        record["pane_id"] = pane_id
        record["cleanup_pending"] = True
    try:
        ctx.save_state()
    except OrchestrationError as exc:
        action = "remove record" if closed else "preserve cleanup record"
        errors.append(action + ": " + " ".join(str(exc).split()))
    try:
        _equalize_touched(ctx, touched)
    except OrchestrationError as exc:
        errors.append("restore pane widths: " + " ".join(str(exc).split()))
    return errors


def _panes_by_x(panes: list[dict[str, Any]], layout: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    rects = {}
    if layout:
        for item in layout.get("panes", []):
            rects[item.get("pane_id")] = item.get("rect", {})
    return sorted(
        panes,
        key=lambda pane: (
            rects.get(pane.get("pane_id"), {}).get("y", 0),
            rects.get(pane.get("pane_id"), {}).get("x", 0),
        ),
    )


def _layout_for(tab: dict[str, Any], panes: list[dict[str, Any]]) -> dict[str, Any]:
    if not panes:
        return {"area": {"width": 0, "height": 0}, "panes": [], "splits": []}
    data = _herdr_json("pane", "layout", "--pane", str(panes[0]["pane_id"]))
    layout = data.get("layout", data)
    if not isinstance(layout, dict):
        raise OrchestrationError(f"Herdr returned invalid layout for {tab.get('label', 'tab')}")
    return layout


def _equalize(tab: dict[str, Any], panes: list[dict[str, Any]]) -> None:
    if len(panes) < 2:
        return
    if len(panes) > 3:
        raise OrchestrationError(f"{tab.get('label', 'tab')} has more than three panes")
    layout = _layout_for(tab, panes)
    ordered = _panes_by_x(panes, layout)
    area = layout.get("area", {})
    area_width = float(area.get("width", 0) or 0)
    area_height = float(area.get("height", 0) or 0)
    rect_by_id = {item.get("pane_id"): item.get("rect", {}) for item in layout.get("panes", [])}
    if not area_width or not area_height:
        raise OrchestrationError(f"Herdr returned no geometry for {tab.get('label', 'tab')}")
    for pane in ordered:
        rect = rect_by_id.get(pane.get("pane_id"), {})
        if float(rect.get("height", area_height)) < area_height * 0.95:
            raise OrchestrationError(f"{tab.get('label', 'tab')} has a vertical pane stack")

    for index in range(len(ordered) - 1):
        current = _layout_for(tab, ordered)
        current_rects = {item.get("pane_id"): item.get("rect", {}) for item in current.get("panes", [])}
        ordered = _panes_by_x(ordered, current)
        left = ordered[index]
        right = ordered[index + 1]
        left_rect = current_rects.get(left.get("pane_id"), {})
        right_rect = current_rects.get(right.get("pane_id"), {})
        actual = float(left_rect.get("x", 0)) + float(left_rect.get("width", 0))
        target = float(current.get("area", {}).get("x", 0)) + area_width * (index + 1) / len(ordered)
        delta = target - actual
        if abs(delta) < 1.25:
            continue
        splits = current.get("splits", [])
        parent_width = area_width
        left_x = float(left_rect.get("x", 0))
        candidates = [
            split
            for split in splits
            if split.get("direction") == "right"
            and abs(float(split.get("rect", {}).get("x", -9999)) - left_x) < 1.5
        ]
        if candidates:
            parent_width = float(candidates[0].get("rect", {}).get("width", area_width))
        if parent_width <= 0:
            parent_width = area_width
        target_pane = left if delta > 0 else right
        direction = "right" if delta > 0 else "left"
        amount = abs(delta) / parent_width
        _herdr_json(
            "pane", "resize", "--pane", str(target_pane["pane_id"]),
            "--direction", direction, "--amount", f"{amount:.6f}"
        )


def _equalize_touched(ctx: Context, tab_ids: set[str]) -> None:
    if not tab_ids:
        return
    snapshot = ctx.snapshot()
    tabs = {tab.get("tab_id"): tab for tab in snapshot["tabs"]}
    managed_ids = _managed_pane_ids(ctx, snapshot)
    for tab_id in tab_ids:
        tab = tabs.get(tab_id)
        if tab:
            panes = _tab_panes(snapshot, tab_id)
            if panes and {str(pane.get("pane_id", "")) for pane in panes} <= managed_ids:
                _equalize(tab, panes)


def _equalize_managed_tabs(ctx: Context) -> None:
    snapshot = ctx.snapshot()
    managed_ids = _managed_pane_ids(ctx, snapshot)
    safe_tabs = _managed_tab_ids(snapshot, ctx.state)
    for tab in snapshot["tabs"]:
        tab_id = str(tab.get("tab_id", ""))
        panes = _tab_panes(snapshot, tab_id)
        if tab_id in safe_tabs and panes and {str(pane.get("pane_id", "")) for pane in panes} <= managed_ids:
            _equalize(tab, panes)


def _new_tab(ctx: Context, label: str, cwd: Path | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
    data = _herdr_json(
        "tab", "create", "--workspace", ctx.workspace,
        "--cwd", str(cwd or ctx.root), "--label", label, "--no-focus"
    )
    tab = data.get("tab", {})
    pane = data.get("root_pane", {})
    if not tab.get("tab_id") or not pane.get("pane_id"):
        raise OrchestrationError("Herdr did not return the new tab and root pane IDs")
    return tab, pane


def _tab_sequence(tabs: list[dict[str, Any]], kind: str) -> list[dict[str, Any]]:
    pattern = OVERFLOW_RE if kind == "Agent" else SCRIPT_TAB_RE
    def sequence(tab: dict[str, Any]) -> tuple[int, int]:
        match = pattern.match(str(tab.get("label", "")))
        if not match:
            return (999999, 0)
        return (int(match.group(1) or 1), int(tab.get("number", 0) or 0))
    return sorted([tab for tab in tabs if pattern.match(str(tab.get("label", "")))], key=sequence)


def _next_tab_label(tabs: list[dict[str, Any]], kind: str) -> str:
    labels = {str(tab.get("label", "")) for tab in tabs}
    if kind not in labels:
        return kind
    number = 2
    while f"{kind} {number}" in labels:
        number += 1
    return f"{kind} {number}"


def _is_script(ctx: Context, pane: dict[str, Any], agents_by_pane: dict[str, dict[str, Any]]) -> bool:
    pane_id = str(pane.get("pane_id", ""))
    if pane_id in agents_by_pane or pane_id == _orchestrator_pane_id(ctx.snapshot()):
        return False
    if pane_id in _script_pane_ids(ctx.state) and str(pane.get("tab_id", "")) in _managed_tab_ids(ctx.snapshot(), ctx.state):
        return True
    return False


def _script_purpose(ctx: Context, pane: dict[str, Any]) -> str:
    label = str(pane.get("label") or "").strip()
    if label and label.casefold() != "orchestrator":
        purpose = label
    else:
        title = str(pane.get("terminal_title_stripped") or pane.get("terminal_title") or "Script").strip()
        purpose = title or "Script"
    purpose = re.sub(r"\s+", " ", purpose)
    if len(purpose) > 20:
        purpose = purpose[:20].rstrip()
    if not purpose:
        purpose = "Script"
    if purpose.casefold() == "orchestrator":
        purpose = "Script"
    return purpose


def _record_script(ctx: Context, purpose: str, pane_id: str) -> None:
    if purpose not in ctx.state["scripts"]:
        ctx.state["scripts"][purpose] = {
            "pane_id": pane_id, "started_at": _now(), "start_order": _next_start_order(ctx.state)
        }
        ctx.save_state()


def _move_pane(ctx: Context, pane: dict[str, Any], target: dict[str, Any], touched: set[str]) -> str:
    pane_id = str(pane["pane_id"])
    from_tab = str(pane.get("tab_id", ""))
    target_id = str(target.get("tab_id", ""))
    snapshot = ctx.snapshot()
    managed_ids = _managed_pane_ids(ctx, snapshot)
    if pane_id not in managed_ids or target_id not in _managed_tab_ids(snapshot, ctx.state):
        raise OrchestrationError("refusing to move a pane outside the managed layout")
    target_panes = _managed_panes_in_tab(ctx, snapshot, target_id)
    if not target_panes:
        raise OrchestrationError(f"tab {target.get('label', target_id)} has no target pane")
    target_layout = _layout_for(target, target_panes)
    ordered = _panes_by_x(target_panes, target_layout)
    anchor = ordered[-1]
    _herdr_json(
        "pane", "move", pane_id, "--tab", target_id, "--split", "right",
        "--target-pane", str(anchor["pane_id"]), "--ratio", "0.5", "--no-focus"
    )
    touched.update(filter(None, (from_tab, target_id)))
    refreshed = ctx.snapshot()
    moved = next((item for item in refreshed["panes"] if item.get("pane_id") == pane_id), None)
    if moved:
        return str(moved["pane_id"])
    agent = next((item for item in refreshed["agents"] if item.get("pane_id") == pane_id), None)
    if agent:
        return str(agent["pane_id"])
    return pane_id


def _move_to_new_tab(ctx: Context, pane: dict[str, Any], label: str, touched: set[str]) -> str:
    pane_id = str(pane["pane_id"])
    snapshot = ctx.snapshot()
    if pane_id not in _managed_pane_ids(ctx, snapshot):
        raise OrchestrationError("refusing to move an unmanaged pane")
    from_tab = str(pane.get("tab_id", ""))
    _herdr_json(
        "pane", "move", pane_id, "--new-tab", "--workspace", ctx.workspace,
        "--label", label, "--no-focus"
    )
    touched.add(from_tab)
    refreshed = ctx.snapshot()
    moved = next((item for item in refreshed["panes"] if item.get("pane_id") == pane_id), None)
    if moved and moved.get("tab_id"):
        _register_managed_tab(ctx, str(moved["tab_id"]))
    return str(moved.get("pane_id", pane_id)) if moved else pane_id


def _target_tab(ctx: Context, kind: str, snapshot: dict[str, Any]) -> dict[str, Any] | None:
    safe_tabs = _managed_tab_ids(snapshot, ctx.state)
    for tab in _tab_sequence(snapshot["tabs"], kind):
        tab_id = str(tab.get("tab_id", ""))
        panes = _managed_panes_in_tab(ctx, snapshot, tab_id)
        if tab_id in safe_tabs and panes and len(panes) < 3:
            return tab
    return None


def _create_target_tab(
    ctx: Context, kind: str, snapshot: dict[str, Any], cwd: Path | None = None
) -> tuple[dict[str, Any], dict[str, Any]]:
    label = _next_tab_label(snapshot["tabs"], kind)
    return _new_tab(ctx, label, cwd)


def _available_pane(
    ctx: Context,
    tab: dict[str, Any],
    snapshot: dict[str, Any],
    cwd: Path | None = None,
) -> dict[str, Any]:
    tab_id = str(tab["tab_id"])
    panes = _managed_panes_in_tab(ctx, snapshot, tab_id)
    if not panes:
        raise OrchestrationError(f"tab {tab.get('label')} has no available pane")
    if len(_tab_panes(snapshot, tab_id)) >= 3:
        raise OrchestrationError(f"tab {tab.get('label')} is full")
    layout = _layout_for(tab, panes)
    ordered = _panes_by_x(panes, layout)
    data = _herdr_json(
        "pane", "split", str(ordered[-1]["pane_id"]), "--direction", "right",
        "--ratio", "0.5", "--cwd", str(cwd or ctx.root), "--no-focus"
    )
    pane = data.get("pane", {})
    if not pane.get("pane_id"):
        raise OrchestrationError("Herdr did not return the new pane ID")
    return pane


def _target_or_new_overflow(
    ctx: Context, kind: str, touched: set[str], cwd: Path | None = None
) -> tuple[dict[str, Any], dict[str, Any]]:
    snapshot = ctx.snapshot()
    tab = _target_tab(ctx, kind, snapshot)
    if not tab:
        tab, root_pane = _create_target_tab(ctx, kind, snapshot, cwd)
        _register_managed_tab(ctx, str(tab["tab_id"]))
        touched.add(str(tab["tab_id"]))
        return tab, root_pane
    pane = _available_pane(ctx, tab, snapshot, cwd)
    touched.add(str(tab["tab_id"]))
    return tab, pane


def _scripts_to_tab(ctx: Context, pane: dict[str, Any], touched: set[str]) -> dict[str, Any]:
    snapshot = ctx.snapshot()
    target = _target_tab(ctx, "Scripts", snapshot)
    if not target:
        label = _next_tab_label(snapshot["tabs"], "Scripts")
        _move_to_new_tab(ctx, pane, label, touched)
        refreshed = ctx.snapshot()
        target = _tab_by_label(refreshed, label)
        if not target:
            raise OrchestrationError("Herdr did not create the destination Scripts tab")
        touched.add(str(target["tab_id"]))
        purpose = _script_purpose(ctx, pane)
        _record_script(ctx, purpose, str(pane["pane_id"]))
        return target
    # Refresh the target after an earlier move or tab creation.
    snapshot = ctx.snapshot()
    target = next((t for t in snapshot["tabs"] if t.get("tab_id") == target.get("tab_id")), target)
    panes = _tab_panes(snapshot, str(target["tab_id"]))
    if not panes:
        raise OrchestrationError(f"Scripts tab {target.get('label')} has no pane")
    else:
        _move_pane(ctx, pane, target, touched)
    purpose = _script_purpose(ctx, pane)
    _record_script(ctx, purpose, str(pane["pane_id"]))
    return target


def _move_main_scripts(ctx: Context, snapshot: dict[str, Any], touched: set[str]) -> bool:
    main = _main(snapshot)
    agents_by_pane = _pane_agents(snapshot, ctx.state)
    script_ids = _script_pane_ids(ctx.state)
    scripts = [
        pane for pane in _tab_panes(snapshot, str(main["tab_id"]))
        if str(pane.get("pane_id", "")) in script_ids
        and _is_script(ctx, pane, agents_by_pane)
    ]
    for pane in scripts:
        _assert_unique_purpose(
            ctx, snapshot, _script_purpose(ctx, pane), except_pane_id=str(pane["pane_id"])
        )
    moved_any = False
    for pane in scripts:
        purpose = _script_purpose(ctx, pane)
        if purpose not in ctx.state["scripts"]:
            _record_script(ctx, purpose, str(pane["pane_id"]))
        if pane.get("label") != purpose:
            _herdr_json("pane", "rename", str(pane["pane_id"]), purpose)
            pane["label"] = purpose
        _scripts_to_tab(ctx, pane, touched)
        moved_any = True
    return moved_any


def _clean_empty_overflow_tabs(ctx: Context) -> None:
    # Tabs can be user-owned even when their labels match our overflow names.
    return


def _agent_sort_key(
    agent: dict[str, Any], pane_order: dict[str, tuple[int, int]], main_tab_id: str
) -> tuple[Any, ...]:
    meta = agent.get("_meta", {})
    started = str(meta.get("started_at", ""))
    sequence = int(meta.get("start_order", 0) or 0)
    order = pane_order.get(str(agent.get("pane_id")), (999, 999))
    in_main = agent.get("tab_id") == main_tab_id
    return (0 if in_main else 1, 0 if started else 1, started, sequence, *order)


def _live_agents(ctx: Context, snapshot: dict[str, Any]) -> list[dict[str, Any]]:
    managed = ctx.state["agents"]
    managed_panes = _pane_agents(snapshot, ctx.state)
    live = []
    for pane_id, agent in managed_panes.items():
        name = agent.get("name")
        meta = managed.get(name, {}) if name else {}
        item = dict(agent)
        item["_meta"] = meta if isinstance(meta, dict) else {}
        live.append(item)
    return live


def _destination_overflow(ctx: Context, agent: dict[str, Any], touched: set[str]) -> None:
    snapshot = ctx.snapshot()
    current = next((p for p in snapshot["panes"] if p.get("pane_id") == agent.get("pane_id")), None)
    if not current:
        return
    current_tab = next((tab for tab in snapshot["tabs"] if tab.get("tab_id") == current.get("tab_id")), None)
    if not current_tab or str(current_tab.get("tab_id", "")) not in _managed_tab_ids(snapshot, ctx.state):
        return
    target = _target_tab(ctx, "Agent", snapshot)
    if target and target.get("tab_id") == current.get("tab_id"):
        return
    if target:
        panes = _managed_panes_in_tab(ctx, snapshot, str(target["tab_id"]))
        if panes:
            _move_pane(ctx, current, target, touched)
            return
    if current_tab and OVERFLOW_RE.match(str(current_tab.get("label", ""))):
        if len(_managed_panes_in_tab(ctx, snapshot, str(current_tab["tab_id"]))) <= 3:
            return
    label = _next_tab_label(snapshot["tabs"], "Agent")
    _move_to_new_tab(ctx, current, label, touched)
    refreshed = ctx.snapshot()
    tab = _tab_by_label(refreshed, label)
    if tab:
        touched.add(str(tab["tab_id"]))


def _move_agent_to_main(ctx: Context, agent: dict[str, Any], touched: set[str]) -> None:
    snapshot = ctx.snapshot()
    main = _main(snapshot)
    pane = next((p for p in snapshot["panes"] if p.get("pane_id") == agent.get("pane_id")), None)
    if not pane or pane.get("tab_id") == main.get("tab_id"):
        return
    main_panes = _tab_panes(snapshot, str(main["tab_id"]))
    if len(main_panes) >= 3:
        _move_main_scripts(ctx, snapshot, touched)
        snapshot = ctx.snapshot()
        main = _main(snapshot)
        main_panes = _tab_panes(snapshot, str(main["tab_id"]))
    if len(main_panes) >= 3:
        raise OrchestrationError("Main is full and contains no movable script pane")
    _move_pane(ctx, pane, main, touched)


def _layout(ctx: Context) -> str:
    snapshot = ctx.snapshot()
    main = _main(snapshot)
    touched: set[str] = {str(main["tab_id"])}
    safe_tabs = _managed_tab_ids(snapshot, ctx.state)
    panes_by_tab = {
        tab.get("tab_id"): _managed_panes_in_tab(ctx, snapshot, str(tab.get("tab_id")))
        for tab in snapshot["tabs"] if str(tab.get("tab_id", "")) in safe_tabs
    }
    pane_order: dict[str, tuple[int, int]] = {}
    tab_order = {
        tab.get("tab_id"): i
        for i, tab in enumerate(
            tab for tab in snapshot["tabs"] if str(tab.get("tab_id", "")) in safe_tabs
        )
    }
    for tab in snapshot["tabs"]:
        tab_panes = panes_by_tab.get(tab.get("tab_id"), [])
        ordered = _panes_by_x(tab_panes)
        for index, pane in enumerate(ordered):
            pane_order[str(pane.get("pane_id"))] = (tab_order.get(tab.get("tab_id"), 999), index)
    agents = sorted(
        _live_agents(ctx, snapshot),
        key=lambda agent: _agent_sort_key(agent, pane_order, str(main["tab_id"])),
    )
    main_agent_slots = _main_agent_slots(ctx, snapshot)
    desired_main = agents[:main_agent_slots]

    # Main agents always take priority over scripts.
    if len(_tab_panes(snapshot, str(main["tab_id"]))) > 3 or any(
        agent.get("tab_id") != main.get("tab_id") for agent in desired_main
    ):
        _move_main_scripts(ctx, snapshot, touched)
    for agent in desired_main:
        _move_agent_to_main(ctx, agent, touched)

    snapshot = ctx.snapshot()
    main = _main(snapshot)
    agents_by_pane = _pane_agents(snapshot, ctx.state)
    main_agents = [
        pane for pane in _managed_panes_in_tab(ctx, snapshot, str(main["tab_id"]))
        if str(pane.get("pane_id", "")) in agents_by_pane
    ]
    for pane in list(main_agents):
        agent = agents_by_pane[pane.get("pane_id")]
        if not any(item.get("pane_id") == agent.get("pane_id") for item in desired_main):
            _destination_overflow(ctx, agent, touched)

    # Keep every overflow tab to three agent panes; preserve the earliest names first.
    snapshot = ctx.snapshot()
    main = _main(snapshot)
    active = sorted(
        _live_agents(ctx, snapshot),
        key=lambda agent: _agent_sort_key(agent, pane_order, str(main["tab_id"])),
    )
    for agent in active[main_agent_slots:]:
        _destination_overflow(ctx, agent, touched)

    # A script may use a spare Main slot only after every active agent has been placed.
    snapshot = ctx.snapshot()
    main = _main(snapshot)
    overflow_agents = [
        agent for agent in _live_agents(ctx, snapshot)
        if agent.get("tab_id") != main.get("tab_id")
    ]
    main_panes = _tab_panes(snapshot, str(main["tab_id"]))
    while not overflow_agents and len(main_panes) < 3:
        script_tabs = _tab_sequence(snapshot["tabs"], "Scripts")
        candidate_pane = None
        for script_tab in script_tabs:
            script_panes = [
                pane for pane in _managed_panes_in_tab(ctx, snapshot, str(script_tab["tab_id"]))
                if str(pane.get("pane_id", "")) in _script_pane_ids(ctx.state)
            ]
            if not script_panes:
                continue
            script_pane = _panes_by_x(script_panes)[0]
            candidate_pane = script_pane
            break
        if not candidate_pane:
            break
        _move_pane(ctx, candidate_pane, main, touched)
        snapshot = ctx.snapshot()
        main = _main(snapshot)
        main_panes = _tab_panes(snapshot, str(main["tab_id"]))

    _clean_empty_overflow_tabs(ctx)
    _equalize_managed_tabs(ctx)
    snapshot = ctx.snapshot()
    return _layout_map(ctx, snapshot)


def _layout_map(ctx: Context, snapshot: dict[str, Any]) -> str:
    visible = []
    safe_tabs = _managed_tab_ids(snapshot, ctx.state)
    tabs = sorted(
        (tab for tab in snapshot["tabs"] if str(tab.get("tab_id", "")) in safe_tabs),
        key=lambda tab: (0 if tab.get("label") == "Main" else 1, int(tab.get("number", 0) or 0)),
    )
    for tab in tabs:
        if str(tab.get("tab_id", "")) not in safe_tabs:
            continue
        label = str(tab.get("label", "Tab"))
        panes = _managed_panes_in_tab(ctx, snapshot, str(tab.get("tab_id")))
        if not panes:
            continue
        ordered = _panes_by_x(panes)
        visible.append(f"{label}: " + " | ".join(_label(pane, snapshot, ctx.state) for pane in ordered))
    return "; ".join(visible)


def _place_start_pane(
    ctx: Context, touched: set[str], cwd: Path | None = None
) -> tuple[dict[str, Any], dict[str, Any]]:
    snapshot = ctx.snapshot()
    main = _main(snapshot)
    main_id = str(main["tab_id"])
    main_panes = _tab_panes(snapshot, main_id)
    managed_main_panes = _managed_panes_in_tab(ctx, snapshot, main_id)
    agents_by_pane = _pane_agents(snapshot, ctx.state)
    scripts = [pane for pane in managed_main_panes if str(pane.get("pane_id", "")) in _script_pane_ids(ctx.state)]
    agents_in_main = [pane for pane in managed_main_panes if str(pane.get("pane_id", "")) in agents_by_pane]
    if scripts and (len(main_panes) >= 3 or len(agents_in_main) < 2):
        _move_main_scripts(ctx, snapshot, touched)
        snapshot = ctx.snapshot()
        main = _main(snapshot)
        main_id = str(main["tab_id"])
        main_panes = _tab_panes(snapshot, main_id)
        managed_main_panes = _managed_panes_in_tab(ctx, snapshot, main_id)
        agents_in_main = [pane for pane in managed_main_panes if str(pane.get("pane_id", "")) in _pane_agents(snapshot, ctx.state)]
    if len(agents_in_main) < 2 and len(main_panes) < 3:
        pane = _available_pane(ctx, main, snapshot, cwd)
        touched.add(main_id)
        return main, pane
    return _target_or_new_overflow(ctx, "Agent", touched, cwd)


def _codex_update_prompt(name: str) -> None:
    visible = _herdr_text("agent", "read", name, "--source", "visible")
    lowered = visible.lower()
    prompts = ("update available", "new version available", "press enter to update", "install update")
    if any(prompt in lowered for prompt in prompts):
        _herdr_json("agent", "send-keys", name, "esc")


def _start(args: argparse.Namespace, ctx: Context) -> None:
    name = args.name
    if not NAME_RE.fullmatch(name):
        raise OrchestrationError("agent name must match [a-z][a-z0-9_-]{0,31}")
    model_lower = args.model.lower()
    if "astra" in model_lower or "fable" in model_lower:
        raise OrchestrationError("refusing Astra and Fable models")
    if "terra" in model_lower and not args.allow_terra:
        raise OrchestrationError("refusing Terra without --allow-terra")
    purpose = args.purpose.strip()
    if not purpose:
        raise OrchestrationError("pane purpose cannot be empty")
    if len(purpose) > 20:
        raise OrchestrationError("pane purpose must be 20 characters or fewer")
    if purpose.casefold() == "orchestrator":
        raise OrchestrationError("pane purpose 'Orchestrator' is reserved")
    owns = _ownership_patterns(args.owns)
    snapshot = ctx.snapshot(refresh=True)
    _reconcile_agent_records(ctx, snapshot)
    if name in ctx.state["agents"]:
        raise OrchestrationError(f"agent {name} is already managed")
    _assert_unique_purpose(ctx, snapshot, purpose)
    _assert_ownership_available(ctx, owns)
    if any(agent.get("name") == name for agent in snapshot["agents"]):
        raise OrchestrationError(f"agent {name} is already running")
    touched: set[str] = set()
    cwd = Path(args.cwd).expanduser() if args.cwd else None
    if cwd and not cwd.is_absolute():
        cwd = ctx.root / cwd
    if cwd:
        cwd = cwd.resolve()
        if not cwd.is_dir():
            raise OrchestrationError(f"working directory does not exist: {cwd}")
    notes_dir = _workspace_notes_directory(ctx.state_path.parent, ctx.workspace)
    try:
        notes_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise OrchestrationError(f"cannot prepare shared investigation notes {notes_dir}: {exc}") from exc
    _layout(ctx)
    tab, pane = _place_start_pane(ctx, touched, cwd)
    pane_id = str(pane["pane_id"])
    try:
        ctx.state["agents"][name] = {
            "kind": args.kind,
            "model": args.model,
            "role": args.role,
            "purpose": purpose,
            "pane_id": pane_id,
            "owns": owns,
            "started_at": _now(),
            "start_order": _next_start_order(ctx.state),
        }
        ctx.save_state()
        _herdr_json("pane", "rename", pane_id, purpose)

        if args.kind == "codex":
            effort = args.effort or ("max" if model_lower == "gpt-6-luna" else "high")
            herdr_args = [
                "agent", "start", name, "--kind", "codex", "--pane", pane_id,
                "--", "-m", args.model, "-c", f"model_reasoning_effort={effort}",
                "-s", "workspace-write", "--add-dir", str(notes_dir),
                "-a", "on-request"
            ]
        else:
            tool_list = IMPLEMENTER_TOOLS if args.role == "implementer" else REVIEWER_TOOLS
            herdr_args = [
                "agent", "start", name, "--kind", "claude", "--pane", pane_id,
                "--", "--model", args.model, "--permission-mode", "acceptEdits",
                "--add-dir", str(notes_dir),
                "--allowedTools", tool_list
            ]
        _herdr_json(*herdr_args)
        _wait_for_agent_registration(ctx, name, pane_id)
    except Exception as exc:
        cleanup_errors = _rollback_agent_start(ctx, name, pane_id, touched)
        cause = " ".join(str(exc).split()) or type(exc).__name__
        if cleanup_errors:
            raise OrchestrationError(
                f"agent {name} failed to start: {cause}; cleanup incomplete: "
                + "; ".join(cleanup_errors)
            ) from exc
        raise OrchestrationError(
            f"agent {name} failed to start: {cause}; created pane {pane_id} closed and record removed"
        ) from exc
    if args.kind == "codex":
        try:
            _codex_update_prompt(name)
        except OrchestrationError:
            pass
    _equalize_touched(ctx, touched)
    refreshed = ctx.snapshot()
    agent = next((item for item in refreshed["agents"] if item.get("name") == name), {})
    actual_pane = str(agent.get("pane_id") or pane["pane_id"])
    actual_tab = next(
        (item for item in refreshed["panes"] if item.get("pane_id") == actual_pane), {}
    ).get("tab_id")
    tab_label = next(
        (item.get("label") for item in refreshed["tabs"] if item.get("tab_id") == actual_tab),
        tab.get("label", "Unknown"),
    )
    print(f"started {name} pane={actual_pane} tab={tab_label} kind={args.kind} model={args.model}")


def _prefixed(message: str) -> str:
    prefix = "Orchestrator: "
    return message if message.startswith(prefix) else prefix + message


def _prompt(args: argparse.Namespace, ctx: Context) -> None:
    meta = ctx.state["agents"].get(args.name)
    if not isinstance(meta, dict):
        raise OrchestrationError(f"agent {args.name} is not managed")
    pane_id = str(meta.get("pane_id", ""))
    snapshot = ctx.snapshot()
    pane = next((item for item in snapshot["panes"] if str(item.get("pane_id", "")) == pane_id), None)
    if not pane_id or not pane:
        raise OrchestrationError(f"agent {args.name} has no recorded pane")
    if pane_id == _orchestrator_pane_id(snapshot):
        raise OrchestrationError(f"agent {args.name} points to the Orchestrator pane")
    if str(pane.get("tab_id", "")) not in _managed_tab_ids(snapshot, ctx.state):
        raise OrchestrationError(f"agent {args.name} is in a user-owned tab; refusing to prompt it")
    if pane_id not in _managed_pane_ids(ctx, snapshot):
        raise OrchestrationError(f"agent {args.name} does not identify a managed pane")
    if args.brief:
        message = f"Read {args.brief} and do exactly what it says. Reply DONE or BLOCKED."
    else:
        message = args.text
    message = _prefixed(message)
    _herdr_json("agent", "prompt", args.name, message)
    if not args.wait:
        return
    ctx.release_state_lock()
    wait_seconds = args.timeout if args.timeout is not None else WAIT_DEFAULT_SECONDS
    deadline = time.monotonic() + wait_seconds
    terminal_states = {"idle", "done", "blocked"}
    state = "working"
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        wait_args = [
            "agent", "wait", args.name, "--timeout",
            str(max(1, int(remaining * 1000))),
        ]
        try:
            _herdr_json(*wait_args, timeout=remaining + WAIT_TRANSPORT_MARGIN_SECONDS)
        except OrchestrationError:
            # A vanished pane can make Herdr's wait command fail; the refreshed
            # agent list below still decides whether the managed agent settled.
            pass
        snapshot = ctx.snapshot(refresh=True)
        live = next(
            (
                item for item in snapshot["agents"]
                if item.get("name") == args.name and str(item.get("pane_id", "")) == pane_id
            ),
            {},
        )
        state = str(live.get("agent_status", "unknown")) if live else "unknown"
        if state in terminal_states:
            break
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        time.sleep(min(0.1, remaining))
    report = ctx.root / "build" / "briefs" / f"{args.name}.report.md"
    output = f"{args.name} state={state}"
    if report.exists():
        output += f" report={report.relative_to(ctx.root)}"
    print(output)
    if state == "blocked":
        visible = _herdr_text("agent", "read", args.name, "--source", "visible")
        rows = [row.rstrip() for row in visible.splitlines() if row.strip()]
        for row in rows[-5:]:
            print(row)
    elif state not in terminal_states:
        raise OrchestrationError(
            f"timed out waiting for agent {args.name} (state={state})"
        )


def _status(ctx: Context, name: str | None) -> None:
    snapshot = ctx.snapshot()
    pane_lookup = {pane.get("pane_id"): pane for pane in snapshot["panes"]}
    tab_lookup = {tab.get("tab_id"): tab for tab in snapshot["tabs"]}
    live_by_name = {agent.get("name"): agent for agent in _live_agents(ctx, snapshot) if agent.get("name")}
    orphaned = ctx.state.get("orphaned_panes", {})
    selected_orphans = [] if name in ctx.state["agents"] else [
        (pane_id, meta) for pane_id, meta in orphaned.items()
        if isinstance(meta, dict) and (name is None or meta.get("name") == name)
    ]
    if name and name not in ctx.state["agents"] and not selected_orphans:
        raise OrchestrationError(f"agent {name} is not managed")
    if name is None:
        names = sorted(ctx.state["agents"])
    elif name in ctx.state["agents"]:
        names = [name]
    else:
        names = []
    if not names and not selected_orphans:
        print("no managed agents")
        return
    for agent_name in names:
        agent = live_by_name.get(agent_name)
        meta = ctx.state["agents"].get(agent_name, {})
        pane_id = str(meta.get("pane_id", "")) if isinstance(meta, dict) else ""
        pane = pane_lookup.get(pane_id, {})
        tab = tab_lookup.get(pane.get("tab_id"), {})
        owns = meta.get("owns", []) if isinstance(meta, dict) else []
        owns_text = ",".join(str(value) for value in owns) if isinstance(owns, list) else ""
        owns_field = f" owns={owns_text or '-'}"
        if isinstance(meta, dict) and meta.get("cleanup_pending"):
            print(
                f"{agent_name} state=cleanup-pending pane={pane_id or '-'} tab={tab.get('label', '-')} "
                f"kind={meta.get('kind', '-')} model={meta.get('model', '-')}{owns_field}"
            )
            continue
        if not agent:
            print(
                f"{agent_name} state=not-running pane={pane_id or '-'} tab={tab.get('label', '-')} "
                f"kind={meta.get('kind', '-')} model={meta.get('model', '-')}{owns_field}"
            )
            continue
        pane = pane_lookup.get(agent.get("pane_id"), {})
        tab = tab_lookup.get(pane.get("tab_id"), {})
        print(
            f"{agent_name} state={agent.get('agent_status', 'unknown')} "
            f"pane={agent.get('pane_id', '-')} tab={tab.get('label', '-')} "
            f"kind={meta.get('kind', agent.get('agent', '-'))} model={meta.get('model', '-')}{owns_field}"
        )
    for pane_id, meta in selected_orphans:
        pane = pane_lookup.get(pane_id, {})
        tab = tab_lookup.get(pane.get("tab_id"), {})
        owns = meta.get("owns", [])
        owns_text = ",".join(str(value) for value in owns) if isinstance(owns, list) else ""
        print(
            f"{meta.get('name', 'orphan')} state=not-running pane={pane_id} tab={tab.get('label', '-')} "
            f"kind={meta.get('kind', '-')} model={meta.get('model', '-')} "
            f"owns={owns_text or '-'} owner=pane"
        )


def _close_empty_tabs(ctx: Context) -> None:
    # Overflow labels do not prove tab ownership; leave empty tabs untouched.
    return


def _oldest_waiting(ctx: Context, snapshot: dict[str, Any], main_tab_id: str) -> dict[str, Any] | None:
    tabs = {tab.get("tab_id"): tab for tab in snapshot["tabs"]}
    waiting = [
        agent for agent in _live_agents(ctx, snapshot)
        if agent.get("tab_id") != main_tab_id
        and OVERFLOW_RE.match(str(tabs.get(agent.get("tab_id"), {}).get("label", "")))
    ]
    waiting.sort(key=lambda agent: (
        str(agent.get("_meta", {}).get("started_at", "~")),
        int(agent.get("_meta", {}).get("start_order", 0) or 0),
        str(agent.get("name", "")),
    ))
    return waiting[0] if waiting else None


def _close_agent(name: str, ctx: Context) -> None:
    meta = ctx.state["agents"].get(name)
    if not meta:
        raise OrchestrationError(f"agent {name} is not managed")
    snapshot = ctx.snapshot()
    pane_id = str(meta.get("pane_id", "")) if isinstance(meta, dict) else ""
    pane = next((item for item in snapshot["panes"] if pane_id and str(item.get("pane_id")) == pane_id), None)
    if pane_id and pane_id == _orchestrator_pane_id(snapshot):
        raise OrchestrationError(f"agent {name} points to the Orchestrator pane; refusing to close it")
    if pane_id and pane_id in _script_pane_ids(ctx.state):
        raise OrchestrationError(f"agent {name} points to a managed script pane; refusing to close it")
    if pane and str(pane.get("tab_id", "")) not in _managed_tab_ids(snapshot, ctx.state):
        raise OrchestrationError(f"agent {name} is in a user-owned tab; refusing to close its pane")
    old_tab = str(pane.get("tab_id", "")) if pane else ""
    closed_pane = pane_id if pane else "already-closed"
    if pane:
        _herdr_json("pane", "close", str(pane["pane_id"]))
    del ctx.state["agents"][name]
    ctx.save_state()
    touched = {old_tab} if old_tab else set()
    snapshot = ctx.snapshot()
    main = _main(snapshot)
    main_panes = _tab_panes(snapshot, str(main["tab_id"]))
    promoted: list[str] = []
    while len(main_panes) < 3:
        candidate = _oldest_waiting(ctx, snapshot, str(main["tab_id"]))
        if not candidate:
            break
        candidate_name = str(candidate.get("name", "agent"))
        _move_agent_to_main(ctx, candidate, touched)
        promoted.append(candidate_name)
        snapshot = ctx.snapshot()
        main = _main(snapshot)
        main_panes = _tab_panes(snapshot, str(main["tab_id"]))
    snapshot = ctx.snapshot()
    main = _main(snapshot)
    main_panes = _tab_panes(snapshot, str(main["tab_id"]))
    while len(main_panes) < 3:
        scripts = _tab_sequence(snapshot["tabs"], "Scripts")
        candidate_pane = None
        for tab in scripts:
            script_panes = [
                candidate for candidate in _managed_panes_in_tab(ctx, snapshot, str(tab["tab_id"]))
                if str(candidate.get("pane_id", "")) in _script_pane_ids(ctx.state)
            ]
            if script_panes:
                candidate_pane = _panes_by_x(script_panes)[0]
                break
        if not candidate_pane:
            break
        _move_pane(ctx, candidate_pane, main, touched)
        snapshot = ctx.snapshot()
        main = _main(snapshot)
        main_panes = _tab_panes(snapshot, str(main["tab_id"]))
    _close_empty_tabs(ctx)
    _equalize_touched(ctx, touched)
    suffix = f" promoted={','.join(promoted)}" if promoted else ""
    print(f"closed {name} pane={closed_pane}{suffix}")


def _script_command(args: argparse.Namespace, ctx: Context) -> None:
    purpose = args.purpose.strip()
    if not purpose or len(purpose) > 20:
        raise OrchestrationError("script purpose must be 1–20 characters")
    command_parts = list(args.script_argv)
    if command_parts and command_parts[0] == "--":
        command_parts.pop(0)
    if not command_parts:
        raise OrchestrationError("script requires a command after --")
    if purpose.casefold() == "orchestrator":
        raise OrchestrationError("pane purpose 'Orchestrator' is reserved")
    snapshot = ctx.snapshot()
    _assert_unique_purpose(ctx, snapshot, purpose)
    _layout(ctx)
    snapshot = ctx.snapshot()
    main = _main(snapshot)
    live_agents = _live_agents(ctx, snapshot)
    waiting = any(agent.get("tab_id") != main.get("tab_id") for agent in live_agents)
    touched: set[str] = set()
    if not waiting and len(_tab_panes(snapshot, str(main["tab_id"]))) < 3:
        tab = main
        pane = _available_pane(ctx, tab, snapshot, ctx.root)
    else:
        tab, pane = _target_or_new_overflow(ctx, "Scripts", touched, ctx.root)
    ctx.state["scripts"][purpose] = {
        "pane_id": str(pane["pane_id"]), "started_at": _now(),
        "start_order": _next_start_order(ctx.state),
    }
    ctx.save_state()
    _herdr_json("pane", "rename", str(pane["pane_id"]), purpose)
    _herdr_json("pane", "run", str(pane["pane_id"]), shlex.join(command_parts))
    touched.add(str(tab["tab_id"]))
    _equalize_touched(ctx, touched)
    print(f"script {purpose} pane={pane['pane_id']} tab={tab.get('label', '?')}")


def _close_script(purpose: str, ctx: Context) -> None:
    if purpose not in ctx.state["scripts"]:
        raise OrchestrationError(f"script {purpose!r} is not managed")
    meta = ctx.state["scripts"][purpose]
    pane_id = str(meta.get("pane_id", "")) if isinstance(meta, dict) else ""
    snapshot = ctx.snapshot()
    agents_by_pane = _pane_agents(snapshot, ctx.state)
    orchestrator_id = _orchestrator_pane_id(snapshot)
    if pane_id and (pane_id in agents_by_pane or pane_id == orchestrator_id):
        raise OrchestrationError(f"managed script {purpose!r} no longer identifies a script pane")
    pane = next((item for item in snapshot["panes"] if item.get("pane_id") == pane_id), None) if pane_id else None
    if pane and str(pane.get("tab_id", "")) not in _managed_tab_ids(snapshot, ctx.state):
        raise OrchestrationError(f"script {purpose!r} is in a user-owned tab; refusing to close its pane")
    if not pane:
        del ctx.state["scripts"][purpose]
        ctx.save_state()
        _close_empty_tabs(ctx)
        print(f"closed-script {purpose} pane=already-closed")
        return
    tab_id = str(pane.get("tab_id", ""))
    _herdr_json("pane", "close", str(pane["pane_id"]))
    del ctx.state["scripts"][purpose]
    ctx.save_state()
    touched = {tab_id}
    _close_empty_tabs(ctx)
    _equalize_touched(ctx, touched)
    print(f"closed-script {purpose} pane={pane['pane_id']}")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage agents and scripts in Herdr panes.")
    sub = parser.add_subparsers(dest="command", required=True)

    start = sub.add_parser("start", help="place and start an agent")
    start.add_argument("name")
    start.add_argument("--kind", choices=("codex", "claude"), required=True)
    start.add_argument("--model", required=True)
    start.add_argument("--effort")
    start.add_argument("--purpose", required=True)
    start.add_argument("--cwd")
    start.add_argument("--owns", action="append", default=[], metavar="GLOB[,GLOB]")
    start.add_argument("--role", choices=("implementer", "reviewer"), default="implementer")
    start.add_argument("--allow-terra", action="store_true")

    prompt = sub.add_parser("prompt", help="send a prefixed message to an agent")
    prompt.add_argument("name")
    source = prompt.add_mutually_exclusive_group(required=True)
    source.add_argument("--brief")
    source.add_argument("--text")
    prompt.add_argument("--wait", action="store_true")
    prompt.add_argument("--timeout", type=float)

    status = sub.add_parser("status", help="show managed agents")
    status.add_argument("name", nargs="?")

    close = sub.add_parser("close", help="close an agent and backfill Main")
    close.add_argument("name")

    script = sub.add_parser("script", help="run a long-running command in its own pane")
    script.add_argument("purpose")
    script.add_argument("script_argv", nargs=argparse.REMAINDER)

    close_script = sub.add_parser("close-script", help="close a managed script pane")
    close_script.add_argument("purpose")

    note = sub.add_parser("note", help="share workspace-scoped investigation notes")
    note_sub = note.add_subparsers(dest="note_command", required=True)
    note_add = note_sub.add_parser("add", help="add or replace a note for one file")
    note_add.add_argument("--topic", required=True)
    note_add.add_argument("--file", required=True)
    note_add.add_argument("--summary", help="short summary with file:line references; stdin is used when omitted")
    note_get = note_sub.add_parser("get", help="read notes for a topic")
    note_get.add_argument("--topic", required=True)

    sub.add_parser("layout", help="re-apply placement and pane widths")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "prompt" and args.timeout is not None and (
            not math.isfinite(args.timeout) or args.timeout <= 0 or args.timeout > 86400
        ):
            raise OrchestrationError("--timeout must be finite and between 0 and 86400 seconds")
        root = _repo_root()
        if args.command == "note":
            workspace = _workspace_from_environment()
            common_dir = _git_common_dir(root)
            notes_parent = common_dir / STATE_RELATIVE_PATH.parent
            if args.note_command == "add":
                _note_add(args, root, notes_parent, workspace)
            else:
                _note_get(args, root, notes_parent, workspace)
            return 0
        common_dir = _git_common_dir(root)
        lock_path = common_dir / STATE_LOCK_RELATIVE_PATH
        with StateFileLock(lock_path) as state_lock:
            ctx = Context(root, common_dir, state_lock)
            if args.command == "start":
                _start(args, ctx)
            elif args.command == "prompt":
                _prompt(args, ctx)
            elif args.command == "status":
                _status(ctx, args.name)
            elif args.command == "close":
                _close_agent(args.name, ctx)
            elif args.command == "script":
                _script_command(args, ctx)
            elif args.command == "close-script":
                _close_script(args.purpose, ctx)
            elif args.command == "layout":
                print(_layout(ctx))
    except OrchestrationError as exc:
        print(str(exc).replace("\n", " "), file=sys.stderr)
        return 2 if "refusing" in str(exc) or "20 characters" in str(exc) else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
