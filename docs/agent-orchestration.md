# Agent orchestration on herdr

How an orchestrating agent splits a large change across cheaper agents running in herdr panes, in one shared working
tree. Written from the #64 Extra Personable run. Read this only when you are orchestrating other agents.

## Roles and model routing

| Role | Model | Owns |
|---|---|---|
| Orchestrator | Opus (or Fable) in the user's pane | Contracts, stubs, project registration, briefs, integration, review, validation, git, PRs |
| Implementer | Codex `gpt-6-luna`, `model_reasoning_effort=max` | One package of whole files with a crisp spec and its tests |
| Copy writer | Codex `gpt-6.1-sol`, effort high | User-facing wording in a content file, against a voice guide |
| Reviewer | Claude Fable, read-only (`--permission-mode plan`) | Findings on a local commit before it is pushed |

Prefer Codex agents for implementation and copy; use Claude agents only when Codex is unavailable. Never start Codex
Astra; always pass an explicit `-m`.

## Panes

- Confirm `HERDR_ENV=1`. Split right from the orchestrator pane for the first agent, then split the newest right-hand pane
  down so columns stay readable. At most three agent panes at once. Keep focus in the orchestrator pane (`--no-focus`).
- Name every pane immediately: `herdr pane rename <id> "<purpose>"`, at most 20 characters, named by purpose, without the
  model or phase (for example "History detectors", "Persona copy", "Review: engine"). The orchestrator pane is
  "Orchestrator".
- Close a pane once its package is reviewed.

```bash
P=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane rename "$P" "History detectors"
herdr agent start detectors --kind codex --pane "$P" -- -m gpt-6-luna -c model_reasoning_effort=max -s workspace-write -a on-request
herdr agent send-keys detectors esc        # dismisses Codex's update prompt if it appears
herdr agent prompt detectors "Read build/briefs/detectors.md and do exactly what it says. Reply DONE or BLOCKED." --wait --timeout 5400000
```

Run the `--wait` prompt as a background command so the orchestrator is notified when the agent settles. A `blocked`
state means an approval dialog; read it with `herdr agent read <name> --source visible` before answering.

## Contracts first

1. The orchestrator alone writes the contracts: shared types, protocols, function signatures, and compiling stubs for
   every file an agent will touch, plus empty test classes and shared fixtures.
2. Register every new Swift file with `python3 scripts/pbxproj.py add` before any agent starts. Agents never edit
   `project.pbxproj`.
3. Build and run `./scripts/validate.sh` on the stubs, then commit them locally so each agent's work shows up as a diff.

Parallel work on an unsettled contract is the most expensive failure mode. If an agent needs a contract change, it asks
in its report; the orchestrator decides.

## Ownership and briefs

- A package owns whole files, never regions of a file. Shared files (composition root, coordinators, settings screens,
  the project file) belong to the orchestrator.
- Put shared rules in `build/briefs/_rules.md` and one brief per agent in `build/briefs/<name>.md` (git-ignored):
  goal, owned files, contracts consumed (exact signatures), behavior spec with every threshold, tests to write, how to
  compile, what is forbidden, and the report to write (`build/briefs/<name>.report.md`).
- Agents never commit, push, stash, reset, or run tests. The simulator is shared and the Codex sandbox cannot reach
  CoreSimulator.

## Compile checks

`scripts/agent-build.sh <agent-name> [--tests]` serializes builds with a lock (reclaimed if its process died), uses a
separate derived-data folder per agent, and prints only errors. Inside the Codex sandbox the asset-catalog step fails
for lack of CoreSimulator; the script says so, and the agent may ask for approval to run it outside the sandbox or
leave the compile to the orchestrator. The orchestrator builds after each agent reports.

## Review and verification

- Do not trust "validation passed". Read each package against its brief, run its tests yourself, and run one mutation
  check per package (change a threshold or remove a guard; a test must fail, then restore the file).
- After an agent reports, `git status --porcelain` must list only its owned files.
- Fix problems yourself instead of sending more rounds to the agent.
- One `./scripts/validate.sh` at a time, with every agent idle. Before pushing, also run
  `TEST_RUNNER_TZ=UTC ./scripts/validate.sh` (CI runs in UTC) and `make notification-character-check` when content or art changed.

## Fable review gate

Before pushing each PR branch: commit locally, write `build/reviews/<branch>.request.md` (scope, acceptance criteria
claimed, tests, deviations), start a read-only Fable pane named "Review: <area>", and ask it to write findings to
`build/reviews/<branch>.findings.md` ranked by severity. Fix blocking and major findings, re-validate, amend, and ask for
one confirm-only pass. If the reviewer cannot run, record "Fable review skipped" in the PR body.

## Unattended runs

- Keep a ledger memory (package, pane, status, branch, PR, deviations) and update it after every package and PR.
- Schedule a resume check about every 30–45 minutes that reads the ledger and continues from the first unfinished item;
  delete it when the run completes.
- Stacked PRs into main, each validated on its own, with "Device validation pending" in the body when no device is
  connected. Never merge.
- Two failed fix attempts on the same test means stop that package, record it, and continue with independent work.
