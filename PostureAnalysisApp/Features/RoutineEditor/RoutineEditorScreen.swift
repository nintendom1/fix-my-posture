import SwiftUI

struct RoutineEditorScreen: View {
    let state: RoutineEditorState
    let send: (RoutineEditorIntent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                navigationHeader
                nameField
                summaryCard
                exercisesHeading

                if state.items.isEmpty {
                    emptyState
                        .padding(.top, 1)
                } else {
                    VStack(spacing: 16.5) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                            RoutineEditorItemRow(
                                item: item,
                                number: index + 1,
                                canMoveUp: index > 0,
                                canMoveDown: index < state.items.count - 1,
                                itemIDs: state.items.map(\.id),
                                send: send
                            )
                        }
                    }
                }

                addExerciseButton
                helperText

                if !state.isNew {
                    editingActions
                }

                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, Metrics.Spacing.screenMargin)
            .padding(.top, 0)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: pickerBinding) {
            AddExerciseSheet(state: state, send: send)
                .presentationDetents([.height(724)])
                .presentationCornerRadius(32)
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(hex: 0x1A1526))
        }
        .alert(deleteTitle, isPresented: deleteConfirmationBinding) {
            Button("Delete Routine", role: .destructive) { send(.confirmDelete) }
            Button("Cancel", role: .cancel) { send(.cancelDelete) }
        } message: {
            Text("This routine and its saved exercise order will be removed.")
        }
    }

    private var navigationHeader: some View {
        HStack(spacing: 0) {
            Button { send(.cancel) } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().tabActive)
                    .fixedSize()
                    .designAnchor("editor.cancel")
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text(state.title)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .tracking(-0.25)
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .fixedSize()
                .designAnchor("editor.title")

            Spacer(minLength: 0)

            Button { send(.save) } label: {
                Text("Save")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(state.isSaveEnabled ? ColorTokens.palette().tabActive : Color(hex: 0x5C5570))
                    .fixedSize()
                    .designAnchor("editor.save")
            }
            .buttonStyle(.plain)
            .disabled(!state.isSaveEnabled)
        }
        .frame(height: 44)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(ColorTokens.palette().textMuted)
                .padding(.leading, 4)
                .frame(height: 16, alignment: .leading)

            TextField("e.g. Morning Strength", text: nameBinding)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(height: 54.5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(ColorTokens.palette().tabActive.opacity(0.25), lineWidth: 1.5)
                }
                .designAnchor("editor.name")
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            Text(state.summary)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(material: "timer")
                .font(.system(size: 28, weight: .regular, design: .rounded))
                .foregroundStyle(Color(hex: 0xE4D9FF))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(height: 67)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x6A3DF0, alpha: 0.35), Color(hex: 0xFF7F9E, alpha: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .designAnchor("editor.summary")
    }

    private var exercisesHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Exercises, in order")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(ColorTokens.palette().textMuted)
            Spacer()
            HStack(spacing: 4) {
                Image(material: "drag_indicator")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("Drag to reorder")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(ColorTokens.palette().textSubtle)
        }
        .padding(.horizontal, 4)
        .frame(height: 16)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(material: "fitness_center")
                .font(.system(size: 30, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(GradientTokens.workoutActive, in: Circle())

            Text("Add your first exercise")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .padding(.top, 12)

            Text("The coach runs them in this order, with rest between sets.")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 188)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    ColorTokens.palette().tabActive.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                )
        }
        .designAnchor("editor.emptyState")
    }

    private var addExerciseButton: some View {
        Button { send(.presentPicker) } label: {
            HStack(spacing: 6) {
                Image(material: "add")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Add Exercise")
                    .font(.system(size: 16, weight: .black, design: .rounded))
            }
            .foregroundStyle(Color(hex: 0xE4D9FF))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color(hex: 0x7C4DFF, alpha: 0.12), in: Capsule())
            .overlay {
                Capsule().strokeBorder(ColorTokens.palette().tabActive.opacity(0.4), lineWidth: 1.5)
            }
            .contentShape(Capsule())
            .designAnchor("editor.addExercise")
        }
        .buttonStyle(.plain)
    }

    private var helperText: some View {
        Text("Weights are logged set by set during the workout, so you can change them as you get stronger. The same exercise can appear more than once.")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(ColorTokens.palette().textSubtle)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 50.5, alignment: .topLeading)
            .designAnchor("editor.helper")
            .accessibilityLabel("Weights are logged set by set during the workout, so you can change them as you get stronger. The same exercise can appear more than once.")
    }

    private var editingActions: some View {
        HStack(spacing: 10) {
            editorAction(title: "Duplicate", icon: "content_copy", tint: ColorTokens.palette().tabActive) {
                send(.duplicate)
            }
            .designAnchor("editor.duplicate")

            editorAction(title: "Delete Routine", icon: "delete", tint: ColorTokens.palette().danger) {
                send(.requestDelete)
            }
            .designAnchor("editor.delete")
        }
        .padding(.top, 4)
    }

    private func editorAction(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(material: icon)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var nameBinding: Binding<String> {
        Binding(get: { state.name }, set: { send(.nameChanged($0)) })
    }

    private var pickerBinding: Binding<Bool> {
        Binding(
            get: { state.isPickerPresented },
            set: { if !$0 { send(.dismissPicker) } }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { state.showsDeleteConfirmation },
            set: { if !$0 { send(.cancelDelete) } }
        )
    }

    private var deleteTitle: String {
        let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Delete routine?" : "Delete \u{201c}\(name)\u{201d}?"
    }
}

