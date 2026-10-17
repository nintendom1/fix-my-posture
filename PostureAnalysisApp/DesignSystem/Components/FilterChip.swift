import SwiftUI

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(isSelected ? ColorTokens.palette().textPrimary : ColorTokens.palette().filterUnselectedBackground)
                    .frame(height: Metrics.Size.filterChipVisual)
                    .designAnchor("component.filterChip.visual")

                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSelected ? ColorTokens.palette().filterSelectedText : ColorTokens.palette().filterUnselectedText)
                    .padding(.horizontal, Metrics.Spacing.medium + 2)
            }
            .frame(minHeight: Metrics.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Filter Chips") {
    HStack(spacing: Metrics.Spacing.small) {
        FilterChip(title: "All", isSelected: true, action: {})
        FilterChip(title: "Upper Body", isSelected: false, action: {})
    }
    .padding()
    .background(ColorTokens.palette().backgroundPrimary)
}
