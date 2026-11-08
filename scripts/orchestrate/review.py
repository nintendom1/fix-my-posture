#!/usr/bin/env python3
"""Prepare review requests and findings templates for a branch or worktree."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
AGENT_OVERRIDE = "FMP_REVIEW_AGENT_TOOL"
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
SEVERITIES = ("Blocking", "Major", "Minor", "Nit")
FINDING_ID_RE = re.compile(r"(?m)^\s*-\s+\[(F\d+)\]")
FINDING_LINE_RE = re.compile(
    r"^\s*-\s+(?:\[(?P<id>F\d+)\]\s+)?\[(?P<location>[^\]]+:\d+)\]"
    r"(?:\s+\[(?P<status>[^\]]+)\])?\s+(?P<body>\S.*)$"
)
FINDING_STATUSES = {"open", "resolved", "accepted-scope"}


class ReviewError(Exception):
    """A review request or collection error suitable for the command line."""


def _run_git(root: Path, *args: str) -> str:
    try:
        result = subprocess.run(
            ["git", *args], cwd=root, capture_output=True, text=True,
            check=False, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ReviewError(f"could not run git {' '.join(args)}: {exc}") from exc
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ReviewError(detail or f"git {' '.join(args)} failed")
    return result.stdout.strip()


def _repo_root() -> Path:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=Path.cwd(),
            capture_output=True, text=True, check=False, timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ReviewError(f"could not resolve repository root from the current directory: {exc}") from exc
    if result.returncode:
        raise ReviewError("run review.sh from inside the target git checkout")
    return Path(result.stdout.strip()).resolve()


def _read_input(path_text: str, root: Path, description: str) -> tuple[str, Path]:
    path = Path(path_text).expanduser()
    if not path.is_absolute():
        path = root / path
    try:
        return path.read_text(encoding="utf-8"), path.resolve()
    except OSError as exc:
        raise ReviewError(f"cannot read {description} {path}: {exc}") from exc


def _section(text: str, wanted: str) -> str:
    lines = text.splitlines()
    active = False
    result: list[str] = []
    for line in lines:
        heading = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", line)
        if heading:
            level = len(heading.group(1))
            if active and level <= 2:
                break
            if level == 2:
                active = heading.group(2).strip().casefold() == wanted.casefold()
            continue
        if active:
            result.append(line)
    return "\n".join(result).strip()


def _notes_sections(notes: str) -> tuple[str, str, str]:
    lines = notes.splitlines()
    sections: dict[str, list[str]] = {}
    active: str | None = None
    for line in lines:
        heading = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", line)
        if heading:
            level = len(heading.group(1))
            if level > 2:
                continue
            title = heading.group(2).casefold().strip()
            if title.startswith("test") or title.startswith("validation"):
                active = "tests"
            elif "deviation" in title:
                active = "deviations"
            else:
                active = None
            if active:
                sections.setdefault(active, [])
            continue
        if active:
            sections[active].append(line)
    tests = "\n".join(sections.get("tests", [])).strip() or "(Not recorded in notes.)"
    deviations = "\n".join(sections.get("deviations", [])).strip() or "(None recorded in notes.)"
    return tests, deviations, notes.strip()


def _link_to_brief(path: Path, root: Path, supplied: str) -> str:
    try:
        repo_path = path.relative_to(root)
        target = os.path.relpath(root / repo_path, root / "build" / "reviews")
        label = repo_path.as_posix()
    except ValueError:
        target = str(path)
        label = supplied
    return f"[{label}](<{target}>)"


def _validate_name(name: str) -> None:
    if not NAME_RE.fullmatch(name):
        raise ReviewError("name must start with a letter or digit and contain only letters, digits, '.', '_' or '-'")


def _diff_data(root: Path, base: str, head: str) -> tuple[str, list[str], str, str]:
    if not base or base.startswith("-") or ".." in base:
        raise ReviewError("base must be a git revision, not an option or revision range")
    if head != "WORKTREE" and (not head or head.startswith("-") or ".." in head):
        raise ReviewError("head must be a git revision or WORKTREE")
    if head == "WORKTREE":
        revisions = [base]
        log_range = f"{base}..HEAD"
        diff_label = f"git diff {base} (includes staged and unstaged tracked changes)"
    else:
        revisions = [f"{base}..{head}"]
        log_range = revisions[0]
        diff_label = f"git diff {base}..{head}"
    stat = _run_git(root, "diff", "--stat", *revisions) or "(no tracked diff)"
    changed = _run_git(root, "diff", "--name-only", *revisions).splitlines()
    if head == "WORKTREE":
        untracked = _run_git(root, "ls-files", "--others", "--exclude-standard").splitlines()
        changed = list(dict.fromkeys([*changed, *untracked]))
    changed = sorted(path for path in changed if path)
    commits = _run_git(root, "log", "--oneline", "--no-decorate", log_range) or "(no commits in range)"
    return stat, changed, commits, diff_label


def _review_state_path(root: Path, name: str) -> Path:
    return root / "build" / "reviews" / f"{name}.state.json"


def _load_review_state(root: Path, name: str) -> dict[str, object] | None:
    path = _review_state_path(root, name)
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError) as exc:
        raise ReviewError(f"cannot read review state {path}: {exc}") from exc
    if not isinstance(state, dict) or state.get("version") != 1:
        raise ReviewError(f"unsupported review state in {path}")
    return state


def _save_review_state(root: Path, name: str, state: dict[str, object]) -> None:
    path = _review_state_path(root, name)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=f".{name}-state-", delete=False
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
        raise ReviewError(f"cannot write review state {path}: {exc}") from exc


def _resolve_since(root: Path, value: str, state: dict[str, object] | None) -> str:
    if not value or value.startswith("-") or ".." in value:
        raise ReviewError("--since must be a commit or a recorded round tag")
    round_tags = state.get("round_tags", {}) if isinstance(state, dict) else {}
    if isinstance(round_tags, dict) and value in round_tags:
        value = str(round_tags[value])
    try:
        return _run_git(root, "rev-parse", "--verify", f"{value}^{{commit}}")
    except ReviewError as exc:
        raise ReviewError(f"cannot resolve --since {value!r} to a commit") from exc


def _git_diff(root: Path, *args: str, allow_difference: bool = False) -> str:
    try:
        result = subprocess.run(
            ["git", *args], cwd=root, capture_output=True, text=True,
            check=False, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ReviewError(f"could not run git {' '.join(args)}: {exc}") from exc
    allowed = (0, 1) if allow_difference else (0,)
    if result.returncode not in allowed:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ReviewError(detail or f"git {' '.join(args)} failed")
    return result.stdout


def _delta_data(root: Path, since: str) -> tuple[list[str], str, str]:
    changed = _run_git(root, "diff", "--name-only", since).splitlines()
    untracked = _run_git(root, "ls-files", "--others", "--exclude-standard").splitlines()
    changed = sorted(dict.fromkeys(path for path in (*changed, *untracked) if path))
    patch = _git_diff(root, "diff", "--no-color", "--no-ext-diff", "--unified=3", since, "--")
    untracked_patches = []
    for path in untracked:
        if path:
            untracked_patches.append(_git_diff(
                root, "diff", "--no-index", "--no-color", "--unified=3", "--", "/dev/null", path,
                allow_difference=True,
            ))
    if untracked_patches:
        patch = "\n".join(part.rstrip() for part in (patch, *untracked_patches) if part.strip())
    commits = _run_git(root, "log", "--oneline", "--no-decorate", f"{since}..HEAD") or "(no commits since this review)"
    return changed, patch, commits


def _read_file_snapshot(path: Path) -> dict[str, object] | None:
    if not path.exists() and not path.is_symlink():
        return None
    mode = stat.S_IMODE(path.lstat().st_mode)
    if path.is_symlink():
        return {"kind": "symlink", "content": os.readlink(path), "mode": mode}
    if not path.is_file():
        return {"kind": "other", "mode": mode}
    content = path.read_bytes()
    try:
        return {"kind": "text", "content": content.decode("utf-8"), "mode": mode}
    except UnicodeDecodeError:
        return {"kind": "binary", "digest": hashlib.sha256(content).hexdigest(), "mode": mode}


def _capture_worktree_snapshot(root: Path, paths: Sequence[str]) -> dict[str, object]:
    return {
        name: _read_file_snapshot(root / name) or {"kind": "missing"}
        for name in paths
    }


def _commit_file_snapshot(root: Path, commit: str, path: str) -> dict[str, object] | None:
    mode_line = _run_git(root, "ls-tree", commit, "--", path)
    mode_match = re.match(r"^(\d+)\s+\w+\s+[0-9a-f]+\t", mode_line)
    if not mode_match:
        return None
    git_mode = int(mode_match.group(1), 8)
    mode = 0o777 if git_mode == 0o120000 else stat.S_IMODE(git_mode)
    try:
        result = subprocess.run(
            ["git", "show", f"{commit}:{path}"], cwd=root, capture_output=True,
            check=False, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ReviewError(f"could not read {path} at {commit}: {exc}") from exc
    if result.returncode:
        raise ReviewError(f"could not read {path} at {commit}")
    if git_mode == 0o120000:
        return {"kind": "symlink", "content": result.stdout.decode("utf-8", "replace"), "mode": mode}
    try:
        return {"kind": "text", "content": result.stdout.decode("utf-8"), "mode": mode}
    except UnicodeDecodeError:
        return {"kind": "binary", "digest": hashlib.sha256(result.stdout).hexdigest(), "mode": mode}


def _snapshot_delta_data(
    root: Path, anchor: str, previous_head: str, baseline: dict[str, object],
) -> tuple[list[str], str, str, dict[str, object]]:
    candidates = set(_run_git(root, "diff", "--name-only", anchor).splitlines())
    candidates.update(_run_git(root, "ls-files", "--others", "--exclude-standard").splitlines())
    candidates.update(str(path) for path in baseline)
    changed: list[str] = []
    patches: list[str] = []
    current: dict[str, object] = {}
    for name in sorted(path for path in candidates if path):
        before = baseline.get(name) if name in baseline else _commit_file_snapshot(root, anchor, name)
        after = _read_file_snapshot(root / name)
        current[name] = after or {"kind": "missing"}
        after_value: dict[str, object] = after or {"kind": "missing"}
        before_value: dict[str, object] = before if isinstance(before, dict) else {"kind": "missing"}
        if before_value == after_value:
            continue
        changed.append(name)
        before_text = str(before_value.get("content", ""))
        after_text = str(after_value.get("content", ""))
        if before_value.get("kind") in {"text", "symlink", "missing"} and after_value.get("kind") in {"text", "symlink", "missing"}:
            lines = list(difflib.unified_diff(
                before_text.splitlines(keepends=True), after_text.splitlines(keepends=True),
                fromfile=f"a/{name}", tofile=f"b/{name}", n=3,
            ))
            prefix = f"diff --git a/{name} b/{name}\n"
            mode_note = ""
            old_mode, new_mode = before_value.get("mode"), after_value.get("mode")
            if old_mode != new_mode:
                mode_note = f"old mode {old_mode or 'missing'}\nnew mode {new_mode or 'missing'}\n"
            patches.append(prefix + mode_note + "".join(lines))
        else:
            patches.append(
                f"diff --git a/{name} b/{name}\n"
                f"Binary or non-text file changed: {before_value.get('digest', before_value.get('kind'))} "
                f"-> {after_value.get('digest', after_value.get('kind'))}\n"
            )
    commits = _run_git(root, "log", "--oneline", "--no-decorate", f"{previous_head}..HEAD") or "(no commits since this review)"
    return changed, "\n".join(patches).rstrip(), commits, current


def _criteria(brief: str, criteria_override: str | None) -> str:
    if criteria_override is not None:
        return criteria_override.strip() or "(No acceptance criteria supplied.)"
    sections = [value for value in (_section(brief, "Goal"), _section(brief, "Done")) if value]
    if not sections:
        raise ReviewError("brief has no ## Goal or ## Done section; pass --criteria")
    return "\n\n".join(sections)


def _delta_request_text(
    *, name: str, branch: str, round_number: int, since: str, head: str,
    changed: list[str], patch: str, commits: str, findings: list[dict[str, str]],
    brief_link: str,
) -> str:
    files = "\n".join(f"- `{path}`" for path in changed) or "- (none)"
    open_findings = "\n".join(
        f"- [{item['id']}] {item['severity']} [{item['location']}] {item['body']}"
        for item in findings if item["status"] == "open"
    ) or "- No open findings. Check the delta for regressions introduced by the fix."
    hunks = patch.strip() or "(No changed hunks.)"
    return f"""# Confirmation review: {name} (round {round_number})