private struct RoutineEditorItemRow: View {
    let item: RoutineEditorItemState
    let number: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let itemIDs: [UUID]
    let send: (RoutineEditorIntent) -> Void

    private var rowGradient: LinearGradient { GradientTokens.linearGradient(from: item.gradient) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(material: "drag_indicator")
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textSubtle)
                    .frame(width: 22, height: 40)
                    .contentShape(Rectangle())
                    .draggable(item.id.uuidString)
                    .accessibilityLabel("Reorder \(item.name)")
                    .accessibilityHint("Drag to change the order. Move up and Move down are also available.")

                Text("\(number)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(rowGradient, in: Circle())

                Button { send(.toggleExpanded(item.id)) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(ColorTokens.palette().textPrimary)
                            .lineLimit(1)
                        Text(item.targetLabel)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(ColorTokens.palette().textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.name), \(item.targetLabel)")
                .accessibilityHint("Edit sets and reps")

                Button { send(.toggleExpanded(item.id)) } label: {
                    Image(material: item.isExpanded ? "expand_less" : "chevron_right")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isExpanded ? "Collapse \(item.name)" : "Edit sets and reps for \(item.name)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)

            if item.isExpanded {
                expandedControls
                    .padding(.horizontal, 14)
                    .padding(.bottom, 25.5)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Edit sets and reps")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: item.isExpanded ? 283.5 : 62.5, alignment: .top)
        .background(item.isExpanded ? Color(hex: 0x7C4DFF, alpha: 0.14) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(item.isExpanded ? ColorTokens.palette().tabActive.opacity(0.45) : Color.white.opacity(0.07), lineWidth: 1.5)
        }
        .designAnchor(rowAnchor)
        .dropDestination(for: String.self) { values, _ in
            guard let draggedID = values.first.flatMap(UUID.init(uuidString:)),
                  let from = currentIndex(for: draggedID),
                  let to = currentIndex(for: item.id) else { return false }
            send(.move(from: from, to: to > from ? to + 1 : to))
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Move up")) { send(.moveUp(item.id)) }
        .accessibilityAction(named: Text("Move down")) { send(.moveDown(item.id)) }
    }

    private var expandedControls: some View {
        VStack(spacing: 0) {
            stepperRow("Sets", value: item.setCount, lowerBound: 1, upperBound: 10) { delta in
                send(.setCountChanged(itemID: item.id, value: item.setCount + delta))
            }
            stepperRow("Min reps", value: item.minimumReps, lowerBound: 1, upperBound: 50) { delta in
                send(.minimumRepsChanged(itemID: item.id, value: item.minimumReps + delta))
            }
            stepperRow("Max reps", value: item.maximumReps, lowerBound: 1, upperBound: 50) { delta in
                send(.maximumRepsChanged(itemID: item.id, value: item.maximumReps + delta))
            }

            HStack(spacing: 8) {
                moveButton(title: "Move up", icon: "arrow_upward", enabled: canMoveUp) {
                    send(.moveUp(item.id))
                }
                moveButton(title: "Move down", icon: "arrow_downward", enabled: canMoveDown) {
                    send(.moveDown(item.id))
                }
                Button { send(.removeExercise(item.id)) } label: {
                    Image(material: "delete")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().danger)
                        .frame(width: 40, height: 40)
                        .background(ColorTokens.palette().danger.opacity(0.16), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove exercise")
            }
            .padding(.top, 8)
        }
    }

    private func stepperRow(
        _ title: String,
        value: Int,
        lowerBound: Int,
        upperBound: Int,
        change: @escaping (Int) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
            Spacer(minLength: 8)
            Button { change(-1) } label: {
                Image(material: "remove")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(value <= lowerBound)
            .opacity(value <= lowerBound ? 0.4 : 1)
            .accessibilityLabel("Decrease \(title)")

            Text("\(value)")
                .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(minWidth: 24)
                .accessibilityLabel("\(title): \(value)")

            Button { change(1) } label: {
                Image(material: "add")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(value >= upperBound)
            .opacity(value >= upperBound ? 0.4 : 1)
            .accessibilityLabel("Increase \(title)")
        }
        .frame(height: 50)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    }

    private func moveButton(title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(material: icon)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color(hex: 0xE4DDF0))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(title)
    }

    private var rowAnchor: String {
        switch item.exerciseID.rawValue {
        case "shoulder_press": return "editor.row.shoulderPress"
        case "dumbbell_row": return "editor.row.dumbbellRow"
        case "hammer_curl": return "editor.row.hammerCurl"
        case "triceps_extension": return "editor.row.triceps"
        default: return "editor.row.\(number)"
        }
    }

    private func currentIndex(for id: UUID) -> Int? {
        itemIDs.firstIndex(of: id)
    }
}
