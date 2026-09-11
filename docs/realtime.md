# Realtime posture correction

Open **Realtime Posture Correction** from the main menu. The front camera opens by default with a mirrored selfie preview. Stand far enough away to include your body, choose the front or side view that matches your position, and watch the skeleton and geometric measurements as you move. The overlay can be hidden and the camera can be switched. Measurements describe geometry rather than prescribing a posture or making a diagnosis.

## Implementation

- `RealtimeCorrectionView` renders the preview and overlay in identical, safe-area-respecting bounds with aspect-fit scaling. Both capture and preview use portrait rotation. Camera buffers are explicitly unmirrored; only the selfie preview and its display pose are mirrored. The analyzer always receives the original, unmirrored pixel geometry.
- `RealtimeCameraModel` owns UI and lifecycle state on the main actor. Capture events carry a generation ID; changing view/camera, leaving the screen, or backgrounding invalidates old results immediately. Permission callbacks cannot start capture while the screen or application is inactive.
- `RealtimeCameraController` configures, starts, stops, and processes capture on one serial queue. Synchronous `FramePoseEstimator` inference is limited to 10 frames per second and late frames are discarded. No per-frame asynchronous tasks retain camera buffers. The request-generation lock cancels obsolete queued starts and suppresses obsolete results.
- All Vision requests and joint mapping remain inside `AppleVisionPoseEstimator`. Still-photo estimation uses the separate `PoseEstimator` protocol.
- Landmarks below 0.3 confidence are excluded from live geometry. Measurements below 0.5 confidence receive a visible warning. Values use neutral colors and stable measurement IDs; there is no universal numerical good/bad threshold across angles, percentages, and ratios.
- Tracking loss or errors clear the last overlay and metrics. Capture interruptions pause feedback, and runtime/setup failures show an error. Returning from Settings rechecks authorization. Live frames and results are not persisted or transmitted.

## Automated validation

Run `./scripts/validate.sh`. `RealtimeCameraTests` uses an injected capture service and permission provider to exercise permission completion after dismissal, foreground recovery, rejection of old results, interruption/failure clearing, confidence filtering, and the production mirror/aspect-fit transform. `GeometryTests` covers horizontal-line endpoint order, mirroring, vertical and coincident points, alongside existing geometry/baseline tests. Existing reference geometry tests must continue to pass.

## Physical-device acceptance checks

Simulator tests do not validate camera hardware, actual Vision detections, or preview latency. On an iPhone 15 Pro:

1. Open the feature from the menu. Grant camera permission and verify an upright mirrored selfie. Raise one arm and move toward either edge: landmarks must stay over the same joints across the preview, including near letterboxing.
2. Tilt shoulders and return to level. Values should update responsively and return near zero for a level shoulder line. Repeat with the rear camera and the supported side views; verify there is no extra horizontal flip.
3. Hide/reveal the overlay, switch cameras repeatedly, and change analysis view while moving. Old overlays and measurements must clear rather than flash results from the previous selection.
4. Leave the frame or obscure key joints. Missing/unreliable measurements should disappear, with framing guidance when no measurements remain. Check low-light confidence warnings.
5. Deny access, open Settings, grant access, and return. Also close while permission is pending. A closed screen must never start the camera after the response.
6. Background/foreground the app, lock/unlock the phone, and cause a camera interruption. Feedback must clear and recover when available. Close the screen and verify the camera privacy indicator turns off.
7. Use the live view for several minutes to assess heat and responsiveness. Verify taking/importing still photos, viewing references, and baseline history still work afterward.

These device checks remain manual; a successful simulator test run does not imply they were performed.
