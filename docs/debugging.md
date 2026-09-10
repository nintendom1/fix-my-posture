# Developer Diagnostics Guide

`DeveloperDebugView` provides in-app diagnostic visibility:

1. **Summary Diagnostics**: View, processing duration in seconds, image dimensions, total landmark count, average confidence, app version.
2. **Measurement Breakdown**: Displays stable `MeasurementID`s, values, units, landmark types used, and confidence ratings.
3. **Raw Landmark Coordinates**: Normalized Vision coordinates `(x, y)` vs. Top-left pixel coordinates `(x, y)` and manual edit status (`MANUAL` badge).
4. **Copy Diagnostics Action**: One-tap copy to system clipboard formatted report for developer debugging.
