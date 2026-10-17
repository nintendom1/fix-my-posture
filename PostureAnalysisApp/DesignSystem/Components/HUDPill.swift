import SwiftUI

/// State instruction shown above the camera preview.
struct HUDPill: View {
    let icon: String
    let message: String
    let tint: Color
    var isTall = false
    var horizontalPadding: CGFloat = 17.4

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(material: icon)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 20, height: 28)

            Text(message)
                .font(.system(size: 15.2, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, isTall ? 11 : 8)
        .frame(maxWidth: 350, alignment: .leading)
        .frame(minHeight: 46.5)
        .background(Color(hex: 0x14101E, alpha: 0.75), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.9), lineWidth: 1.5))
        .shadow(color: tint.opacity(0.16), radius: 18)
        .accessibilityElement(children: .combine)
    }
}
