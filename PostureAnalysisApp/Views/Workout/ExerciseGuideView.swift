import SwiftUI

/// "How to" sheet: an animated demonstration, steps highlighted in sync, and an optional read-aloud.
struct ExerciseGuideView: View {
    let exercise: ExerciseDefinition
    /// Shows "Start Workout" before the coach has started, "Back to Workout" afterwards.
    let hasStarted: Bool
    let isSpeaking: Bool
    let onReadAloud: () -> Void
    let onStopReading: () -> Void
    let onShowVoiceCommands: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 28

    private var guide: ExerciseGuide { exercise.guide }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.displayName)
                            .font(.title2.bold())
                        Text(guide.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    voiceCommandsRow
                    Text("The coach counts reps from the camera's view of your arms. It doesn't judge form or safety.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }

            VStack(spacing: 10) {
                Button(action: onDone) {
                    Text(hasStarted ? "Back to Workout" : "Start Workout")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("exerciseGuideDoneButton")

                Button(action: isSpeaking ? onStopReading : onReadAloud) {
                    Label(isSpeaking ? "Stop Reading" : "Read Aloud",
                          systemImage: isSpeaking ? "stop.circle" : "speaker.wave.2")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("exerciseGuideReadAloudButton")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func animatedDemonstration(_ sample: ArmMotionSample) -> some View {
        VStack(spacing: 6) {
            ExerciseDemoFigureView(angles: sample.angles, forearmPlane: guide.motion.forearmPlane, cameraView: exercise.cameraView)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
            Text(guide.steps.indices.contains(sample.stepIndex) ? guide.steps[sample.stepIndex].title : "")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(demonstrationLabel)
    }

    /// Reduce Motion: the start and top positions side by side.
    private var staticDemonstration: some View {
        HStack(alignment: .center, spacing: 8) {
            labeledFigure(guide.motion.startAngles, title: guide.steps.first?.title ?? "Start")
            Image(systemName: "arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            labeledFigure(guide.motion.topAngles, title: "Top")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(demonstrationLabel)
    }

    private func labeledFigure(_ angles: ArmAngles, title: String) -> some View {
        VStack(spacing: 4) {
            ExerciseDemoFigureView(angles: angles, forearmPlane: guide.motion.forearmPlane, cameraView: exercise.cameraView)
                .frame(height: 200)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func steps(activeIndex: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                let isActive = index == activeIndex
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: badgeSize, height: badgeSize)
                        .background(Circle().fill(isActive ? Color.accentColor : Color.secondary.opacity(0.2)))
                        .foregroundStyle(isActive ? .white : .primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.headline)
                        Text(step.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var voiceCommandsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Voice commands: say \u{201C}what can I say\u{201D} anytime.", systemImage: "mic")
                .font(.subheadline)
            Button("Show Voice Commands", action: onShowVoiceCommands)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("exerciseGuideVoiceCommandsButton")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
    }

    private var demonstrationLabel: String {
        "Animated figure demonstrating the \(exercise.spokenName): " + guide.steps.map(\.detail).joined(separator: " ")
    }
}
