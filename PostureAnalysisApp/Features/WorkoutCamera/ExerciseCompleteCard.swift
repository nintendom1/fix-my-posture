import SwiftUI

/// Shown when every set of the exercise is done: this round's reps, then what to do next.
struct ExerciseCompleteCard: View {
    let session: WorkoutSession
    let onAnotherRound: () -> Void
    let onChooseExercise: () -> Void
    let onEndWorkout: () -> Void

    var body: some View {
        if let plan = session.plan, session.isFollowingPlan {
            planCard(plan)
        } else if let exercise = session.exercise {
            let record = session.progress[exercise.id] ?? ExerciseProgress()
            let sets = record.roundSetReps
            VStack(spacing: 12) {
                Image(material: "check_circle")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0x063A26))
                    .frame(width: 64, height: 64)
                    .background(GradientTokens.success, in: Circle())
                    .accessibilityHidden(true)
                Text("\(exercise.displayName) complete")
                    .textStyle(.title2)
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 4) {
                    if record.round > 1 {
                        Text("Round \(record.round)")
                            .textStyle(.body)
                            .foregroundStyle(ColorTokens.palette().textMuted)
                    }
                    Text(sets.enumerated().map { "\(exercise.setLabel(entry: $0.offset)): \($0.element)\(exercise.doseUnit == .seconds ? " s" : "")" }.joined(separator: " · "))
                        .textStyle(.headline)
                        .monospacedDigit()
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                    // A timed hold's amounts are seconds.
                    Text(exercise.doseUnit == .seconds ? "\(sets.reduce(0, +)) s" : "\(sets.reduce(0, +)) reps")
                        .textStyle(.body)
                        .monospacedDigit()
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                    if let workoutLine {
                        Text(workoutLine)
                            .textStyle(.caption1)
                            .foregroundStyle(ColorTokens.palette().textMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)

                buttons
            }
            .modifier(CardStyle())
        }
    }

    /// The whole Saved Set: each occurrence completed with its reps, or skipped.
    private func planCard(_ plan: WorkoutPlan) -> some View {
        VStack(spacing: 12) {
            Image(material: "check_circle")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: 0x063A26))
                .frame(width: 64, height: 64)
                .background(GradientTokens.success, in: Circle())
                .accessibilityHidden(true)
            Text("\(plan.name) complete")
                .textStyle(.title2)
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summaryRows(of: plan), id: \.item.id) { row in
                    PlanItemSummaryRow(index: row.index, item: row.item, record: session.planRecords[row.item.id],
                                       exercise: session.exercises.first { $0.id == row.item.exerciseID })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            buttons
        }
        .modifier(CardStyle())
    }

    /// The plan's occurrences in order, numbered among the exercises. A bonus has no number and shows only once it has
    /// sets, so it is never listed as skipped or not reached.
    private func summaryRows(of plan: WorkoutPlan) -> [(index: Int?, item: WorkoutPlanItem)] {
        var exercisesSoFar = 0
        return plan.items.compactMap { item in
            if item.isBonus {
                return session.planRecords[item.id]?.setReps.isEmpty == false ? (index: nil, item: item) : nil
            }
            exercisesSoFar += 1
            return (index: exercisesSoFar - 1, item: item)
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: "Another Round", icon: "arrow.clockwise", action: onAnotherRound)
                .accessibilityIdentifier("anotherRoundButton")
            if session.exercises.count > 1 {
                secondaryButton("Choose Exercise", systemImage: "list.bullet", action: onChooseExercise)
                    .accessibilityIdentifier("chooseExerciseButton")
            }
            secondaryButton("End Workout", systemImage: "flag.checkered", tint: ColorTokens.palette().danger,
                            action: onEndWorkout)
                .accessibilityIdentifier("completeEndWorkoutButton")
        }
        .padding(.top, 4)
    }

    /// Everything finished in this workout, when more than this exercise's round.
    private var workoutLine: String? {
        let finished = session.exercises.compactMap { exercise -> (String, Int)? in
            let entries = session.progress[exercise.id]?.setReps.count ?? 0
            let sets = exercise.perSide ? entries / 2 : entries
            return sets > 0 ? (exercise.displayName, sets) : nil
        }
        let total = finished.map(\.1).reduce(0, +)
        guard let current = session.exercise, total > session.setsDone(for: current) else { return nil }
        return "This workout: " + finished.map { "\($0.0) \($0.1 == 1 ? "1 set" : "\($0.1) sets")" }.joined(separator: " · ")
    }

    private func secondaryButton(_ title: String, systemImage: String,
                                 tint: Color = ColorTokens.palette().textPrimary,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(ColorTokens.palette().borderCard, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: 360)
            .background(Color(hex: 0x1A1526), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(ColorTokens.palette().borderCard, lineWidth: 1))
            .padding(24)
            .environment(\.colorScheme, .dark)
    }
}

/// "2. Hammer Curl — Set 1: 10 · Set 2: 9", or "Skipped" with any sets done first.
struct PlanItemSummaryRow: View {
    /// Zero-based position among the exercises; nil for a bonus, which isn't one of them.
    let index: Int?
    let item: WorkoutPlanItem
    let record: PlanItemRecord?
    let exercise: ExerciseDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(index.map { "\($0 + 1). " } ?? "")\(item.label(for: exercise))")
                .textStyle(.body)
                .foregroundStyle(ColorTokens.palette().textPrimary)
            Text(detail)
                .textStyle(.caption2)
                .monospacedDigit()
                .foregroundStyle(record?.outcome == .skipped && !item.isBonus
                                 ? ColorTokens.palette().warning : ColorTokens.palette().textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: Metrics.Radius.row, style: .continuous))
    }

    private var detail: String {
        let sets = (record?.setReps ?? []).enumerated().map { entry in
            "\(exercise?.setLabel(entry: entry.offset) ?? "Set \(entry.offset + 1)"): \(entry.element)"
                + (exercise?.doseUnit == .seconds ? " s" : "")
        }.joined(separator: " · ")
        // A bonus left partway shows what was done, not "Skipped after ...".
        if item.isBonus, !sets.isEmpty { return sets }
        switch record?.outcome {
        case .completed: return sets
        case .skipped:
            if sets.isEmpty { return item.isOptional ? "Optional, skipped" : "Skipped" }
            return "Skipped after \(sets)"
        case nil: return "Not reached"
        }
    }
}
