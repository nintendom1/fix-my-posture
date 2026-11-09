"""Tests for compact XCTest summaries and orchestration test runners."""

from __future__ import annotations

import json
import os
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures" / "orchestrate"


FAKE_XCRUN = r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
record = os.environ.get("FAKE_XCRUN_CALLS")
if record:
    with Path(record).open("a") as stream:
        stream.write(json.dumps(args) + "\n")
if args[:2] == ["simctl", "list"]:
    simulator_file = os.environ.get("FAKE_SIMULATORS")
    print(Path(simulator_file).read_text() if simulator_file else '{"devices":{}}')
    sys.exit(0)
if args[:2] != ["xcresulttool", "get"]:
    sys.exit(2)
if os.environ.get("FAKE_XCRUN_UNREADABLE") == "1":
    error_file = os.environ["FAKE_XCRUN_UNREADABLE_JSON"]
    print(Path(error_file).read_text(), file=sys.stderr)
    sys.exit(1)
if "--legacy" in args:
    kind = "legacy"
elif len(args) > 3 and args[2] == "test-results":
    kind = args[3]
else:
    sys.exit(2)
if os.environ.get("FAKE_XCRUN_FAIL_MODERN") == "1" and kind != "legacy":
    print("unsupported Xcode 16 query", file=sys.stderr)
    sys.exit(1)
fixture = os.environ.get("FAKE_XCRUN_" + kind.upper())
if not fixture:
    sys.exit(2)
print(Path(fixture).read_text())
'''


FAKE_XCODEBUILD = r'''#!/usr/bin/env python3
import json
import os
import signal
import sys
import time
from pathlib import Path

args = sys.argv[1:]
Path(os.environ["FAKE_XCODEBUILD_ARGS"]).write_text(json.dumps(args))
if "-resultBundlePath" in args:
    bundle = Path(args[args.index("-resultBundlePath") + 1])
    bundle.mkdir(parents=True, exist_ok=True)
    (bundle / "Info.plist").write_text("fake result")
active = Path(os.environ["FAKE_XCODEBUILD_ACTIVE"]) if os.environ.get("FAKE_XCODEBUILD_ACTIVE") else None
owns_active = False
overlap = Path(os.environ["FAKE_XCODEBUILD_OVERLAP"]) if os.environ.get("FAKE_XCODEBUILD_OVERLAP") else None
if active:
    try:
        active.mkdir()
        owns_active = True
    except FileExistsError:
        if overlap:
            overlap.touch()

def terminate(signum, frame):
    marker = os.environ.get("FAKE_XCODEBUILD_TERM_MARKER")
    if marker:
        Path(marker).touch()
    time.sleep(0.3)
    raise SystemExit(143)

signal.signal(signal.SIGTERM, terminate)
try:
    if os.environ.get("FAKE_XCODEBUILD_HOLD") == "1":
        while True:
            time.sleep(0.1)
    time.sleep(float(os.environ.get("FAKE_XCODEBUILD_DELAY", "0.05")))
    print("fake xcodebuild completed")
    sys.exit(int(os.environ.get("FAKE_XCODEBUILD_EXIT", "0")))
finally:
    if owns_active:
        active.rmdir()
