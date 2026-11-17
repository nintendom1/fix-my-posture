#!/usr/bin/env python3
"""Check the required opening and sections in a pull request or commit body."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


REQUIRED_PR_SECTIONS = ("Summary", "Testing", "Docs")
TRAILER_PATTERN = re.compile(r"^(?:Co-Authored-By|Claude-Session):", re.IGNORECASE)
ATX_HEADING_PATTERN = re.compile(r"^#{1,6}[ \t]+(.*?)[ \t]*#*[ \t]*$")
SETEXT_HEADING_PATTERN = re.compile(r"^(?:=+|-+)[ \t]*$")
FENCE_OPEN_PATTERN = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
LIST_START_PATTERN = re.compile(r"^ {0,3}(?:[-+*]|[0-9]{1,9}[.)])[ \t]+")
THEMATIC_BREAK_PATTERN = re.compile(
    r"^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$"
)


def _remove_html_comments(line: str, in_comment: bool) -> tuple[str, bool]:
    """Remove HTML comments while preserving text outside each comment."""
    visible: list[str] = []
    cursor = 0

    while cursor < len(line):
        if in_comment:
            end = line.find("-->", cursor)
            if end == -1:
                return "".join(visible), True
            cursor = end + 3
            in_comment = False
            continue

        start = line.find("<!--", cursor)
        if start == -1:
            visible.append(line[cursor:])
            break
        visible.append(line[cursor:start])
        cursor = start + 4
        in_comment = True

    return "".join(visible), in_comment


def _markdown_context_lines(lines: list[str]) -> tuple[list[str], list[str]]:
    """Return opening text without comments and heading text without comments or fences."""
    opening_lines: list[str] = []
    heading_lines: list[str] = []
    fence_character: str | None = None
    fence_length = 0
    in_comment = False

    for line in lines:
        if fence_character is not None:
            opening_lines.append(line)
            heading_lines.append("")
            stripped = line.lstrip(" ")
            indent = len(line) - len(stripped)
            run_length = len(stripped) - len(stripped.lstrip(fence_character))
            remainder = stripped[run_length:]
            if (
                indent <= 3
                and run_length >= fence_length
                and remainder.strip() == ""
            ):
                fence_character = None
                fence_length = 0
            continue

        fence = None if in_comment else FENCE_OPEN_PATTERN.match(line)
        if fence is not None:
            marker = fence.group(1)
            info = fence.group(2)
            if marker[0] != "`" or "`" not in info:
                fence_character = marker[0]
                fence_length = len(marker)
                opening_lines.append(line)
                heading_lines.append("")
                continue

        visible, in_comment = _remove_html_comments(line, in_comment)
        opening_lines.append(visible)
        heading_lines.append(visible)

    return opening_lines, heading_lines


def _starts_markdown_block(line: str) -> bool:
    """Identify block starts that cannot be wrapped opening-paragraph text."""
    if _heading(line) is not None:
        return True
    if FENCE_OPEN_PATTERN.match(line) is not None:
        return True
    if LIST_START_PATTERN.match(line) is not None:
        return True
    indentation = len(line) - len(line.lstrip(" "))
    if line.lstrip(" ").startswith(">") and indentation <= 3:
        return True
    return THEMATIC_BREAK_PATTERN.fullmatch(line) is not None


def _heading(line: str) -> tuple[int, str] | None:
    """Return an ATX heading's level and text, including headings in blockquotes."""
    text = line
    while True:
        text = text.lstrip(" ")
        if len(line) - len(line.lstrip(" ")) > 3:
            return None
        if not text.startswith(">"):
            break
        text = text[1:]
        if text.startswith(" "):
            text = text[1:]
        line = text

    match = ATX_HEADING_PATTERN.match(text)
    if match is None:
        return None

    marker_count = len(text) - len(text.lstrip("#"))
    heading_text = re.sub(r"[ \t]+#+[ \t]*$", "", match.group(1)).strip()
    return marker_count, heading_text


def _is_forbidden_heading(lines: list[str], index: int) -> bool:
    heading = _heading(lines[index])
    if heading is not None and heading[1].casefold() in {"before", "now"}:
        return True

    if index + 1 < len(lines) and SETEXT_HEADING_PATTERN.fullmatch(lines[index + 1].strip()):
        return lines[index].strip().casefold() in {"before", "now"}
    return False


def _is_required_section(line: str, section: str) -> bool:
    heading = _heading(line)
    return heading == (2, section)


def _strip_commit_trailers(lines: list[str]) -> list[str]:
    end = len(lines)
    while end > 0 and not lines[end - 1].strip():
        end -= 1

    while end > 0:
        start = end - 1
        while start > 0 and lines[start].startswith((" ", "\t")):
            start -= 1
        if TRAILER_PATTERN.match(lines[start]) is None:
            break
        end = start
        while end > 0 and not lines[end - 1].strip():
            end -= 1

    return lines[:end]


