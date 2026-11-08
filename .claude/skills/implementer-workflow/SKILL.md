---
name: implementer-workflow
description: Use when implementing a scoped repository brief and reporting its build, focused verification, deviations, and changed files.
---

# Implementer Workflow

Follow the assigned brief and `AGENTS.md`. Change only owned files. If a required file is outside scope, record it under `Requests` in the report. Never commit, push, stash, reset, checkout, rebase, or run `git add`.
Before exploring shared seams, check `agent.py note get --topic TOPIC`; verify current notes and add a concise reusable note with file:line refs after exploring. Do deterministic steps directly instead of assigning another agent.

## Compile and verify

- Compile with `scripts/agent-build.sh <agent-name> --tests` until it prints `BUILD SUCCEEDED`.
- Run only focused tests on the assigned simulator with `scripts/orchestrate/test.sh --sim <id> --name <agent> <TestClass>[/method]`. Package tests use `swift test --package-path Packages/<Name>`. Node tests use `node --test tools/session-replay/test/`; Python tests use `python3 -m unittest discover -s scripts/tests`.
- Summarize an XCTest result bundle or derived-data folder with `scripts/orchestrate/test-summary.py <path>`. If a simulator-dependent build cannot run in the sandbox because CoreSimulator is unavailable, report that and leave the build to the orchestrator.
- Agents never run `scripts/validate.sh` or the full app test suite. The orchestrator runs `scripts/orchestrate/validate-both.sh`.
- Run at most one `xcodebuild` command at a time and never in the background. Run focused simulator tests at most twice per package; prefer Swift package, Node, and Python tests when sufficient.
- Check every test is meaningful, deterministic, and fails when its fix is reverted. Do not add or run mutation checks unless the brief or defect warrants them; use the mutation skill for those checks.
- Run `make notification-character-check` when notification character content or art changes.

## Report

Write `build/briefs/<agent-name>.report.md` inside this checkout. Include what changed; ambiguous decisions; deviations and anything incomplete; `Requests`; revert checks; and the exact changed-file list. Include this section for checks the orchestrator can trust without repeating:

## Checks run
- `<exact command>` — PASS/FAIL; include test counts and failures.

List only commands actually run and state their results. Keep personal workout recordings out of the report. Reply `DONE` or `BLOCKED: <reason>` after writing it.
