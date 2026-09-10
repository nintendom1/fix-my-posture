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
2. **Preserved Segment Lengths**: Observed limb and torso bone segment lengths (e.g., hip-to-knee, knee-to-ankle, shoulder-to-hip, shoulder-to-shoulder, hip-to-hip) are strictly preserved from the input pose.
3. **Rigid Group Transformations**: Head points and facial landmarks translate and rotate as a group relative to the neck rather than repositioning facial points independently. Arms maintain their relative orientation to their respective shoulders.
4. **Independent Region Evaluation**:
   - Evaluates Head, Torso/Pelvis, and Legs regions independently based on anchor availability and confidence threshold (confidence $\ge 0.3$ or manually corrected).
   - Missing leg anchors permit upper-body reference geometry anchored to the observed pelvis/hips.
   - Unsupported regions remain unaltered and receive no correction caption.
5. **Deterministic Constrained Optimization**:
   - Operates in image pixel space.
   - Alignment rules (e.g. level shoulders/hips, vertical ear-shoulder-hip alignment) serve as soft objectives.
   - Residual segment length checks enforce that no segment deviates by more than 5% from its original observed length. If constraints are violated, invalid results or motion steps are rejected.
6. **2-Second Motion Precomputation**:
   - Interpolates intermediate constrained poses along valid geometric paths ($t \in [0.1, 1.0]$).
   - Validates segment lengths and anchor constraints at every step to prevent artificial limb stretching or distortion during Replay.

### Non-Diagnostic Illustration Notice

Alignment Reference overlays and animated replays are non-diagnostic geometric illustrations depicting structural differences between poses. They do not constitute a medical diagnosis, prescription, or prescribed exercise sequence.
