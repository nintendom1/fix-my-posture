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
* Describe Traveler/Follower impact only when the roles experience different behavior. Prefer one concise sentence over a full role-by-role analysis.
* Technical details, commit-by-commit notes, test commands, and file changes belong in separate `Summary` or `Testing` sections, not in the opening Before/Now.

## Good PR Body Example

```text
Before, Travelers and Followers opened the app to the Seattle fallback even when the trip had better location context available. This made the map feel disconnected from the current trip unless the user manually centered it.
Now, Travelers open near their current location when permission is available, while Followers open near the Traveler's live shared location or the most recent valid pin. The map starts closer to the trip automatically, without forcing users to tap center after launch.

## Summary
- Added launch-centering behavior for Traveler and Follower map views.
- Preserved manual centering and follow-mode behavior after launch.
- For Travelers, fire a single
navigator.geolocation.getCurrentPosition at mount that is independent
of the Live pill, so on the native app the map can jump to your current
fix without you having to enable sharing
- Followers get their most recent map pin if Traveler GPS is not live.

## Testing
- npm run validate
- Manually verified launch behavior with location permission on and off.
```

## Bad PR Body Pattern

```text
Before, <long explanation of each hook, query, fallback path, helper, and commit>.
Now, <long explanation of the deterministic priority chain, implementation gates, refs, test mocks, and internal camera behavior>.
```

This is too implementation-heavy for the opening Before/Now. Move those details to Summary or Testing if they matter.
