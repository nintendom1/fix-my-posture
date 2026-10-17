import SwiftUI

/// An exercise's name and its sets × reps target.
struct ExerciseSummaryLabel: View {
    let exercise: ExerciseDefinition
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.displayName)
                .textStyle(.headline)
                .foregroundStyle(ColorTokens.palette().textPrimary)
            Text(detail ?? "\(exercise.sets) sets × \(exercise.targetLabel) reps")
                .textStyle(.caption1)
                .foregroundStyle(ColorTokens.palette().textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Mid-workout exercise chooser over the camera, for "change exercise". Picking one switches;
/// Cancel returns to where you were.
struct ExerciseChooserOverlay: View {
    let session: WorkoutSession
    let voiceActive: Bool
    let onSelect: (ExerciseID) -> Void
    let onCancel: () -> Void

    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        VStack(spacing: 12) {
            Text("Choose an exercise")
                .textStyle(.title2)
                .foregroundStyle(palette.textPrimary)
            if let plan = session.plan, session.isFollowingPlan {
                Text("Choosing another exercise leaves \(plan.name); the rest of it is skipped. Cancel to stay in it.")
                    .textStyle(.caption1)
                    .foregroundStyle(palette.textMuted)
                    .multilineTextAlignment(.center)
            }
            ForEach(session.exercises) { exercise in
                Button { onSelect(exercise.id) } label: {
                    HStack {
                        ExerciseSummaryLabel(exercise: exercise, detail: detail(for: exercise))
                        Spacer()
                        if exercise.id == session.exerciseID {
                            Image(material: "check_circle")
                                .foregroundStyle(palette.success)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: Metrics.Radius.row, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.row, style: .continuous)
                        .strokeBorder(exercise.id == session.exerciseID ? palette.tabActive.opacity(0.3) : palette.borderCard, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.Radius.row, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chooseExercise_\(exercise.id.rawValue)")
            }
            if voiceActive {
                Text("Say an exercise name, or \u{201C}cancel\u{201D}.")
                    .textStyle(.caption1)
                    .foregroundStyle(palette.textMuted)
            }
            CapsuleButton(title: "Cancel", tint: palette.tabActive, action: onCancel)
                .accessibilityIdentifier("cancelChooseExerciseButton")
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color(hex: 0x1A1526), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
            .strokeBorder(palette.borderCard, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .padding(24)
        .environment(\.colorScheme, .dark)
    }

    private func detail(for exercise: ExerciseDefinition) -> String {
        let done = session.setsDone(for: exercise)
        let target = "\(exercise.sets) sets × \(exercise.targetLabel) reps"
        guard done > 0 else { return target }
        return done >= exercise.sets ? "All \(exercise.sets) sets done" : "\(target) · \(done) done"
    }
}
