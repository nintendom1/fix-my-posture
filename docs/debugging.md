# Developer Diagnostics Guide

`DeveloperDebugView` provides in-app diagnostic visibility:

1. **Summary Diagnostics**: View, processing duration in seconds, image dimensions, total landmark count, average confidence, app version.
2. **Measurement Breakdown**: Displays stable `MeasurementID`s, values, units, landmark types used, and confidence ratings.
3. **Raw Landmark Coordinates**: Normalized Vision coordinates `(x, y)` vs. Top-left pixel coordinates `(x, y)` and manual edit status (`MANUAL` badge).
4. **Copy Diagnostics Action**: One-tap copy to system clipboard formatted report for developer debugging.

## Workout session recordings

Workout Coach sessions can be recorded frame by frame for review and replay: Settings › About › Developer diagnostics › Workout recordings. See [Workout Session Recordings](diagnostics.md) for the recording page, markers, `make diagnostics`, the file format, and the rule that real recordings are never committed.

Adaptive training recommendations can be inspected and exported from Settings › Developer diagnostics › Adaptive training; replay an export with `make adaptive-replay`. See [Adaptive Training](adaptive-training.md#debug-view-and-export).
