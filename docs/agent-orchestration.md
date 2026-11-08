# Agent orchestration on Herdr

Read this when splitting a change across agents in the shared working tree. The orchestration command is
`scripts/orchestrate/agent.py`; it discovers the repository root from the current directory and stores its small
metadata file at `build/orchestrate/state.json`.

## Messages and model routing

Every message an orchestrator sends an agent starts with `Orchestrator:`. Agents treat these messages as
authoritative. The tool adds the prefix to `prompt` messages and avoids adding it twice.

| Role | Model | Owns |
|---|---|---|
| Orchestrator | Opus (or Fable) | Contracts, stubs, project registration, briefs, integration, review, validation, git, PRs |
| Implementer | Codex `gpt-6-luna`, effort `max` | One package of whole files with a crisp spec and its tests |
| Copy writer | Codex `gpt-6.1-sol`, effort `high` | User-facing wording in a content file, against a voice guide |
| Reviewer | Codex `gpt-6.1-sol` or Claude `claude-opus-5-5` | Read-only review findings |

The user's standing preference is Codex subagents, with Claude subagents only when Codex is unavailable. Always pass an
explicit model. Never start Codex Astra or use Fable or Codex Astra as a reviewer.

## Pane layout and commands

- Keep `Orchestrator` in `Main`; Main has room for at most two agents.
- Count every physical Main pane toward its three-column capacity, including user panes; send new agents to managed overflow when Main is full.
- Keep each tab to at most three side-by-side, equal-width columns; never stack panes vertically.
- Place active agents before scripts. Overflow agents go to `Agent`, `Agent 2`, and later tabs; overflow scripts go to
  `Scripts`, `Scripts 2`, and later tabs.
- Keep running processes alive while moving panes, re-equalize after layout changes, and preserve focus.
- Only operate on pane IDs recorded in `build/orchestrate/state.json`; identify managed overflow tabs by their recorded tab IDs. Ignore other tabs and unmanaged agents for placement.

Run the tool from a Herdr pane (`HERDR_ENV=1`). It enforces placement, naming, model restrictions, agent flags, focus,
and width rules. Pane purposes are at most 20 characters.

```bash
scripts/orchestrate/agent.py start detectors --kind codex --model gpt-6-luna --purpose "History detectors"
scripts/orchestrate/agent.py start review --kind claude --model claude-opus-5-5 --role reviewer --purpose "Review: engine"
scripts/orchestrate/agent.py prompt detectors --brief build/briefs/detectors.md --wait --timeout 5400
scripts/orchestrate/agent.py status
scripts/orchestrate/agent.py script Validation -- scripts/orchestrate/validate-both.sh
scripts/orchestrate/agent.py layout
scripts/orchestrate/agent.py close detectors # after reviewing its package
```

Use `prompt --text` for direct instructions. `prompt --wait` prints `NAME state=<state>` and adds `report=<path>` when
the report exists. A blocked state prints the last five visible lines. `close` promotes the earliest waiting agent,
then fills a spare Main slot from `Scripts`; `close-script PURPOSE` closes a managed script pane after its result or
log is captured. Do not close an agent before its package is reviewed.

## Contracts and ownership

1. The orchestrator owns shared types, protocols, function signatures, compiling stubs, empty test classes, shared
   fixtures, and project registration. Register new Swift files with `python3 scripts/pbxproj.py add` before
   implementation begins. Build and validate the stubs, then commit them locally so implementation diffs are clear.
2. Each package owns whole files, never regions of a shared file. Composition roots, coordinators, settings screens,
   and the project file stay with the orchestrator.
3. Put shared rules in `build/briefs/_rules.md` and one brief per agent in `build/briefs/<name>.md` (git-ignored).
   Include owned files, exact contracts, behavior and thresholds, tests, compile steps, forbidden actions, and the report
   path `build/briefs/<name>.report.md`.

## Compile and verify

Compile with `scripts/agent-build.sh <agent-name> --tests` until it prints `BUILD SUCCEEDED`. The orchestrator builds
after each agent report. The script serializes builds and uses separate derived data. Its asset-catalog step can fail
in the Codex sandbox when CoreSimulator is unavailable; leave that compile to the orchestrator if needed.
`agent-build.sh` and `test.sh` share `build/agents/build.lock`; `with-lock.py` holds a kernel `flock`. The lock file
stays empty on disk after a run and has no PID-based stale state.

