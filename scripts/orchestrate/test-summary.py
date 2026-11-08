#!/usr/bin/env python3
"""Print a compact summary of an Xcode result bundle."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlsplit


MAX_OUTPUT_LINES = 30
XCRESULT_TIMEOUT_SECONDS = 120


class SummaryError(Exception):
    """A result bundle could not be summarized."""


def _resolve_bundle(value: str) -> Path:
    path = Path(value).expanduser()
    if path.name.endswith(".xcresult"):
        if not path.is_dir() or not (path / "Info.plist").is_file():
            raise SummaryError(f"incomplete or missing result bundle: {path}")
        return path
    if not path.is_dir():
        raise SummaryError(f"not an .xcresult bundle or derived-data directory: {path}")
    candidates = [
        item for item in (path / "Logs" / "Test").glob("*.xcresult")
        if item.is_dir() and (item / "Info.plist").is_file()
    ]
    if not candidates:
        raise SummaryError(f"no completed xcresult bundle under {path / 'Logs' / 'Test'}")
    return max(candidates, key=lambda item: item.stat().st_mtime_ns)


def _xcresult_json(*args: str) -> dict[str, Any]:
    try:
        process = subprocess.run(
            ["xcrun", "xcresulttool", *args], capture_output=True, text=True,
            check=False, timeout=XCRESULT_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise SummaryError(f"xcresulttool could not run: {exc}") from exc
    if process.returncode:
        detail = (process.stderr or process.stdout).strip()
        raise SummaryError(detail or "xcresulttool failed")
    try:
        payload = json.loads(process.stdout)
    except json.JSONDecodeError as exc:
        raise SummaryError("xcresulttool returned invalid JSON") from exc
    if not isinstance(payload, dict):
        raise SummaryError("xcresulttool returned a non-object JSON result")
    return payload


def _count(payload: dict[str, Any], keys: tuple[str, ...]) -> int | None:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, int) and not isinstance(value, bool):
            return value
    return None


def _walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def _legacy_plain(value: Any) -> Any:
    """Unwrap xcresulttool's typed legacy scalar and array values."""
    if isinstance(value, dict):
        if "_value" in value:
            return _legacy_plain(value["_value"])
        if "_values" in value:
            return [_legacy_plain(item) for item in value["_values"]]
        return {key: _legacy_plain(child) for key, child in value.items() if key != "_type"}
    if isinstance(value, list):
        return [_legacy_plain(item) for item in value]
    return value


def _legacy_value(payload: dict[str, Any], aliases: tuple[str, ...]) -> int | None:
    wanted = {alias.casefold() for alias in aliases}
    for item in _walk(payload):
        for key, value in item.items():
            if key.casefold() in wanted:
                try:
                    return int(value)
                except (TypeError, ValueError):
                    continue
    return None


def _case_parts(identifier: str, ancestors: tuple[str, ...] = ()) -> tuple[str, str]:
    bracket = re.search(r"\[\S*?\.?([A-Za-z_][\w]*)\s+([A-Za-z_][\w]*)\]", identifier)
    if bracket:
        return bracket.group(1), bracket.group(2)
    parts = [part for part in re.split(r"[/\\]", identifier.strip()) if part]
    method = parts[-1] if parts else identifier.strip()
    if method.endswith("()"):
        method = method[:-2]
    class_name = parts[-2] if len(parts) >= 2 else ""
    if class_name.endswith(".xctest"):
        class_name = ""
    if not class_name:
        class_name = next(
            (name for name in reversed(ancestors) if name and not name.endswith(".xctest")),
            "UnknownClass",
        )
    return class_name, method or "unknownTest"


def _location(details: Any) -> tuple[str, str]:
    first_line = "0"
    for item in _walk(details):
        item_line = "0"
        for key, value in item.items():
            if key.casefold() in {"linenumber", "startinglinenumber", "endinglinenumber"}:
                try:
                    candidate = int(value)
                    if candidate > 0:
                        item_line = str(candidate)
                        break
                except (TypeError, ValueError):
                    pass
        if first_line == "0" and item_line != "0":
            first_line = item_line
        for key, value in item.items():
            lowered = key.casefold()
            if not isinstance(value, str):
                continue
            if lowered in {"url", "file", "path", "documentlocationincreatingworkspace"} or (
                lowered == "details" and ".swift" in value and ("#" in value or "://" in value)
            ):
                candidate_url = value
                parsed = urlsplit(candidate_url)
                path = unquote(parsed.path or candidate_url.split("#", 1)[0])
                match = re.search(r"([^/\\]+\.swift)", path)
                if match:
                    file_name = match.group(1)
                    line = item_line if item_line != "0" else first_line
                    fragment = parse_qs(parsed.fragment)
                    for line_key in ("StartingLineNumber", "EndingLineNumber", "lineNumber"):
                        values = fragment.get(line_key)
                        if values and values[0].isdigit():
                            line = values[0]
                            break
                    return file_name, line
            match = re.search(r"([^\s:/\\]+\.swift):(\d+)(?::\d+)?", value)
            if match:
                return match.group(1), match.group(2)
    return "unknown.swift", first_line


