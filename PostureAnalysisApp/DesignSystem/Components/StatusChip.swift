import SwiftUI

struct StatusChip: View {
    let title: String
    let icon: String
    var tint: Color = ColorTokens.palette().success

    var body: some View {
        HStack(spacing: Metrics.Spacing.xSmall) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Metrics.Spacing.small + 2)
        .padding(.vertical, 4)
        .frame(minHeight: Metrics.Size.statusChip)
        .background(ColorTokens.palette().backgroundPrimary.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Status Chips") {
    VStack(alignment: .leading, spacing: Metrics.Spacing.small) {
        StatusChip(title: "Listening · say “pause”", icon: "mic.fill", tint: ColorTokens.palette().success)
        StatusChip(title: "Voice commands off", icon: "mic.slash.fill", tint: Color(hex: 0xFF9AA6))
    }
    .padding()
    .background(ColorTokens.palette().backgroundPrimary)
}
