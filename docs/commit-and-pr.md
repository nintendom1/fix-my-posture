# Commit & PR Protocol

## Commits

Before every commit, stage the intended changes and run:

```bash
gitleaks git . --pre-commit --staged --redact --exit-code=1
```

The scan is mandatory. Commit only after it exits successfully. If Gitleaks is
not installed, install it before committing rather than bypassing the check.

* Prefix: `feat: `, `fix: `, `docs: `, `chore: `, `refactor: `, `dev: `.
* Subject: Imperative Title Case.
* Body Format:

```text
Before, <the old user-visible problem, limitation, disabled path, or fallback behavior>. <If the old behavior was intentional, briefly state why. If it was a bug or blunder, say what failed without over-explaining the implementation.>
Now, <the new user-visible behavior or capability, and what it enables for the user>.
```

## Pull Requests

* Format: Must start with the same `Before, ... Now, ...` shape used for commits.
* The PR Before/Now should summarize the product outcome of the whole branch, not retell every commit.
* Keep the opening Before/Now user-facing. Avoid helper names, hooks, files, tests, algorithms, state refs, query names, or priority-chain internals unless they are necessary to explain the user outcome.
* Describe separate user impacts only when different groups experience different behavior. Prefer one concise sentence over a role-by-role analysis.
* Technical details, commit-by-commit notes, test commands, and file changes belong in separate `Summary` or `Testing` sections, not in the opening Before/Now.

## Good PR Body Example

```text
Before, Workout Coach guided only the shoulder press, so people needed another tool to follow a different exercise.
Now, it guides six exercises and lets people save workout sets and review their history with the weights they used.

## Summary
- Added guides and rep counting for hammer curls, triceps extensions, air squats, one-arm rows, and push-ups.
- Added Saved Sets and workout history with weight tracking.
- Kept workout pose analysis on device.

## Testing
- ./scripts/validate.sh
- Manually checked a saved workout and weight entry.
```

## Bad PR Body Pattern

```text
Before, <long explanation of each hook, query, fallback path, helper, and commit>.
Now, <long explanation of the deterministic priority chain, implementation gates, refs, test mocks, and internal camera behavior>.
```

This is too implementation-heavy for the opening Before/Now. Move those details to Summary or Testing if they matter.
