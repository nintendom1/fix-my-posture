# Posture Analysis Geometry Specifications

## Coordinate Systems & Axis Orientations

The application deals with three distinct coordinate frames:

1. **Vision Normalized Space**:
   - Origin: Bottom-left `(0, 0)`. Top-right is `(1.0, 1.0)`.
   - Used by Apple Vision `VNHumanBodyPoseObservation`.

2. **Image Pixel Space**:
   - Origin: Top-left `(0, 0)`. Bottom-right is `(width, height)`.
   - Used by `PostureAnalyzer` for aspect-correct angular geometry calculations.
   - Conversion: `x_pixel = x_norm * width`, `y_pixel = (1.0 - y_norm) * height`.

3. **SwiftUI Container Display Space**:
   - Aspect-fit letterboxed/pillarboxed frame rect calculation handled by `CoordinateConverter.aspectFitRect(for:in:)`.
   - Ensures visual overlay points align perfectly over the scaled image regardless of screen aspect ratio.

## Aspect Distortion Prevention Rule

Calculating angles directly on normalized `(x_norm, y_norm)` coordinates on non-square photos distorts angular values (e.g. a 1:2 aspect ratio image distorts vertical displacements relative to horizontal).

`PostureAnalyzer` computes all horizontal, vertical, and joint angles using equal-scale pixel coordinates `(x_pixel, y_pixel)`.
