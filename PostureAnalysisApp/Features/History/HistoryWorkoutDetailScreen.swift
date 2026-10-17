import SwiftUI

struct HistoryWorkoutDetailScreen: View {
    @State private var record: WorkoutRecord
    @State private var editing: WeightEditTarget?

    let viewModel: HistoryViewModel

    private let palette = ColorTokens.palette()

    init(record: WorkoutRecord, viewModel: HistoryViewModel) {
        _record = State(initialValue: record)
        self.viewModel = viewModel
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Started", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Duration.seconds(max(0, record.endedAt.timeIntervalSince(record.startedAt)))
                    .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                if let planName = record.planName {
                    LabeledContent("Saved Set", value: planName)
                }
            }
            ForEach(record.entries) { entry in
                let equipment = viewModel.exerciseCatalog.exercise(entry.exerciseID)?.equipment ?? .dumbbells
                Section {
                    ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                        HStack(spacing: 10) {
                            Text("Set \(setNumber(index, in: entry))\(set.side.map { " \($0)" } ?? "")")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 8)
                            Text(set.reps == 1 ? "1 rep" : "\(set.reps) reps")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(palette.textMuted)
                            if equipment != .bodyweight {
                                Button(set.weight?.label ?? "Add weight") {
                                    editing = WeightEditTarget(entryID: entry.id, setIndex: index, equipment: equipment)
                                }
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(palette.tabActive)
                                .buttonStyle(.borderless)
                                .frame(minWidth: 96, alignment: .trailing)
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.035))
                    }
                } header: {
                    Text(entry.name + outcomeLabel(entry.outcome))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.backgroundPrimary)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color(hex: 0x0E0B16, alpha: 0.9), for: .navigationBar)
        .sheet(item: $editing) { target in
            WeightEditorView(weight: weight(at: target),
                             preferredWeightUnit: viewModel.preferredWeightUnit,
                             equipment: target.equipment) { weight, applyToLater in
                if let updated = viewModel.updateWeight(
                    recordID: record.id,
                    entryID: target.entryID,
                    setIndex: target.setIndex,
                    weight: weight,
                    applyToLater: applyToLater
                ) {
                    record = updated
                }
            }
            .presentationDetents([.medium])
        }
        .environment(\.colorScheme, .dark)
    }

    private func setNumber(_ index: Int, in entry: WorkoutRecordEntry) -> Int {
        entry.sets.first?.side == nil ? index + 1 : index / 2 + 1
    }

    private func outcomeLabel(_ outcome: WorkoutRecordEntry.Outcome?) -> String {
        switch outcome {
        case .skipped: return " · Skipped"
        case .completed, nil: return ""
        }
    }

    private func weight(at target: WeightEditTarget) -> WorkoutWeight? {
        record.entries.first { $0.id == target.entryID }.flatMap { entry in
            entry.sets.indices.contains(target.setIndex) ? entry.sets[target.setIndex].weight : nil
        }
    }
}

private struct WeightEditTarget: Identifiable {
    let entryID: UUID
    let setIndex: Int
    let equipment: ExerciseEquipment

    var id: String { "\(entryID)-\(setIndex)" }
}

/// Enters a mass or band name for this set, optionally applying it to later sets of the exercise.
private struct WeightEditorView: View {
    let equipment: ExerciseEquipment
    let onSave: (WorkoutWeight?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    @State private var unit: WeightUnit = .pounds
    @State private var bandName = ""
    @State private var applyToLater = true

    init(weight: WorkoutWeight?, preferredWeightUnit: PreferredWeightUnit,
         equipment: ExerciseEquipment, onSave: @escaping (WorkoutWeight?, Bool) -> Void) {
        self.equipment = equipment
        self.onSave = onSave
        switch weight {
        case .mass(let amount, let massUnit):
            _value = State(initialValue: amount)
            _unit = State(initialValue: massUnit)
        case .band(let name):
            _bandName = State(initialValue: name)
        case nil:
            _unit = State(initialValue: preferredWeightUnit == .lb ? .pounds : .kilograms)
        }
    }

    private var newWeight: WorkoutWeight? {
        if equipment == .band {
            let name = bandName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : .band(name)
        }
        return value.flatMap { $0 > 0 ? .mass($0, unit) : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if equipment == .band {
                        TextField("Band, for example Red band", text: $bandName)
                    } else {
                        HStack {
                            TextField("Per dumbbell", value: $value, format: .number)
                                .keyboardType(.decimalPad)
                            Picker("Unit", selection: $unit) {
                                ForEach(WeightUnit.allCases) { Text($0.symbol).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 110)
                        }
                    }
                    Toggle("Also for the later sets", isOn: $applyToLater)
                } footer: {
                    Text(equipment == .band ? "The band used for this set." : "The weight of each dumbbell.")
                }
                Section {
                    Button("Remove Weight", role: .destructive) {
                        onSave(nil, applyToLater)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(newWeight, applyToLater)
                        dismiss()
                    }
                    .disabled(newWeight == nil)
                }
            }
            .environment(\.colorScheme, .dark)
        }
    }
}
