"""Guardrails for shared instructions and on-demand agent skills."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AGENTS = ROOT / "AGENTS.md"
ORCHESTRATION_INDEX = ROOT / "docs" / "agent-orchestration.md"
COMMIT_INDEX = ROOT / "docs" / "commit-and-pr.md"
SKILL_NAMES = (
    "herdr-orchestration",
    "implementer-workflow",
    "mutation-checks",
    "review-workflow",
    "pr-handoff",
)
SKILL_ROOTS = (ROOT / ".agents" / "skills", ROOT / ".claude" / "skills")

# Baseline AGENTS.md size before this change. The budget includes each client's
# skill frontmatter because names and descriptions are exposed at session start.
ALWAYS_LOADED_BUDGET_BYTES = 13_986
SKILL_DOCUMENTATION_BUDGET_CHARS = 22_371

CRITICAL_RULES = (
    "1. **Aspect-Correct Geometry**: Compute angles and deviations with pixel coordinates or aspect-fit normalized coordinates (`CoordinateConverter`) to avoid distortion on non-square images.",
    "2. **Decoupled Pose Estimator**: Keep all Apple Vision code inside `AppleVisionPoseEstimator`. Domain models use estimator-independent `BodyPose` and `Landmark`.",
    "3. **Stable Measurement Identity**: Give every metric a stable `MeasurementID` string key, such as `front.shoulder_line_angle`, separate from its display name.",
    "4. **Non-Diagnostic Framing**: Make no medical claims (for example, scoliosis). Measurements are geometric observations relative to baseline.",
    "5. **Recordings Stay Local**: Developer workout recordings in `diagnostics/` and shared `FMP … .json` files contain real human pose data. Never commit or paste them into issues or PRs unless the developer explicitly asks; use synthetic tests instead.",
    "6. **Adaptive Engine Boundary**: `Packages/AdaptiveTraining` alone decides easier, harder, and next prescriptions. It remains Foundation-only with stable string IDs. Screens and view models encode no progression rules; app code uses `PostureAnalysisApp/AdaptiveTraining/` adapters. Never rename a `MovementFamilyID` or `VariantID`.",
)

# Keep this list explicit: these policies have had conflicting formulations.
KNOWN_RULES = {
    "agents_do_not_run_validate": {
        "required": re.compile(r"Agents never run `scripts/validate\.sh`"),
        "contradictory": re.compile(
            r"\b(?:agents|implementers)\s+(?:(?:must|should|may|can)\s+)?(?:always\s+)?run\s+`?\.?/?scripts/validate\.sh",
            re.IGNORECASE,
        ),
    },
    "fable_is_forbidden": {
        "required": re.compile(r"Never start Fable", re.IGNORECASE),
        "contradictory": re.compile(
            r"(?:\b(?:may|can|should|must)\s+(?:start|use)\s+(?:Codex\s+)?Fable\b|"
            r"\bOpus\s*\(\s*or\s+Fable\s*\)|"
            r"^\s*(?:[-*]\s*)?(?:start|use)\s+(?:Codex\s+)?Fable\b)",
            re.IGNORECASE | re.MULTILINE,
        ),
    },
    "astra_is_forbidden": {
        "required": re.compile(r"Never start Fable or Codex Astra", re.IGNORECASE),
        "contradictory": re.compile(
            r"\b(?:may|can|should|must)\s+(?:start|use)\s+(?:Codex\s+)?Astra\b|"
            r"\bAstra\s+(?:is\s+)?allowed\b|"
            r"^\s*(?:[-*]\s*)?(?:start|use)\s+(?:Codex\s+)?Astra\b",
            re.IGNORECASE | re.MULTILINE,
        ),
    },
    "pull_requests_are_not_merged": {
        "required": re.compile(r"Never merge a PR|never merge a pull request", re.IGNORECASE),
        "contradictory": re.compile(
            r"(?:\b(?:may|can|should|must)\s+merge\s+(?:a\s+)?(?:PR|pull request|stack)|"
            r"^\s*(?:[-*]\s*)?merge\s+(?:a\s+)?(?:PR|pull request|stack)\b)",
            re.IGNORECASE | re.MULTILINE,
        ),
    },
}


CONTRADICTORY_FIXTURES = {
    "agents_do_not_run_validate": (
        "Agents run `scripts/validate.sh` after every change.",
        "Agents should run `scripts/validate.sh` after every change.",
        "Implementers must run `./scripts/validate.sh` after every change.",
    ),
    "fable_is_forbidden": (
        "Orchestrator role: Opus (or Fable).",
        "Use Fable as orchestrator.",
    ),
    "astra_is_forbidden": (
        "Start Codex Astra as reviewer.",
        "Codex Astra is allowed as reviewer.",
    ),
    "pull_requests_are_not_merged": (
        "Merge a pull request.",
        "You may merge a stack.",
    ),
}


def assert_known_rules_consistent(text: str) -> None:
    for key, patterns in KNOWN_RULES.items():
        if patterns["required"].search(text) is None:
            raise AssertionError(f"required instruction missing for {key}")
        if patterns["contradictory"].search(text) is not None:
            raise AssertionError(f"contradictory instruction found for {key}")


def parse_skill_frontmatter_text(text: str, source: str) -> tuple[str, str, bytes]:
    if not text.startswith("---\n"):
        raise AssertionError(f"{source} must start with YAML frontmatter")
    parts = text[4:].split("\n---\n", maxsplit=1)
    if len(parts) != 2:
        raise AssertionError(f"{source} has no closing frontmatter marker")

    values: dict[str, str] = {}
    for line in parts[0].splitlines():
        match = re.fullmatch(r"(name|description): ([^\n]+)", line)
        if match is None or match.group(1) in values:
            raise AssertionError(f"{source} has invalid skill frontmatter line: {line!r}")
        values[match.group(1)] = match.group(2)
    if set(values) != {"name", "description"}:
        raise AssertionError(f"{source} must define name and description")
    if re.fullmatch(r"[a-z0-9-]+", values["name"]) is None:
        raise AssertionError(f"{source} has invalid skill name {values['name']!r}")
    # Keep descriptions in this valid, unquoted YAML string-scalar subset. The
    # fixed text prefix avoids YAML 1.1 booleans/numbers; the character set
    # excludes mapping syntax (`:`), comments (`#`), and YAML indicators.
    if re.fullmatch(r"Use when [A-Za-z][A-Za-z0-9 ,.'()/+-]*", values["description"]) is None:
        raise AssertionError(f"{source} has a description outside the plain YAML scalar subset")
    frontmatter_end = text.index("\n---\n", 4) + 5
    return values["name"], values["description"], text[:frontmatter_end].encode("utf-8")


def parse_skill_frontmatter(path: Path) -> tuple[str, str, bytes]:
    return parse_skill_frontmatter_text(path.read_text(encoding="utf-8"), str(path.relative_to(ROOT)))


class AgentInstructionTests(unittest.TestCase):
    def test_critical_invariant_heading_and_rules_remain_in_agents(self) -> None:
        text = AGENTS.read_text(encoding="utf-8")
        self.assertIn("## Critical Invariants", text)
        for rule in CRITICAL_RULES:
            with self.subTest(rule=rule.split(":", maxsplit=1)[0]):
                self.assertIn(rule, text)

    def test_referenced_agent_instructions_exist(self) -> None:
        for document in (AGENTS, ORCHESTRATION_INDEX, COMMIT_INDEX):
            text = document.read_text(encoding="utf-8")
            for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text):
                with self.subTest(document=document.relative_to(ROOT), target=target):
                    self.assertTrue((document.parent / target).is_file(), f"missing reference: {target}")

        for name in SKILL_NAMES:
            for skill_root in SKILL_ROOTS:
                with self.subTest(skill=name, root=skill_root.relative_to(ROOT)):
                    self.assertTrue((skill_root / name / "SKILL.md").is_file())

    def test_native_client_skills_have_valid_matching_frontmatter(self) -> None:
        for name in SKILL_NAMES:
            parsed = []
            for skill_root in SKILL_ROOTS:
                path = skill_root / name / "SKILL.md"
                with self.subTest(skill=name, root=skill_root.relative_to(ROOT)):
                    skill_name, description, frontmatter = parse_skill_frontmatter(path)
                    self.assertEqual(skill_name, name)
                    self.assertLessEqual(len(frontmatter), 500)
                    parsed.append((description, path.read_bytes()))
            if len(parsed) == 2:
                self.assertEqual(parsed[0], parsed[1], f"client copies of {name} must stay identical")

    def test_known_instruction_keys_have_no_contradictions(self) -> None:
        paths = [AGENTS, ORCHESTRATION_INDEX, COMMIT_INDEX]
        paths.extend(root / name / "SKILL.md" for root in SKILL_ROOTS for name in SKILL_NAMES)
        text = "\n".join(path.read_text(encoding="utf-8") for path in paths)
        assert_known_rules_consistent(text)

    def test_direct_and_modal_contradiction_fixtures_are_rejected(self) -> None:
        paths = [AGENTS, ORCHESTRATION_INDEX, COMMIT_INDEX]
        paths.extend(root / name / "SKILL.md" for root in SKILL_ROOTS for name in SKILL_NAMES)
        base_text = "\n".join(path.read_text(encoding="utf-8") for path in paths)
        for key, fixtures in CONTRADICTORY_FIXTURES.items():
            for fixture in fixtures:
                with self.subTest(key=key, fixture=fixture):
                    with self.assertRaisesRegex(AssertionError, key):
                        assert_known_rules_consistent(f"{base_text}\n{fixture}")

    def test_frontmatter_rejects_invalid_yaml_scalar_fixtures(self) -> None:
        malformed_values = (
            "Use when: reviewing a branch",
            "true",
            "123",
            "Use when reviewing # a branch",
        )
        for description in malformed_values:
            malformed = f"---\nname: sample-skill\ndescription: {description}\n---\n"
            with self.subTest(description=description):
                with self.assertRaisesRegex(AssertionError, "plain YAML scalar subset"):
                    parse_skill_frontmatter_text(malformed, "fixture")

    def test_herdr_skill_uses_shared_workspace_state_location(self) -> None:
        for skill_root in SKILL_ROOTS:
            text = (skill_root / "herdr-orchestration" / "SKILL.md").read_text(encoding="utf-8")
            with self.subTest(root=skill_root.relative_to(ROOT)):
                self.assertIn("`<git-common-dir>/build/orchestrate/state.json`", text)
                self.assertIn("`HERDR_WORKSPACE_ID`", text)
                self.assertIn("`<git-common-dir>/build/orchestrate/notes/<workspace-key>/`", text)
                self.assertIn("writable via `--add-dir`", text)
                self.assertIn("`note get` skips the state lock", text)
                self.assertNotIn("pane IDs recorded in `build/orchestrate/state.json`", text)

    def test_agent_skills_document_notes_ownership_and_check_handoffs(self) -> None:
        for skill_root in SKILL_ROOTS:
            herdr = (skill_root / "herdr-orchestration" / "SKILL.md").read_text(encoding="utf-8")
            implementer = (skill_root / "implementer-workflow" / "SKILL.md").read_text(encoding="utf-8")
            reviewer = (skill_root / "review-workflow" / "SKILL.md").read_text(encoding="utf-8")
            with self.subTest(root=skill_root.relative_to(ROOT)):
                self.assertIn("note get --topic TOPIC", herdr)
                self.assertIn("note add --topic TOPIC --file PATH", herdr)
                self.assertIn("--owns 'glob,glob'", herdr)
                self.assertIn("Do deterministic steps directly", herdr)
                self.assertIn("note get --topic TOPIC", implementer)
                self.assertIn("## Checks run", implementer)
                self.assertIn("`<exact command>` — PASS/FAIL", implementer)
                self.assertIn("note get --topic TOPIC", reviewer)
                self.assertIn("verify every claim independently", reviewer)

    def test_full_skill_documentation_stays_within_budget(self) -> None:
        character_count = sum(
            len(path.read_text(encoding="utf-8"))
            for root in SKILL_ROOTS for path in root.rglob("SKILL.md")
        )
        self.assertLessEqual(character_count, SKILL_DOCUMENTATION_BUDGET_CHARS)

    def test_always_loaded_instruction_budget_does_not_grow(self) -> None:
        agents_bytes = AGENTS.read_bytes()
        for skill_root in SKILL_ROOTS:
            metadata_bytes = 0
            for name in SKILL_NAMES:
                _, _, frontmatter = parse_skill_frontmatter(skill_root / name / "SKILL.md")
                metadata_bytes += len(frontmatter)
            with self.subTest(client_root=skill_root.relative_to(ROOT)):
                self.assertLessEqual(
                    len(agents_bytes) + metadata_bytes,
                    ALWAYS_LOADED_BUDGET_BYTES,
                    "AGENTS.md plus skill discovery metadata exceeded the previous always-loaded byte budget",
                )


if __name__ == "__main__":
    unittest.main()
