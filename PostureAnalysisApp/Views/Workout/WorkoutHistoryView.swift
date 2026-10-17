import SwiftData
import SwiftUI

/// Saved workouts, newest first. Swipe to delete; open one to add or change its weights.
struct WorkoutHistoryView: View {
    @Environment(\.appRepositories) private var appRepositories
    @Query(sort: \WorkoutRecordEntity.startedAt, order: .reverse) private var records: [WorkoutRecordEntity]

    var body: some View {
        List {
            if records.isEmpty {
                Text("Workouts you finish are saved here with their sets, reps, and weights.")
                    .foregroundStyle(.secondary)
            }
            ForEach(records) { entity in
                NavigationLink {
                    WorkoutRecordDetailView(entity: entity)
                } label: {
                    WorkoutRecordRow(record: entity.value)
                }
            }
            .onDelete { offsets in
                guard let appRepositories else { return }
                for index in offsets { try? appRepositories.workoutHistory.delete(id: records[index].id) }
            }
        }
        .navigationTitle("History")
    }
}

private struct WorkoutRecordRow: View {
    let record: WorkoutRecord

    var body: some View {
        let sets = record.entries.map(\.sets.count).reduce(0, +)
        VStack(alignment: .leading, spacing: 2) {
            Text(record.startedAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                .font(.headline)
            Text(record.planName ?? record.entries.map(\.name).joined(separator: ", "))
                .font(.subheadline)
                .lineLimit(2)
            Text("\(sets == 1 ? "1 set" : "\(sets) sets") · \(record.totalReps) reps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One saved workout. Each set's weight can be added, changed, or removed.
struct WorkoutRecordDetailView: View {
    @Environment(\.appRepositories) private var appRepositories
    let entity: WorkoutRecordEntity
    @State private var record: WorkoutRecord
    @State private var editing: WeightEditTarget?

    init(entity: WorkoutRecordEntity) {
        self.entity = entity
        _record = State(initialValue: entity.value)
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
                let equipment = ExerciseCatalog.definition(for: entry.exerciseID)?.equipment ?? .dumbbells
                Section {
                    ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text("Set \(setNumber(index, in: entry))\(set.side.map { " \($0)" } ?? "")")
                            Spacer()
                            Text(set.reps == 1 ? "1 rep" : "\(set.reps) reps")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if equipment != .bodyweight {
                                Button(set.weight?.label ?? "Add weight") {
                                    editing = WeightEditTarget(entryID: entry.id, setIndex: index, equipment: equipment)
                                }
                                .buttonStyle(.borderless)
                                .frame(minWidth: 96, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text(entry.name + outcomeLabel(entry.outcome))
                }
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            WeightEditorView(weight: weight(at: target), equipment: target.equipment) { weight, applyToLater in
                update(target, weight: weight, applyToLater: applyToLater)
            }
            .presentationDetents([.medium])
        }
    }

    /// One-arm exercises record each arm as its own entry; both share a set number.
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

    private func update(_ target: WeightEditTarget, weight: WorkoutWeight?, applyToLater: Bool) {
        guard let entryIndex = record.entries.firstIndex(where: { $0.id == target.entryID }) else { return }
        let sets = record.entries[entryIndex].sets.indices
        for index in sets where index == target.setIndex || (applyToLater && index > target.setIndex) {
            record.entries[entryIndex].sets[index].weight = weight
        }
        try? appRepositories?.workoutHistory.updateWeights(for: record)
    }
}

private struct WeightEditTarget: Identifiable {
    let entryID: UUID
    let setIndex: Int
    let equipment: ExerciseEquipment
    var id: String { "\(entryID)-\(setIndex)" }
}

/// Enters a weight per dumbbell (pounds or kilograms) or a band's name, optionally for the later sets too.
struct WeightEditorView: View {
    let equipment: ExerciseEquipment
    let onSave: (WorkoutWeight?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    @State private var unit: WeightUnit = .pounds
    @State private var bandName = ""
    @State private var applyToLater = true

    init(weight: WorkoutWeight?, equipment: ExerciseEquipment, onSave: @escaping (WorkoutWeight?, Bool) -> Void) {
        self.equipment = equipment
        self.onSave = onSave
        switch weight {
        case .mass(let amount, let massUnit):
            _value = State(initialValue: amount)
            _unit = State(initialValue: massUnit)
        case .band(let name):
            _bandName = State(initialValue: name)
        case nil:
            break
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
        }
    }
}
