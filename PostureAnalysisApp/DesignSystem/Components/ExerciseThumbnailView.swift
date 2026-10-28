import SwiftUI

/// Decorative exercise identification. The containing row supplies the accessible exercise name.
struct ExerciseThumbnailView: View {
    let exerciseID: ExerciseID
    var cornerRadius: CGFloat = Metrics.Radius.thumbnail
    /// Optional override used by the snapshot test while the production placeholder list is empty.
    var placeholderSymbolName: String? = nil

    var resolvedPlaceholderSymbolName: String? {
        placeholderSymbolName ?? ExercisePhotography.placeholders[exerciseID]
    }

    var resolvedPhotograph: ExercisePhotography? {
        guard resolvedPlaceholderSymbolName == nil else { return nil }
        return ExercisePhotography.photograph(for: exerciseID)
    }

    var body: some View {
        GeometryReader { geometry in
            if let symbolName = resolvedPlaceholderSymbolName {
                ZStack {
                    Rectangle().fill(placeholderGradient)
                    Image(systemName: symbolName)
                        .font(.system(size: max(24, min(geometry.size.width, geometry.size.height) * 0.38),
                                      weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let photograph = resolvedPhotograph {
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

    private var placeholderGradient: LinearGradient {
        guard let gradient = ExerciseCatalog.definition(for: exerciseID)?.presentation.gradient else {
            return GradientTokens.workoutActive
        }
        return GradientTokens.linearGradient(from: gradient)
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
