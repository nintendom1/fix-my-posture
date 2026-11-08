#!/usr/bin/env python3
"""Run a command while holding a kernel-managed advisory file lock."""

from __future__ import annotations

import argparse
import fcntl
import math
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


LOCK_TIMEOUT_EXIT = 75


class LockInterrupted(Exception):
    """Lock acquisition was interrupted by a termination signal."""

    def __init__(self, signum: int) -> None:
        self.signum = signum


def _arguments(argv: list[str]) -> tuple[Path, list[str], float | None]:
    try:
        separator = argv.index("--")
    except ValueError as exc:
        raise ValueError("expected LOCKFILE -- COMMAND [ARG ...]") from exc

    parser = argparse.ArgumentParser(
        description="Run a command while holding an advisory file lock."
    )
    parser.add_argument("--timeout", type=float, help="maximum seconds to wait for the lock")
    parser.add_argument("lockfile")
    options = parser.parse_args(argv[:separator])
    command = argv[separator + 1:]
    if not command:
        raise ValueError("a command is required after --")
    if options.timeout is not None and (
        not math.isfinite(options.timeout) or options.timeout <= 0
    ):
        raise ValueError("--timeout must be finite and greater than zero")
    return Path(options.lockfile).expanduser(), command, options.timeout


def _acquire(fd: int, timeout: float | None) -> bool:
    if timeout is None:
        fcntl.flock(fd, fcntl.LOCK_EX)
        return True

    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except BlockingIOError:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            time.sleep(min(0.05, remaining))


def _wait_for_group(pgid: int) -> None:
    while True:
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return
        except PermissionError:
            return
        time.sleep(0.05)


def _run(command: list[str]) -> int:
    child: subprocess.Popen[bytes] | None = None

    def forward_signal(signum: int, _frame: object) -> None:
        if child is None:
            raise LockInterrupted(signum)
        try:
            os.killpg(child.pid, signum)
        except ProcessLookupError:
            pass

    signal.signal(signal.SIGINT, forward_signal)
    signal.signal(signal.SIGTERM, forward_signal)
    try:
        child_environment = os.environ.copy()
        child_environment["FMP_WITH_LOCK_PARENT_PID"] = str(os.getpid())
        child = subprocess.Popen(command, start_new_session=True, env=child_environment)
    except LockInterrupted as exc:
        return 128 + exc.signum
    except OSError as exc:
        print(f"with-lock.py: cannot run {command[0]}: {exc}", file=sys.stderr)
        return 127

    return_code = child.wait()
    _wait_for_group(child.pid)
    return return_code if return_code >= 0 else 128 - return_code


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    try:
        lockfile, command, timeout = _arguments(arguments)
    except (ValueError, SystemExit) as exc:
        if isinstance(exc, SystemExit):
            return int(exc.code)
        print(f"with-lock.py: {exc}", file=sys.stderr)
        return 2

    try:
        lockfile.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(lockfile, os.O_CREAT | os.O_RDWR, 0o666)
    except OSError as exc:
        print(f"with-lock.py: cannot open lock file {lockfile}: {exc}", file=sys.stderr)
        return 2

    try:
        try:
            acquired = _acquire(fd, timeout)
        except LockInterrupted as exc:
            return 128 + exc.signum
        if not acquired:
            print(f"with-lock.py: timed out waiting for {lockfile}", file=sys.stderr)
            return LOCK_TIMEOUT_EXIT
        return _run(command)
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


if __name__ == "__main__":
    raise SystemExit(main())
