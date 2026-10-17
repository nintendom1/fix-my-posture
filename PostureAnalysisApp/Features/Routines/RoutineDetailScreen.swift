import SwiftUI

struct RoutineDetailScreen: View {
    let state: RoutineDetailState
    let send: (RoutineDetailIntent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                navigationHeader
                Color.clear.frame(height: 22)

                if let routine = state.routine {
                    titleBlock(routine)
                    Color.clear.frame(height: 18)
                    sequence(routine.steps)
                    Color.clear.frame(height: 30)
                    actions
                    Text("The coach runs them in this order, with rest between sets.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textMuted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else {
                    ContentUnavailableView("Routine Unavailable", systemImage: "list.number")
                }
            }
            .padding(.horizontal, Metrics.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .stickyCTA(bottomSpacing: Metrics.Spacing.medium + 3) {
            PrimaryButton(
                title: "Start Routine",
                icon: "play.fill",
                variant: .gradient,
                size: .sticky
            ) {
                send(.start)
            }
            .disabled(state.routine?.canStart != true)
            .opacity(state.routine?.canStart == true ? 1 : 0.55)
            .designAnchor("cta.sticky")
        }
        .onAppear { send(.appeared) }
        .alert(deleteTitle, isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) { send(.confirmDelete) }
            Button("Cancel", role: .cancel) { send(.cancelDelete) }
        } message: {
            Text("This routine and its saved exercise order will be removed.")
        }
    }

    private var navigationHeader: some View {
        HStack {
            Button { send(.back) } label: {
                HStack(spacing: 4) {
                    Image(material: "chevron_left")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Routines")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(ColorTokens.palette().tabActive)
                .frame(height: 36)
                .contentShape(Rectangle())
                .designAnchor("routine.back")
            }
            .buttonStyle(.plain)
            .padding(.leading, -6)

            Spacer()

            Button { send(.edit) } label: {
                Text("Edit")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().tabActive)
                    .fixedSize()
                    .designAnchor("routine.edit")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit routine")
        }
        .frame(height: 36)
    }

    private func titleBlock(_ routine: RoutineDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(routine.name)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 38, alignment: .leading)
                .designAnchor("routine.title")

            Text(routine.summary)
                .font(Typography.body)
                .foregroundStyle(ColorTokens.palette().textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 18, alignment: .leading)
                .designAnchor("routine.summary")
        }
    }

    private func sequence(_ steps: [RoutineStepPresentation]) -> some View {
        VStack(spacing: 12) {
            ForEach(steps) { step in
                SequenceStepView(step: step, isLast: step.id == steps.last?.id)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            RoutineActionButton(
                title: "Duplicate",
                icon: "content_copy",
                tint: ColorTokens.palette().tabActive,
                action: { send(.duplicate) }
            )
            .designAnchor("routine.actions.duplicate")

            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 68)

            RoutineActionButton(
                title: "Delete",
                icon: "delete",
                tint: ColorTokens.palette().danger,
                action: { send(.requestDelete) }
            )
            .designAnchor("routine.actions.delete")
        }
        .frame(height: 68)
    }

    private var deleteTitle: String {
        guard let name = state.routine?.name else { return "Delete routine?" }
        return "Delete \u{201c}\(name)\u{201d}?"
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { state.showsDeleteConfirmation },
            set: { isPresented in
                if !isPresented { send(.cancelDelete) }
            }
        )
    }
}

private struct SequenceStepView: View {
    let step: RoutineStepPresentation
    let isLast: Bool

    private var gradient: LinearGradient {
        GradientTokens.linearGradient(from: step.gradient)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text("\(step.number)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(gradient, in: Circle())

                if !isLast {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 3)
                        .padding(.vertical, 4)
                } else {
                    Color.clear.frame(width: 3)
                }
            }
            .frame(width: 28, height: 78)

            HStack(spacing: 12) {
                ExercisePlaceholderTile()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.name)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .lineLimit(1)
                    Text(step.targetLine)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .lineLimit(1)
                    Text(step.camera)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RoutineReorderGrip()
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            }
            .designAnchor(stepAnchor(for: step.exerciseID))
        }
        .frame(height: 78, alignment: .top)
    }

    private func stepAnchor(for id: ExerciseID) -> String {
        switch id.rawValue {
        case "shoulder_press": return "routine.step.shoulderPress"
        case "dumbbell_row": return "routine.step.dumbbellRow"
        case "hammer_curl": return "routine.step.hammerCurl"
        case "triceps_extension": return "routine.step.triceps"
        default: return "routine.step.\(step.number)"
        }
    }
}

private struct RoutineReorderGrip: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(ColorTokens.palette().textSubtle)
        .frame(width: 12, height: 14)
        .accessibilityHidden(true)
    }
}

private struct ExercisePlaceholderTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
            Canvas { context, size in
                let spacing: CGFloat = 16
                for offset in stride(from: -size.height, through: size.width, by: spacing) {
                    var path = Path()
                    path.move(to: CGPoint(x: offset, y: size.height))
                    path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                    context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 9)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RoutineActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(material: icon)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct RoutineDetailRouteView: View {
    @State private var viewModel: RoutineDetailViewModel

    init(viewModel: RoutineDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        RoutineDetailScreen(state: viewModel.state, send: viewModel.send)
    }
}
