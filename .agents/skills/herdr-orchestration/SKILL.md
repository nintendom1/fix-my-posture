---
name: herdr-orchestration
description: Use when managing Herdr agents or long-running scripts, assigning work, arranging panes, or preparing agent briefs.
---

# Herdr Orchestration

Use `scripts/orchestrate/agent.py` from a Herdr pane with `HERDR_ENV=1`. It finds the current checkout and stores shared metadata at `<git-common-dir>/build/orchestrate/state.json`, keyed by `HERDR_WORKSPACE_ID`.

## Start and message agents

```sh
scripts/orchestrate/agent.py start posture --kind codex --model gpt-6-luna --effort max --role implementer --purpose "Posture change"
scripts/orchestrate/agent.py prompt posture --brief build/briefs/posture.md --wait --timeout 5400
scripts/orchestrate/agent.py status
```

Keep names valid and purposes unique, at most 20 characters; `Orchestrator` is reserved. Every orchestrator message starts with `Orchestrator:`. `agent.py prompt` adds the prefix and avoids doubling it. Use `--text` for direct instructions.

Use these model roles: Opus orchestrator; Codex Luna at max effort implementer; Codex Sol at high effort copy writer; Codex Sol or Claude Opus reviewer. Never start Fable or Codex Astra. `agent.py` also refuses Terra unless `--allow-terra` is explicitly set; reviewers are only Sol or Opus.

## Pane layout

- Keep the Orchestrator pane and up to two agents in `Main`; count every physical Main pane, including user panes, toward its three equal-width columns.
- Put overflow agents in managed `Agent`, `Agent 2`, … tabs and overflow scripts in `Scripts`, `Scripts 2`, … tabs. Place agents before scripts; do not stack panes vertically.
- Operate only on pane IDs recorded in the current workspace entry of `<git-common-dir>/build/orchestrate/state.json` and on managed overflow tabs recorded there. Ignore unmanaged panes and tabs.
- Preserve running processes and focus while moving panes. Re-equalize after layout changes. Use `layout` to reapply placement.
- Close a managed script with `close-script PURPOSE` after capturing its result. Do not close an agent before reviewing its package; `close` promotes waiting agents and fills a spare Main slot.

## Briefs and ownership

The orchestrator owns shared contracts, compiling stubs, fixtures, project registration, integration, review, validation, git, and PRs. Agents own complete files within their briefs, not regions of shared files. Keep composition roots, coordinators, settings screens, and the Xcode project with the orchestrator.

Put shared rules in `build/briefs/_rules.md` and one brief per agent in `build/briefs/<name>.md`. State owned files, contracts, behavior, thresholds, tests, compile command, forbidden actions, and the report path `build/briefs/<name>.report.md`. Register new Swift files before implementation and validate stubs before assigning work.

Only start work explicitly assigned by the user or orchestrator. Keep a ledger for unattended multi-package runs and resume from its first unfinished item. Keep agents idle while validation runs; builds and focused tests share a lock.

Use `scripts/orchestrate/agent.py script PURPOSE -- COMMAND ...` for a long-running command in a managed pane. Capture its output before closing it. Never merge a PR.
