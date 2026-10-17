import SwiftUI

struct SettingsRow: View {
    let icon: String
    let title: String
    let iconColor: Color
    var value: String? = nil
    var valueAnchor: String? = nil
    var toggle: Binding<Bool>? = nil
    var showsChevron = false
    var showsSeparator = false
    var isDisabled = false
    var action: (() -> Void)? = nil

    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        Group {
            if let toggle {
                Toggle(isOn: toggle) {
                    leadingContent
                }
                .toggleStyle(.switch)
                .tint(palette.brand)
            } else if let action, !isDisabled {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 14)
        .padding(.top, showsSeparator ? 1 : 0)
        .overlay(alignment: .top) {
            if showsSeparator {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
            }
        }
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            leadingContent
            Spacer(minLength: 8)
            if let value {
                valueLabel(value)
            }
            if showsChevron {
                Image(material: "chevron_right")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textSubtle)
            }
        }
        .contentShape(Rectangle())
    }

    private var leadingContent: some View {
        HStack(spacing: 12) {
            Image(material: icon)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func valueLabel(_ value: String) -> some View {
        let label = Text(value)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(palette.textMuted)
            .lineLimit(1)
        if let valueAnchor {
            label.designAnchor(valueAnchor)
        } else {
            label
        }
    }
}
