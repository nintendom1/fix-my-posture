# Realtime posture correction

Open **Realtime Posture Correction** from the main menu. The front camera opens by default with a mirrored selfie preview. Stand far enough away to include your body, choose the front or side view that matches your position, and watch the skeleton and geometric measurements as you move. The overlay can be hidden and the camera can be switched. Measurements describe geometry rather than prescribing a posture or making a diagnosis.

## Implementation

- `RealtimeCorrectionView` renders the preview and overlay in identical, safe-area-respecting bounds with aspect-fit scaling. Both capture and preview use portrait rotation. Camera buffers are explicitly unmirrored; only the selfie preview and its display pose are mirrored. The analyzer always receives the original, unmirrored pixel geometry.
- `RealtimeCameraModel` owns UI and lifecycle state on the main actor. Capture events carry a generation ID; changing view/camera, leaving the screen, or backgrounding invalidates old results immediately. Permission callbacks cannot start capture while the screen or application is inactive.
- `RealtimeCameraController` configures, starts, stops, and processes capture on one serial queue. Synchronous `FramePoseEstimator` inference is limited by the persistent Feedback refresh setting (2, 5, or 10 updates per second; default 5) and late frames are discarded. No per-frame asynchronous tasks retain camera buffers. The request-generation lock cancels obsolete queued starts and suppresses obsolete results.
- All Vision requests and joint mapping remain inside `AppleVisionPoseEstimator`. Still-photo estimation uses the separate `PoseEstimator` protocol.
- Landmarks below 0.3 confidence are excluded from live geometry. Measurements below 0.5 confidence receive a visible warning and no color judgment. Reliable values use the active geometric reference profile: green is within its tolerance, amber is up to twice its tolerance, and coral is farther away. Measurements without a matching stable measurement ID rule remain neutral. These bands describe distance from a geometric reference rather than health or diagnosis.
- Live measurements appear in compact callouts beside their related body regions. Each region shows its highest-priority reliable observation, and the layout tries both sides and several vertical positions before hiding a callout that would cover the body, controls, or another callout. Hidden and low-confidence measurements remain available from Details. Opening Details pauses capture; closing it resumes capture when the view is active.
- Floating callouts use 16-point wrapping labels, 28-point values, 5-point padding, 3-point spacing, and leader lines. Candidate widths are 120, 104, and 88 points. SwiftUI content is measured at each width with the current Dynamic Type setting; long units wrap below the value. If an unshrunk numeric reading cannot fit on one line, that card is hidden and remains available in Details. Placement uses the local protected body boundary with 8-point clearance, continuous limb coverage, torso interiors, target rings, controls, and other boxes. Valid placements persist between accepted frames; boxes that cannot fit remain in Details. The same overlay appears over still-photo reports, whose taller preview gives the body and callouts more room. Detailed measurement cards use smaller 20-point labels and 30-point values. On-device checks should confirm readability from normal standing distance without obscuring full-body framing.
- Tracking loss or errors clear the last overlay and metrics. Capture interruptions pause feedback, and runtime/setup failures show an error. Returning from Settings rechecks authorization. Live frames and results are not persisted or transmitted.

## Personalized targets and directional feedback

Alignment targets are independently enabled by default. Hollow violet rings show the final personalized reference, preserving observed proportions and foot anchors; no height or physical length estimate is requested. Photo replay remains available separately and never animates target rings. Live static references run after throttling on the capture queue, skipping replay generation. Small coordinate changes under 2.5% of image width are blended by 40%; larger movements follow immediately. Reduce Motion disables blending. Targets clear on tracking loss, interruption, dismissal, camera/view changes and capture restarts.

Measured joints use the highest reliable severity among all contributing metrics, even if no callout fits. Unassessed joints and skeleton segments remain gray. Manual-edit selection and correction indicators remain available in the editor. Details explain colors, sign conventions and partial target availability. Details holds capture paused across background/foreground transitions and refresh preference changes.

Signed values are presentation-only and derive from original unmirrored pixel coordinates. Front positive means the user's right side is lower for level metrics, or upper-body displacement toward their right. Side positive means forward; face geometry on the selected side must establish the forward axis, otherwise values remain unsigned. Knee angles, stance ratios and asymmetry magnitudes remain original values. Baseline comparisons keep stored values and identify magnitude changes.

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
