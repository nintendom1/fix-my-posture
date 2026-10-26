import SwiftUI

/// Decorative exercise identification. The containing row supplies the accessible exercise name.
struct ExerciseThumbnailView: View {
    let exerciseID: ExerciseID
    var cornerRadius: CGFloat = Metrics.Radius.thumbnail

    var body: some View {
        GeometryReader { geometry in
            if let photograph = ExercisePhotography.photograph(for: exerciseID) {
                let side = max(geometry.size.width, geometry.size.height)
                Image(photograph.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .offset(
                        x: (geometry.size.width - side) / 2,
                        y: (geometry.size.height - side) * verticalCropAnchor
                    )
            } else {
                // Saved routines may contain an exercise that is no longer available.
                Color.white.opacity(0.06)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    /// Wider Quick Start tiles keep heads and raised weights visible. Square tiles use the full crop.
    private var verticalCropAnchor: CGFloat {
        switch exerciseID {
        case .shoulderPress, .lateralRaise, .dumbbellRow, .dumbbellShrug: return 0
        case .airSquat: return 0.25
        case .gluteBridge: return 0.3
        default: return 0.5
        }
    }
}
