"""Tests for review request generation and reviewer handoff."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ENTRY_POINT = REPO_ROOT / "scripts" / "orchestrate" / "review.sh"

FAKE_AGENT = r'''#!/usr/bin/env python3
import json
import os
import sys
with open(os.environ["FAKE_REVIEW_EVENTS"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps({"source": "agent", "args": sys.argv[1:]}) + "\n")
if sys.argv[1] == "start":
    failure = os.environ.get("FAKE_AGENT_START_ERROR")
    if failure:
        print(failure, file=sys.stderr)
        sys.exit(1)
    print("started " + sys.argv[2] + " pane=fake")
'''

FAKE_HERDR = r'''#!/usr/bin/env python3
import json
import os
import sys
with open(os.environ["FAKE_REVIEW_EVENTS"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps({"source": "herdr", "args": sys.argv[1:]}) + "\n")
sys.stdout.write(os.environ.get("FAKE_REVIEW_FOOTER", ""))
'''


class OrchestrateReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        self.events = Path(self.temp.name) / "events.jsonl"
        self.fake_agent = self.bin / "fake-agent"
        self.fake_agent.write_text(FAKE_AGENT, encoding="utf-8")
        self.fake_agent.chmod(0o755)
        herdr = self.bin / "herdr"
        herdr.write_text(FAKE_HERDR, encoding="utf-8")
        herdr.chmod(0o755)
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "config", "user.name", "Review Test"], check=True)
        subprocess.run(["git", "-C", str(self.root), "config", "user.email", "review@example.invalid"], check=True)
        source = self.root / "source.txt"
        source.write_text("baseline\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.root), "add", "source.txt"], check=True)
        subprocess.run(["git", "-C", str(self.root), "commit", "--quiet", "-m", "baseline"], check=True)
        self.base_commit = subprocess.check_output(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True
        ).strip()
        self.brief = self.root / "build" / "briefs" / "sample.md"
        self.brief.parent.mkdir(parents=True)
        self.brief.write_text(
            "## Goal\nReview the stable result.\n\n### Coverage\nCheck nested acceptance too.\n\n"
            "## Done\nConfirm the test catches a regression.\n",
            encoding="utf-8",
        )
        self.environment = os.environ.copy()
        self.environment.update({
            "PATH": f"{self.bin}{os.pathsep}{os.environ.get('PATH', '')}",
            "FMP_REVIEW_AGENT_TOOL": str(self.fake_agent),
            "FAKE_REVIEW_EVENTS": str(self.events),
        })

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_review(self, *args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        environment = dict(self.environment)
        if env:
            environment.update(env)
        return subprocess.run(
            [str(ENTRY_POINT), *args], cwd=cwd or self.root,
            env=environment, capture_output=True, text=True, check=False,
        )

    def event_rows(self) -> list[dict[str, object]]:
        if not self.events.exists():
            return []
        return [json.loads(line) for line in self.events.read_text(encoding="utf-8").splitlines()]

    def commit_change(self, message: str = "implement feature") -> str:
        (self.root / "source.txt").write_text("feature\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.root), "add", "source.txt"], check=True)
        subprocess.run(["git", "-C", str(self.root), "commit", "--quiet", "-m", message], check=True)
        return subprocess.check_output(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True
        ).strip()

    def test_commit_range_includes_scope_brief_criteria_notes_and_template(self) -> None:
        head = self.commit_change()
        notes = self.root / "build" / "notes.md"
        notes.write_text(
            "## Tests and checks\n- python3 -m unittest\n\n## Deviations\n- None.\n",
            encoding="utf-8",
        )
        result = self.run_review(
            f"{self.base_commit}..{head}", "--name", "feature", "--brief",
            "build/briefs/sample.md", "--notes", "build/notes.md",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "request=build/reviews/feature.request.md findings=build/reviews/feature.findings.md",
        )
        request = (self.root / "build/reviews/feature.request.md").read_text(encoding="utf-8")
        self.assertIn(f"- Base: `{self.base_commit}`", request)
        self.assertIn(f"- Head: `{head}`", request)
        self.assertIn("implement feature", request)
        self.assertIn("git diff", request)
        self.assertIn("`source.txt`", request)
        self.assertIn("[build/briefs/sample.md](<../briefs/sample.md>)", request)
        self.assertIn("Review the stable result.", request)
        self.assertIn("Check nested acceptance too.", request)
        self.assertIn("Confirm the test catches a regression.", request)
        self.assertIn("python3 -m unittest", request)
        self.assertIn("- None.", request)
        findings = (self.root / "build/reviews/feature.findings.md").read_text(encoding="utf-8")
        for heading in ("## Blocking", "## Major", "## Minor", "## Nit", "## Verdict"):
            self.assertIn(heading, findings)
        self.assertTrue(findings.rstrip().endswith("Pending"))

    def test_worktree_includes_untracked_files_and_resolves_root_from_cwd(self) -> None:
        child = self.root / "nested" / "work"
        child.mkdir(parents=True)
        (self.root / "source.txt").write_text("working change\n", encoding="utf-8")
        (self.root / "new-source.txt").write_text("new\n", encoding="utf-8")
        result = self.run_review(
            f"{self.base_commit}..WORKTREE", "--name", "working", "--brief",
            "build/briefs/sample.md", cwd=child,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        request = (self.root / "build/reviews/working.request.md").read_text(encoding="utf-8")
        self.assertIn("- Head: `WORKTREE`", request)
        self.assertIn("includes staged and unstaged tracked changes", request)
        self.assertIn("`source.txt`", request)
        self.assertIn("`new-source.txt`", request)
        self.assertIn("untracked files are listed", request)

    def test_criteria_file_overrides_brief_sections(self) -> None:
        criteria = self.root / "acceptance.md"
        criteria.write_text("Check the custom contract.\n", encoding="utf-8")
        result = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "custom", "--brief",
            "build/briefs/sample.md", "--criteria", "acceptance.md",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        request = (self.root / "build/reviews/custom.request.md").read_text(encoding="utf-8")
        self.assertIn("Check the custom contract.", request)
        self.assertNotIn("Review the stable result.", request)

    def test_notes_peer_headings_stop_tests_and_deviations_sections(self) -> None:
        notes = self.root / "notes.md"
        notes.write_text(
            "## Tests and checks\n- suite passed\n\n## Requests\n- this is not a test\n\n"
            "## Deviations\n- none\n\n## Files changed\n- this is not a deviation\n",
            encoding="utf-8",
        )
        result = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "notes", "--brief",
            "build/briefs/sample.md", "--notes", "notes.md",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        request = (self.root / "build/reviews/notes.request.md").read_text(encoding="utf-8")
        self.assertIn("- suite passed", request)
        self.assertIn("- none", request)
        self.assertNotIn("this is not a test", request)
        self.assertNotIn("this is not a deviation", request)

    def test_collect_counts_and_prints_only_blocking_and_major_findings(self) -> None:
        findings = self.root / "build/reviews/findings.findings.md"
        findings.parent.mkdir(parents=True)
        findings.write_text(
            "## Blocking\n- [A.swift:2] blocks — serious — fix it\n"
            "## Major\n- [B.swift:4] major one — matters — correct it\n"
            "- [B.swift:8] major two — matters — correct it\n"
            "## Minor\n- [C.swift:1] minor — small — adjust it\n"
            "## Nit\n- [D.swift:3] nit — tiny — polish it\n"
            "## Verdict\nNeeds changes\n",
            encoding="utf-8",
        )
        result = self.run_review("--collect", "findings")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "blocking=1 major=2 minor=1 nit=1",
                "Blocking: - [A.swift:2] blocks — serious — fix it",
                "Major: - [B.swift:4] major one — matters — correct it",
                "Major: - [B.swift:8] major two — matters — correct it",
            ],
        )

    def test_start_sol_uses_exact_agent_commands_and_verifies_footer(self) -> None:
        result = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "engine", "--brief",
            "build/briefs/sample.md", "--start", "sol", "--purpose", "Review: engine",
            env={"FAKE_REVIEW_FOOTER": "prompt box\ngpt-6.1-sol high · ready\nstatus"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "request=build/reviews/engine.request.md findings=build/reviews/engine.findings.md agent=review-engine",
        )
        events = self.event_rows()
        agent_events = [event["args"] for event in events if event["source"] == "agent"]
        self.assertEqual(agent_events, [
            ["start", "review-engine", "--kind", "codex", "--model", "gpt-6.1-sol",
             "--effort", "high", "--role", "reviewer", "--purpose", "Review: engine"],
            ["prompt", "review-engine", "--brief", "build/reviews/engine.request.md"],
        ])
        self.assertEqual(events[1], {
            "source": "herdr",
            "args": ["agent", "read", "review-engine", "--source", "visible", "--lines", "12"],
        })

    def test_reviewer_start_error_is_reported_and_returns_nonzero(self) -> None:
        result = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "engine", "--brief",
            "build/briefs/sample.md", "--start", "sol",
            env={"FAKE_AGENT_START_ERROR": "agent review-engine failed to register"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("review.sh: agent review-engine failed to register", result.stderr)
        self.assertIn("request=build/reviews/engine.request.md", result.stdout)
        self.assertNotIn("agent=", result.stdout)

    def test_start_opus_uses_claude_model_and_accepts_display_footer(self) -> None:
        result = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "persona", "--brief",
            "build/briefs/sample.md", "--start", "opus", "--purpose", "Review: persona",
            env={"FAKE_REVIEW_FOOTER": "❯ read request\nOpus 5.5 · Claude Code"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        start = self.event_rows()[0]["args"]
        self.assertEqual(start, [
            "start", "review-persona", "--kind", "claude", "--model", "claude-opus-5-5",
            "--role", "reviewer", "--purpose", "Review: persona",
        ])

    def test_automatic_reviewer_purposes_are_unique_and_within_pane_limit(self) -> None:
        first = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "feature-area-alpha", "--brief",
            "build/briefs/sample.md", "--start", "sol",
            env={"FAKE_REVIEW_FOOTER": "gpt-6.1-sol"},
        )
        second = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "feature-area-beta", "--brief",
            "build/briefs/sample.md", "--start", "sol",
            env={"FAKE_REVIEW_FOOTER": "gpt-6.1-sol"},
        )
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        starts = [event["args"] for event in self.event_rows() if event["source"] == "agent" and event["args"][0] == "start"]
        purposes = [start[start.index("--purpose") + 1] for start in starts]
        self.assertEqual(len(set(purposes)), 2)
        self.assertTrue(all(purpose.startswith("Review: ") and len(purpose) <= 20 for purpose in purposes))

    def test_mismatched_quota_fallback_footer_emits_warning(self) -> None:
        result = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "quota", "--brief",
            "build/briefs/sample.md", "--start", "sol",
            env={"FAKE_REVIEW_FOOTER": "gpt-6-luna medium · quota fallback"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("WARNING: review-quota model footer does not show requested gpt-6.1-sol", result.stderr)
        self.assertIn("gpt-6-luna medium", result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
