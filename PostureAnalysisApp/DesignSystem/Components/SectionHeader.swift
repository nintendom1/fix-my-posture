import SwiftUI

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .textStyle(.title2)
                .foregroundStyle(ColorTokens.palette().textPrimary)

            Spacer(minLength: Metrics.Spacing.small)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().tabActive)
                        .frame(minHeight: Metrics.Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .designAnchor("component.sectionHeader.action")
            }
        }
        .frame(maxWidth: .infinity, minHeight: Metrics.Size.tapTarget, alignment: .leading)
    }
}

#Preview("Section Header") {
    ZStack {
        ColorTokens.palette().backgroundPrimary.ignoresSafeArea()
        SectionHeader(title: "Quick Start", actionTitle: "All Exercises", action: {})
            .padding(.horizontal, Metrics.Spacing.screenMargin)
    }
}