def commit_body(message: str) -> list[str]:
    """Remove the subject and trailing metadata lines from a full commit message."""
    lines = message.splitlines()
    return _strip_commit_trailers(lines[1:]) if lines else []


def validate_body(body: str, *, is_pr: bool = False) -> list[tuple[int, str, str]]:
    """Return ordered (line number, line text, reason) validation issues."""
    lines = body.splitlines()
    opening_lines, heading_lines = _markdown_context_lines(lines)
    nonempty = [
        (number, line)
        for number, line in enumerate(opening_lines, start=1)
        if line.strip()
    ]
    issues: list[tuple[int, str, str]] = []

    if not nonempty:
        issues.append((1, "", 'body must start with a non-empty line beginning "Before, "'))
        issues.append((1, "", 'body must have a next non-empty line beginning "Now, "'))
    else:
        first_number, first_line = nonempty[0]
        if not first_line.startswith("Before, "):
            issues.append((first_number, first_line, 'first non-empty line must begin "Before, "'))

        if len(nonempty) < 2:
            issues.append((len(lines) + 1, "", 'next non-empty line must begin "Now, "'))
        elif is_pr and not nonempty[1][1].startswith("Now, "):
            now_number, now_line = nonempty[1]
            issues.append((now_number, now_line, 'next non-empty line must begin "Now, "'))
        elif not is_pr and not nonempty[1][1].startswith("Now, "):
            # The historical 693ee23 commit wraps Before over several physical
            # lines. In commit mode, accept Now only within that same opening
            # paragraph; blank lines and Markdown block starts end the exception.
            now_found = False
            for index in range(first_number, len(lines)):
                raw_line = lines[index]
                line = opening_lines[index]
                if not raw_line.strip():
                    break
                if not line.strip():
                    continue
                if line.startswith("Now, "):
                    now_found = True
                    break
                if _starts_markdown_block(line):
                    break
            if not now_found:
                now_number, now_line = nonempty[1]
                issues.append(
                    (
                        now_number,
                        now_line,
                        'next opening paragraph must contain a line beginning "Now, "',
                    )
                )

    for index, line in enumerate(heading_lines):
        if _is_forbidden_heading(heading_lines, index):
            issues.append((index + 1, lines[index], "Markdown headings named Before or Now are not allowed"))

    if is_pr:
        for section in REQUIRED_PR_SECTIONS:
            if not any(_is_required_section(line, section) for line in heading_lines):
                issues.append((len(lines) + 1, "", f"missing required ## {section} section"))

    return sorted(issues, key=lambda issue: issue[0])


def _read_pr_body(number: int) -> str:
    result = subprocess.run(
        ["gh", "pr", "view", str(number), "--json", "body"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "gh returned an error"
        raise RuntimeError(f"could not read PR #{number}: {detail}")

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"gh returned invalid JSON for PR #{number}: {error}") from error
    if not isinstance(payload, dict):
        raise RuntimeError(f"gh returned invalid data for PR #{number}")

    body = payload.get("body")
    return body if isinstance(body, str) else ""


def _read_commit_message(sha: str) -> str:
    result = subprocess.run(
        ["git", "show", "-s", "--format=%B", sha],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "git returned an error"
        raise RuntimeError(f"could not read commit {sha}: {detail}")
    return result.stdout


def _read_file(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    try:
        return Path(path).read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeError(f"could not read body file {path}: {error}") from error


def _print_failure(issues: list[tuple[int, str, str]], *, is_pr: bool) -> None:
    print('Expected: first non-empty line "Before, ...", then "Now, ..."; no Markdown headings named Before or Now.')
    if is_pr:
        print("PR bodies also need ## Summary, ## Testing, and ## Docs.")

    line_number, line, reason = issues[0]
    if line:
        shown = line if len(line) <= 180 else line[:177] + "..."
        print(f"First offending line {line_number}: {shown!r} ({reason}).", file=sys.stderr)
    else:
        print(f"First offending line: <end of body> ({reason}).", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--file", metavar="PATH", help="read a body from PATH, or - for stdin")
    source.add_argument("--pr", type=int, metavar="N", help="read PR N with gh")
    source.add_argument("--commit", metavar="SHA", help="read commit SHA with git")
    args = parser.parse_args(argv)

    is_pr = args.commit is None
    try:
        if args.pr is not None:
            body = _read_pr_body(args.pr)
        elif args.commit is not None:
            body = "\n".join(commit_body(_read_commit_message(args.commit)))
        else:
            body = _read_file(args.file)
    except (OSError, RuntimeError, FileNotFoundError) as error:
        print(str(error), file=sys.stderr)
        return 1

    issues = validate_body(body, is_pr=is_pr)
    if issues:
        _print_failure(issues, is_pr=is_pr)
        return 1

    print("PR body format OK." if is_pr else "Body format OK.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
