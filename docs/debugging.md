# Developer diagnostics

`DeveloperDebugView` shows the posture view, processing time, image dimensions, landmark count, average confidence, app version, and each measurement's stable `MeasurementID`, value, unit, used landmarks, and confidence. Raw landmark rows show normalized Vision and top-left pixel coordinates, confidence, and a `MANUAL` badge for edited points. **Copy Diagnostics Summary** copies the date, view, image and processing summary, and measurement rows to the clipboard.

Workout recordings are managed from **Settings → Developer diagnostics → Workout recordings**. See [Workout Session Recordings](diagnostics.md) for recording, markers, `make diagnostics`, and replay.

Adaptive training snapshots and exports are in **Settings → Developer diagnostics → Adaptive training**. Replay an export with `make adaptive-replay`; see [Adaptive Training](adaptive-training.md#debug-view-and-export).
