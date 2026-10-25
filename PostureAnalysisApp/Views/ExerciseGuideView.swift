import SwiftUI

/// "How to" sheet: an animated demonstration, steps highlighted in sync, and an optional read-aloud.
struct ExerciseGuideView: View {
    let exercise: ExerciseDefinition
    /// Shows "Start Workout" before the coach has started, "Back to Workout" afterwards.
    let hasStarted: Bool
    let isSpeaking: Bool
    let onReadAloud: (() -> Void)?
    let onStopReading: (() -> Void)?
    let onShowVoiceCommands: (() -> Void)?
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 28

    private var guide: ExerciseGuide { exercise.guide }
    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.displayName)
                            .textStyle(.title2)
                            .foregroundStyle(palette.textPrimary)
                        Text(guide.summary)
                            .textStyle(.body)
                            .foregroundStyle(palette.textSecondary)
                    }

                    if reduceMotion {
                        staticDemonstration
                        steps(activeIndex: nil)
                    } else {
                        TimelineView(.animation) { timeline in
                            let sample = guide.motion.sample(at: timeline.date.timeIntervalSinceReferenceDate)
                            VStack(alignment: .leading, spacing: 16) {
                                animatedDemonstration(sample)
                                steps(activeIndex: sample.stepIndex)
                            }
                        }
                    }

                    if let tip = guide.tip {
                        Label(tip, systemImage: "lightbulb")
                            .textStyle(.caption1)
                            .foregroundStyle(palette.warning)
                    }
                    voiceCommandsRow
                    Text("The coach counts reps from the camera's view of your arms. It doesn't judge form or safety.")
                        .textStyle(.caption1)
                        .foregroundStyle(palette.textMuted)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(palette.backgroundPrimary)

            VStack(spacing: 10) {
                PrimaryButton(title: hasStarted ? "Back to Workout" : "Start Workout",
                              icon: hasStarted ? "arrow.uturn.backward" : "play.fill",
                              action: onDone)
                .accessibilityIdentifier("exerciseGuideDoneButton")

                if let readingAction = isSpeaking ? onStopReading : onReadAloud {
                    CapsuleButton(title: isSpeaking ? "Stop Reading" : "Read Aloud",
                                  icon: isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
                                  tint: palette.tabActive,
                                  action: readingAction)
                    .accessibilityIdentifier("exerciseGuideReadAloudButton")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(hex: 0x1A1526))
        }
        .background(palette.backgroundPrimary)
        .environment(\.colorScheme, .dark)
    }

    private func animatedDemonstration(_ sample: ArmMotionSample) -> some View {
        VStack(spacing: 6) {
            ExerciseDemoFigureView(angles: sample.angles, forearmPlane: guide.motion.forearmPlane, cameraView: exercise.cameraView,
                                   holdsDumbbells: guide.motion.holdsDumbbells, legs: sample.legs,
                                   torsoPitch: guide.motion.torsoPitch, shape: sample.shape,
                                   figureBounds: ExerciseDemoFigureView.bounds(for: guide.motion,
                                                                               cameraView: exercise.cameraView))
                .frame(maxWidth: .infinity)
                .frame(height: 240)
            Text(guide.steps.indices.contains(sample.stepIndex) ? guide.steps[sample.stepIndex].title : "")
                .textStyle(.headline)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(demonstrationLabel)
    }

    /// Reduce Motion: the start and top positions side by side.
    private var staticDemonstration: some View {
        HStack(alignment: .center, spacing: 8) {
            labeledFigure(guide.motion.startSample, title: guide.steps.first?.title ?? "Start")
            Image(systemName: "arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            labeledFigure(guide.motion.topSample, title: "Top")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(demonstrationLabel)
    }

    private func labeledFigure(_ sample: ArmMotionSample, title: String) -> some View {
        VStack(spacing: 4) {
            ExerciseDemoFigureView(angles: sample.angles, forearmPlane: guide.motion.forearmPlane, cameraView: exercise.cameraView,
                                   holdsDumbbells: guide.motion.holdsDumbbells, legs: sample.legs,
                                   torsoPitch: guide.motion.torsoPitch, shape: sample.shape,
                                   figureBounds: ExerciseDemoFigureView.bounds(for: guide.motion, cameraView: exercise.cameraView))
                .frame(height: 200)
            Text(title)
                .textStyle(.headline)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func steps(activeIndex: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                let isActive = index == activeIndex
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .textStyle(.headline)
                        .monospacedDigit()
                        .frame(width: badgeSize, height: badgeSize)
                        .background(Circle().fill(isActive ? palette.brand : Color.white.opacity(0.08)))
                        .foregroundStyle(isActive ? .white : palette.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .textStyle(.headline)
                            .foregroundStyle(palette.textPrimary)
                        Text(step.detail)
                            .textStyle(.body)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? palette.brand.opacity(0.14) : palette.backgroundCard))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isActive ? palette.tabActive.opacity(0.25) : palette.borderCard, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var voiceCommandsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Voice commands: say \u{201C}what can I say\u{201D} anytime.", systemImage: "mic")
                .textStyle(.body)
                .foregroundStyle(palette.textPrimary)
            if let onShowVoiceCommands {
                Button("Show Voice Commands", action: onShowVoiceCommands)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.tabActive)
                    .accessibilityIdentifier("exerciseGuideVoiceCommandsButton")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(palette.borderCard, lineWidth: 1))
    }

    private var demonstrationLabel: String {
        "Animated figure demonstrating the \(exercise.spokenName): " + guide.steps.map(\.detail).joined(separator: " ")
    }
}
