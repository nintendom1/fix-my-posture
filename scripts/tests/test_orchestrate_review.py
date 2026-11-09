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
elif sys.argv[1] == "status":
    print(sys.argv[2] + " state=" + os.environ.get("FAKE_AGENT_STATUS", "working") + " pane=fake")
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
        (self.root / ".gitignore").write_text("build/briefs/\nbuild/reviews/\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.root), "add", "source.txt", ".gitignore"], check=True)
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

    def commit_file(self, path: str, contents: str, message: str) -> str:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents, encoding="utf-8")
        subprocess.run(["git", "-C", str(self.root), "add", path], check=True)
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
            "## Blocking\n- [F1] [A.swift:2] [open] blocks — serious — fix it\n"
            "## Major\n- [F2] [B.swift:4] [open] major one — matters — correct it\n"
            "- [F3] [B.swift:8] [open] major two — matters — correct it\n"
            "- [F4] [B.swift:9] [resolved] old major — already fixed — no action\n"
            "- [F5] [B.swift:10] [accepted-scope] scoped major — accepted — no action\n"
            "## Minor\n- [F6] [C.swift:1] [open] minor — small — adjust it\n"
            "## Nit\n- [F7] [D.swift:3] [open] nit — tiny — polish it\n"
            "## Verdict\nNeeds changes\n",
            encoding="utf-8",
        )
        result = self.run_review("--collect", "findings")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "blocking=1 major=2 minor=1 nit=1",
                "Blocking: - [F1] [A.swift:2] [open] blocks — serious — fix it",
                "Major: - [F2] [B.swift:4] [open] major one — matters — correct it",
                "Major: - [F3] [B.swift:8] [open] major two — matters — correct it",
            ],
        )

    def test_failed_initial_start_keeps_full_review_pending_until_confirm_handoff(self) -> None:
        (self.root / "source.txt").write_text("change missed by failed reviewer\n", encoding="utf-8")
        failed = self.run_review(
            f"{self.base_commit}..WORKTREE", "--name", "initial-retry", "--brief",
            "build/briefs/sample.md", "--start", "sol",
            env={"FAKE_AGENT_START_ERROR": "registration failed"},
        )
        self.assertNotEqual(failed.returncode, 0)
        state_path = self.root / "build/reviews/initial-retry.state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        self.assertTrue(state["initial_handoff_pending"])
        self.assertNotIn("last_reviewed", state)

        retried = self.run_review(
            "--confirm", "initial-retry",
            env={"FAKE_AGENT_STATUS": "not-running", "FAKE_REVIEW_FOOTER": "gpt-6.1-sol high ready"},
        )
        self.assertEqual(retried.returncode, 0, retried.stderr)
        self.assertIn("request=build/reviews/initial-retry.request.md", retried.stdout)
        request = (self.root / "build/reviews/initial-retry.request.md").read_text(encoding="utf-8")
        self.assertIn("- Head: `WORKTREE`", request)
        self.assertIn("- `source.txt`", request)
        self.assertIn("git diff", request)
        self.assertNotIn("(No changed hunks.)", request)
        state = json.loads(state_path.read_text(encoding="utf-8"))
        self.assertNotIn("initial_handoff_pending", state)
        self.assertEqual(state["round"], 1)
        self.assertEqual(state["last_reviewed"], state["last_head"])

    def test_since_opus_records_actual_reviewer_for_next_confirmation(self) -> None:
        (self.root / "source.txt").write_text("opus review change\n", encoding="utf-8")
        initial = self.run_review(
            "--since", self.base_commit, "--name", "since-opus", "--brief",
            "build/briefs/sample.md", "--start", "opus",
            env={"FAKE_REVIEW_FOOTER": "❯ review request\nOpus 5.5 · Claude Code"},
        )
        self.assertEqual(initial.returncode, 0, initial.stderr)
        state_path = self.root / "build/reviews/since-opus.state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        self.assertEqual(state["reviewer"]["mode"], "opus")
        self.assertEqual(state["reviewer"]["kind"], "claude")
        self.assertEqual(state["reviewer"]["model"], "claude-opus-5-5")

        confirmed = self.run_review(
            "--confirm", "since-opus",
            env={"FAKE_AGENT_STATUS": "working", "FAKE_REVIEW_FOOTER": "❯ ready\nOpus 5.5 · Claude Code"},
        )
        self.assertEqual(confirmed.returncode, 0, confirmed.stderr)
        agent_calls = [event["args"] for event in self.event_rows() if event["source"] == "agent"]
        self.assertEqual([call[0] for call in agent_calls], ["start", "prompt", "status", "prompt"])
        self.assertEqual(agent_calls[-1][1], "review-since-opus")

    def test_confirm_reuses_done_reviewer_after_verifying_model(self) -> None:
        first_head = self.commit_change("initial completed review")
        full = self.run_review(
            f"{self.base_commit}..{first_head}", "--name", "done-reviewer", "--brief",
            "build/briefs/sample.md", "--start", "sol",
            env={"FAKE_REVIEW_FOOTER": "gpt-6.1-sol high ready"},
        )
        self.assertEqual(full.returncode, 0, full.stderr)
        self.commit_file("source.txt", "confirmed fix\n", "confirmation fix")

        confirmed = self.run_review(
            "--confirm", "done-reviewer",
            env={"FAKE_AGENT_STATUS": "done", "FAKE_REVIEW_FOOTER": "gpt-6.1-sol high ready"},
        )
        self.assertEqual(confirmed.returncode, 0, confirmed.stderr)
        calls = [event["args"] for event in self.event_rows() if event["source"] == "agent"]
        self.assertEqual(calls[-2:], [
            ["status", "review-done-reviewer"],
            ["prompt", "review-done-reviewer", "--brief", "build/reviews/done-reviewer.round-2.request.md"],
        ])
        self.assertFalse(any(call[0] == "close" for call in calls))
        self.assertEqual(sum(call[0] == "start" for call in calls), 1)

    def test_full_fallback_preserves_custom_criteria_and_notes(self) -> None:
        brief = self.root / "build/briefs/no-headings.md"
        brief.write_text("This brief intentionally has no criteria headings.\n", encoding="utf-8")
        criteria = self.root / "acceptance-override.md"
        criteria.write_text("Honor the external acceptance contract.\n", encoding="utf-8")
        notes = self.root / "review-notes.md"
        notes.write_text(
            "## Tests\n- rerun the focused review tests\n\n## Deviations\n- preserve local fixture behavior\n",
            encoding="utf-8",
        )
        first_head = self.commit_change("review custom criteria")
        full = self.run_review(
            f"{self.base_commit}..{first_head}", "--name", "custom-fallback", "--brief",
            "build/briefs/no-headings.md", "--criteria", "acceptance-override.md", "--notes", "review-notes.md",
        )
        self.assertEqual(full.returncode, 0, full.stderr)
        state_path = self.root / "build/reviews/custom-fallback.state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["last_reviewed"] = "invalid-state-ref"
        state_path.write_text(json.dumps(state), encoding="utf-8")
        self.commit_file("source.txt", "custom fallback fix\n", "fallback fix")

        confirmed = self.run_review(
            "--confirm", "custom-fallback",
            env={"FAKE_AGENT_STATUS": "working", "FAKE_REVIEW_FOOTER": "gpt-6.1-sol high ready"},
        )
        self.assertEqual(confirmed.returncode, 0, confirmed.stderr)
        self.assertIn("falling back to a full review", confirmed.stderr)
        request = (self.root / "build/reviews/custom-fallback.request.md").read_text(encoding="utf-8")
        self.assertIn("Honor the external acceptance contract.", request)
        self.assertIn("rerun the focused review tests", request)
        self.assertIn("preserve local fixture behavior", request)
        self.assertNotIn("brief has no", request)

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

    def test_open_findings_assigns_stable_ids_and_filters_status(self) -> None:
        findings = self.root / "build" / "reviews" / "findings.findings.md"
        findings.parent.mkdir(parents=True)
        findings.write_text(
            "## Major\n- [A.swift:2] first issue — impact — fix\n"
            "## Minor\n- [B.swift:4] second issue — impact — fix\n",
            encoding="utf-8",
        )
        first = self.run_review("--findings-for", "findings", "--open")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout.splitlines(), [
            "F1 Major [A.swift:2] first issue — impact — fix",
            "F2 Minor [B.swift:4] second issue — impact — fix",
        ])
        canonical = findings.read_text(encoding="utf-8")
        self.assertIn("- [F1] [A.swift:2] [open] first issue", canonical)
        self.assertIn("- [F2] [B.swift:4] [open] second issue", canonical)

        findings.write_text(canonical.replace("[F1] [A.swift:2] [open]", "[F1] [A.swift:2] [resolved]"), encoding="utf-8")
        second = self.run_review("--findings-for", "findings", "--open")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout.strip(), "F2 Minor [B.swift:4] second issue — impact — fix")
        self.assertIn("[F1] [A.swift:2] [resolved]", findings.read_text(encoding="utf-8"))

    def test_confirm_builds_hunk_delta_and_hands_off_to_running_reviewer(self) -> None:
        base = self.base_commit
        (self.root / "source.txt").write_text("First reviewed line.\n", encoding="utf-8")
        full = self.run_review(
            f"{base}..WORKTREE", "--name", "delta", "--brief", "build/briefs/sample.md",
        )
        self.assertEqual(full.returncode, 0, full.stderr)
        findings = self.root / "build" / "reviews" / "delta.findings.md"
        findings.write_text(
            "## Major\n- [F1] [source.txt:1] [open] first issue — impact — fix\n"
            "- [F2] [source.txt:2] [resolved] old issue — impact — fix\n",
            encoding="utf-8",
        )
        second_head = self.commit_file("source.txt", "First reviewed line.\nFix one.\n", "round two")
        manual_delta = self.run_review("--since", "round-1", "--name", "delta")
        self.assertEqual(manual_delta.returncode, 0, manual_delta.stderr)
        self.assertIn("delta.round-2.request.md", manual_delta.stdout)
        result = self.run_review(
            "--confirm", "delta",
            env={"FAKE_AGENT_STATUS": "working", "FAKE_REVIEW_FOOTER": "gpt-6.1-sol high ready"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("delta.round-2.request.md", result.stdout)
        delta = (self.root / "build" / "reviews" / "delta.round-2.request.md").read_text(encoding="utf-8")
        self.assertIn("[F1] Major [source.txt:1] first issue", delta)
        self.assertNotIn("[F2]", delta)
        self.assertIn("+Fix one.", delta)
        self.assertNotIn("+First reviewed line.", delta)
        self.assertNotIn("Review the stable result.", delta)
        state = json.loads((self.root / "build" / "reviews" / "delta.state.json").read_text(encoding="utf-8"))
        self.assertEqual(state["last_reviewed"], second_head)
        self.assertEqual(state["round_tags"]["round-2"], second_head)
        events = self.event_rows()
        self.assertTrue(any(event["args"] == ["status", "review-delta"] for event in events))
        self.assertTrue(any(event["args"] == ["prompt", "review-delta", "--brief", "build/reviews/delta.round-2.request.md"] for event in events))
        self.assertFalse(any(event["args"][0] == "start" for event in events if event["source"] == "agent"))

    def test_confirm_starts_reviewer_when_absent_and_stops_on_unverifiable_model(self) -> None:
        first_head = self.commit_change("initial review change")
        full = self.run_review(
            f"{self.base_commit}..{first_head}", "--name", "start-confirm", "--brief",
            "build/briefs/sample.md",
        )
        self.assertEqual(full.returncode, 0, full.stderr)
        self.commit_file("source.txt", "confirm change\n", "confirm change")
        result = self.run_review(
            "--confirm", "start-confirm",
            env={"FAKE_AGENT_STATUS": "not-running", "FAKE_REVIEW_FOOTER": ""},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reviewer handoff stopped (unverifiable)", result.stderr)
        self.assertIn("request=build/reviews/start-confirm.round-2.request.md", result.stdout)
        events = self.event_rows()
        self.assertTrue(any(event["args"][0] == "start" for event in events if event["source"] == "agent"))
        self.assertFalse(any(event["args"][0] == "prompt" for event in events if event["source"] == "agent"))

    def test_confirm_refuses_running_reviewer_with_different_model(self) -> None:
        first_head = self.commit_change("initial review change")
        full = self.run_review(
            f"{self.base_commit}..{first_head}", "--name", "mismatch", "--brief",
            "build/briefs/sample.md",
        )
        self.assertEqual(full.returncode, 0, full.stderr)
        self.commit_file("source.txt", "confirmation change\n", "confirmation change")
        result = self.run_review(
            "--confirm", "mismatch",
            env={"FAKE_AGENT_STATUS": "idle", "FAKE_REVIEW_FOOTER": "gpt-6-luna medium"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reviewer handoff stopped (mismatch)", result.stderr)
        events = self.event_rows()
        self.assertTrue(any(event["args"] == ["status", "review-mismatch"] for event in events))
        self.assertFalse(any(event["args"][0] in {"start", "prompt"} for event in events if event["source"] == "agent"))

    def test_confirm_falls_back_to_full_review_when_delta_state_is_invalid(self) -> None:
        first_head = self.commit_change("initial review change")
        full = self.run_review(
            f"{self.base_commit}..{first_head}", "--name", "fallback", "--brief",
            "build/briefs/sample.md",
        )
        self.assertEqual(full.returncode, 0, full.stderr)
        findings = self.root / "build" / "reviews" / "fallback.findings.md"
        findings.write_text(
            "## Major\n- [F1] [source.txt:1] [open] retain me — impact — fix\n",
            encoding="utf-8",
        )
        state_path = self.root / "build" / "reviews" / "fallback.state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["last_reviewed"] = "invalid-state-ref"
        state_path.write_text(json.dumps(state), encoding="utf-8")
        current_head = self.commit_file("source.txt", "fallback fix\n", "fallback fix")
        result = self.run_review(
            "--confirm", "fallback",
            env={"FAKE_AGENT_STATUS": "working", "FAKE_REVIEW_FOOTER": "gpt-6.1-sol high ready"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("falling back to a full review", result.stderr)
        self.assertIn("request=build/reviews/fallback.request.md", result.stdout)
        self.assertIn("retain me", findings.read_text(encoding="utf-8"))
        state = json.loads(state_path.read_text(encoding="utf-8"))
        self.assertEqual(state["last_reviewed"], current_head)

    def test_three_round_fixture_reports_actual_full_and_incremental_request_bytes(self) -> None:
        self.brief.write_text(
            "## Goal\n" + ("Check the documented acceptance behavior across changed modules.\n" * 45)
            + "\n## Done\nVerify the focused regression tests and preserve the public contract.\n",
            encoding="utf-8",
        )
        base = self.base_commit
        round_one = self.commit_file("source.txt", "Reviewed baseline.\n", "review round one")
        full_one = self.run_review(
            f"{base}..{round_one}", "--name", "measure", "--brief", "build/briefs/sample.md",
        )
        self.assertEqual(full_one.returncode, 0, full_one.stderr)
        findings = self.root / "build" / "reviews" / "measure.findings.md"
        findings.write_text(
            "## Major\n- [F1] [source.txt:1] [open] fix one — impact — change it\n"
            "- [F2] [source.txt:2] [open] fix two — impact — change it\n",
            encoding="utf-8",
        )
        bytes_full_one = (self.root / "build/reviews/measure.request.md").stat().st_size

        round_two = self.commit_file("source.txt", "Reviewed baseline.\nFix one.\n", "review round two")
        full_round_two = self.run_review(
            f"{base}..{round_two}", "--name", "full-two-current", "--brief", "build/briefs/sample.md",
        )
        self.assertEqual(full_round_two.returncode, 0, full_round_two.stderr)
        bytes_full_two = (self.root / "build/reviews/full-two-current.request.md").stat().st_size
        delta_two = self.run_review(
            "--confirm", "measure",
            env={"FAKE_AGENT_STATUS": "working", "FAKE_REVIEW_FOOTER": "gpt-6.1-sol high ready"},
        )
        self.assertEqual(delta_two.returncode, 0, delta_two.stderr)
        bytes_delta_two = (self.root / "build/reviews/measure.round-2.request.md").stat().st_size

        findings.write_text(
            findings.read_text(encoding="utf-8").replace("[F1] [source.txt:1] [open]", "[F1] [source.txt:1] [resolved]"),
            encoding="utf-8",
        )
        round_three = self.commit_file("other.txt", "Fix two.\n", "review round three")
        full_three = self.run_review(
            f"{base}..{round_three}", "--name", "full-three", "--brief", "build/briefs/sample.md",
        )
        self.assertEqual(full_three.returncode, 0, full_three.stderr)
        bytes_full_three = (self.root / "build/reviews/full-three.request.md").stat().st_size
        delta_three = self.run_review(
            "--confirm", "measure",
            env={"FAKE_AGENT_STATUS": "working", "FAKE_REVIEW_FOOTER": "gpt-6.1-sol high ready"},
        )
        self.assertEqual(delta_three.returncode, 0, delta_three.stderr)
        bytes_delta_three = (self.root / "build/reviews/measure.round-3.request.md").stat().st_size
        delta_three_text = (self.root / "build/reviews/measure.round-3.request.md").read_text(encoding="utf-8")
        self.assertIn("[F2] Major [source.txt:2] fix two", delta_three_text)
        self.assertNotIn("- [F1] Major", delta_three_text)
        full_total = bytes_full_one + bytes_full_two + bytes_full_three
        incremental_total = bytes_full_one + bytes_delta_two + bytes_delta_three
        print(
            "THREE_ROUND_REQUEST_BYTES "
            f"full={full_total} (rounds={bytes_full_one},{bytes_full_two},{bytes_full_three}) "
            f"incremental={incremental_total} (rounds={bytes_full_one},{bytes_delta_two},{bytes_delta_three})"
        )
        self.assertLess(incremental_total, full_total)

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

    def test_mismatched_quota_fallback_footer_blocks_handoff(self) -> None:
        result = self.run_review(
            f"{self.base_commit}..HEAD", "--name", "quota", "--brief",
            "build/briefs/sample.md", "--start", "sol",
            env={"FAKE_REVIEW_FOOTER": "gpt-6-luna medium · quota fallback"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("WARNING: review-quota model footer does not show requested gpt-6.1-sol", result.stderr)
        self.assertIn("gpt-6-luna medium", result.stderr)
        self.assertIn("reviewer handoff stopped (mismatch)", result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 1)
        self.assertFalse(any(event["source"] == "agent" and event["args"][0] == "prompt" for event in self.event_rows()))


if __name__ == "__main__":
    unittest.main()
