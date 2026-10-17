#if DEBUG
import SwiftUI

struct DesignSystemGallery: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.Spacing.small), count: 6)

    var body: some View {
        ZStack {
            AuraBackground(tab: .train)

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Spacing.xLarge) {
                    Text("Design System")
                        .textStyle(.largeTitle)
                        .foregroundStyle(ColorTokens.palette().textPrimary)

                    colorTokens
                    gradients
                    typography
                    icons
                    components
                }
                .padding(Metrics.Spacing.screenMargin)
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.motionPolicy, .reduced)
    }

    private var colorTokens: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
            sectionTitle("Color tokens")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.Spacing.small), count: 3), spacing: Metrics.Spacing.medium) {
                ForEach(Array(tokenSwatches.enumerated()), id: \.offset) { _, token in
                    VStack(alignment: .leading, spacing: Metrics.Spacing.xSmall) {
                        RoundedRectangle(cornerRadius: Metrics.Radius.thumbnail)
                            .fill(token.color)
                            .frame(height: 42)
                            .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.thumbnail).strokeBorder(Color.white.opacity(0.12)))
                        Text(token.name)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(ColorTokens.palette().textSecondary)
                    }
                }
            }
        }
    }

    private var gradients: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
            sectionTitle("Gradients")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Metrics.Spacing.small) {
                gradientSwatch("train.hero", gradient: GradientTokens.trainHero)
                gradientSwatch("workout.active", gradient: GradientTokens.workoutActive)
                gradientSwatch("progress", gradient: GradientTokens.progress)
                gradientSwatch("posture", gradient: GradientTokens.posture)
                gradientSwatch("success", gradient: GradientTokens.success)
                gradientSwatch("rest", gradient: GradientTokens.rest)
            }
        }
    }

    private var typography: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
            sectionTitle("Typography")
            VStack(alignment: .leading, spacing: Metrics.Spacing.small) {
                ForEach(Typography.Style.allCases, id: \.self) { style in
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(describing: style))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(ColorTokens.palette().textMuted)
                            .frame(width: 96, alignment: .leading)
                        Text(sample(for: style))
                            .textStyle(style)
                            .foregroundStyle(ColorTokens.palette().textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    private var icons: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
            sectionTitle("Material → SF Symbols (60)")
            LazyVGrid(columns: columns, spacing: Metrics.Spacing.medium) {
                ForEach(IconMap.materialToSFSymbol.keys.sorted(), id: \.self) { name in
                    VStack(spacing: Metrics.Spacing.xSmall) {
                        Image(material: name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(ColorTokens.palette().tabActive)
                            .frame(height: 24)
                        Text(name)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(ColorTokens.palette().textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                }
            }
        }
    }

    private var components: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.large) {
            sectionTitle("Components")
            PrimaryButton(title: "Start Exercise", icon: "play.fill", action: {})
            PrimaryButton(title: "Start Routine", icon: "play.fill", variant: .white, size: .sticky, action: {})
            HStack(spacing: Metrics.Spacing.small) {
                CapsuleButton(title: "How to Do It", icon: "info.circle", action: {})
                FilterChip(title: "All", isSelected: true, action: {})
                FilterChip(title: "Upper", isSelected: false, action: {})
            }
            StatusChip(title: "Listening · say “pause”", icon: "mic.fill", tint: ColorTokens.palette().success)
            StatusChip(title: "Voice commands off", icon: "mic.slash.fill", tint: Color(hex: 0xFF9AA6))
            SectionHeader(title: "Quick Start", actionTitle: "All Exercises", action: {})
            ProgressBar(progress: 0.65)
            EmptyStateTile(title: "No sets yet", message: "Save a routine to get started.", icon: "dumbbell.fill")
        }
    }

    private var tokenSwatches: [(name: String, color: Color)] {
        let palette = ColorTokens.palette()
        return [
            ("brand", palette.brand), ("accent", palette.accent), ("success", palette.success),
            ("warning", palette.warning), ("danger", palette.danger), ("rest/info", palette.restInfo),
            ("bg.primary", palette.backgroundPrimary), ("bg.card", palette.backgroundCard),
            ("border.card", palette.borderCard), ("text.primary", palette.textPrimary),
            ("text.secondary", palette.textSecondary), ("text.muted", palette.textMuted),
            ("text.subtle", palette.textSubtle), ("tab.active", palette.tabActive),
            ("tab.posture", palette.tabPostureActive), ("tab.inactive", palette.tabInactive),
            ("HUD toggle off", palette.hudToggleOff)
        ]
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .textStyle(.eyebrow)
            .foregroundStyle(ColorTokens.palette().textMuted)
    }

    private func gradientSwatch(_ title: String, gradient: LinearGradient) -> some View {
        RoundedRectangle(cornerRadius: Metrics.Radius.thumbnail)
            .fill(gradient)
            .frame(height: 54)
            .overlay(alignment: .leading) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Metrics.Spacing.small)
            }
    }

    private func sample(for style: Typography.Style) -> String {
        switch style {
        case .largeTitle: return "Train"
        case .title: return "Shoulder Press"
        case .title2: return "Quick Start"
        case .headline: return "Workout complete"
        case .body: return "Build a steady routine"
        case .caption1: return "Last workout · Wednesday"
        case .caption2: return "2 sets × 10 reps"
        case .eyebrow: return "READY TO TRAIN?"
        case .repCounter: return "08"
        }
    }
}

#Preview("Design System Gallery") {
    DesignSystemGallery()
}
#endif
