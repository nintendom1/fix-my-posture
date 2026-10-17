import SwiftUI

struct LibraryScreen: View {
    let state: LibraryState
    let send: (LibraryIntent) -> Void

    private let horizontalMargin: CGFloat = Metrics.Spacing.screenMargin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                navigationHeader
                Text("Exercises")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 38, alignment: .leading)
                    .designAnchor("library.title")

                searchField
                filters

                if let emptyState = state.emptyState {
                    EmptyStateTile(
                        title: emptyState.title,
                        message: emptyState.message,
                        icon: "magnifyingglass",
                        actionTitle: emptyState.actionTitle,
                        action: { send(.clearFilters) }
                    )
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(state.groups) { group in
                            exerciseGroup(group)
                        }
                    }
                }

                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, horizontalMargin)
            .padding(.top, 0)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { send(.appeared) }
    }

    private var navigationHeader: some View {
        HStack {
            Button { send(.back) } label: {
                HStack(spacing: 4) {
                    Image(material: "chevron_left")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Train")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(ColorTokens.palette().tabActive)
                .frame(height: 36)
                .contentShape(Rectangle())
                .designAnchor("library.back")
            }
            .buttonStyle(.plain)
            .padding(.leading, -6)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(material: "search")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSubtle)
            TextField(state.searchPlaceholder, text: searchBinding)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSubtle)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(state.searchPlaceholder)
                .accessibilityIdentifier("librarySearch")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .designAnchor("library.search")
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ExerciseFilterChip.allCases) { filter in
                    let isSelected = filter == state.selectedFilter
                    Button { send(.filterSelected(filter)) } label: {
                        Text(filter.title)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(isSelected
                                ? ColorTokens.palette().filterSelectedText
                                : ColorTokens.palette().filterUnselectedText)
                            .frame(width: filterWidth(for: filter), height: Metrics.Size.filterChipVisual)
                            .background(
                                isSelected
                                    ? ColorTokens.palette().textPrimary
                                    : ColorTokens.palette().filterUnselectedBackground,
                                in: Capsule()
                            )
                            .contentShape(Rectangle().inset(by: -4))
                            .designAnchor(filterAnchor(for: filter))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func exerciseGroup(_ group: LibraryExerciseGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(ColorTokens.palette().textMuted)
                .frame(height: 16, alignment: .leading)
                .padding(.top, 4)

            ForEach(group.exercises) { exercise in
                Button { send(.exerciseSelected(exercise.id)) } label: {
                    exerciseRow(exercise)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel("\(exercise.name), \(exercise.target)")
                .designAnchor(rowAnchor(for: exercise.id))
            }
        }
    }

    private func exerciseRow(_ exercise: LibraryExerciseRow) -> some View {
        HStack(spacing: 12) {
            ZStack {
                GradientTokens.linearGradient(from: exercise.gradient)
            }
            .frame(width: 56, height: 56)
            .opacity(0.85)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.thumbnail, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: 19, alignment: .leading)

                Text(exercise.muscles)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 15, alignment: .leading)

                HStack(spacing: 6) {
                    metadataChip(exercise.equipment)
                    metadataChip(cameraLabel(exercise.cameraSetup))
                }
                .frame(height: 16, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(material: "chevron_right")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x6C6578))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background {
            RoundedRectangle(cornerRadius: Metrics.Radius.row, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.Radius.row, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
    }

    private func metadataChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(hex: 0xD8D0E8))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func cameraLabel(_ value: String) -> String {
        if value.hasPrefix("Front") { return "Front camera" }
        if value.hasPrefix("Side-on") { return "Side-on" }
        return "Floor camera"
    }

    private var searchBinding: Binding<String> {
        Binding(get: { state.query }, set: { send(.queryChanged($0)) })
    }

    private func filterWidth(for filter: ExerciseFilterChip) -> CGFloat {
        switch filter {
        case .all: return 48
        case .upper: return 105.5
        case .lower: return 106
        case .bodyweight: return 108.5
        case .dumbbells: return 101
        }
    }

    private func filterAnchor(for filter: ExerciseFilterChip) -> String {
        switch filter {
        case .all: return "library.filter.all"
        case .upper: return "library.filter.upperBody"
        case .lower: return "library.filter.lowerBody"
        case .bodyweight: return "library.filter.bodyweight"
        case .dumbbells: return "library.filter.dumbbells"
        }
    }

    private func rowAnchor(for id: ExerciseID) -> String {
        switch id {
        case .shoulderPress: return "library.exercise.shoulderPress"
        case .hammerCurl: return "library.exercise.hammerCurl"
        case .tricepsExtension: return "library.exercise.tricepsExtension"
        case .dumbbellRow: return "library.exercise.dumbbellRow"
        default: return "library.exercise.\(id.rawValue)"
        }
    }
}