'''


class OrchestrateTestsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.repo.mkdir()
        (self.repo / "scripts" / "orchestrate").mkdir(parents=True)
        (self.repo / "scripts" / "tests").mkdir(parents=True)
        for name in ("test-summary.py", "validate-both.sh", "test.sh", "with-lock.py"):
            source = REPO_ROOT / "scripts" / "orchestrate" / name
            destination = self.repo / "scripts" / "orchestrate" / name
            shutil.copyfile(source, destination)
            destination.chmod(0o755)
        shutil.copyfile(
            REPO_ROOT / "scripts" / "agent-build.sh",
            self.repo / "scripts" / "agent-build.sh",
        )
        (self.repo / "scripts" / "agent-build.sh").chmod(0o755)
        self.xcrun_log = self.base / "xcrun.jsonl"
        self.xcode_args = self.base / "xcodebuild-args.json"
        for name, source in (("xcrun", FAKE_XCRUN), ("xcodebuild", FAKE_XCODEBUILD)):
            executable = self.bin / name
            executable.write_text(source, encoding="utf-8")
            executable.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + self.env.get("PATH", ""),
            "FAKE_XCRUN_CALLS": str(self.xcrun_log),
            "FAKE_XCODEBUILD_ARGS": str(self.xcode_args),
            "FAKE_XCODEBUILD_ACTIVE": str(self.base / "xcode-active"),
            "FAKE_XCODEBUILD_OVERLAP": str(self.base / "xcode-overlap"),
            "FAKE_XCRUN_SUMMARY": str(FIXTURES / "pass-summary.json"),
            "FAKE_XCRUN_TESTS": str(FIXTURES / "pass-tests.json"),
            "FAKE_XCRUN_LEGACY": str(FIXTURES / "legacy-summary.json"),
            "FAKE_XCRUN_UNREADABLE_JSON": str(FIXTURES / "unreadable.json"),
        })

    def tearDown(self) -> None:
        self.temp.cleanup()

    def make_bundle(self, name: str = "Run.xcresult") -> Path:
        bundle = self.base / name
        bundle.mkdir(parents=True)
        (bundle / "Info.plist").write_text("ready", encoding="utf-8")
        return bundle

    def run_script(self, script: str, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.repo / "scripts" / "orchestrate" / script), *args],
            cwd=self.repo,
            env=env or self.env,
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
        )

    def run_parallel(
        self, commands: list[list[str]], env: dict[str, str]
    ) -> list[subprocess.CompletedProcess[str]]:
        processes = [
            subprocess.Popen(
                command,
                cwd=self.repo, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            for command in commands
        ]
        results = []
        for process in processes:
            try:
                stdout, stderr = process.communicate(timeout=30)
            except subprocess.TimeoutExpired:
                for pending in processes:
                    if pending.poll() is None:
                        pending.kill()
                for pending in processes:
                    pending.communicate()
                self.fail("parallel lock contenders did not finish")
            results.append(subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr))
        return results

    def lock_command(self, lockfile: Path, *command: str) -> list[str]:
        return [
            sys.executable,
            str(self.repo / "scripts" / "orchestrate" / "with-lock.py"),
            str(lockfile), "--", *command,
        ]

    def assert_empty_lockfile(self, lockfile: Path) -> None:
        self.assertTrue(lockfile.is_file())
        self.assertEqual(lockfile.read_bytes(), b"")
        self.assertFalse((lockfile.parent / "pid").exists())
        self.assertFalse((lockfile.parent / "owner").exists())
        self.assertEqual(list(lockfile.parent.glob(f"{lockfile.name}.stale.*")), [])

    def test_summary_pass_and_skipped_counts(self) -> None:
        bundle = self.make_bundle()
        passed = self.run_script("test-summary.py", str(bundle))
        self.assertEqual(passed.returncode, 0, passed.stderr)
        self.assertEqual(passed.stdout.strip(), "PASS 4 tests, 0 skipped, 0 failed (1m 2s)")

        env = self.env.copy()
        env["FAKE_XCRUN_SUMMARY"] = str(FIXTURES / "skipped-summary.json")
        env["FAKE_XCRUN_TESTS"] = str(FIXTURES / "skipped-tests.json")
        skipped = self.run_script("test-summary.py", str(bundle), env=env)
        self.assertEqual(skipped.returncode, 0, skipped.stderr)
        self.assertEqual(skipped.stdout.strip(), "PASS 5 tests, 2 skipped, 0 failed (10s)")

    def test_summary_failure_includes_class_file_line_and_short_message(self) -> None:
        bundle = self.make_bundle()
        env = self.env.copy()
        env["FAKE_XCRUN_SUMMARY"] = str(FIXTURES / "failures-summary.json")
        env["FAKE_XCRUN_TESTS"] = str(FIXTURES / "failures-tests.json")
        result = self.run_script("test-summary.py", str(bundle), env=env)
        self.assertEqual(result.returncode, 1)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], "FAIL 2 tests, 0 skipped, 1 failed (7s)")
        self.assertEqual(
            lines[1],
            "WorkoutSessionTests/testRepCount WorkoutSessionTests.swift:47 XCTAssertEqual failed: count was 0",
        )

        summary = json.loads((FIXTURES / "failures-summary.json").read_text())
        summary["testFailures"][0]["failureText"] = "failure detail " * 30
        summary_file = self.base / "long-failure.json"
        summary_file.write_text(json.dumps(summary), encoding="utf-8")
        env["FAKE_XCRUN_SUMMARY"] = str(summary_file)
        env["FAKE_XCRUN_TESTS"] = str(FIXTURES / "skipped-tests.json")
        long_message = self.run_script("test-summary.py", str(bundle), env=env)
        self.assertEqual(long_message.returncode, 1)
        failure_line = long_message.stdout.splitlines()[1]
        self.assertLessEqual(len(failure_line.split(" ", 2)[2]), 160)

    def test_summary_caps_failure_lines_at_thirty(self) -> None:
        bundle = self.make_bundle()
        summary = json.loads((FIXTURES / "failures-summary.json").read_text())
        summary["totalTestCount"] = 35
        summary["failedTests"] = 35
        summary["testFailures"] = [
            {
                "testName": f"testFailure{index}()",
                "targetName": "PostureAnalysisAppTests",
                "failureText": f"failure {index}",
                "testIdentifierString": f"PostureAnalysisAppTests/SampleTests/testFailure{index}()",
            }
            for index in range(35)
        ]
        summary_file = self.base / "many-failures.json"
        summary_file.write_text(json.dumps(summary), encoding="utf-8")
        env = self.env.copy()
        env["FAKE_XCRUN_SUMMARY"] = str(summary_file)
        result = self.run_script("test-summary.py", str(bundle), env=env)
        self.assertEqual(result.returncode, 1)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 30)
        self.assertEqual(lines[-1], "… 7 more")

    def test_summary_falls_back_to_legacy_json(self) -> None:
        bundle = self.make_bundle()
        env = self.env.copy()
        env["FAKE_XCRUN_FAIL_MODERN"] = "1"
        result = self.run_script("test-summary.py", str(bundle), env=env)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines()[0], "FAIL 3 tests, 0 skipped, 1 failed (6s)")
        self.assertIn("WorkoutSessionTests/testLegacyFailure WorkoutSessionTests.swift:71 XCTAssertTrue failed", result.stdout)

    def test_summary_rejects_successful_malformed_json_without_test_counts(self) -> None:
        bundle = self.make_bundle()
        env = self.env.copy()
        env["FAKE_XCRUN_SUMMARY"] = str(FIXTURES / "unreadable.json")
        env["FAKE_XCRUN_LEGACY"] = str(FIXTURES / "unreadable.json")
        result = self.run_script("test-summary.py", str(bundle), env=env)
        self.assertEqual(result.returncode, 2)
        self.assertIn("no usable test counts", result.stderr)

    def test_summary_rejects_explicit_incomplete_bundle(self) -> None:
        bundle = self.base / "Partial.xcresult"
        bundle.mkdir()
        result = self.run_script("test-summary.py", str(bundle))
        self.assertEqual(result.returncode, 2)
        self.assertIn("incomplete or missing result bundle", result.stderr)

    def test_summary_unreadable_result_exits_two(self) -> None:
        bundle = self.make_bundle()
        env = self.env.copy()
        env["FAKE_XCRUN_UNREADABLE"] = "1"
        result = self.run_script("test-summary.py", str(bundle), env=env)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Error: cannot read result bundle", result.stderr)

    def test_summary_uses_newest_bundle_under_derived_data(self) -> None:
        derived_data = self.base / "DerivedData"
        result_dir = derived_data / "Logs" / "Test"
        result_dir.mkdir(parents=True)
        older = result_dir / "old.xcresult"
        newer = result_dir / "new.xcresult"
        older.mkdir()
        newer.mkdir()
        (older / "Info.plist").write_text("ready", encoding="utf-8")
        os.utime(older, (1000, 1000))
        os.utime(newer, (2000, 2000))
        result = self.run_script("test-summary.py", str(derived_data))
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.xcrun_log.read_text().splitlines()]
        self.assertTrue(all(call[call.index("--path") + 1] == str(older) for call in calls))

    def test_summary_errors_when_derived_data_has_no_completed_bundle(self) -> None:
        derived_data = self.base / "DerivedData"
        result_dir = derived_data / "Logs" / "Test"
        result_dir.mkdir(parents=True)
        (result_dir / "partial.xcresult").mkdir()
        result = self.run_script("test-summary.py", str(derived_data))
        self.assertEqual(result.returncode, 2)
        self.assertIn("no completed xcresult bundle", result.stderr)

    def test_test_runner_builds_only_testing_arguments(self) -> None:
        lockfile = self.repo / "build" / "agents" / "build.lock"
        result = self.run_script(
            "test.sh", "--sim", "12345678-1234-1234-1234-123456789abc", "--name", "movement",
            "WorkoutSessionTests/testRepCount", "RoutineTests",
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        args = json.loads(self.xcode_args.read_text())
        self.assertEqual(args[args.index("-destination") + 1], "platform=iOS Simulator,id=12345678-1234-1234-1234-123456789abc")
        self.assertEqual(args[args.index("-derivedDataPath") + 1], "build/agents/movement")
        self.assertIn("-parallel-testing-enabled", args)
        self.assertIn("NO", args)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", args)
        self.assertEqual(
            [arg for arg in args if arg.startswith("-only-testing:")],
            [
                "-only-testing:PostureAnalysisAppTests/WorkoutSessionTests/testRepCount",
                "-only-testing:PostureAnalysisAppTests/RoutineTests",
            ],
        )
        bundle = Path(args[args.index("-resultBundlePath") + 1])
        self.assertTrue(bundle.as_posix().startswith("build/agents/movement/results/"))
        self.assertTrue(bundle.name.endswith(".xcresult"))
        self.assert_empty_lockfile(lockfile)
        self.assertIn("PASS 4 tests", result.stdout)

    def test_test_runner_uses_validate_default_simulator(self) -> None:
        simulator_file = self.base / "simulators.json"
        simulator_file.write_text(json.dumps({
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                    {"name": "iPhone 16", "udid": "id-new", "isAvailable": True},
                    {"name": "iPhone 15 Pro", "udid": "id-pro", "isAvailable": True},
                ],
            },
        }), encoding="utf-8")
        env = self.env.copy()
        env["FAKE_SIMULATORS"] = str(simulator_file)
        result = self.run_script("test.sh", "SampleTests", env=env)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        args = json.loads(self.xcode_args.read_text())
        self.assertEqual(args[args.index("-destination") + 1], "platform=iOS Simulator,id=id-pro")

    def _prepare_validate_repo(self, *, fail: bool = False) -> Path:
        validate_script = self.repo / "scripts" / "validate.sh"
        if fail:
            validate_script.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"${VALIDATE_CREATE_BUNDLE:-0}\" == 1 ]]; then\n"
                "  mkdir -p build/validation/Logs/Test/failed.xcresult\n"
                "  echo ready > build/validation/Logs/Test/failed.xcresult/Info.plist\n"
                "fi\n"
                "echo 'Starting Python tests'\n"
                "echo 'Error: Python helper tests failed.'\n"
                "echo 'FAIL: test_first'\n"
                "for n in {1..20}; do echo \"AssertionError: failure $n\"; done\n"
                "exit 1\n",
                encoding="utf-8",
            )
        else:
            validate_script.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ -n \"${VALIDATE_ACTIVE:-}\" ]]; then\n"
                "  if ! mkdir \"$VALIDATE_ACTIVE\" 2>/dev/null; then touch \"$VALIDATE_OVERLAP\"; exit 98; fi\n"
                "  sleep 0.2\n"
                "  rmdir \"$VALIDATE_ACTIVE\"\n"
                "fi\n"
                "python3 - \"$VALIDATE_CAPTURE\" <<'PY'\n"
                "import os, sys, time\n"
                "runner_tz = os.environ.get('TEST_RUNNER_TZ')\n"
                "if runner_tz is not None:\n"
                "    os.environ['TZ'] = runner_tz\n"
                "time.tzset()\n"
                "with open(sys.argv[1], 'a') as stream:\n"
                "    stream.write(f\"{os.environ.get('SIMULATOR_DESTINATION', '')}|{runner_tz if runner_tz is not None else '<unset>'}|{','.join(time.tzname)}\\n\")\n"
                "PY\n"
                "mkdir -p build/validation/Logs/Test\n"
                "result_bundle=\"build/validation/Logs/Test/fake-${TEST_RUNNER_TZ:-local}-$$.xcresult\"\n"
                "mkdir -p \"$result_bundle\"\n"
                "echo ready > \"$result_bundle/Info.plist\"\n"
                "echo 'new result' > \"$result_bundle/run.txt\"\n"
                "echo 'fake XCTest completed'\n",
                encoding="utf-8",
            )
        validate_script.chmod(0o755)
        return validate_script

    def test_validate_both_builds_sim_destinations(self) -> None:
        self._prepare_validate_repo()
        lockfile = self.repo / "build" / "orchestrate" / "validate.lock"
        capture = self.base / "validate-env.txt"
        env = self.env.copy()
        env["VALIDATE_CAPTURE"] = str(capture)
        env["TEST_RUNNER_TZ"] = "UTC"
        env["TZ"] = "America/Los_Angeles"

        simulator_id = "12345678-1234-1234-1234-123456789abc"
        by_id = self.run_script("validate-both.sh", "--sim", simulator_id, "--only", "local", env=env)
        self.assertEqual(by_id.returncode, 0, by_id.stderr + by_id.stdout)
        self.assertIn("local: PASS 4 tests", by_id.stdout)
        self.assert_empty_lockfile(lockfile)
        self.assertEqual(
            capture.read_text().splitlines()[-1],
            f"platform=iOS Simulator,id={simulator_id}|<unset>|PST,PDT",
        )

        by_name = self.run_script("validate-both.sh", "--sim", "iPhone 15 Pro", "--only", "utc", env=env)
        self.assertEqual(by_name.returncode, 0, by_name.stderr + by_name.stdout)
        self.assertIn("utc: PASS 4 tests", by_name.stdout)
        self.assertEqual(
            capture.read_text().splitlines()[-1],
            "platform=iOS Simulator,name=iPhone 15 Pro|UTC|UTC,UTC",
        )

    def test_validate_both_runs_local_then_utc_by_default(self) -> None:
        self._prepare_validate_repo()
        capture = self.base / "validate-env.txt"
        env = self.env.copy()
        env["VALIDATE_CAPTURE"] = str(capture)
        env["TZ"] = "America/Los_Angeles"
        env["TEST_RUNNER_TZ"] = "UTC"
        result = self.run_script("validate-both.sh", env=env)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(capture.read_text().splitlines(), ["|<unset>|PST,PDT", "|UTC|UTC,UTC"])
        self.assertLess(result.stdout.index("local:"), result.stdout.index("utc:"))

    def test_validate_both_reports_pre_xctest_failure_and_last_relevant_lines(self) -> None:
        self._prepare_validate_repo(fail=True)
        result = self.run_script("validate-both.sh", "--only", "local")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local: Error: Python helper tests failed.", result.stdout)
        assertion_lines = [line for line in result.stdout.splitlines() if line.startswith("AssertionError:")]
        self.assertEqual(len(assertion_lines), 15)
        self.assertIn("AssertionError: failure 6", result.stdout)
        self.assertIn("AssertionError: failure 20", result.stdout)
        self.assertNotIn("AssertionError: failure 1\n", result.stdout)

    def test_validate_both_uses_pre_xctest_diagnostics_even_with_bundle(self) -> None:
        self._prepare_validate_repo(fail=True)
        env = self.env.copy()
        env["VALIDATE_CREATE_BUNDLE"] = "1"
        result = self.run_script("validate-both.sh", "--only", "local", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local: Error: Python helper tests failed.", result.stdout)
        self.assertIn("AssertionError: failure 20", result.stdout)
        self.assertFalse(self.xcrun_log.exists(), "pre-XCTest errors must bypass result summarization")

    def test_with_lock_serializes_two_contenders(self) -> None:
        lockfile = self.repo / "build" / "shared.lock"
        active = self.base / "lock-active"
        overlap = self.base / "lock-overlap"
        child = self.base / "serialized-child.py"
        child.write_text(
            "import pathlib, sys, time\n"
            "active, overlap = map(pathlib.Path, sys.argv[1:])\n"
            "try:\n"
            "    active.mkdir()\n"
            "    owner = True\n"
            "except FileExistsError:\n"
            "    overlap.touch()\n"
            "    owner = False\n"
            "time.sleep(0.25)\n"
            "if owner:\n"
            "    active.rmdir()\n",
            encoding="utf-8",
        )
        command = [sys.executable, str(child), str(active), str(overlap)]
        results = self.run_parallel(
            [self.lock_command(lockfile, *command), self.lock_command(lockfile, *command)],
            self.env,
        )
        self.assertEqual([result.returncode for result in results], [0, 0], results)
        self.assertFalse(overlap.exists())
        self.assert_empty_lockfile(lockfile)

    def test_with_lock_returns_child_exit_status(self) -> None:
        lockfile = self.repo / "build" / "status.lock"
        result = self.run_script(
            "with-lock.py", str(lockfile), "--", sys.executable, "-c",
            "import sys; sys.exit(23)",
        )
        self.assertEqual(result.returncode, 23)
        self.assert_empty_lockfile(lockfile)

    def test_with_lock_timeout_and_killed_holder_release(self) -> None:
        lockfile = self.repo / "build" / "held.lock"
        child = self.base / "holding-child.py"
        child_pid_path = self.base / "holding-child.pid"
        child.write_text(
            "import pathlib, sys, time\n"
            "pathlib.Path(sys.argv[1]).write_text(str(__import__('os').getpid()))\n"
            "while True: time.sleep(0.1)\n",
            encoding="utf-8",
        )
        holder = subprocess.Popen(
            self.lock_command(lockfile, sys.executable, str(child), str(child_pid_path)),
            cwd=self.repo, env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 5
        while not child_pid_path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(child_pid_path.exists(), "lock holder child did not start")

        timed_out = self.run_script(
            "with-lock.py", "--timeout", "0.1", str(lockfile), "--",
            sys.executable, "-c", "pass",
        )
        self.assertEqual(timed_out.returncode, 75, timed_out.stderr)

        child_pid = int(child_pid_path.read_text())
        holder.kill()
        holder.wait(timeout=5)
        acquired = self.run_script(
            "with-lock.py", "--timeout", "1", str(lockfile), "--",
            sys.executable, "-c", "pass",
        )
        self.assertEqual(acquired.returncode, 0, acquired.stderr)
        self.assert_empty_lockfile(lockfile)
        try:
            os.killpg(child_pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    def test_with_lock_forwards_signal_to_group_and_waits_for_descendants(self) -> None:
        child = self.base / "signal-tree.py"
        child.write_text(
            "import pathlib, signal, subprocess, sys, time\n"
            "mode, term, ready, ended = sys.argv[1:]\n"
            "if mode == 'descendant':\n"
            "    signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
            "    signal.signal(signal.SIGINT, signal.SIG_IGN)\n"
            "    pathlib.Path(ready).touch()\n"
            "    time.sleep(0.8)\n"
            "    pathlib.Path(ended).touch()\n"
            "    raise SystemExit(0)\n"
            "subprocess.Popen([sys.executable, __file__, 'descendant', term, ready, ended])\n"
            "def stop(signum, frame):\n"
            "    pathlib.Path(term).touch()\n"
            "    raise SystemExit(0)\n"
            "signal.signal(signal.SIGTERM, stop)\n"
            "signal.signal(signal.SIGINT, stop)\n"
            "while not pathlib.Path(ready).exists(): time.sleep(0.01)\n"
            "while True: time.sleep(0.1)\n",
            encoding="utf-8",
        )
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum):
                suffix = "int" if signum == signal.SIGINT else "term"
                lockfile = self.repo / "build" / f"signals-{suffix}.lock"
                term_marker = self.base / f"child-{suffix}"
                descendant_ready = self.base / f"descendant-{suffix}-ready"
                descendant_ended = self.base / f"descendant-{suffix}-ended"
                process = subprocess.Popen(
                    self.lock_command(
                        lockfile, sys.executable, str(child), "parent", str(term_marker),
                        str(descendant_ready), str(descendant_ended),
                    ),
                    cwd=self.repo, env=self.env, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                )
                deadline = time.monotonic() + 5
                while not descendant_ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(descendant_ready.exists(), "descendant process did not start")
                process.send_signal(signum)
                deadline = time.monotonic() + 5
                while not term_marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(term_marker.exists(), f"signal {signum} did not reach the command")
                self.assertIsNone(process.poll(), "lock holder exited while a process-group child remained")
                self.assertTrue(lockfile.exists())
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 0, stdout + stderr)
                self.assertTrue(descendant_ended.exists())
                self.assert_empty_lockfile(lockfile)

    def test_validate_lock_serializes_complete_local_utc_pairs(self) -> None:
        self._prepare_validate_repo()
        lockfile = self.repo / "build" / "orchestrate" / "validate.lock"
        env = self.env.copy()
        env.update({
            "VALIDATE_CAPTURE": str(self.base / "validate-env.txt"),
            "VALIDATE_ACTIVE": str(self.base / "validate-active"),
            "VALIDATE_OVERLAP": str(self.base / "validate-overlap"),
        })
        command = [str(self.repo / "scripts" / "orchestrate" / "validate-both.sh")]
        results = self.run_parallel([command, command], env)
        self.assertEqual([result.returncode for result in results], [0, 0], results)
        self.assertFalse(Path(env["VALIDATE_OVERLAP"]).exists())
        self.assertEqual(
            [row.split("|")[1] for row in Path(env["VALIDATE_CAPTURE"]).read_text().splitlines()],
            ["<unset>", "UTC", "<unset>", "UTC"],
        )
        self.assert_empty_lockfile(lockfile)

    def test_test_runner_and_agent_build_share_kernel_lock(self) -> None:
        lockfile = self.repo / "build" / "agents" / "build.lock"
        env = self.env.copy()
        env["FAKE_XCODEBUILD_DELAY"] = "0.25"
        test_command = [
            str(self.repo / "scripts" / "orchestrate" / "test.sh"),
            "--sim", "12345678-1234-1234-1234-123456789abc", "--name", "racer", "SampleTests",
        ]
        build_command = [str(self.repo / "scripts" / "agent-build.sh"), "builder"]
        results = self.run_parallel([test_command, build_command], env)
        self.assertEqual([result.returncode for result in results], [0, 0], results)
        self.assertFalse(Path(env["FAKE_XCODEBUILD_OVERLAP"]).exists())
        build_result = results[1]
        self.assertIn("BUILD SUCCEEDED (build). Log: build/agents/builder.log", build_result.stdout)
        self.assert_empty_lockfile(lockfile)


if __name__ == "__main__":
    unittest.main()
