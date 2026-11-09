#!/usr/bin/env python3
"""Apply temporary source mutations, run focused tests, and restore the source."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCRIPT_FILE = Path(__file__).resolve()
ROOT: Path | None = None
SUMMARY_PATTERNS = (
    re.compile(r"\b(?:PASS|FAIL)\s+(\d+)\s+tests?,\s*(\d+)\s+skipped,\s*(\d+)\s+failed\b", re.I),
    re.compile(r"\bExecuted\s+(\d+)\s+tests?,\s+with\s+(\d+)\s+failures?\b", re.I),
)
COMPILER_DIAGNOSTIC = re.compile(
    r"(?im)^\s*(?:.*?:\d+:\d+(?::\d+)?:\s*)?(?:fatal error|error):\s*"
)
TOOL_DIAGNOSTIC = re.compile(r"(?im)^\s*(?:xcodebuild|swift|test\.sh|with-lock\.py):\s*error:")


class MutationNotApplied(Exception):
    """The requested edit could not be applied to the target file."""


class RunnerUnavailable(Exception):
    """A test command or required runner helper could not be launched."""


class MutationInterrupted(Exception):
    """A signal arrived while tests were running; source was restored first."""

    def __init__(self, signum: int) -> None:
        self.signum = signum


@dataclass(frozen=True)
class Mutation:
    identifier: str
    file: str
    operation: str
    value: Any
    tests: tuple[str, ...]
    package: str | None = None


@dataclass(frozen=True)
class TestResult:
    status: str
    failed: int
    run: int


def _arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run focused mutation checks and restore every source file.")
    parser.add_argument("--file")
    operation = parser.add_mutually_exclusive_group()
    operation.add_argument("--sed")
    operation.add_argument("--replace", nargs=2, metavar=("OLD", "NEW"))
    operation.add_argument("--patch")
    parser.add_argument("--tests", nargs="+")
    parser.add_argument("--sim")
    parser.add_argument("--name", default="orchestrator")
    parser.add_argument("--package")
    parser.add_argument("--batch")
    options = parser.parse_args(argv)

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", options.name) or options.name in {".", ".."}:
        parser.error("--name must be a simple agent name")
    if options.batch:
        if any((options.file, options.sed is not None, options.replace is not None,
                options.patch, options.tests, options.package)):
            parser.error("--batch cannot be combined with single-mutation options")
        return options

    operations = [options.sed is not None, options.replace is not None, options.patch is not None]
    if not options.file or sum(operations) != 1 or not options.tests:
        parser.error("single mutation requires --file, exactly one edit option, and --tests")
    return options


def _mutation_from_object(value: Any, index: int, base: Path | None = None) -> Mutation:
    if not isinstance(value, dict):
        raise ValueError(f"batch entry {index} must be an object")
    identifier = value.get("id", f"mutant-{index}")
    file = value.get("file")
    tests = value.get("tests")
    if not isinstance(identifier, str) or not identifier or any(c in identifier for c in "\r\n"):
        raise ValueError(f"batch entry {index} has an invalid id")
    if not isinstance(file, str) or not file:
        raise ValueError(f"batch entry {index} requires a file")
    if isinstance(tests, str):
        tests = [tests]
    if not isinstance(tests, list) or not tests or not all(isinstance(item, str) and item for item in tests):
        raise ValueError(f"batch entry {index} requires a non-empty tests list")

    operations = [name for name in ("replace", "sed", "patch") if name in value]
    if len(operations) != 1:
        raise ValueError(f"batch entry {index} requires exactly one of replace, sed, or patch")
    operation = operations[0]
    edit = value[operation]
    if operation == "replace" and (
        not isinstance(edit, list) or len(edit) != 2 or not all(isinstance(part, str) for part in edit)
    ):
        raise ValueError(f"batch entry {index} replace must be [old, new]")
    if operation in {"sed", "patch"} and not isinstance(edit, str):
        raise ValueError(f"batch entry {index} {operation} must be a string")
    if operation == "replace" and not edit[0]:
        raise ValueError(f"batch entry {index} replace old value must not be empty")
    package = value.get("package")
    if package is not None and (not isinstance(package, str) or not package):
        raise ValueError(f"batch entry {index} package must be a path")
    if base is not None:
        file = str((base / file).resolve())
        if operation == "patch":
            edit = str((base / edit).resolve())
        if package is not None:
            package = str((base / package).resolve())
    return Mutation(identifier, file, operation, edit, tuple(tests), package)


def _load_mutations(options: argparse.Namespace) -> list[Mutation]:
    if not options.batch:
        operation = "sed" if options.sed is not None else "replace" if options.replace is not None else "patch"
        edit: Any = options.sed if operation == "sed" else options.replace if operation == "replace" else options.patch
        return [Mutation(Path(options.file).name, options.file, operation, edit, tuple(options.tests), options.package)]
    batch_path = Path(options.batch).expanduser().resolve()
    try:
        data = json.loads(batch_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read batch file {batch_path}: {exc}") from exc
    if not isinstance(data, list) or not data:
        raise ValueError("batch file must contain a non-empty JSON list")
    return [_mutation_from_object(item, index, Path.cwd()) for index, item in enumerate(data, 1)]


def _apply_mutation(mutation: Mutation, target: Path, original: bytes) -> bytes:
    if mutation.operation == "replace":
        old, new = mutation.value
        if not old:
            raise MutationNotApplied("replace OLD must not be empty")
        old_bytes = old.encode("utf-8")
        if old_bytes not in original:
            raise MutationNotApplied("replace OLD was not found")
        return original.replace(old_bytes, new.encode("utf-8"))

    if mutation.operation == "sed":
        try:
            result = subprocess.run(
                ["sed", "-e", mutation.value, str(target)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        except OSError as exc:
            raise MutationNotApplied(f"could not run sed: {exc}") from exc
        if result.returncode != 0:
            message = result.stderr.decode("utf-8", errors="replace").strip()
            raise MutationNotApplied(message or "sed could not apply the expression")
        return result.stdout

    if mutation.operation == "patch":
        return _apply_patch(mutation.value, target, original)
    raise MutationNotApplied(f"unknown operation {mutation.operation}")


def _patch_header_path(line: str) -> str:
    path = line[4:].rstrip("\r\n").split("\t", 1)[0]
    if path.startswith("a/") or path.startswith("b/"):
        path = path[2:]
    return path


def _apply_patch(patch_path: str, target: Path, original: bytes) -> bytes:
    try:
        patch_text = Path(patch_path).expanduser().read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise MutationNotApplied(f"cannot read patch: {exc}") from exc
    lines = patch_text.splitlines(keepends=True)
    header_indices = [index for index, line in enumerate(lines) if line.startswith("--- ")]
    if len(header_indices) != 1 or header_indices[0] + 1 >= len(lines) or not lines[header_indices[0] + 1].startswith("+++ "):
        raise MutationNotApplied("patch must contain one unified diff for one file")
    header = header_indices[0]
    old_name = _patch_header_path(lines[header])
    new_name = _patch_header_path(lines[header + 1])
    target_names = {target.name, str(target), str(target.resolve())}
    try:
        target_names.add(str(target.resolve().relative_to(Path.cwd().resolve())))
    except ValueError:
        pass
    if old_name != new_name or old_name not in target_names:
        raise MutationNotApplied("patch paths must both name the requested file")

    # Patch only a disposable copy under a sanitized basename, then return those bytes.
    safe_name = "mutation-target"
    rewritten = list(lines)
    newline = "\r\n" if lines[header].endswith("\r\n") else "\n"
    rewritten[header] = f"--- {safe_name}{newline}"
    rewritten[header + 1] = f"+++ {safe_name}{newline}"
    try:
        with tempfile.TemporaryDirectory(prefix="fmp-mutate-patch-") as directory:
            temp_dir = Path(directory)
            temp_target = temp_dir / safe_name
            temp_target.write_bytes(original)
            result = subprocess.run(
                ["patch", "-s", "-f", "-p0"],
                input="".join(rewritten).encode("utf-8"),
                cwd=temp_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout).decode("utf-8", errors="replace").strip()
                raise MutationNotApplied(detail or "patch did not apply")
            return temp_target.read_bytes()
    except OSError as exc:
        raise MutationNotApplied(f"could not run patch: {exc}") from exc


def _first_changed_line(original: bytes, changed: bytes) -> int:
    before = original.splitlines()
    after = changed.splitlines()
    for index, (left, right) in enumerate(zip(before, after), 1):
        if left != right:
            return index
    return min(len(before), len(after)) + 1


def _runner_command(mutation: Mutation, options: argparse.Namespace) -> list[list[str]]:
    selectors = list(mutation.tests)
    injected = os.environ.get("FMP_MUTATE_RUNNER")
    if injected:
        prefix = shlex.split(injected)
        if not prefix:
            raise RunnerUnavailable("FMP_MUTATE_RUNNER is empty")
        return [prefix + selectors]
    if mutation.package:
        package = str(Path(mutation.package).expanduser().resolve())
        return [["swift", "test", "--package-path", package, "--filter", selector]
                for selector in selectors]
    if ROOT is None:
        raise RuntimeError("repository root has not been resolved")
    test_runner = SCRIPT_FILE.with_name("test.sh")
    if not test_runner.is_file():
        raise RunnerUnavailable(f"test runner is missing: {test_runner}")
    command = [str(test_runner), "__with_kernel_lock"]
    if options.sim:
        command.extend(("--sim", options.sim))
    command.extend(("--name", options.name))
    return [command + selectors]


def _parse_test_counts(output: str) -> tuple[int, int] | None:
    """Parse one authoritative XCTest total plus any Swift Testing run total."""
    xctest_candidates: list[tuple[int, int, int]] = []
    for pattern_index, pattern in enumerate(SUMMARY_PATTERNS):
        for match in pattern.finditer(output):
            values = tuple(int(group) for group in match.groups())
            if pattern_index == 0:
                total, skipped, failed = values
                xctest_candidates.append((max(0, total - skipped), failed, match.start()))
            else:
                total, failed = values
                xctest_candidates.append((total, failed, match.start()))

    xctest = max(xctest_candidates, key=lambda item: (item[0], item[2]), default=None)
    swift_runs = list(re.finditer(
        r"(?m)^\s*[✔✘✓✗]?\s*Test run with\s+(\d+)\s+tests?\b[^\n]*(passed|failed)",
        output,
        re.I,
    ))
    swift_testing: tuple[int, int] | None = None
    if swift_runs:
        # A test process emits one final run summary; repeated nested summaries are
        # represented by its largest total, just like XCTest's suite summaries.
        summary = max(swift_runs, key=lambda item: (int(item.group(1)), item.start()))
        swift_count = int(summary.group(1))
        if swift_count > 0:
            failure_names = set()
            for line in output.splitlines():
                match = re.match(r"^\s*✘\s+Test\s+(?!run with)(.+)$", line)
                if match:
                    name = re.split(r"\s+(?:recorded an issue|failed)\b", match.group(1), maxsplit=1)[0]
                    failure_names.add(name)
            swift_failed = len(failure_names)
            if summary.group(2).lower() == "failed" and swift_failed == 0:
                swift_failed = 1
            swift_testing = (swift_failed, swift_count)

    counts: list[tuple[int, int]] = []
    if xctest is not None and xctest[0] > 0:
        counts.append((xctest[1], xctest[0]))
    if swift_testing is not None:
        counts.append(swift_testing)
    if not counts:
        return None
    return sum(item[0] for item in counts), sum(item[1] for item in counts)


def _invocation_result(returncode: int, output: str) -> TestResult:
    counts = _parse_test_counts(output)
    if COMPILER_DIAGNOSTIC.search(output) or TOOL_DIAGNOSTIC.search(output):
        return TestResult("BUILD-FAILED", 0 if counts is None else counts[0], 0 if counts is None else counts[1])
    if returncode < 0 or returncode not in (0, 1):
        return TestResult("BUILD-FAILED", 0 if counts is None else counts[0], 0 if counts is None else counts[1])
    if counts is None or counts[1] == 0:
        return TestResult("BUILD-FAILED", 0, 0)
    failed, run = counts
    if returncode == 1 and failed == 0:
        return TestResult("BUILD-FAILED", failed, run)
    if failed > 0:
        return TestResult("CAUGHT", failed, run)
    if returncode != 0:
        return TestResult("BUILD-FAILED", failed, run)
    return TestResult("SURVIVED", 0, run)


def _run_tests(mutation: Mutation, options: argparse.Namespace) -> TestResult:
    global _ACTIVE_CHILD_PID
    if _INTERRUPTED is not None:
        raise MutationInterrupted(_INTERRUPTED)
    commands = _runner_command(mutation, options)
    invocation_results: list[TestResult] = []
    for command in commands:
        child_env = os.environ.copy()
        child_env["FMP_MUTATE_FILE"] = mutation.file
        if not mutation.package and not os.environ.get("FMP_MUTATE_RUNNER"):
            # test.sh is a direct child while mutate.py holds the shared lock.
            child_env["FMP_WITH_LOCK_PARENT_PID"] = str(os.getpid())
        try:
            child = subprocess.Popen(
                command,
                cwd=Path.cwd(),
                env=child_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        except OSError as exc:
            raise RunnerUnavailable(f"cannot launch {command[0]}: {exc}") from exc
        _ACTIVE_CHILD_PID = child.pid
        if _INTERRUPTED is not None:
            try:
                os.killpg(child.pid, _INTERRUPTED)
            except ProcessLookupError:
                pass
        deadline: float | None = None
        output = b""
        try:
            while True:
                try:
                    output, _ = child.communicate(timeout=0.1)
                    break
                except subprocess.TimeoutExpired:
                    if _INTERRUPTED is not None:
                        if deadline is None:
                            deadline = time.monotonic() + 5
                        elif time.monotonic() >= deadline:
                            try:
                                os.killpg(child.pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass
                            deadline = float("inf")
        finally:
            _ACTIVE_CHILD_PID = None
        rendered = output.decode("utf-8", errors="replace")
        if _INTERRUPTED is not None:
            raise MutationInterrupted(_INTERRUPTED)
        if child.returncode in (126, 127) or "RUNNER_ERROR:" in rendered:
            detail = rendered.strip() or f"runner exited {child.returncode} before tests started"
            raise RunnerUnavailable(detail)
        if command[0] == str(SCRIPT_FILE.with_name("test.sh")) and child.returncode == 2:
            detail = rendered.strip() or "test.sh rejected the request"
            raise RunnerUnavailable(detail)
        invocation_results.append(_invocation_result(child.returncode, rendered))

    failed = sum(result.failed for result in invocation_results)
    run = sum(result.run for result in invocation_results)
    if any(result.status == "BUILD-FAILED" for result in invocation_results):
        return TestResult("BUILD-FAILED", failed, run)
    if failed > 0:
        return TestResult("CAUGHT", failed, run)
    return TestResult("SURVIVED", 0, run)


_INTERRUPTED: int | None = None


def _install_signal_handlers() -> None:
    def interrupt(signum: int, _frame: object) -> None:
        global _INTERRUPTED
        if _INTERRUPTED is None:
            _INTERRUPTED = signum
            # The test runner is in its own process group. Its wrapper forwards this
            # signal to compiler/test children and waits before returning.
            # The active child pid is stored by _run_tests while it waits.
            child_pid = _ACTIVE_CHILD_PID
            if child_pid is not None:
                try:
                    os.killpg(child_pid, signum)
                except ProcessLookupError:
                    pass

    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)


_ACTIVE_CHILD_PID: int | None = None


def _resolve_root() -> Path:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=Path.cwd(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except OSError as exc:
        raise ValueError(f"cannot run git rev-parse: {exc}") from exc
    if result.returncode != 0 or not result.stdout.strip():
        message = result.stderr.strip() or "current directory is not inside a git worktree"
        raise ValueError(f"cannot resolve repository root: {message}")
    return Path(result.stdout.strip()).resolve()


def _is_locked_by_parent() -> bool:
    return os.environ.get("FMP_WITH_LOCK_PARENT_PID") == str(os.getppid())


def _run_under_build_lock(arguments: list[str], root: Path) -> int:
    lock_tool = SCRIPT_FILE.with_name("with-lock.py")
    lock_file = root / "build/agents/build.lock"
    environment = os.environ.copy()
    environment["FMP_MUTATE_ROOT_ANNOUNCED"] = "1"
    command = [
        sys.executable,
        str(lock_tool),
        str(lock_file),
        "--",
        sys.executable,
        str(SCRIPT_FILE),
        *arguments,
    ]
    try:
        os.execvpe(command[0], command, environment)
    except OSError as exc:
        print(f"mutate: cannot acquire the build lock: {exc}", file=sys.stderr)
        return 2
    return 127


def _restore(target: Path, backup: Path, mode: int) -> bool:
    try:
        fd, restore_name = tempfile.mkstemp(prefix=f".{target.name}.restore-", dir=target.parent)
        os.close(fd)
        restore_path = Path(restore_name)
        try:
            shutil.copyfile(backup, restore_path)
            os.chmod(restore_path, mode)
            os.replace(restore_path, target)
        finally:
            restore_path.unlink(missing_ok=True)
        comparison = subprocess.run(["cmp", "-s", str(backup), str(target)], check=False)
        return comparison.returncode == 0
    except OSError:
        return False


def _run_one(mutation: Mutation, options: argparse.Namespace) -> tuple[str, int]:
    target = Path(mutation.file).expanduser().resolve()
    try:
        original = target.read_bytes()
        current_stat = target.stat()
    except OSError as exc:
        print(f"mutate: cannot read {target}: {exc}", file=sys.stderr)
        print(f"{mutation.identifier} BUILD-FAILED {mutation.file}:0 tests=0/0")
        return "BUILD-FAILED", 0
    backup_fd, backup_name = tempfile.mkstemp(prefix=f".{target.name}.mutate-", dir=target.parent)
    backup = Path(backup_name)
    try:
        with os.fdopen(backup_fd, "wb") as stream:
            stream.write(original)
        os.chmod(backup, stat.S_IMODE(current_stat.st_mode))
    except OSError as exc:
        backup.unlink(missing_ok=True)
        print(f"mutate: cannot back up {target}: {exc}", file=sys.stderr)
        print(f"{mutation.identifier} BUILD-FAILED {mutation.file}:0 tests=0/0")
        return "BUILD-FAILED", 0

    result_status = "BUILD-FAILED"
    failed = run = 0
    changed_line = 0
    interrupted: int | None = None
    runner_error: str | None = None
    restore_ok = True
    try:
        try:
            changed = _apply_mutation(mutation, target, original)
        except MutationNotApplied as exc:
            print(f"mutate: {mutation.identifier}: {exc}", file=sys.stderr)
            result_status = "NOT-APPLIED"
            changed = original
        if changed == original:
            result_status = "NOT-APPLIED"
        else:
            changed_line = _first_changed_line(original, changed)
            target.write_bytes(changed)
            os.chmod(target, stat.S_IMODE(current_stat.st_mode))
            try:
                result = _run_tests(mutation, options)
                result_status, failed, run = result.status, result.failed, result.run
            except RunnerUnavailable as exc:
                runner_error = str(exc)
            except MutationInterrupted as exc:
                interrupted = exc.signum
                result_status = "BUILD-FAILED"
            except (OSError, ValueError) as exc:
                print(f"mutate: {mutation.identifier}: test runner failed: {exc}", file=sys.stderr)
                result_status = "BUILD-FAILED"
    except BaseException as exc:
        # The restore in finally is required for exceptions and signals alike.
        if not isinstance(exc, (KeyboardInterrupt, SystemExit)):
            print(f"mutate: {mutation.identifier}: {exc}", file=sys.stderr)
        if isinstance(exc, MutationInterrupted):
            interrupted = exc.signum
    finally:
        restore_ok = _restore(target, backup, stat.S_IMODE(current_stat.st_mode))
        if restore_ok:
            try:
                backup.unlink(missing_ok=True)
            except OSError as exc:
                print(f"mutate: restored source but could not remove backup {backup}: {exc}", file=sys.stderr)

    if not restore_ok:
        print(
            f"RESTORE FAILED: could not verify byte-for-byte restoration of {target}; "
            f"backup retained at {backup}",
            file=sys.stderr,
        )
        print(f"{mutation.identifier} BUILD-FAILED {mutation.file}:{changed_line} tests={failed}/{run}")
        return "RESTORE-FAILED", 3
    if runner_error is not None:
        print(f"mutate: runner unavailable for {mutation.identifier}: {runner_error}", file=sys.stderr)
        return "RUNNER-ERROR", 2
    path_label = mutation.file
    print(f"{mutation.identifier} {result_status} {path_label}:{changed_line} tests={failed}/{run}")
    if interrupted is not None:
        return result_status, 128 + interrupted
    return result_status, 0


def main(argv: list[str] | None = None) -> int:
    global ROOT, _INTERRUPTED
    arguments = sys.argv[1:] if argv is None else argv
    try:
        ROOT = _resolve_root()
    except ValueError as exc:
        print(f"mutate: {exc}", file=sys.stderr)
        return 2
    if not os.environ.get("FMP_MUTATE_ROOT_ANNOUNCED"):
        print(f"Repository root: {ROOT}", flush=True)
    if not _is_locked_by_parent():
        return _run_under_build_lock(arguments, ROOT)

    options = _arguments(arguments)
    try:
        mutations = _load_mutations(options)
    except ValueError as exc:
        print(f"mutate: {exc}", file=sys.stderr)
        return 2
    _INTERRUPTED = None
    _install_signal_handlers()

    totals = {"CAUGHT": 0, "SURVIVED": 0, "NOT-APPLIED": 0, "BUILD-FAILED": 0}
    exit_code = 0
    for mutation in mutations:
        status, code = _run_one(mutation, options)
        if status == "RESTORE-FAILED":
            totals["BUILD-FAILED"] += 1
            print("TOTALS " + " ".join(f"{key.lower().replace('-', '_')}={value}" for key, value in totals.items()))
            return 3
        if status == "RUNNER-ERROR":
            print("TOTALS " + " ".join(f"{key.lower().replace('-', '_')}={value}" for key, value in totals.items()))
            return 2
        totals[status] += 1
        if code:
            exit_code = code
            break
        if status != "CAUGHT":
            exit_code = 1
    print("TOTALS " + " ".join(f"{key.lower().replace('-', '_')}={value}" for key, value in totals.items()))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
