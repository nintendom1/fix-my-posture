import SwiftUI

struct WorkoutCompleteScreen: View {
    let viewModel: WorkoutCompleteViewModel
    let onDone: () -> Void

    private let palette = ColorTokens.palette()

    var body: some View {
        ZStack {
            AuraBackground(tab: .complete)

            ScrollView {
                VStack(spacing: 18) {
                    header
                    successHero
                    metricGroup
                    exerciseRows
                    doneButton
                    historyButton
                }
                .padding(.horizontal, Metrics.Spacing.screenMargin)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.backgroundPrimary)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: finish) {
                Image(material: "close")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("completeCloseButton")
            .designAnchor("complete.close")
        }
        .frame(height: 44)
    }

    private var successHero: some View {
        VStack(spacing: 10) {
            Image(material: "check_circle")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: 0x063A26))
                .frame(width: 120, height: 120)
                .background(GradientTokens.success, in: Circle())
                .shadow(color: palette.success.opacity(0.35), radius: 22)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .designAnchor("complete.check")
                .accessibilityHidden(true)

            Text(viewModel.state.title)
                .font(.system(size: 31, weight: .black, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .designAnchor("complete.title")
                .padding(.top, 16)

            Text(viewModel.state.subtitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0xCFE9DD))
                .multilineTextAlignment(.center)
                .designAnchor("complete.subtitle")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var metricGroup: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.state.stats.metrics) { metric in
                VStack(spacing: 2) {
                    Text(metric.value)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(metric.title)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, -2)
        .designAnchor("complete.stats")
        .accessibilityElement(children: .combine)
    }

    private var exerciseRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.state.stats.exerciseRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                        .padding(.leading, 32)
                }
                HStack(spacing: 10) {
                    Image(material: "check_circle")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.success)
                        .accessibilityHidden(true)
                    Text(row.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.detail)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(minHeight: 52)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .designAnchor("complete.exercises")
    }

    private var doneButton: some View {
        Button(action: finish) {
            Text("Done")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: 0x063A26))
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.Size.primaryCTA)
                .background(GradientTokens.success, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workoutCompleteDoneButton")
        .designAnchor("complete.done")
    }

    private var historyButton: some View {
        Button {
            onDone()
            viewModel.viewHistory()
        } label: {
            Text("View in history")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.tabActive)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .contentShape(Rectangle())
                .designAnchor("complete.history")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workoutCompleteHistoryButton")
        .padding(.top, -4)
    }

    private func finish() {
        onDone()
        viewModel.done()
    }
}

private extension WorkoutCompletionStats.ExerciseRow {
    var detail: String {
        if outcome == .skipped, setCount == 0 { return "Skipped" }
        var parts = ["\(setCount) \(setCount == 1 ? "set" : "sets")", amountLabel]
        if let weightLabel { parts.append(weightLabel) }
        if outcome == .skipped { parts.append("Skipped") }
        return parts.joined(separator: " · ")
    }
}
