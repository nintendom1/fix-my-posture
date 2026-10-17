import SwiftUI

/// A 44-point camera HUD control with the design's muted and disabled states.
struct HUDIconButton: View {
    let icon: String
    let label: String
    var isOff = false
    var isSelected = false
    var isEnabled = true
    var backgroundTint: Color = Color(hex: 0x14101E, alpha: 0.62)
    var iconSize: CGFloat = 22
    var accessibilityHint = ""
    var accessibilityIdentifier: String?
    let action: () -> Void

    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        Button(action: action) {
            Image(material: icon)
                .font(.system(size: iconSize, weight: .bold, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .frame(width: Metrics.Size.hudIconButton, height: Metrics.Size.hudIconButton)
                .background(isOff ? palette.hudToggleOff : backgroundTint, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(isSelected ? 0.28 : 0), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier ?? label)
    }
}
