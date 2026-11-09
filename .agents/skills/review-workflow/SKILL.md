---
name: review-workflow
description: Use when requesting, collecting, fixing, or confirming a read-only review of a branch or worktree change.
---

# Review Workflow

Before pushing a branch, prepare a review with `scripts/orchestrate/review.sh`. Use `WORKTREE` as the head for uncommitted changes. The command writes a request and findings template; criteria come from the brief's Goal and Done sections unless `--criteria` overrides them. Use `--notes` to include test and deviation notes.

```sh
scripts/orchestrate/review.sh <base>..<head> --name <branch> --brief <brief> --start sol --purpose "Review: engine"
scripts/orchestrate/review.sh --collect <branch>
```

Reviewer choices are Codex Sol (`--start sol`) or Claude Opus (`--start opus`). Never use Fable or Codex Astra as a reviewer. The script starts a read-only reviewer and checks its visible model footer; it warns when the footer is unavailable or mismatched.

Findings carry stable ids (`F1`, `F2`, …) and a status (`open`, `resolved`, `accepted-scope`); `--collect` counts only open ones. Give implementers just the open findings with `review.sh --findings-for <branch> --open`. After fixes, rebuild and rerun focused validation, then run `review.sh --confirm <branch>`: it sends the reviewer only the hunks changed since the last reviewed state plus the open findings, reusing the live reviewer (`--since <commit>` sets the base by hand). If review cannot run, record that in the PR body. Never merge.
