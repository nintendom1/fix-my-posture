---
name: mutation-checks
description: Use when proving a focused regression test catches a specific code change or guard removal and the brief requires a revert check.
---

# Mutation Checks

Use `scripts/orchestrate/mutate.sh` only for a meaningful regression test. It takes a backup, applies one mutation, runs the selected tests under the build lock, restores the file, and verifies restoration byte-for-byte. Report the resulting status and test counts.

```sh
scripts/orchestrate/mutate.sh --file Packages/AdaptiveTraining/Sources/Engine.swift --replace 'threshold: 0.7' 'threshold: 0.8' --tests EngineTests/testThreshold
scripts/orchestrate/mutate.sh --file Sources/Feature.swift --sed 's/guard ready/guard false/' --tests FeatureTests/testReady --sim <assigned-id> --name <agent>
scripts/orchestrate/mutate.sh --file Packages/AdaptiveTraining/Sources/Engine.swift --patch build/mutations/remove-guard.patch --tests EngineTests/testGuard --package Packages/AdaptiveTraining
scripts/orchestrate/mutate.sh --batch build/mutations.json
```

Batch JSON is a list of objects with `id`, `file`, one of `replace: [old, new]`, `sed`, or `patch`, `tests`, and optional `package`. XCTest mutations need the assigned simulator and agent name; package mutations use filtered `swift test`.

Interpret results as `CAUGHT`, `SURVIVED`, `NOT-APPLIED`, or `BUILD-FAILED`. `SURVIVED` means the test did not catch the mutation. If restoration verification fails, stop: exit status 3 preserves the backup for recovery. Do not run a mutation that changes an unowned file.
