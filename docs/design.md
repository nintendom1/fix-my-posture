# Design layout gate

`make design-reference` extracts the 21 `#t2` frames from the untracked local bundle, renders them in Playwright WebKit, and commits updated `Design/Metrics/design-metrics.json`. It also writes reference PNGs and a Google Fonts cache under ignored `build/design/`. The bundle must be present at `fix-my-posture-mobile-app-design/project/`; it stays local and is never modified or committed.

`scripts/design/anchors.mjs` maps each stable frame ID to text or structural locators. Anchor names use `<screen>.<element>` (for example, `train.hero.cta` and `camera.repCount`). `box` anchors tolerate 1 pt and `text` anchors tolerate 2 pt. A screen implementation adds a SwiftUI fixture, attaches `.designAnchor("same.name")` to its elements, adds the frame ID to the fixture set, and removes it from `PendingFrames`.

`make design-snapshots` runs the snapshot harness with a fixed 390×844 window and writes images to `build/design/actual/`. `make design-diff` writes heatmaps, side-by-side images, and a mismatch summary to `build/design/diff/`; it masks the status bar, rounded corners, the native tab-bar strip, camera preview, and progress charts. Diff output is a local review aid, not a CI pass/fail gate. Use `swift scripts/design/diff.swift --tolerance 2` to allow two levels of per-channel pixel variation.

Run `make design-check` to regenerate references and metrics, run the design harness, and produce the available pixel diffs.