def _first_failure_context(details: dict[str, Any]) -> Any:
    """Pair the first failure message with its own nested or adjacent source context."""
    def find(value: Any) -> Any | None:
        if isinstance(value, dict):
            children = value.get("children")
            if isinstance(children, list):
                for index, child in enumerate(children):
                    if not isinstance(child, dict):
                        continue
                    if str(child.get("nodeType", "")).casefold() == "failure message":
                        context: dict[str, Any] = {"failure": child}
                        for sibling in children[index + 1:]:
                            if not isinstance(sibling, dict):
                                continue
                            if str(sibling.get("nodeType", "")).casefold() == "failure message":
                                break
                            if str(sibling.get("nodeType", "")).casefold() == "source code reference":
                                context["source"] = sibling
                                break
                        return context
                    nested = find(child)
                    if nested is not None:
                        return nested
            for key, child in value.items():
                if key != "children":
                    nested = find(child)
                    if nested is not None:
                        return nested
        elif isinstance(value, list):
            for child in value:
                nested = find(child)
                if nested is not None:
                    return nested
        return None

    return find(details) or details


def _failure_message(details: Any) -> str:
    candidates: list[str] = []
    for item in _walk(details):
        for key in ("failureText", "failureMessage", "message"):
            value = item.get(key)
            if isinstance(value, str) and value.strip():
                candidates.append(value.strip())
        if str(item.get("nodeType", "")).casefold() == "failure message":
            value = item.get("details") or item.get("name")
            if isinstance(value, str) and value.strip():
                candidates.append(value.strip())
    if not candidates:
        for item in _walk(details):
            value = item.get("details")
            if isinstance(value, str) and value.strip():
                candidates.append(value.strip())
    text = re.sub(r"\s+", " ", candidates[0]) if candidates else "Test failed"
    return text if len(text) <= 160 else text[:157].rstrip() + "..."


def _identifier(details: dict[str, Any]) -> str:
    for key in ("testIdentifierString", "nodeIdentifier", "testIdentifierURL", "testName", "testCaseName", "name"):
        value = details.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return "UnknownClass/unknownTest"


def _failure_rows(summary: dict[str, Any], tests: dict[str, Any]) -> list[str]:
    failures: list[tuple[dict[str, Any], tuple[str, ...]]] = []
    raw_summary = summary.get("testFailures", [])
    if isinstance(raw_summary, dict):
        raw_summary = [raw_summary]
    if isinstance(raw_summary, list):
        failures.extend((item, ()) for item in raw_summary if isinstance(item, dict))

    def collect_nodes(value: Any, ancestors: tuple[str, ...] = ()) -> None:
        if isinstance(value, dict):
            node_type = str(value.get("nodeType", ""))
            name = str(value.get("name", ""))
            parent_names = ancestors
            if node_type.casefold() == "test suite" and name:
                parent_names = (*ancestors, name)
            if node_type.casefold() in {"test case", "test case run"} and str(value.get("result", "")).casefold() == "failed":
                failures.append((value, ancestors))
            for child in value.values():
                collect_nodes(child, parent_names)
        elif isinstance(value, list):
            for child in value:
                collect_nodes(child, ancestors)

    collect_nodes(tests)
    for value in _walk(summary):
        legacy_failures = value.get("testFailureSummaries")
        if isinstance(legacy_failures, dict):
            legacy_failures = legacy_failures.get("_values", [])
        if isinstance(legacy_failures, list):
            failures.extend((item, ()) for item in legacy_failures if isinstance(item, dict))

    rows: dict[str, str] = {}
    for details, ancestors in failures:
        identifier = _identifier(details)
        class_name, method_name = _case_parts(identifier, ancestors)
        key = f"{class_name}/{method_name}"
        context = _first_failure_context(details)
        file_name, line = _location(context)
        row = f"{key} {file_name}:{line} {_failure_message(context)}"
        previous = rows.get(key)
        if previous is None or " unknown.swift:0 " in previous:
            rows[key] = row
    return list(rows.values())


def _duration(summary: dict[str, Any]) -> float:
    def as_seconds(value: Any) -> float | None:
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return float(value)
        if isinstance(value, str):
            try:
                return float(value)
            except ValueError:
                try:
                    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
                except ValueError:
                    return None
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                return parsed.timestamp()
        return None

    duration = as_seconds(summary.get("duration"))
    if duration is not None:
        return max(0.0, duration)
    start = as_seconds(summary.get("startTime"))
    finish = as_seconds(summary.get("finishTime"))
    if start is not None and finish is not None:
        return max(0.0, finish - start)
    return 0.0