## Delta

- Branch: `{branch or '(detached HEAD)'}`
- Since: `{since}`
- Head: `{head}`
- Commits: {commits}
- Changed files:

{files}

## Still-open findings

{open_findings}

## Changed hunks

```diff
{hunks}
```

## Checklist

- Verify each open finding against these hunks; keep its ID and mark it `resolved`, `accepted-scope`, or `open`.
- Check whether the fix adds the needed regression test.
- Escalate to a full review if the fix expands scope, invalidates assumptions, or touches safety-critical behavior.
- Read beyond this delta only when a fix touches shared code; the brief is {brief_link}.
- Add new findings with the next stable ID (`F1`, `F2`, …), initial status `open`, and the standard severity format.
- Never edit repository files or run builds/tests. Update only `build/reviews/{name}.findings.md` and reply `DONE`.
"""


def _new_review_state(root: Path, args: argparse.Namespace) -> dict[str, object]:
    base, head = args.range.split("..", 1)
    head_commit = _run_git(root, "rev-parse", "--verify", "HEAD^{commit}") if head == "WORKTREE" else _resolve_since(root, head, None)
    _, changed, _, _ = _diff_data(root, base, head)
    snapshot = (
        _capture_worktree_snapshot(root, changed) if head == "WORKTREE"
        else {path: _commit_file_snapshot(root, head_commit, path) or {"kind": "missing"} for path in changed}
    )
    branch = _run_git(root, "branch", "--show-current")
    mode = args.start or "sol"
    name = args.name
    brief_text, _ = _read_input(args.brief, root, "brief")
    criteria_text = None
    if args.criteria:
        criteria_text, _ = _read_input(args.criteria, root, "criteria file")
    criteria = _criteria(brief_text, criteria_text)
    notes = ""
    if args.notes:
        notes, _ = _read_input(args.notes, root, "notes file")
    state: dict[str, object] = {
        "version": 1,
        "name": name,
        "base": base,
        "last_head": head_commit,
        "anchor_commit": head_commit,
        "worktree_snapshot": snapshot,
        "branch": branch,
        "brief": args.brief,
        "criteria_content": criteria,
        "notes_content": notes,
        "round": 0,
        "round_tags": {},
        "round_snapshots": {},
        "reviewer": _reviewer_record(name, mode, args.purpose),
    }
    if args.start:
        state["initial_handoff_pending"] = True
    else:
        state["last_reviewed"] = head_commit
        state["round"] = 1
        state["round_tags"] = {"round-1": head_commit}
        state["round_snapshots"] = {"round-1": {
            "head": head_commit, "anchor_commit": head_commit,
            "worktree_snapshot": snapshot,
        }}
    return state


def _reviewer_record(name: str, mode: str, purpose: str | None = None) -> dict[str, str]:
    if mode not in {"sol", "opus"}:
        raise ReviewError(f"unsupported reviewer model mode: {mode}")
    kind, model = ("codex", "gpt-6.1-sol") if mode == "sol" else ("claude", "claude-opus-5-5")
    return {
        "name": _agent_name(name), "mode": mode, "kind": kind, "model": model,
        "purpose": purpose or _default_purpose(name),
    }


def _write_delta_request(
    root: Path, name: str, since_value: str, state: dict[str, object] | None,
    brief_override: str | None = None,
) -> tuple[Path, Path, dict[str, object]]:
    _validate_name(name)
    state = state or {
        "version": 1, "name": name, "round": 0, "round_tags": {},
        "branch": _run_git(root, "branch", "--show-current"),
        "brief": brief_override or "(No brief recorded.)",
        "reviewer": {
            "name": _agent_name(name), "mode": "sol", "kind": "codex",
            "model": "gpt-6.1-sol", "purpose": _default_purpose(name),
        },
    }
    since = _resolve_since(root, since_value, state)
    last_reviewed = str(state.get("last_reviewed", ""))
    baseline = state.get("worktree_snapshot")
    round_snapshots = state.get("round_snapshots", {})
    checkpoint = round_snapshots.get(since_value) if isinstance(round_snapshots, dict) else None
    if isinstance(checkpoint, dict) and isinstance(checkpoint.get("worktree_snapshot"), dict):
        anchor = str(checkpoint.get("anchor_commit", since))
        previous_head = str(checkpoint.get("head", since))
        changed, patch, commits, next_snapshot = _snapshot_delta_data(
            root, anchor, previous_head, checkpoint["worktree_snapshot"]
        )
    elif isinstance(baseline, dict) and since == last_reviewed:
        anchor = str(state.get("anchor_commit", last_reviewed))
        changed, patch, commits, next_snapshot = _snapshot_delta_data(
            root, anchor, last_reviewed, baseline
        )
    else:
        changed, patch, commits = _delta_data(root, since)
        next_snapshot = _capture_worktree_snapshot(root, changed)
        anchor = _run_git(root, "rev-parse", "--verify", "HEAD^{commit}")
    findings_path = root / "build" / "reviews" / f"{name}.findings.md"
    if not findings_path.exists():
        findings_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            findings_path.write_text(_findings_template(), encoding="utf-8")
        except OSError as exc:
            raise ReviewError(f"cannot write findings file {findings_path}: {exc}") from exc
    findings_path, _, findings = _finding_documents(root, name, normalize=True)
    round_number = int(state.get("round", 0)) + 1
    head = _run_git(root, "rev-parse", "--verify", "HEAD^{commit}")
    branch = _run_git(root, "branch", "--show-current")
    brief = str(brief_override or state.get("brief") or "(No brief recorded.)")
    if brief == "(No brief recorded.)":
        brief_link = "(unavailable)"
    else:
        _, brief_path = _read_input(brief, root, "brief")
        brief_link = _link_to_brief(brief_path, root, brief)
    request = root / "build" / "reviews" / f"{name}.round-{round_number}.request.md"
    request.parent.mkdir(parents=True, exist_ok=True)
    try:
        request.write_text(_delta_request_text(
            name=name, branch=branch, round_number=round_number, since=since,
            head=head, changed=changed, patch=patch, commits=commits,
            findings=findings, brief_link=brief_link,
        ), encoding="utf-8")
    except OSError as exc:
        raise ReviewError(f"cannot write delta request {request}: {exc}") from exc
    return request, findings_path, {
        **state, "branch": branch, "last_head": head, "pending_round": round_number,
        "anchor_commit": anchor, "worktree_snapshot": next_snapshot,
    }


def _request_text(
    *, name: str, branch: str, base: str, head: str, stat: str,
    changed: list[str], commits: str, diff_label: str, brief_link: str,
    criteria: str, tests: str, deviations: str, notes: str,
) -> str:
    files = "\n".join(f"- `{path}`" for path in changed) or "- (none)"
    if head == "WORKTREE":
        diff_instruction = (
            f"Inspect `{diff_label}` and read the listed files directly; untracked files are listed but do not "
            "appear in `git diff`."
        )
    else:
        diff_instruction = f"Inspect `{diff_label}` and read the listed files directly."
    extra_notes = notes if notes and tests == "(Not recorded in notes.)" and deviations == "(None recorded in notes.)" else ""
    body = f"""# Review request: {name}

