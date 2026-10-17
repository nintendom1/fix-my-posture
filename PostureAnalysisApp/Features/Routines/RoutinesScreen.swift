import SwiftUI

struct RoutinesScreen: View {
    let state: RoutinesState
    let send: (RoutinesIntent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    Text("Exercises in order, with your own sets and reps.")
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 18, alignment: .leading)
                        .designAnchor("routines.subtitle")
                }

                ForEach(Array(state.routines.enumerated()), id: \.element.id) { index, routine in
                    RoutineCardView(
                        routine: routine,
                        anchor: cardAnchor(for: routine, index: index),
                        open: { send(.open(routine.id)) },
                        start: { send(.start(routine.id)) },
                        edit: { send(.edit(routine.id)) },
                        duplicate: { send(.duplicate(routine.id)) },
                        delete: { send(.requestDelete(routine.id)) }
                    )
                }

                createRoutineTile
            }
            .padding(.horizontal, Metrics.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { send(.appeared) }
        .alert("Delete routine?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) { send(.confirmDelete) }
            Button("Cancel", role: .cancel) { send(.cancelDelete) }
        } message: {
            Text("This routine will be removed from your saved routines.")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("Routines")
                .textStyle(.largeTitle)
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .scaleEffect(x: 0.88, y: 1, anchor: .leading)
                .frame(width: 144, height: 40, alignment: .leading)
                .designAnchor("routines.title")
                .padding(.top, 20)

            Spacer(minLength: 0)

            Button { send(.createRoutine) } label: {
                Image(material: "add")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(GradientTokens.workoutActive, in: Circle())
                    .contentShape(Circle())
                    .designAnchor("routines.create")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New routine")
        }
        .frame(height: 60, alignment: .bottom)
    }

    private var createRoutineTile: some View {
        Button { send(.createRoutine) } label: {
            VStack(spacing: 4) {
                Image(material: "add_circle")
                    .font(.system(size: 28, weight: .regular, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().tabActive)
                Text("Create Routine")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                Text("Pick exercises, then drag to reorder.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        ColorTokens.palette().tabActive.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .designAnchor("routines.emptyState")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create Routine")
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { state.showsDeleteConfirmation },
            set: { isPresented in
                if !isPresented { send(.cancelDelete) }
            }
        )
    }

    private func cardAnchor(for routine: RoutineCardPresentation, index: Int) -> String {
        switch routine.name {
        case "Upper Body": return "routines.card.upperBody"
        case "Quick Strength": return "routines.card.quickStrength"
        case "Legs & Push": return "routines.card.legsPush"
        default: return "routines.card.\(index)"
        }
    }
}

private struct RoutineCardView: View {
    let routine: RoutineCardPresentation
    let anchor: String
    let open: () -> Void
    let start: () -> Void
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    private var gradient: LinearGradient {
        switch routine.theme {
        case .exercise(let gradient):
            return GradientTokens.linearGradient(from: gradient)
        case .brand:
            return GradientTokens.workoutActive
        }
    }

    private var cardHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(routine.exerciseNames.count) / 3.0)))
        return 180 + CGFloat(max(0, rows - 1) * 31)
    }

    var body: some View {
        Button(action: open) {
            VStack(spacing: 10) {
                HStack {
                    Text(routine.name)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(height: 32, alignment: .leading)
                    Spacer(minLength: 36)
                }

                Text(routine.summary)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 17, alignment: .leading)

                RoutineTagFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(Array(routine.exerciseNames.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(ColorTokens.palette().textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(height: 39)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: cardHeight, alignment: .topLeading)
            .background(Color.white.opacity(0.06))
            .overlay(alignment: .top) {
                gradient.frame(height: 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .designAnchor(anchor)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("Edit", action: edit)
                Button("Duplicate", systemImage: "doc.on.doc", action: duplicate)
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(material: "more_horiz")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textMuted)
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Routine actions")
            .padding(.top, 19)
            .padding(.trailing, 10)
        }
        .overlay(alignment: .bottomTrailing) {
            RoutineStartButton(gradient: gradient, action: start)
                .disabled(!routine.canStart)
                .opacity(routine.canStart ? 1 : 0.55)
                .padding(.trailing, 12)
                .padding(.bottom, 14)
        }
    }
}

private struct RoutineStartButton: View {
    let gradient: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Start")
                    .font(.system(size: 14, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(gradient, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start routine")
    }
}

private struct RoutineTagFlowLayout: Layout {
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
