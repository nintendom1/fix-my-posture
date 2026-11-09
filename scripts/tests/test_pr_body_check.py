"""Regression tests for the PR and commit body format checker."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "orchestrate" / "pr_body_check.py"

# This bad opening reproduces the headings used on the incident PRs.
BAD_PR_BODY = """## Before
People could not see the changed behavior.

## Now
People can see the changed behavior.

## Summary
- Update the behavior.

## Testing
- Python tests pass.

## Docs
- None.
"""

# Based on the good squash commit inspected with `git show 693ee23`.
GOOD_COMMIT_MESSAGE = """dev: Share Investigation Notes and File Leases Between Agents (#170)

Before, agents working in parallel each re-explored the same code. Two
agents could be handed overlapping files with nothing to stop it, and
the orchestrator re-ran checks its agents had already run because their
reports didn't say what was checked.
Now, agents leave and read short shared investigation notes, flagged
stale when their files change. The launcher refuses to start an agent
whose file globs overlap another agent's active lease, and implementer
reports list the exact checks they ran.

Closes #166. Stacked on #169.

## Summary
- **Notes:** `agent.py note add --topic X --file F` and `note get
--topic X` keep short summaries with file:line refs and the commit they
were written against.
  - A note is marked **stale** when its referenced files change.
  - Notes live where every sandboxed Codex and Claude agent can write.
- **File leases:** `agent.py start … --owns 'glob,glob'` records a
lease.
  - An overlapping start is refused with a one-line conflict.
  - Overlap is symmetric, including `**` on both sides.
  - `close` releases the lease; `status` lists leases.
- **Checks-run report:** the implementer skill's report template gains a
"Checks run" section with exact commands.
- **Allowed tools:** Claude implementers may run `note get`/`note add`,
and reviewers `note get`, without permission prompts.

## Measured
In a simulated two-agent case, shared notes cut context reads from
**5,176 to 3,105 bytes (−40%)**. These are context bytes, not model
tokens.

## Testing
- Python suite: 202 tests, OK.
- `./scripts/validate.sh` local + UTC: 1458 tests, 0 failures.
- Mutation: disabling lease-overlap detection fails 3 tests.

Reviewed by Codex Sol, using the incremental confirm from #165.
- Fixed: 2 majors (asymmetric `**` overlap; notes outside the agents'
writable area).
- I fixed 1 minor (note commands missing from the Claude tool lists).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01J4mroDKX7VaL8cs7sUQXJP

Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>
"""

GOOD_PR_BODY = (
    GOOD_COMMIT_MESSAGE.split("\n", maxsplit=1)[1]
    .rsplit("\nCo-authored-by:", maxsplit=1)[0]
    .lstrip("\n")
    + "\n## Docs\n- None.\n"
)


class PrBodyCheckTests(unittest.TestCase):
    def run_checker(
        self,
        *arguments: str,
        input_text: str | None = None,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CHECKER), *arguments],
            cwd=cwd or ROOT,
            env=env,
            input=input_text,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_good_pr_body_passes_from_stdin(self) -> None:
        result = self.run_checker("--file", "-", input_text=GOOD_PR_BODY)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_bad_heading_shape_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            body_path = Path(directory) / "body.md"
            body_path.write_text(BAD_PR_BODY, encoding="utf-8")
            result = self.run_checker("--file", str(body_path))

        self.assertEqual(result.returncode, 1)
        self.assertIn('Expected: first non-empty line "Before, ..."', result.stdout)
        self.assertIn("First offending line 1: '## Before'", result.stderr)

    def test_before_or_now_heading_is_rejected_anywhere(self) -> None:
        body = GOOD_PR_BODY + "\n## Now\nThis heading is not allowed.\n"
        result = self.run_checker("--file", "-", input_text=body)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Markdown headings named Before or Now are not allowed", result.stderr)

    def test_missing_now_line_is_rejected(self) -> None:
        body = "Before, this is the prior behavior.\n\n## Summary\n- Change.\n## Testing\n- Pass.\n## Docs\n- None.\n"
        result = self.run_checker("--file", "-", input_text=body)
        self.assertEqual(result.returncode, 1)
        self.assertIn('begin "Now, "', result.stderr)

    def test_missing_pr_section_is_rejected(self) -> None:
        body = "Before, old behavior.\nNow, new behavior.\n## Summary\n- Change.\n## Testing\n- Pass.\n"
        result = self.run_checker("--file", "-", input_text=body)
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing required ## Docs section", result.stderr)

    def test_pr_mode_uses_gh_json_body(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bin_directory = Path(directory)
            gh = bin_directory / "gh"
            gh.write_text(
                "#!/usr/bin/env python3\n"
                "import json, sys\n"
                "if sys.argv[1:] != ['pr', 'view', '42', '--json', 'body']:\n"
                "    raise SystemExit(2)\n"
                f"print(json.dumps({{'body': {json.dumps(GOOD_PR_BODY)}}}))\n",
                encoding="utf-8",
            )
            gh.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = str(bin_directory) + os.pathsep + env.get("PATH", "")
            result = self.run_checker("--pr", "42", env=env)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PR body format OK", result.stdout)

    def test_good_commit_with_trailers_passes_in_a_temporary_git_repo(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            self.initialize_repo(repo)
            message = (
                GOOD_COMMIT_MESSAGE
                + "Claude-Session: session metadata\n"
                + " ## Before\n"
            )
            commit = self.create_commit(repo, "good.txt", message)

            result = self.run_checker("--commit", commit, cwd=repo)

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_commit_with_now_but_no_before_is_rejected_in_a_temporary_git_repo(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            self.initialize_repo(repo)
            message = (
                "fix: describe changed behavior\n\n"
                "Prior, the old behavior had this limitation.\n"
                "Now, the changed behavior is available.\n"
            )
            commit = self.create_commit(repo, "bad.txt", message)

            result = self.run_checker("--commit", commit, cwd=repo)

        self.assertEqual(result.returncode, 1)
        self.assertIn('begin "Before, "', result.stderr)

    @staticmethod
    def initialize_repo(repo: Path) -> None:
        subprocess.run(["git", "init", "--quiet"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "Body Check Test"], cwd=repo, check=True)
        subprocess.run(
            ["git", "config", "user.email", "body-check@example.invalid"], cwd=repo, check=True
        )

    @staticmethod
    def create_commit(repo: Path, filename: str, message: str) -> str:
        source = repo / filename
        source.write_text("temporary fixture\n", encoding="utf-8")
        message_path = repo / "message.txt"
        message_path.write_text(message, encoding="utf-8")
        subprocess.run(["git", "add", filename], cwd=repo, check=True)
        subprocess.run(["git", "commit", "--quiet", "-F", str(message_path)], cwd=repo, check=True)
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=repo, check=True, capture_output=True, text=True
        ).stdout.strip()


if __name__ == "__main__":
    unittest.main()