## Scope

- Branch: `{branch or '(detached HEAD)'}`
- Base: `{base}`
- Head: `{head}`
- Diff: `{diff_instruction}`

### Commits

```text
{commits}
```

### Diff stat

```text
{stat}
```

### Changed files

{files}

## Brief

{brief_link}

## Acceptance criteria

{criteria}

## Tests run by the orchestrator

{tests}

## Deviations

{deviations}
"""
    if extra_notes:
        body += f"\n## Additional notes\n\n{extra_notes}\n"
    body += f"""
## Reviewer instructions

Read the brief and inspect the diff before reviewing. Check correctness, behavior parity where the brief requires it,
regressions that would fail if the change were reverted, documentation accuracy, and the repository invariants in
`AGENTS.md`. Never edit repository files. Never run builds or tests that touch the simulator. Write findings only to
`build/reviews/{name}.findings.md`, using one of the template severity headings and the format
`- [F1] [file:line] [open] problem — why it matters — suggested fix`. Give findings sequential stable IDs; preserve each ID
on later rounds and set status to `resolved`, `accepted-scope`, or `open`. Finish by replying `DONE`.
"""
    return body


def _findings_template() -> str:
    sections = [f"## {severity}\n\n<!-- Add findings as: - [F1] [file:line] [open] problem — why it matters — suggested fix -->\n"
                for severity in SEVERITIES]
    return "# Review findings\n\n" + "\n".join(sections) + "\n## Verdict\n\nPending\n"


def _finding_documents(root: Path, name: str, *, normalize: bool) -> tuple[Path, str, list[dict[str, str]]]:
    path = root / "build" / "reviews" / f"{name}.findings.md"
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ReviewError(f"cannot read findings file {path}: {exc}") from exc
    used_ids = FINDING_ID_RE.findall(text)
    if len(used_ids) != len(set(used_ids)):
        raise ReviewError(f"duplicate finding IDs in {path}")
    next_id = max((int(value[1:]) for value in used_ids), default=0) + 1
    active: str | None = None
    findings: list[dict[str, str]] = []
    output: list[str] = []
    changed = False
    for line in text.splitlines():
        heading = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", line)
        if heading:
            title = heading.group(2).strip().casefold()
            active = next((item for item in SEVERITIES if item.casefold() == title), None)
            output.append(line)
            continue
        if active and (match := FINDING_LINE_RE.match(line)):
            finding_id = match.group("id")
            status = match.group("status") or "open"
            if status not in FINDING_STATUSES:
                raise ReviewError(f"invalid status {status!r} for a finding in {path}")
            if not finding_id:
                finding_id = f"F{next_id}"
                next_id += 1
            canonical = (
                f"- [{finding_id}] [{match.group('location')}] [{status}] {match.group('body')}"
            )
            output.append(canonical)
            changed |= canonical != line
            findings.append({
                "id": finding_id, "severity": active,
                "location": match.group("location"), "status": status,
                "body": match.group("body"),
            })
        else:
            output.append(line)
    normalized = "\n".join(output) + ("\n" if text.endswith("\n") else "")
    if normalize and changed:
        try:
            path.write_text(normalized, encoding="utf-8")
        except OSError as exc:
            raise ReviewError(f"cannot update findings file {path}: {exc}") from exc
    return path, normalized, findings


def _open_findings(root: Path, name: str) -> int:
    _validate_name(name)
    _, _, findings = _finding_documents(root, name, normalize=True)
    opened = [finding for finding in findings if finding["status"] == "open"]
    if not opened:
        print("no open findings")
        return 0
    for finding in opened:
        print(
            f"{finding['id']} {finding['severity']} [{finding['location']}] {finding['body']}"
        )
    return 0


def _agent_name(name: str) -> str:
    slug = re.sub(r"[^a-z0-9_-]+", "-", name.casefold()).strip("-_") or "branch"
    if len(slug) > 25:
        suffix = hashlib.sha256(name.encode("utf-8")).hexdigest()[:4]
        slug = f"{slug[:20].rstrip('-_')}-{suffix}"
    return f"review-{slug}"


def _default_purpose(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.casefold()).strip("-")[:5].rstrip("-") or "branch"
    digest = hashlib.sha256(name.encode("utf-8")).hexdigest()[:6]
    return f"Review: {slug}-{digest}"


def _agent_tool(root: Path) -> Path:
    override = os.environ.get(AGENT_OVERRIDE)
    path = Path(override).expanduser() if override else SCRIPT_DIR / "agent.py"
    if not path.is_absolute():
        path = root / path
    path = path.resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ReviewError(f"agent tool is missing or not executable: {path}")
    return path


def _run_agent(tool: Path, root: Path, args: Sequence[str]) -> None:
    try:
        result = subprocess.run(
            [str(tool), *args], cwd=root, capture_output=True, text=True,
            check=False, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ReviewError(f"could not run agent.py {' '.join(args)}: {exc}") from exc
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ReviewError(detail or f"agent.py {' '.join(args)} failed ({result.returncode})")


def _model_tokens(model: str) -> list[tuple[str, ...]]:
    tokens = tuple(re.findall(r"[a-z0-9]+", model.casefold()))
    if model.casefold() == "claude-opus-5-5":
        return [tokens, ("opus", "5", "5")]
    return [tokens]


def _footer_has_model(visible: str, requested_model: str) -> bool:
    clean = ANSI_RE.sub("", visible)
    lines = [line.strip().casefold() for line in clean.splitlines() if line.strip()]
    footer_tokens = re.findall(r"[a-z0-9]+", " ".join(lines[-12:]))
    aliases = _model_tokens(requested_model)
    for alias in aliases:
        if not alias:
            continue
        width = len(alias)
        if any(tuple(footer_tokens[index:index + width]) == alias
               for index in range(len(footer_tokens) - width + 1)):
            return True
    return False


def _verify_model_footer(root: Path, agent_name: str, requested_model: str) -> tuple[str, str]:
    try:
        result = subprocess.run(
            ["herdr", "agent", "read", agent_name, "--source", "visible", "--lines", "12"],
            cwd=root, capture_output=True, text=True, check=False, timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        message = f"could not verify {agent_name} model footer ({exc})"
        print(f"WARNING: {message}", file=sys.stderr)
        return "unverifiable", message
    visible = result.stdout
    if result.returncode:
        message = f"could not verify {agent_name} model footer (herdr exited {result.returncode})"
        print(f"WARNING: {message}", file=sys.stderr)
        return "unverifiable", message
    if _footer_has_model(visible, requested_model):
        return "verified", ""
    clean = ANSI_RE.sub("", visible)
    excerpt = " / ".join(line.strip() for line in clean.splitlines()[-4:] if line.strip())
    excerpt = re.sub(r"[\x00-\x1f\x7f]", " ", excerpt)[:240]
    if not excerpt:
        message = f"could not verify {agent_name} requested model {requested_model}; footer was empty"
        print(f"WARNING: {message}", file=sys.stderr)
        return "unverifiable", message
    message = f"{agent_name} model footer does not show requested {requested_model}; visible: {excerpt}"
    print(f"WARNING: {message}", file=sys.stderr)
    return "mismatch", message


def _require_model(root: Path, agent_name: str, requested_model: str) -> None:
    status, detail = _verify_model_footer(root, agent_name, requested_model)
    if status != "verified":
        raise ReviewError(f"reviewer handoff stopped ({status}): {detail}")


def _start_reviewer(args: argparse.Namespace, root: Path, request_relative: str) -> str:
    if args.start == "sol":
        kind, model = "codex", "gpt-6.1-sol"
    else:
        kind, model = "claude", "claude-opus-5-5"
    name = _agent_name(args.name)
    purpose = args.purpose or _default_purpose(args.name)
    tool = _agent_tool(root)
    start_args = [
        "start", name, "--kind", kind, "--model", model,
    ]
    if kind == "codex":
        start_args.extend(("--effort", "high"))
    start_args.extend(("--role", "reviewer", "--purpose", purpose))
    _run_agent(tool, root, start_args)
    try:
        _require_model(root, name, model)
    except ReviewError as exc:
        try:
            _run_agent(tool, root, ["close", name])
        except ReviewError as close_error:
            raise ReviewError(f"{exc}; could not close mismatched reviewer: {close_error}") from exc
        raise
    _run_agent(tool, root, ["prompt", name, "--brief", request_relative])
    return name


def _advance_review_state(
    root: Path, name: str, pending: dict[str, object], reviewer: dict[str, object] | None = None,
) -> None:
    updated = dict(pending)
    round_number = int(updated.pop("pending_round", int(updated.get("round", 0)) + 1))
    head = str(updated.get("last_head", ""))
    tags = dict(updated.get("round_tags", {})) if isinstance(updated.get("round_tags"), dict) else {}
    checkpoints = dict(updated.get("round_snapshots", {})) if isinstance(updated.get("round_snapshots"), dict) else {}
    tags[f"round-{round_number}"] = head
    checkpoints[f"round-{round_number}"] = {
        "head": head,
        "anchor_commit": updated.get("anchor_commit", head),
        "worktree_snapshot": updated.get("worktree_snapshot", {}),
    }
    updated["round"] = round_number
    updated.pop("initial_handoff_pending", None)
    updated["round_tags"] = tags
    updated["round_snapshots"] = checkpoints
    updated["last_reviewed"] = head
    if reviewer:
        updated["reviewer"] = reviewer
    _save_review_state(root, name, updated)


def _reviewer_agent_status(tool: Path, root: Path, agent_name: str) -> str:
    try:
        result = subprocess.run(
            [str(tool), "status", agent_name], cwd=root, capture_output=True,
            text=True, check=False, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ReviewError(f"could not check reviewer {agent_name} status: {exc}") from exc
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        if "is not managed" in detail:
            return "not-running"
        raise ReviewError(detail or f"could not check reviewer {agent_name} status")
    match = re.search(r"\bstate=([a-z-]+)\b", result.stdout)
    if not match:
        raise ReviewError(f"could not determine reviewer {agent_name} status")
    return match.group(1)


def _confirm_handoff(root: Path, name: str, request: Path, state: dict[str, object]) -> str:
    reviewer = state.get("reviewer", {})
    if not isinstance(reviewer, dict):
        reviewer = {}
    mode = str(reviewer.get("mode", "sol"))
    if mode not in {"sol", "opus"}:
        raise ReviewError(f"unsupported reviewer model mode in review state: {mode}")
    agent_name = str(reviewer.get("name", _agent_name(name)))
    model = str(reviewer.get("model", "gpt-6.1-sol" if mode == "sol" else "claude-opus-5-5"))
    tool = _agent_tool(root)
    status = _reviewer_agent_status(tool, root, agent_name)
    if status in {"working", "idle", "done"}:
        _require_model(root, agent_name, model)
        _run_agent(tool, root, ["prompt", agent_name, "--brief", str(request.relative_to(root))])
        return agent_name
    if status not in {"not-running", "done", "blocked", "cleanup-pending"}:
        raise ReviewError(f"reviewer {agent_name} is not in a promptable state ({status})")
    if status != "not-running":
        _run_agent(tool, root, ["close", agent_name])
    brief_request = argparse.Namespace(
        start=mode, name=name, purpose=str(reviewer.get("purpose", _default_purpose(name)))
    )
    return _start_reviewer(brief_request, root, str(request.relative_to(root)))


def _fallback_full_request(
    root: Path, name: str, state: dict[str, object], reason: ReviewError,
) -> tuple[Path, Path, dict[str, object]]:
    base, brief = str(state.get("base", "")), str(state.get("brief", ""))
    if not base or not brief:
        raise ReviewError(f"incremental review failed ({reason}); full-review fallback lacks its base or brief")
    findings_path = root / "build" / "reviews" / f"{name}.findings.md"
    try:
        prior_findings = findings_path.read_bytes() if findings_path.exists() else None
    except OSError as exc:
        raise ReviewError(f"cannot preserve findings for full-review fallback: {exc}") from exc
    args = argparse.Namespace(
        name=name, range=f"{base}..WORKTREE", brief=brief, criteria=None, notes=None,
        criteria_content=state.get("criteria_content"), notes_content=state.get("notes_content"),
    )
    _, request, findings = _write_request(args)
    if prior_findings is not None:
        try:
            findings.write_bytes(prior_findings)
        except OSError as exc:
            raise ReviewError(f"cannot restore findings after full-review fallback: {exc}") from exc
    changed, _, _, _ = _diff_data(root, base, "WORKTREE")
    head = _run_git(root, "rev-parse", "--verify", "HEAD^{commit}")
    pending = {
        **state, "last_head": head, "pending_round": int(state.get("round", 0)) + 1,
        "anchor_commit": head, "worktree_snapshot": _capture_worktree_snapshot(root, changed),
    }
    print(f"review.sh: incremental review unavailable ({reason}); falling back to a full review", file=sys.stderr)
    return request, findings, pending


def _retry_initial_full_request(
    root: Path, name: str, state: dict[str, object],
) -> tuple[Path, Path, dict[str, object]]:
    base, brief = str(state.get("base", "")), str(state.get("brief", ""))
    if not base or not brief:
        raise ReviewError("initial reviewer handoff is pending, but its full-review base or brief is missing")
    findings_path = root / "build" / "reviews" / f"{name}.findings.md"
    try:
        prior_findings = findings_path.read_bytes() if findings_path.exists() else None
    except OSError as exc:
        raise ReviewError(f"cannot preserve findings for initial full-review retry: {exc}") from exc
    args = argparse.Namespace(
        name=name, range=f"{base}..WORKTREE", brief=brief, criteria=None, notes=None,
        criteria_content=state.get("criteria_content"), notes_content=state.get("notes_content"),
    )
    _, request, findings = _write_request(args)
    if prior_findings is not None:
        try:
            findings.write_bytes(prior_findings)
        except OSError as exc:
            raise ReviewError(f"cannot restore findings after initial full-review retry: {exc}") from exc
    changed, _, _, _ = _diff_data(root, base, "WORKTREE")
    head = _run_git(root, "rev-parse", "--verify", "HEAD^{commit}")
    pending = {
        **state, "last_head": head, "anchor_commit": head,
        "pending_round": 1, "initial_handoff_pending": True,
        "worktree_snapshot": _capture_worktree_snapshot(root, changed),
    }
    return request, findings, pending


def _write_request(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    _validate_name(args.name)
    root = _repo_root()
    if args.range is None or args.range.count("..") != 1:
        raise ReviewError("review range must have the form <base>..<head>")
    base, head = args.range.split("..", 1)
    if not base or not head:
        raise ReviewError("review range must contain both base and head")
    brief_text, brief_path = _read_input(args.brief, root, "brief")
    criteria_content = getattr(args, "criteria_content", None)
    if criteria_content is not None:
        criteria = str(criteria_content)
    else:
        criteria_text = None
        if args.criteria:
            criteria_text, _ = _read_input(args.criteria, root, "criteria file")
        criteria = _criteria(brief_text, criteria_text)
    notes_content = getattr(args, "notes_content", None)
    if notes_content is not None:
        notes = str(notes_content)
    else:
        notes = ""
        if args.notes:
            notes, _ = _read_input(args.notes, root, "notes file")
    tests, deviations, raw_notes = _notes_sections(notes)
    branch = _run_git(root, "branch", "--show-current")
    stat, changed, commits, diff_label = _diff_data(root, base, head)
    review_dir = root / "build" / "reviews"
    try:
        review_dir.mkdir(parents=True, exist_ok=True)
        request = review_dir / f"{args.name}.request.md"
        findings = review_dir / f"{args.name}.findings.md"
        request.write_text(
            _request_text(
                name=args.name, branch=branch, base=base, head=head, stat=stat,
                changed=changed, commits=commits, diff_label=diff_label,
                brief_link=_link_to_brief(brief_path, root, args.brief),
                criteria=criteria, tests=tests, deviations=deviations, notes=raw_notes,
            ),
            encoding="utf-8",
        )
        findings.write_text(_findings_template(), encoding="utf-8")
    except OSError as exc:
        raise ReviewError(f"cannot write review files in {review_dir}: {exc}") from exc
    return root, request, findings


def _collect(root: Path, name: str) -> int:
    _validate_name(name)
    _, _, parsed = _finding_documents(root, name, normalize=True)
    found: dict[str, list[str]] = {severity: [] for severity in SEVERITIES}
    for finding in parsed:
        if finding["status"] != "open":
            continue
        found[finding["severity"]].append(
            f"- [{finding['id']}] [{finding['location']}] [open] {finding['body']}"
        )
    print(" ".join(f"{severity.casefold()}={len(found[severity])}" for severity in SEVERITIES))
    for severity in ("Blocking", "Major"):
        for finding in found[severity]:
            print(f"{severity}: {finding}")
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Prepare and collect branch review requests.")
    parser.add_argument("range", nargs="?", help="<base>..<head>, with WORKTREE for uncommitted changes")
    parser.add_argument("--name")
    parser.add_argument("--brief")
    parser.add_argument("--criteria")
    parser.add_argument("--notes")
    parser.add_argument("--start", choices=("sol", "opus"))
    parser.add_argument("--purpose")
    parser.add_argument("--collect", metavar="NAME")
    parser.add_argument("--since", metavar="COMMIT_OR_ROUND")
    parser.add_argument("--confirm", metavar="NAME")
    parser.add_argument("--findings-for", metavar="NAME")
    parser.add_argument("--open", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        if args.collect is not None:
            if any((args.range, args.name, args.brief, args.criteria, args.notes, args.start, args.purpose,
                    args.since, args.confirm, args.findings_for, args.open)):
                raise ReviewError("--collect cannot be combined with review request options")
            return _collect(_repo_root(), args.collect)
        if args.findings_for is not None:
            if not args.open or any((args.range, args.name, args.brief, args.criteria, args.notes, args.start,
                                     args.purpose, args.collect, args.since, args.confirm)):
                raise ReviewError("--findings-for NAME requires --open and cannot be combined with other options")
            return _open_findings(_repo_root(), args.findings_for)
        if args.open:
            raise ReviewError("--open requires --findings-for NAME")
        if args.confirm is not None:
            if any((args.range, args.name, args.brief, args.criteria, args.notes, args.start, args.purpose,
                    args.collect, args.since)):
                raise ReviewError("--confirm NAME cannot be combined with other options")
            name = args.confirm
            _validate_name(name)
            root = _repo_root()
            state = _load_review_state(root, name)
            if state is None:
                raise ReviewError(f"no prior review state for {name}; run a full review before confirming")
            if state.get("initial_handoff_pending"):
                request, findings, pending = _retry_initial_full_request(root, name, state)
            else:
                since = str(state.get("last_reviewed", ""))
                if not since:
                    raise ReviewError(f"review state for {name} has no last-reviewed commit")
                try:
                    request, findings, pending = _write_delta_request(root, name, since, state)
                except ReviewError as delta_error:
                    request, findings, pending = _fallback_full_request(root, name, state, delta_error)
            result = 0
            reviewer_name = ""
            try:
                reviewer_name = _confirm_handoff(root, name, request, pending)
                _advance_review_state(root, name, pending)
            except ReviewError as exc:
                print(f"review.sh: {exc}", file=sys.stderr)
                result = 1
            output = f"request={request.relative_to(root)} findings={findings.relative_to(root)}"
            if reviewer_name:
                output += f" agent={reviewer_name}"
            print(output)
            return result
        if args.since is not None:
            if args.range or not args.name or args.criteria or args.notes or args.purpose:
                raise ReviewError("--since requires --name and cannot be combined with a range, --criteria, --notes, or --purpose")
            _validate_name(args.name)
            root = _repo_root()
            state = _load_review_state(root, args.name)
            if state is None and not args.brief:
                raise ReviewError("--since without prior state requires --brief")
            request, findings, pending = _write_delta_request(root, args.name, args.since, state, args.brief)
            reviewer_name = ""
            if args.start:
                reviewer_name = _start_reviewer(args, root, str(request.relative_to(root)))
                prior_reviewer = state.get("reviewer", {}) if isinstance(state, dict) else {}
                prior_purpose = prior_reviewer.get("purpose") if isinstance(prior_reviewer, dict) else None
                _advance_review_state(
                    root, args.name, pending,
                    _reviewer_record(args.name, args.start, str(prior_purpose) if prior_purpose else None),
                )
            output = f"request={request.relative_to(root)} findings={findings.relative_to(root)}"
            if reviewer_name:
                output += f" agent={reviewer_name}"
            print(output)
            return 0
        if not args.name or not args.brief:
            parser.error("review mode requires --name and --brief")
        if args.purpose and not args.start:
            raise ReviewError("--purpose requires --start")
        root, request, findings = _write_request(args)
        initial_state = _new_review_state(root, args)
        _save_review_state(root, args.name, initial_state)
        started: str | None = None
        result = 0
        if args.start:
            try:
                started = _start_reviewer(
                    args, root, str(request.relative_to(root))
                )
                _advance_review_state(root, args.name, initial_state)
            except ReviewError as exc:
                print(f"review.sh: {exc}", file=sys.stderr)
                result = 1
        output = (
            f"request={request.relative_to(root)} findings={findings.relative_to(root)}"
        )
        if started:
            output += f" agent={started}"
        print(output)
        return result
    except ReviewError as exc:
        print(f"review.sh: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