def _format_duration(seconds: float) -> str:
    rounded = int(round(seconds))
    hours, remainder = divmod(rounded, 3600)
    minutes, seconds_left = divmod(remainder, 60)
    if hours:
        return f"{hours}h {minutes}m {seconds_left}s"
    if minutes:
        return f"{minutes}m {seconds_left}s"
    return f"{seconds_left}s"


def _count_nodes(tests: dict[str, Any], result: str) -> int:
    return sum(
        1 for item in _walk(tests)
        if str(item.get("nodeType", "")).casefold() == "test case"
        and str(item.get("result", "")).casefold() == result.casefold()
    )


def _legacy_action_count(summary: dict[str, Any], aliases: tuple[str, ...]) -> int | None:
    actions = summary.get("actions")
    if not isinstance(actions, list):
        return None
    counts: list[int] = []
    for action in actions:
        if not isinstance(action, dict):
            continue
        result = action.get("actionResult")
        if not isinstance(result, dict):
            continue
        metrics = result.get("metrics")
        if isinstance(metrics, dict):
            count = _count(metrics, aliases)
            if count is None:
                count = _legacy_value(metrics, aliases)
            if count is not None:
                counts.append(count)
    return sum(counts) if counts else None


def _summarize(summary: dict[str, Any], tests: dict[str, Any]) -> tuple[str, list[str], int]:
    total = _count(summary, ("totalTestCount", "totalTests", "testsCount"))
    skipped = _count(summary, ("skippedTests", "skippedTestCount", "testsSkipped"))
    failed = _count(summary, ("failedTests", "failedTestCount", "testsFailed"))
    if total is None:
        total = _legacy_action_count(summary, ("testsCount", "totalTestCount"))
    if total is None:
        total = _legacy_value(summary, ("testsCount", "totalTestCount"))
    if skipped is None:
        skipped = _legacy_action_count(summary, ("testsSkippedCount", "skippedTests"))
    if skipped is None:
        skipped = _legacy_value(summary, ("testsSkippedCount", "skippedTests"))
    if failed is None:
        failed = _legacy_action_count(summary, ("testsFailedCount", "failedTests"))
    if failed is None:
        failed = _legacy_value(summary, ("testsFailedCount", "failedTests"))
    node_total = _count_nodes(tests, "Passed") + _count_nodes(tests, "Failed") + _count_nodes(tests, "Skipped")
    if total is None and node_total:
        total = node_total
    skipped = skipped if skipped is not None else _count_nodes(tests, "Skipped")
    failed = failed if failed is not None else _count_nodes(tests, "Failed")
    if total is None or total <= 0:
        raise SummaryError("result bundle has no usable test counts")
    if skipped is None or failed is None:
        raise SummaryError("result bundle is missing test outcome counts")
    result = str(summary.get("result", "")).casefold()
    if result and result not in {"passed", "failed", "skipped"}:
        raise SummaryError(f"result bundle has an unrecognized test result: {result}")
    status = "FAIL" if failed > 0 or result == "failed" else "PASS"
    header = f"{status} {total} tests, {skipped} skipped, {failed} failed ({_format_duration(_duration(summary))})"
    return header, _failure_rows(summary, tests), failed


def _modern_summary(bundle: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    summary = _xcresult_json("get", "test-results", "summary", "--path", str(bundle))
    tests = _xcresult_json("get", "test-results", "tests", "--path", str(bundle))
    if not any(key in summary for key in ("totalTestCount", "totalTests", "testsCount")):
        raise SummaryError("Xcode test summary JSON has an unexpected shape")
    return summary, tests


def _legacy_summary(bundle: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    summary = _legacy_plain(_xcresult_json("get", "--legacy", "--format", "json", "--path", str(bundle)))
    if not summary:
        raise SummaryError("legacy xcresult JSON is empty")
    return summary, {}


def _render(value: str) -> list[str]:
    bundle = _resolve_bundle(value)
    try:
        summary, tests = _modern_summary(bundle)
    except SummaryError as modern_error:
        try:
            summary, tests = _legacy_summary(bundle)
        except SummaryError as legacy_error:
            raise SummaryError(f"cannot read result bundle: {legacy_error}; Xcode 16: {modern_error}") from legacy_error
    header, failures, _ = _summarize(summary, tests)
    lines = [header]
    if len(lines) + len(failures) <= MAX_OUTPUT_LINES:
        lines.extend(failures)
    else:
        visible_failures = MAX_OUTPUT_LINES - 2
        lines.extend(failures[:visible_failures])
        lines.append(f"… {len(failures) - visible_failures} more")
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Summarize an Xcode .xcresult bundle or derived-data folder.")
    parser.add_argument("path", help=".xcresult bundle or derived-data folder")
    args = parser.parse_args(argv)
    try:
        lines = _render(args.path)
    except SummaryError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    print("\n".join(lines))
    return 1 if lines[0].startswith("FAIL ") else 0


if __name__ == "__main__":
    raise SystemExit(main())
