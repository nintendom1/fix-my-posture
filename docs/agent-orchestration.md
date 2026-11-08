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

The user's standing preference is Codex subagents, with Claude subagents only when Codex is unavailable (the #64 run
moved copy from a planned Opus pane to Codex Sol for that reason). Never start Codex Astra; always pass an explicit `-m`.

## Pane layout and tab maintenance

Keep the orchestrator in the `Main` tab. Manage agent and long-running-script panes in the same Herdr workspace,
with **at most three side-by-side columns per tab and no vertical stacking**. Divide each tab evenly: one pane
gets 100% width, two get 50% each, and three get approximately 33.3% each (terminal-cell rounding is fine).
Never squeeze a column below 33% to make another pane fit. If the terminal is too narrow for three readable
columns, move overflow into another tab instead of forcing an unreadable layout.

**Placement priority (including existing running panes):**

1. `Main` always contains the orchestrator. Fill its other two slots with active **agents first**, then
   **long-running scripts** if slots remain. A new agent displaces a Main script to `Scripts` before occupying
   the freed slot; an agent waiting in `Agent` takes priority over any script in Main.
2. Put agents that cannot fit in Main into the `Agent` tab, retaining at most three evenly sized columns
   there. If `Agent` fills, create `Agent 2`, `Agent 3`, etc., with the same three-column limit.
3. Give every long-running script its own named pane. Examples include `./scripts/validate.sh`, build commands,
   diagnostics collection, watchers, and local servers. Put a script in an unused Main slot only when all
   higher-priority agents have been placed. Put remaining scripts in `Scripts`; when it fills, use
   `Scripts 2`, `Scripts 3`, etc. Do not bury long-running output in the orchestrator or an agent pane.
4. When a Main agent is reviewed and its pane closes, promote the earliest waiting agent from `Agent` to
   Main, then fill any remaining Main slots with scripts from `Scripts`. Preserve existing running processes
   during moves. Close a completed script pane only after its result/log is captured or reviewed.
5. Re-check and equalize column widths after creating, closing, or moving panes, and after a detected terminal
   resize (or at the next layout check). Preserve the orchestrator's focus and avoid unnecessary pane moves.
   Do not assume Herdr automatically maintains these proportions.

Use `herdr pane list`, `herdr tab list`, and `herdr pane layout --current` to inspect before changing
the layout. Herdr supports `pane split --direction right [--ratio FLOAT]`, `pane resize --direction
left|right --amount FLOAT`, and `pane move` into existing or new tabs. Move live panes, rather than
closing and restarting them:

```bash
herdr pane move "$P" --new-tab --label Agent --no-focus
herdr pane move "$P" --new-tab --label Scripts --no-focus
herdr pane move "$P" --tab "$TAB_ID" --split right --target-pane "$TARGET_PANE" --no-focus
herdr pane run "$SCRIPT_PANE" './scripts/validate.sh'
```

The first `--new-tab` command is for creating the first overflow tab of that kind; after that, target
the existing tab rather than creating duplicates. Capture pane/tab IDs from Herdr's JSON responses.
Check geometry after moving or splitting, and adjust widths to the applicable equal-share target.
Avoid changing focus: use `--no-focus`. The orchestrator pane is named `Orchestrator`; rename agent
panes immediately with `herdr pane rename <id> "<purpose>"`, at most 20 characters, named by purpose
rather than model/phase (for example `History detectors`, `Persona copy`, `Review: engine`).
Name script panes by the command's purpose (for example `Validation` or `Build`).

**Orchestration:** Confirm `HERDR_ENV=1` before using Herdr. Preserve the existing rule that agent
panes are closed only after their package is reviewed. Run only one `./scripts/validate.sh` at a
time, with agents idle; dedicating a pane does not authorize overlapping validations.

```bash
P=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane rename "$P" "History detectors"
herdr agent start detectors --kind codex --pane "$P" -- -m gpt-6-luna -c model_reasoning_effort=max -s workspace-write -a on-request
herdr agent send-keys detectors esc        # dismisses Codex's update prompt if it appears
herdr agent prompt detectors "Read build/briefs/detectors.md and do exactly what it says. Reply DONE or BLOCKED." --wait --timeout 5400000
```

Choose the initial split location only after applying the placement rules. For a new agent, move an
existing Main script to `Scripts` first when Main is full; otherwise create the agent in Main or
in the designated `Agent` overflow tab. Run the `--wait` prompt as a background command so the
orchestrator is notified when the agent settles. A `blocked` state means an approval dialog; read
it with `herdr agent read <name> --source visible` before answering.

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
