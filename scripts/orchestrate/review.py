#!/usr/bin/env python3
"""Prepare review requests and findings templates for a branch or worktree."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
AGENT_OVERRIDE = "FMP_REVIEW_AGENT_TOOL"
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
FINDING_RE = re.compile(r"^\s*-\s+\[[^\]]+:\d+\]\s+\S")
SEVERITIES = ("Blocking", "Major", "Minor", "Nit")


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


def _criteria(brief: str, criteria_override: str | None) -> str:
    if criteria_override is not None:
        return criteria_override.strip() or "(No acceptance criteria supplied.)"
    sections = [value for value in (_section(brief, "Goal"), _section(brief, "Done")) if value]
    if not sections:
        raise ReviewError("brief has no ## Goal or ## Done section; pass --criteria")
    return "\n\n".join(sections)


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
`- [file:line] problem — why it matters — suggested fix`. Finish by replying `DONE`.
"""
    return body


def _findings_template() -> str:
    sections = [f"## {severity}\n\n<!-- Add findings as: - [file:line] problem — why it matters — suggested fix -->\n"
                for severity in SEVERITIES]
    return "# Review findings\n\n" + "\n".join(sections) + "\n## Verdict\n\nPending\n"


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


def _verify_model_footer(root: Path, agent_name: str, requested_model: str) -> None:
    try:
        result = subprocess.run(
            ["herdr", "agent", "read", agent_name, "--source", "visible", "--lines", "12"],
            cwd=root, capture_output=True, text=True, check=False, timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"WARNING: could not verify {agent_name} model footer ({exc})", file=sys.stderr)
        return
    visible = result.stdout
    if result.returncode:
        print(
            f"WARNING: could not verify {agent_name} model footer (herdr exited {result.returncode})",
            file=sys.stderr,
        )
        return
    if _footer_has_model(visible, requested_model):
        return
    clean = ANSI_RE.sub("", visible)
    excerpt = " / ".join(line.strip() for line in clean.splitlines()[-4:] if line.strip())
    excerpt = re.sub(r"[\x00-\x1f\x7f]", " ", excerpt)[:240]
    detail = f"; visible: {excerpt}" if excerpt else "; footer was empty"
    print(
        f"WARNING: {agent_name} model footer does not show requested {requested_model}{detail}",
        file=sys.stderr,
    )


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
    _verify_model_footer(root, name, model)
    _run_agent(tool, root, ["prompt", name, "--brief", request_relative])
    return name


def _write_request(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    _validate_name(args.name)
    root = _repo_root()
    if args.range is None or args.range.count("..") != 1:
        raise ReviewError("review range must have the form <base>..<head>")
    base, head = args.range.split("..", 1)
    if not base or not head:
        raise ReviewError("review range must contain both base and head")
    brief_text, brief_path = _read_input(args.brief, root, "brief")
    criteria_text = None
    if args.criteria:
        criteria_text, _ = _read_input(args.criteria, root, "criteria file")
    criteria = _criteria(brief_text, criteria_text)
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
    findings_path = root / "build" / "reviews" / f"{name}.findings.md"
    try:
        text = findings_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ReviewError(f"cannot read findings file {findings_path}: {exc}") from exc
    found: dict[str, list[str]] = {severity: [] for severity in SEVERITIES}
    active: str | None = None
    for line in text.splitlines():
        heading = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", line)
        if heading:
            title = heading.group(1).strip().casefold()
            active = next((severity for severity in SEVERITIES if title == severity.casefold()), None)
            continue
        if active and FINDING_RE.match(line):
            found[active].append(line.strip())
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
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        if args.collect is not None:
            if any((args.range, args.name, args.brief, args.criteria, args.notes, args.start, args.purpose)):
                raise ReviewError("--collect cannot be combined with review request options")
            return _collect(_repo_root(), args.collect)
        if not args.name or not args.brief:
            parser.error("review mode requires --name and --brief")
        if args.purpose and not args.start:
            raise ReviewError("--purpose requires --start")
        root, request, findings = _write_request(args)
        started: str | None = None
        result = 0
        if args.start:
            try:
                started = _start_reviewer(
                    args, root, str(request.relative_to(root))
                )
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
