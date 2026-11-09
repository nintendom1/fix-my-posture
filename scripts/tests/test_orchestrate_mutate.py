from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MUTATE = REPO_ROOT / "scripts/orchestrate/mutate.py"
MUTATE_SH = REPO_ROOT / "scripts/orchestrate/mutate.sh"
TEST_SH = REPO_ROOT / "scripts/orchestrate/test.sh"
VALIDATE_BOTH = REPO_ROOT / "scripts/orchestrate/validate-both.sh"
WITH_LOCK = REPO_ROOT / "scripts/orchestrate/with-lock.py"
ORCHESTRATION_FIXTURES = REPO_ROOT / "scripts/tests/fixtures/orchestrate"


RUNNER_SOURCE = '''\
import json
import os
import signal
import sys
import time
from pathlib import Path

args = sys.argv[1:]
mode = os.environ.get("FMP_FAKE_MODE", "caught")
selector = args[0] if args else ""
source_path = Path(os.environ["FMP_MUTATE_FILE"])
source = source_path.read_text(encoding="utf-8")
marker = Path(os.environ["FMP_RUNNER_MARKER"])
with marker.open("a", encoding="utf-8") as stream:
    stream.write(json.dumps({"args": args, "source": source}) + "\\n")

expected = os.environ.get("FMP_EXPECTED_MUTANT", "threshold = 11")
delay = 0
if selector.startswith("Catch/"):
    expected = "threshold = 11"
elif selector.startswith("Survive/"):
    expected = "threshold = 21"
    mode = "survived"
elif selector.startswith("First/"):
    expected = "threshold = 11"
    Path(os.environ["FMP_FIRST_STARTED"]).write_text("started")
    delay = 0.25
elif selector.startswith("Second/"):
    expected = "enabled = false"
    delay = 0.5
mutant_present = expected in source

if mode == "killed" and not mutant_present:
    print("PASS 3 tests, 0 skipped, 0 failed (0.1s)")
elif mode == "killed":
    Path(os.environ["FMP_STARTED"]).write_text("started")
    def stop(_signum, _frame):
        Path(os.environ["FMP_ENDED"]).write_text("ended")
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    while True:
        time.sleep(0.05)
elif mode == "build":
    print("error: compile error")
    raise SystemExit(1)
elif mode == "prefixed-build":
    if mutant_present:
        print("FAIL 3 tests, 0 skipped, 1 failed (0.1s)")
    print("/tmp/Example.swift:1:1: error: cannot compile mutant")
    raise SystemExit(1)
elif mode == "kill-after-fail":
    if not mutant_present:
        print("PASS 3 tests, 0 skipped, 0 failed (0.1s)")
        raise SystemExit(0)
    print("FAIL 3 tests, 0 skipped, 1 failed (0.1s)", flush=True)
    os.kill(os.getpid(), signal.SIGKILL)
elif mode == "timeout-after-fail":
    if not mutant_present:
        print("PASS 3 tests, 0 skipped, 0 failed (0.1s)")
        raise SystemExit(0)
    print("FAIL 3 tests, 0 skipped, 1 failed (0.1s)", flush=True)
    raise SystemExit(124)
elif mode == "nested-xctest":
    if mutant_present:
        print("Test Suite 'ExampleTests' failed at 2026-11-08")
        print("Executed 3 tests, with 1 failure (0 unexpected) in 0.1 seconds")
        print("Test Suite 'Selected tests' failed at 2026-11-08")
        print("Executed 3 tests, with 1 failure (0 unexpected) in 0.1 seconds")
        print("Test Suite 'All tests' failed at 2026-11-08")
        print("Executed 3 tests, with 1 failure (0 unexpected) in 0.1 seconds")
        raise SystemExit(1)
    print("Executed 3 tests, with 0 failures (0 unexpected) in 0.1 seconds")
elif mode == "swift-testing-failed":
    print("Executed 0 tests, with 0 failures (0 unexpected) in 0.0 seconds")
    if mutant_present:
        print("◇ Test thresholdIsEnforced() started.")
        print("✘ Test thresholdIsEnforced() recorded an issue at ExampleTests.swift:10:5")
        print("✘ Test run with 1 test in 1 suite failed after 0.1 seconds.")
        raise SystemExit(1)
    print("✔ Test run with 1 test in 1 suite passed after 0.1 seconds.")
elif mode == "swift-testing-passed":
    print("Executed 0 tests, with 0 failures (0 unexpected) in 0.0 seconds")
    print("✔ Test run with 2 tests in 1 suite passed after 0.1 seconds.")
elif mode == "mixed-frameworks":
    if mutant_present:
        print("Executed 2 tests, with 1 failure (0 unexpected) in 0.1 seconds")
    else:
        print("Executed 2 tests, with 0 failures (0 unexpected) in 0.1 seconds")
    print("✔ Test run with 1 test in 1 suite passed after 0.1 seconds.")
    if mutant_present:
        raise SystemExit(1)
elif not mutant_present or mode == "survived":
    print("PASS 3 tests, 0 skipped, 0 failed (0.1s)")
else:
    if delay:
        time.sleep(delay)
    print("FAIL 3 tests, 0 skipped, 1 failed (0.1s)")
    raise SystemExit(1)
'''


class MutateToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="fmp-mutate-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "Example.swift"
        self.original = b"let threshold = 10\nlet enabled = true\n"
        self.source.write_bytes(self.original)
        self.runner = self.root / "fake_runner.py"
        self.runner.write_text(RUNNER_SOURCE, encoding="utf-8")
        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        fake_git = self.fake_bin / "git"
        fake_git.write_text(
            f"#!{sys.executable}\n"
            "import os, sys\n"
            "if sys.argv[1:] == ['rev-parse', '--show-toplevel']:\n"
            "    print(os.environ['FMP_TEST_ROOT'])\n"
            "else:\n"
            "    raise SystemExit(2)\n",
            encoding="utf-8",
        )
        fake_git.chmod(0o755)
        fake_xcodebuild = self.fake_bin / "xcodebuild"
        fake_xcodebuild.write_text(
            f"#!{sys.executable}\n"
            "import os, sys\n"
            "from pathlib import Path\n"
            "args = sys.argv[1:]\n"
            "if '-resultBundlePath' in args:\n"
            "    bundle = Path(args[args.index('-resultBundlePath') + 1])\n"
            "    bundle.mkdir(parents=True, exist_ok=True)\n"
            "    (bundle / 'Info.plist').write_text('fixture')\n"
            "status = int(os.environ.get('FMP_XCODEBUILD_EXIT', '0'))\n"
            "source_path = os.environ.get('FMP_MUTATE_FILE')\n"
            "if source_path and 'threshold = 11' in Path(source_path).read_text():\n"
            "    status = 1\n"
            "raise SystemExit(status)\n",
            encoding="utf-8",
        )
        fake_xcodebuild.chmod(0o755)
        fake_xcrun = self.fake_bin / "xcrun"
        fake_xcrun.write_text(
            f"#!{sys.executable}\n"
            "import os, sys\n"
            "from pathlib import Path\n"
            "kind = 'summary' if 'summary' in sys.argv else 'tests'\n"
            "result = os.environ.get('FMP_TEST_RESULT', 'pass')\n"
            "print(Path(os.environ[f'FMP_{result.upper()}_{kind.upper()}']).read_text())\n",
            encoding="utf-8",
        )
        fake_xcrun.chmod(0o755)
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.fake_bin}{os.pathsep}{self.env.get('PATH', '')}"
        self.env["FMP_TEST_ROOT"] = str(self.root.resolve())
        self.env["FMP_MUTATE_RUNNER"] = f"{sys.executable} {self.runner}"
        self.env["FMP_RUNNER_MARKER"] = str(self.root / "runner-invocations.jsonl")
        self.env["FMP_EXPECTED_MUTANT"] = "threshold = 11"
        self.env["FMP_PASS_SUMMARY"] = str(ORCHESTRATION_FIXTURES / "pass-summary.json")
        self.env["FMP_PASS_TESTS"] = str(ORCHESTRATION_FIXTURES / "pass-tests.json")
        self.env["FMP_FAIL_SUMMARY"] = str(ORCHESTRATION_FIXTURES / "failures-summary.json")
        self.env["FMP_FAIL_TESTS"] = str(ORCHESTRATION_FIXTURES / "failures-tests.json")

    def run_mutate(
        self,
        *arguments: str,
        env: dict[str, str] | None = None,
        timeout: float = 20,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(MUTATE), *arguments],
            cwd=self.root,
            env=self.env if env is None else env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=timeout,
        )

    def single(self, *edit: str) -> list[str]:
        return [
            "--file", str(self.source), *edit,
            "--tests", "Example/testThreshold",
        ]

    def test_failed_assertion_catches_mutant_and_restores_original(self) -> None:
        result = self.run_mutate(*self.single("--replace", "10", "11"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Example.swift CAUGHT", result.stdout)
        self.assertIn("Example.swift:1 tests=1/3", result.stdout)
        self.assertIn("TOTALS caught=1", result.stdout)
        records = [json.loads(line) for line in Path(self.env["FMP_RUNNER_MARKER"]).read_text().splitlines()]
        self.assertIn("threshold = 11", records[0]["source"])
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_passing_tests_mean_mutant_survived(self) -> None:
        env = self.env | {"FMP_FAKE_MODE": "survived"}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Example.swift SURVIVED", result.stdout)
        self.assertIn("tests=0/3", result.stdout)
        records = [json.loads(line) for line in Path(self.env["FMP_RUNNER_MARKER"]).read_text().splitlines()]
        self.assertIn("threshold = 11", records[0]["source"])
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_missing_replace_text_is_not_applied_and_does_not_run_tests(self) -> None:
        marker = Path(self.env["FMP_RUNNER_MARKER"])
        result = self.run_mutate(*self.single("--replace", "absent", "changed"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("NOT-APPLIED", result.stdout)
        self.assertIn("tests=0/0", result.stdout)
        self.assertFalse(marker.exists())
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_compile_failure_without_test_data_is_build_failed(self) -> None:
        env = self.env | {"FMP_FAKE_MODE": "build"}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("BUILD-FAILED", result.stdout)
        self.assertIn("tests=0/0", result.stdout)
        self.assertNotIn("CAUGHT", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_missing_runner_exits_two_without_build_failed_status(self) -> None:
        missing = self.root / "no-such-test-runner"
        env = self.env | {"FMP_MUTATE_RUNNER": str(missing)}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 2)
        self.assertIn("runner unavailable", result.stderr)
        self.assertNotIn("BUILD-FAILED", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_sigterm_waits_for_runner_then_restores_original(self) -> None:
        started = self.root / "runner-started"
        ended = self.root / "runner-ended"
        env = self.env | {
            "FMP_FAKE_MODE": "killed",
            "FMP_STARTED": str(started),
            "FMP_ENDED": str(ended),
        }
        process = subprocess.Popen(
            [sys.executable, str(MUTATE), *self.single("--replace", "10", "11")],
            cwd=self.root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            deadline = time.monotonic() + 5
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(started.exists(), "fake runner did not start")
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 128 + signal.SIGTERM, stderr)
            self.assertTrue(ended.exists(), "runner did not receive SIGTERM")
            self.assertIn("BUILD-FAILED", stdout)
            self.assertEqual(self.source.read_bytes(), self.original)
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGTERM)
                process.communicate(timeout=10)

    def test_sigkill_after_failure_summary_is_build_failed(self) -> None:
        env = self.env | {"FMP_FAKE_MODE": "kill-after-fail"}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("BUILD-FAILED", result.stdout)
        self.assertNotIn("CAUGHT", result.stdout)
        self.assertIn("tests=1/3", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_timed_out_runner_after_failure_summary_is_build_failed(self) -> None:
        env = self.env | {"FMP_FAKE_MODE": "timeout-after-fail"}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("BUILD-FAILED", result.stdout)
        self.assertNotIn("CAUGHT", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_filename_prefixed_compile_diagnostic_dominates_failure_summary(self) -> None:
        env = self.env | {"FMP_FAKE_MODE": "prefixed-build"}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("BUILD-FAILED", result.stdout)
        self.assertNotIn("CAUGHT", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_nested_xctest_summaries_use_one_authoritative_total(self) -> None:
        env = self.env | {"FMP_FAKE_MODE": "nested-xctest"}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CAUGHT", result.stdout)
        self.assertIn("tests=1/3", result.stdout)
        self.assertNotIn("tests=3/9", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_swift_testing_results_are_used_after_empty_xctest_summary(self) -> None:
        failed = self.env | {"FMP_FAKE_MODE": "swift-testing-failed"}
        caught = self.run_mutate(*self.single("--replace", "10", "11"), env=failed)
        self.assertEqual(caught.returncode, 0, caught.stderr)
        self.assertIn("CAUGHT", caught.stdout)
        self.assertIn("tests=1/1", caught.stdout)

        passed = self.env | {"FMP_FAKE_MODE": "swift-testing-passed"}
        survived = self.run_mutate(*self.single("--replace", "10", "11"), env=passed)
        self.assertEqual(survived.returncode, 1)
        self.assertIn("SURVIVED", survived.stdout)
        self.assertIn("tests=0/2", survived.stdout)

    def test_mixed_xctest_and_swift_testing_counts_are_combined(self) -> None:
        env = self.env | {"FMP_FAKE_MODE": "mixed-frameworks"}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CAUGHT", result.stdout)
        self.assertIn("tests=1/3", result.stdout)

    def test_package_selector_infrastructure_failure_dominates_test_failure(self) -> None:
        fake_swift = self.fake_bin / "swift"
        invocation_file = self.root / "package-invocations.jsonl"
        fake_swift.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "args = sys.argv[1:]\n"
            "with Path(os.environ['FMP_PACKAGE_INVOCATIONS']).open('a') as stream:\n"
            "    stream.write(json.dumps(args) + '\\n')\n"
            "selector = args[args.index('--filter') + 1]\n"
            "if selector.endswith('testInfra'):\n"
            "    print('Error: test summary was empty')\n"
            "else:\n"
            "    source = Path(os.environ['FMP_MUTATE_FILE']).read_text()\n"
            "    if 'threshold = 11' in source:\n"
            "        print('FAIL 3 tests, 0 skipped, 1 failed (0.1s)')\n"
            "        raise SystemExit(1)\n"
            "    print('PASS 3 tests, 0 skipped, 0 failed (0.1s)')\n",
            encoding="utf-8",
        )
        fake_swift.chmod(0o755)
        env = self.env.copy()
        env.pop("FMP_MUTATE_RUNNER")
        env["FMP_PACKAGE_INVOCATIONS"] = str(invocation_file)
        package = self.root / "AdaptiveTraining"
        package.mkdir()
        result = self.run_mutate(
            "--file", str(self.source), "--replace", "10", "11",
            "--tests", "Example/testCaught", "Example/testInfra",
            "--package", str(package), env=env,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("BUILD-FAILED", result.stdout)
        self.assertNotIn("CAUGHT", result.stdout)
        self.assertIn("tests=1/3", result.stdout)
        self.assertEqual(len(invocation_file.read_text(encoding="utf-8").splitlines()), 2)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_restore_verification_failure_exits_three_loudly(self) -> None:
        fake_cmp = self.fake_bin / "cmp"
        fake_cmp.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        fake_cmp.chmod(0o755)
        result = self.run_mutate(*self.single("--replace", "10", "11"))
        self.assertEqual(result.returncode, 3)
        self.assertIn("RESTORE FAILED", result.stderr)
        self.assertIn("backup retained at", result.stderr)
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertTrue(list(self.root.glob(".Example.swift.mutate-*")))

    def test_failed_restore_replace_keeps_recovery_backup(self) -> None:
        hook_dir = self.root / "python-hook"
        hook_dir.mkdir()
        (hook_dir / "sitecustomize.py").write_text(
            "import os\n"
            "from pathlib import Path\n"
            "_original_replace = os.replace\n"
            "def _fail_restore(source, target, *args, **kwargs):\n"
            "    if Path(target).name == 'Example.swift' and '.restore-' in Path(source).name:\n"
            "        raise OSError('injected atomic restore failure')\n"
            "    return _original_replace(source, target, *args, **kwargs)\n"
            "os.replace = _fail_restore\n",
            encoding="utf-8",
        )
        env = self.env | {"PYTHONPATH": str(hook_dir)}
        result = self.run_mutate(*self.single("--replace", "10", "11"), env=env)
        self.assertEqual(result.returncode, 3)
        self.assertIn("backup retained at", result.stderr)
        backups = list(self.root.glob(".Example.swift.mutate-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), self.original)
        self.assertIn(b"threshold = 11", self.source.read_bytes())

    def test_batch_reports_totals_and_restores_each_file(self) -> None:
        second = self.root / "Other.swift"
        second_original = b"let threshold = 20\n"
        second.write_bytes(second_original)
        batch = self.root / "mutants.json"
        batch.write_text(json.dumps([
            {
                "id": "threshold-caught",
                "file": str(self.source),
                "replace": ["10", "11"],
                "tests": ["Catch/testThreshold"],
            },
            {
                "id": "threshold-survived",
                "file": str(second),
                "replace": ["20", "21"],
                "tests": ["Survive/testThreshold"],
            },
        ]), encoding="utf-8")
        result = self.run_mutate("--batch", str(batch))
        self.assertEqual(result.returncode, 1)
        self.assertIn("threshold-caught CAUGHT", result.stdout)
        self.assertIn("threshold-survived SURVIVED", result.stdout)
        self.assertIn("TOTALS caught=1 survived=1 not_applied=0 build_failed=0", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertEqual(second.read_bytes(), second_original)

    def test_sed_edit_is_applied_and_restored(self) -> None:
        env = self.env | {"FMP_EXPECTED_MUTANT": "let limit = 10"}
        result = self.run_mutate(*self.single("--sed", "s/threshold/limit/"), env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CAUGHT", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_unified_patch_edit_is_applied_and_restored(self) -> None:
        patch_file = self.root / "change.patch"
        patch_file.write_text(
            "--- Example.swift\n+++ Example.swift\n@@ -1,2 +1,2 @@\n"
            "-let threshold = 10\n+let threshold = 11\n let enabled = true\n",
            encoding="utf-8",
        )
        result = self.run_mutate(*self.single("--patch", str(patch_file)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CAUGHT", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_package_tests_use_swift_filter_under_kernel_lock(self) -> None:
        fake_swift = self.fake_bin / "swift"
        args_file = self.root / "swift-args.json"
        fake_swift.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "args = sys.argv[1:]\n"
            "Path(os.environ['FMP_SWIFT_ARGS']).write_text(json.dumps(args))\n"
            "source = Path(os.environ['FMP_MUTATE_FILE']).read_text()\n"
            "if 'threshold = 11' in source:\n"
            "    print('FAIL 3 tests, 0 skipped, 1 failed (0.1s)')\n"
            "    raise SystemExit(1)\n"
            "print('PASS 3 tests, 0 skipped, 0 failed (0.1s)')\n",
            encoding="utf-8",
        )
        fake_swift.chmod(0o755)
        env = self.env.copy()
        env.pop("FMP_MUTATE_RUNNER")
        env["FMP_SWIFT_ARGS"] = str(args_file)
        package = self.root / "AdaptiveTraining"
        package.mkdir()
        lock_file = self.root / "build/agents/build.lock"
        ready = self.root / "lock-holder-ready"
        release = self.root / "lock-holder-release"
        holder_code = (
            "from pathlib import Path\n"
            "import sys, time\n"
            "Path(sys.argv[1]).write_text('ready')\n"
            "release = Path(sys.argv[2])\n"
            "while not release.exists(): time.sleep(0.01)\n"
        )
        holder = subprocess.Popen(
            [sys.executable, str(WITH_LOCK), str(lock_file), "--", sys.executable, "-c", holder_code,
             str(ready), str(release)],
            cwd=self.root,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        process: subprocess.Popen[str] | None = None
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "lock holder did not acquire the build lock")
            process = subprocess.Popen(
                [sys.executable, str(MUTATE), *self.single("--replace", "10", "11"),
                 "--package", str(package)],
                cwd=self.root,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            time.sleep(0.2)
            self.assertFalse(args_file.exists(), "package runner started while another build held the lock")
            self.assertEqual(self.source.read_bytes(), self.original)
            release.write_text("release")
            holder_stdout, holder_stderr = holder.communicate(timeout=5)
            self.assertEqual(holder.returncode, 0, holder_stderr or holder_stdout)
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stderr)
            self.assertIn("CAUGHT", stdout)
            self.assertEqual(stdout.splitlines()[0], f"Repository root: {self.root.resolve()}")
            self.assertEqual(
                json.loads(args_file.read_text(encoding="utf-8")),
                ["test", "--package-path", str(package.resolve()), "--filter", "Example/testThreshold"],
            )
            self.assertEqual(self.source.read_bytes(), self.original)
        finally:
            release.touch(exist_ok=True)
            if holder.poll() is None:
                holder.communicate(timeout=5)
            if process is not None and process.poll() is None:
                process.send_signal(signal.SIGTERM)
                process.communicate(timeout=10)

    def test_mutate_wrapper_announces_the_current_repository_root(self) -> None:
        result = subprocess.run(
            [str(MUTATE_SH), *self.single("--replace", "10", "11")],
            cwd=self.root,
            env=self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], f"Repository root: {self.root.resolve()}")
        self.assertIn("CAUGHT", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_mutation_runs_test_sh_under_the_transaction_lock(self) -> None:
        self._copy_fake_worktree_scripts()
        env = self.env.copy()
        env.pop("FMP_MUTATE_RUNNER")
        env["FMP_TEST_RESULT"] = "fail"
        result = self.run_mutate(
            *self.single("--replace", "10", "11"), "--sim", "FAKE-DEVICE", env=env, timeout=10
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CAUGHT", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_mutate_uses_adjacent_runner_when_target_has_no_orchestration_scripts(self) -> None:
        target_runner = self.root / "scripts/orchestrate/test.sh"
        self.assertFalse(target_runner.exists())
        env = self.env | {"FMP_TEST_RESULT": "fail"}
        result = subprocess.run(
            [str(MUTATE_SH), *self.single("--replace", "10", "11"), "--sim", "FAKE-DEVICE"],
            cwd=self.root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], f"Repository root: {self.root.resolve()}")
        self.assertIn("CAUGHT", result.stdout)
        self.assertEqual(self.source.read_bytes(), self.original)

    def _copy_fake_worktree_scripts(self) -> None:
        orchestrate = self.root / "scripts/orchestrate"
        orchestrate.mkdir(parents=True, exist_ok=True)
        shutil.copy2(WITH_LOCK, orchestrate / "with-lock.py")
        shutil.copy2(TEST_SH, orchestrate / "test.sh")
        shutil.copy2(VALIDATE_BOTH, orchestrate / "validate-both.sh")
        test_summary = orchestrate / "test-summary.py"
        test_summary.write_text(
            "print('PASS 999 tests, 0 skipped, 0 failed (0s)')\n",
            encoding="utf-8",
        )
        (orchestrate / "with-lock.py").write_text(
            f"#!{sys.executable}\nraise SystemExit(91)\n",
            encoding="utf-8",
        )
        (orchestrate / "with-lock.py").chmod(0o755)

    def test_test_and_validate_scripts_use_caller_worktree_root(self) -> None:
        self._copy_fake_worktree_scripts()
        test = subprocess.run(
            [str(TEST_SH), "--sim", "FAKE-DEVICE", "--name", "root-check", "ExampleTests/testOne"],
            cwd=self.root,
            env=self.env | {"FMP_TEST_RESULT": "pass"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(test.returncode, 0, test.stderr)
        self.assertEqual(test.stdout.splitlines()[0], f"Repository root: {self.root.resolve()}")
        self.assertIn("PASS 4 tests", test.stdout)

        (self.root / "build/orchestrate").mkdir(parents=True, exist_ok=True)
        result_root = self.root / "build/validation/Logs/Test"
        result_root.mkdir(parents=True, exist_ok=True)
        validate = self.root / "scripts/validate.sh"
        validate.parent.mkdir(parents=True, exist_ok=True)
        validate.write_text(
            f"#!{sys.executable}\n"
            "from pathlib import Path\n"
            "counter = Path('build/validate-count')\n"
            "count = int(counter.read_text()) + 1 if counter.exists() else 1\n"
            "counter.write_text(str(count))\n"
            "bundle = Path('build/validation/Logs/Test') / f'run-{count}.xcresult'\n"
            "bundle.mkdir(parents=True)\n"
            "(bundle / 'Info.plist').write_text('fixture')\n",
            encoding="utf-8",
        )
        validate.chmod(0o755)
        validation = subprocess.run(
            [str(VALIDATE_BOTH)],
            cwd=self.root,
            env=self.env | {"FMP_TEST_RESULT": "pass"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(validation.returncode, 0, validation.stderr)
        self.assertEqual(validation.stdout.splitlines()[0], f"Repository root: {self.root.resolve()}")
        self.assertIn("local: PASS 4 tests", validation.stdout)
        self.assertIn("utc: PASS 4 tests", validation.stdout)

    def test_competing_mutations_serialize_backup_through_restore(self) -> None:
        first_started = self.root / "first-runner-started"
        env = self.env | {"FMP_FIRST_STARTED": str(first_started)}
        first_args = [
            sys.executable, str(MUTATE), "--file", str(self.source), "--replace", "10", "11",
            "--tests", "First/testThreshold",
        ]
        second_args = [
            sys.executable, str(MUTATE), "--file", str(self.source), "--replace", "true", "false",
            "--tests", "Second/testThreshold",
        ]
        first = subprocess.Popen(
            first_args, cwd=self.root, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        second: subprocess.Popen[str] | None = None
        try:
            deadline = time.monotonic() + 5
            while not first_started.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(first_started.exists(), "first mutation runner did not start")
            second = subprocess.Popen(
                second_args, cwd=self.root, env=env, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            first_stdout, first_stderr = first.communicate(timeout=10)
            second_stdout, second_stderr = second.communicate(timeout=10)
        finally:
            for process in (first, second):
                if process is not None and process.poll() is None:
                    process.send_signal(signal.SIGTERM)
                    process.communicate(timeout=10)
        self.assertEqual(first.returncode, 0, first_stderr)
        self.assertIsNotNone(second)
        assert second is not None
        self.assertEqual(second.returncode, 0, second_stderr)
        self.assertIn("CAUGHT", first_stdout)
        self.assertIn("CAUGHT", second_stdout)
        self.assertEqual(self.source.read_bytes(), self.original)
        records = [json.loads(line) for line in Path(self.env["FMP_RUNNER_MARKER"]).read_text().splitlines()]
        first_record = next(record for record in records if record["args"][0].startswith("First/"))
        second_record = next(record for record in records if record["args"][0].startswith("Second/"))
        self.assertIn("threshold = 11", first_record["source"])
        self.assertIn("enabled = true", first_record["source"])
        self.assertIn("threshold = 10", second_record["source"])
        self.assertIn("enabled = false", second_record["source"])


if __name__ == "__main__":
    unittest.main()
