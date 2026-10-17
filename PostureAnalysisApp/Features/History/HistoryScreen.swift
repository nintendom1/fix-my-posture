import SwiftUI

struct HistoryScreen: View {
    let viewModel: HistoryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRecordID: UUID?
    @State private var isDetailPresented = false

    private let palette = ColorTokens.palette()

    var body: some View {
        List {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(material: "chevron_left")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(width: 22)
                    Text("Progress")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                }
                .foregroundStyle(palette.tabActive)
                .frame(width: 101.5, height: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .designAnchor("history.back")
            .frame(height: 44, alignment: .topLeading)
            .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Text("Workout History")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 38, alignment: .leading)
                .designAnchor("history.title")
                .padding(.top, 10)
                .frame(height: 48, alignment: .topLeading)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if viewModel.state.groups.isEmpty {
                emptyState
                    .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(viewModel.state.groups.enumerated()), id: \.element.id) { groupIndex, group in
                    groupHeading(group)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                        .frame(height: 30, alignment: .bottom)
                        .listRowInsets(EdgeInsets(top: groupIndex == 0 ? 14 : 6, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ForEach(Array(group.records.enumerated()), id: \.element.id) { recordIndex, record in
                        Button {
                            guard viewModel.openRecord(id: record.id) != nil else { return }
                            selectedRecordID = record.id
                            isDetailPresented = true
                        } label: {
                            HistoryWorkoutCard(
                                record: record,
                                gradient: badgeGradient(for: record, index: recordIndex),
                                anchor: designAnchor(for: record)
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.delete(recordID: record.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isDetailPresented) {
            if let selectedRecordID, let record = viewModel.openRecord(id: selectedRecordID) {
                HistoryWorkoutDetailScreen(record: record, viewModel: viewModel)
            } else {
                Text("This workout is no longer available.")
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .onAppear { viewModel.refresh() }
        .environment(\.colorScheme, .dark)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No workouts yet")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text("Workouts you finish are saved here with their sets, reps, and weights.")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.backgroundCard)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(palette.borderCard, lineWidth: 1)
                }
        }
    }

    private func groupHeading(_ group: HistoryWeekGrouping.Week) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(palette.textMuted)
                .lineLimit(1)
                .modifier(OptionalHistoryAnchor(name: group.title == "Last week" ? "history.date.lastWeek" : nil))
            Spacer(minLength: 8)
            Text(group.summary)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(palette.textSubtle)
                .lineLimit(1)
                .modifier(OptionalHistoryAnchor(name: groupIndexAnchor(group)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupIndexAnchor(_ group: HistoryWeekGrouping.Week) -> String? {
        if group.title == "This week" { return "history.week" }
        return nil
    }

    private func designAnchor(for record: WorkoutRecord) -> String? {
        if record.planName == "Upper Body" { return "history.workout.upperBody" }
        if record.planName == "Quick Strength" { return "history.workout.quickStrength" }
        return nil
    }

    private func badgeGradient(for record: WorkoutRecord, index: Int) -> LinearGradient {
        if record.planName == "Upper Body" { return GradientTokens.trainHero }
        if record.planName == "Quick Strength" {
            return GradientTokens.linearGradient(from: AirSquatExercise.definition().presentation.gradient)
        }
        if record.planName == "Lower Body" || record.planName == "Legs & Push" { return GradientTokens.success }
        if record.planName == nil,
           let entry = record.entries.first,
           let exercise = viewModel.exerciseCatalog.exercise(entry.exerciseID) {
            return GradientTokens.linearGradient(from: exercise.presentation.gradient)
        }
        return index.isMultiple(of: 2) ? GradientTokens.progress : GradientTokens.posture
    }
}

private struct HistoryWorkoutCard: View {
    let record: WorkoutRecord
    let gradient: LinearGradient
    let anchor: String?

    private var stats: WorkoutCompletionStats { WorkoutCompletionStats(record: record) }
    private var title: String { record.planName ?? record.entries.first?.name ?? "Workout" }
    private var chips: [String] {
        stats.exerciseRows.map { row in
            guard let weight = row.weightLabel else { return row.name }
            return "\(row.name) \(weight)"
        }
    }
    private var cardHeight: CGFloat { chips.count > 3 ? 136 : 107 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(Self.month(record.startedAt))
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(Self.day(record.startedAt))
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                .background(gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .modifier(OptionalHistoryAnchor(name: Self.day(record.startedAt) == "14" ? "history.date.thisWeek" : nil))
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .lineLimit(1)
                    Text(meta)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(material: "chevron_right")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x6C6578))
            }
            .frame(height: 44)
            .padding(.leading, 1)

            HistoryChipFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    Text(chip)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: 0xD8D0E8))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .modifier(OptionalHistoryAnchor(name: anchor))
    }

    private var meta: String {
        let duration = stats.durationLabel == "<1m"
            ? "<1 min"
            : stats.durationLabel.replacingOccurrences(of: "m", with: " min")
        return "\(duration) · \(stats.totalSets) \(stats.totalSets == 1 ? "set" : "sets") · \(stats.totalReps) \(stats.totalReps == 1 ? "rep" : "reps")"
    }

    private static func month(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: date).uppercased()
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

private struct OptionalHistoryAnchor: ViewModifier {
    let name: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let name { content.designAnchor(name) }
        else { content }
    }
}

private struct HistoryChipFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
