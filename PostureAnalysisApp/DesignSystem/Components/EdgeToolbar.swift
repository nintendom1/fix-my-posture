import SwiftUI

/// The five one-tap controls on the camera's right edge, plus a reveal target when collapsed.
struct EdgeToolbar: View {
    let isVisible: Bool
    let canRestartSet: Bool
    let canAdvanceSet: Bool
    let canSkipExercise: Bool
    let canChangeExercise: Bool
    let showsMeasurements: Bool
    let onAction: (WorkoutCameraControl) -> Void
    let onReveal: () -> Void

    var body: some View {
        Group {
            if isVisible {
                VStack(spacing: 10) {
                    item("menu_book", label: "Exercise guide", control: .exerciseGuide)
                    item("restart_alt", label: "Restart set", control: .restartSet, enabled: canRestartSet)
                    nextSetItem
                    item("swap_horiz", label: "Change exercise", control: .changeExercise, enabled: canChangeExercise)
                    item("straighten",
                         label: showsMeasurements ? "Hide measurements" : "Show measurements",
                         control: .showMeasurements,
                         selected: showsMeasurements)
                }
                .transition(.opacity)
            } else {
                Button(action: onReveal) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .frame(width: 28, height: 56)
                        .background(Color.black.opacity(0.65), in: UnevenRoundedRectangle(
                            topLeadingRadius: 14, bottomLeadingRadius: 14,
                            bottomTrailingRadius: 0, topTrailingRadius: 0
                        ))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show workout controls")
                .transition(.opacity)
            }
        }
        .frame(width: isVisible ? Metrics.Size.hudIconButton : 28)
        .accessibilityIdentifier("workoutEdgeToolbar")
    }

    private func item(_ icon: String, label: String, control: WorkoutCameraControl,
                      enabled: Bool = true, selected: Bool = false) -> some View {
        HUDIconButton(icon: icon,
                      label: label,
                      isSelected: selected,
                      isEnabled: enabled,
                      backgroundTint: Color(hex: 0x14101E, alpha: 0.62),
                      accessibilityIdentifier: "workoutToolbar.\(label.lowercased().replacingOccurrences(of: " ", with: "_"))") {
            onAction(control)
        }
    }

    private var nextSetItem: some View {
        HUDIconButton(icon: "skip_next",
                      label: "Next set",
                      isEnabled: canAdvanceSet,
                      backgroundTint: Color(hex: 0x14101E, alpha: 0.62),
                      accessibilityIdentifier: "workoutToolbar.next_set") {
            onAction(.nextSet)
        }
        .contextMenu {
            if canSkipExercise {
                Button { onAction(.skipExercise) } label: {
                    Label("Skip to Next Exercise", systemImage: "forward.fill")
                }
            }
        }
    }
}
