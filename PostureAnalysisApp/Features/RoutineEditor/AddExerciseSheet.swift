import SwiftUI

struct AddExerciseSheet: View {
    let state: RoutineEditorState
    let send: (RoutineEditorIntent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 40, height: 5)
                .padding(.top, 9)

            titleBar
            searchField

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(state.pickerExercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
                .padding(.horizontal, Metrics.Spacing.screenMargin)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x1A1526))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
        .designAnchor("picker.sheet")
    }

    private var titleBar: some View {
        ZStack {
            Text("Add Exercise")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .tracking(-0.25)
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .fixedSize()
                .designAnchor("picker.title")
                .frame(maxWidth: .infinity)
                .frame(height: 52)

            HStack {
                Color.clear.frame(width: 60, height: 20)
                Spacer(minLength: 0)
                Button { send(.dismissPicker) } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().tabActive)
                        .frame(width: 60, height: 20, alignment: .trailing)
                        .contentShape(Rectangle())
                        .designAnchor("picker.done")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Metrics.Spacing.screenMargin)
        }
        .frame(height: 52)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(material: "search")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSubtle)

            TextField("Search exercises", text: searchBinding)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .tint(ColorTokens.palette().tabActive)

            Menu {
                ForEach(AddExerciseSortOption.allCases) { option in
                    Button {
                        send(.sortPicker(option))
                    } label: {
                        if option == state.pickerSort {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Image(material: "tune")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().tabActive)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Sort exercises, currently \(state.pickerSort.title)")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .designAnchor("picker.search")
        .padding(.horizontal, Metrics.Spacing.screenMargin)
        .padding(.bottom, 12)
    }

    private func exerciseRow(_ exercise: AddExercisePresentation) -> some View {
        Button { send(.addExercise(exercise.exerciseID)) } label: {
            HStack(spacing: 12) {
                ExerciseThumbnailView(exerciseID: exercise.exerciseID, cornerRadius: 13)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .lineLimit(1)
                    Text("\(exercise.muscles) · \(exercise.target)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if exercise.inRoutineCount > 0 {
                    Text(exercise.inRoutineCount > 1 ? "In routine ×\(exercise.inRoutineCount)" : "In routine")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().success)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(ColorTokens.palette().success.opacity(0.16), in: Capsule())
                }

                Image(material: "add")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(GradientTokens.workoutActive, in: Circle())
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight(for: exercise))
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .designAnchor(rowAnchor(for: exercise.exerciseID))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(exercise.name), \(exercise.target)")
        .accessibilityHint(exercise.inRoutineCount > 0 ? "Already in this routine. Adds another occurrence." : "Adds this exercise to the routine.")
    }

    private var searchBinding: Binding<String> {
        Binding(get: { state.pickerSearchText }, set: { send(.pickerSearchChanged($0)) })
    }

    private func rowHeight(for exercise: AddExercisePresentation) -> CGFloat {
        switch exercise.exerciseID.rawValue {
        case "shoulder_press", "hammer_curl", "triceps_extension": return 70
        default: return 68
        }
    }

    private func rowAnchor(for id: ExerciseID) -> String {
        switch id.rawValue {
        case "shoulder_press": return "picker.exercise.shoulderPress"
        case "hammer_curl": return "picker.exercise.hammerCurl"
        case "air_squat": return "picker.exercise.airSquat"
        case "push_up": return "picker.exercise.pushUp"
        default: return "picker.exercise.\(id.rawValue)"
        }
    }
}