Agents never commit, push, stash, or reset. Keep agents idle while validation runs. They run focused XCTest on their
assigned simulator with `scripts/orchestrate/test.sh --sim <assigned-id> --name <agent>`, summarize a result bundle
or derived-data folder with `scripts/orchestrate/test-summary.py`. Derived-data lookup skips bundles without
`Info.plist`; a directly named incomplete bundle is an error. Agents never run `scripts/validate.sh`. Package, Node,
and Python tests use the commands in `build/briefs/_rules.md`. Mutation checks use `scripts/orchestrate/mutate.sh`:

```sh
scripts/orchestrate/mutate.sh --file Packages/AdaptiveTraining/Sources/Engine.swift \
  --replace 'threshold: 0.7' 'threshold: 0.8' --tests EngineTests/testThreshold
scripts/orchestrate/mutate.sh --file Sources/Feature.swift --sed 's/guard ready/guard false/' \
  --tests FeatureTests/testReady --sim <assigned-id> --name <agent>
scripts/orchestrate/mutate.sh --file Packages/AdaptiveTraining/Sources/Engine.swift \
  --patch build/mutations/remove-guard.patch --tests EngineTests/testGuard --package Packages/AdaptiveTraining
scripts/orchestrate/mutate.sh --batch build/mutations.json
```

Batch files are JSON lists with `id`, `file`, one of `replace: [old, new]`, `sed`, or `patch`, `tests`, and an
optional `package` path. XCTest runs go through `test.sh`; package runs use `swift test --package-path ... --filter`.
The tool reports `CAUGHT`, `SURVIVED`, `NOT-APPLIED`, or `BUILD-FAILED` with test counts. It restores each file
after every run and verifies the bytes with `cmp`; restore verification failure exits 3 and preserves the backup.
The mutation command holds the build lock from backup through verified restoration. `mutate.py`, `mutate.sh`,
`test.sh`, and `validate-both.sh` resolve the caller's repository with `git rev-parse --show-toplevel` and print
that root first. The orchestrator reads each package against its brief, checks that only owned files changed, and
fixes problems directly. It runs
`scripts/orchestrate/validate-both.sh` for sequential local-time and UTC validation.
Use `make notification-character-check` when content or art changed.

## Review gate

Before pushing a branch, run `scripts/orchestrate/review.sh <base>..<head> --name <branch> --brief <brief>`.
Use `WORKTREE` as head for uncommitted changes. The command writes the request and findings template; `--criteria`
overrides criteria extracted from the brief's Goal and Done sections, and `--notes` supplies test and deviation notes.
To start a read-only reviewer, add `--start sol` or `--start opus` and a unique `--purpose "Review: area"`. The
command uses the sibling `agent.py`, checks the visible model footer against the requested model, and warns on a
mismatch or unavailable footer. Reviewers are Codex Sol or Claude Opus only; never use Fable or Codex Astra. Collect
the blocking and major findings with `scripts/orchestrate/review.sh --collect <branch>`. Fix blocking and major
findings, re-validate, amend, then request one confirm-only pass. If review cannot run, record that in the PR body.

## Unattended runs

Keep a ledger of package, pane, status, branch, PR, and deviations; update it after each package and PR. Stop work on
a package after two failed fix attempts, then continue independent packages. Schedule a resume check every
30–45 minutes that reads the ledger and resumes at the first unfinished item; delete it when the run
completes. Use stacked PRs into main, validate each branch on its own, and note “Device validation pending” when no
device is connected. Never merge.

## Tool cheat sheet

- Agents and scripts: `scripts/orchestrate/agent.py start|prompt|status|layout ...`
- Focused XCTest: `scripts/orchestrate/test.sh --sim <id> --name <agent> <class>[/method]`
- Mutations: `scripts/orchestrate/mutate.sh --file <path> --replace <old> <new> --tests <selector>` or `--batch <json>`
- Reviews: `scripts/orchestrate/review.sh <base>..<head> --name <branch> --brief <path>`; collect with `--collect <branch>`
