# Posture Analysis Geometry Specifications

## Coordinate Systems & Axis Orientations

The application deals with three distinct coordinate frames:

1. **Vision Normalized Space**:
   - Origin: Bottom-left `(0, 0)`. Top-right is `(1.0, 1.0)`.
   - Used by Apple Vision `VNHumanBodyPoseObservation`.

2. **Image Pixel Space**:
   - Origin: Top-left `(0, 0)`. Bottom-right is `(width, height)`.
   - Used by `PostureAnalyzer` for aspect-correct angular geometry calculations and by `ReferencePoseGenerator` for reference pose calculation.
   - Conversion: `x_pixel = x_norm * width`, `y_pixel = (1.0 - y_norm) * height`.

3. **SwiftUI Container Display Space**:
   - Aspect-fit letterboxed/pillarboxed frame rect calculation handled by `CoordinateConverter.aspectFitRect(for:in:)`.
   - Ensures visual overlay points align perfectly over the scaled image regardless of screen aspect ratio.

## Aspect Distortion Prevention Rule

Calculating angles directly on normalized `(x_norm, y_norm)` coordinates on non-square photos distorts angular values (e.g. a 1:2 aspect ratio image distorts vertical displacements relative to horizontal).

`PostureAnalyzer` computes all horizontal, vertical, and joint angles using equal-scale pixel coordinates `(x_pixel, y_pixel)`.

## Alignment Reference Geometry Engine (`ReferencePoseGenerator`)

The Alignment Reference subsystem generates a whole-body reference overlay illustrating potential geometric alignment while strictly maintaining anatomical constraints.

### Key Constraints & Invariants

1. **Planted Ankles**: Ankle coordinates remain strictly fixed at their observed pixel locations.
2. **Preserved Segment Lengths**: Observed limb and torso segment lengths (e.g., hip-to-knee, knee-to-ankle, shoulder-to-hip, shoulder-to-shoulder, hip-to-hip) are preserved from the input pose within a small floating-point tolerance.
3. **Rigid Group Transformations**: Head points and facial landmarks translate and rotate as a group relative to the neck rather than repositioning facial points independently. Arms maintain their relative orientation to their respective shoulders.
4. **Independent Region Evaluation**:
   - Evaluates Head, Torso/Pelvis, and Legs regions independently based on anchor availability and confidence threshold (confidence $\ge 0.3$ or manually corrected).
   - Missing leg anchors permit upper-body reference geometry anchored to the observed pelvis/hips.
   - Unsupported regions remain unaltered and receive no correction caption.
5. **Deterministic Constrained Optimization**:
   - Operates in image pixel space.
   - Profile targets and tolerances define the desired alignment; targets already within tolerance leave that measurement unchanged.
   - Rule values use the units of their stable `MeasurementID`. Directional angle and offset targets may be signed even though report cards display absolute magnitudes.
   - Alignment rules serve as soft objectives. The generator selects the strongest feasible correction while segment lengths and planted feet take priority.
   - Residual checks reject any geometry that changes a measured segment beyond the solver's floating-point tolerance.
6. **2-Second Motion Precomputation**:
   - Starts at the measured pose and interpolates constrained poses along valid geometric paths ($t \in [0, 1.0]$).
   - Validates segment lengths and anchor constraints at every step to prevent artificial limb stretching or distortion during Replay.

### Non-Diagnostic Illustration Notice

Alignment Reference overlays and animated replays are non-diagnostic geometric illustrations depicting structural differences between poses. They do not constitute a medical diagnosis, prescription, or prescribed exercise sequence.


## Directional presentation and personalized targets

`MeasurementPresentation` supplies signed display strings without mutating `PostureMeasurement` or saved baseline values. Front level signs use right-minus-left pixel y (top-left origin). Lateral signs use upper-minus-base x projected onto the anatomically labeled left-to-right axis. Side signs project the measured upper-to-lower displacement onto reliable nose/eye-to-selected-ear x; an ambiguous face axis yields an unsigned reading. Rounded negative zero displays as `0.0`. Knee angles and stance ratios retain their original targets and precision; unsigned asymmetries remain unsigned.

`ReferencePoseGenerator.generateStaticReference` shares the final solver with replay generation but skips the 31 intermediate solves. Targets remain in original pixel coordinates until display transformation. Photo targets always use the final reference, even during replay. Live mirroring applies identically to measured joints and target rings. Missing supported regions retain the generator's partial-reference explanations.

Callout collision protection covers continuously sampled limb segments at intervals of at most 4 points with overlapping 20-point squares, plus joints and torso bounds. Every protected shape and visible target ring receives 8-point clearance. This conservative coverage may hide a callout; all readings remain available in Details.
