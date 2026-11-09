---
name: pr-handoff
description: Use when preparing a commit or pull request description, documenting changes, or handing off stacked branches.
---

# PR Handoff

Open commit and PR descriptions with two user-facing lines in this form:

```text
Before, <the prior user-visible limitation or behavior>.
Now, <the changed user-visible behavior and what it enables>.
```

Commit subjects use `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, or `dev:` and imperative Title Case. If prior behavior was intentional, briefly say why; if it was a bug, state what failed.

Summarize the user-facing outcome of the whole branch. Keep implementation details out of the opening unless needed to explain the outcome. Put files and technical details in `## Summary`; include `## Docs` and `## Testing` too. List changed documentation under `## Docs` and write `None` when no docs changed. Mention distinct user impacts separately only when different groups experience different behavior.

Use `gh stack` to inspect or manage stacked branches (`gh stack view`, `gh stack submit`). `gh stack submit` pushes branches and creates or updates pull requests, so use it only when authorized. Preserve the stack base relationships and validate each branch on its own. Never run `gh stack merge`; never merge a pull request.
