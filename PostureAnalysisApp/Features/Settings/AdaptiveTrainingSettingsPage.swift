import SwiftUI
import AdaptiveTraining

/// Settings › Adaptive Training.
struct AdaptiveTrainingSettingsPage: View {
    @Bindable var viewModel: AdaptiveTrainingSettingsViewModel

    var body: some View {
        SettingsSubpage(title: "Adaptive Training") {
            ForEach(viewModel.pageSections) { section in
                content(for: section)
            }
        }
        .accessibilityIdentifier("adaptiveSettingsPage")
        .task { viewModel.refresh() }
        .confirmationDialog(viewModel.removalConfirmationTitle, isPresented: removalBinding,
                           titleVisibility: .visible) {
            Button("Remove", role: .destructive) { viewModel.confirmRemoval() }
                .accessibilityIdentifier("adaptiveSettingsConfirmRemove")
            Button("Cancel", role: .cancel) { viewModel.cancelRemoval() }
                .accessibilityIdentifier("adaptiveSettingsCancelRemove")
        }
    }

    private var notCalibrated: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AdaptiveTrainingSettingsCopy.initialDescription)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("adaptiveSettingsInitialDescription")
            primaryButton("Find your starting point", identifier: "adaptiveSettingsFindButton") {
                viewModel.findStartingPoint()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func content(for section: AdaptiveTrainingSettingsViewModel.PageSection) -> some View {
        switch section {
        case .unavailable:
            message(AdaptiveTrainingSettingsCopy.unavailable, identifier: "adaptiveSettingsUnavailable")
        case .notCalibrated:
            notCalibrated
        case .areas(let rows, let canRemove):
            areas(rows, canRemove: canRemove)
        case .addArea:
            addAreaRow
        case .recalibrate:
            recalibration
        case .equipment(let items):
            equipmentSection(items)
        case .notice(let notice):
            message(notice, identifier: "adaptiveSettingsNotice")
        }
    }

    private func areas(_ rows: [AdaptiveTrainingSettingsViewModel.AreaLine], canRemove: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            section(title: "Your areas", identifier: "adaptiveSettingsAreas") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, line in
                        HStack(spacing: 12) {
                            Text(line.text)
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(ColorTokens.palette().textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("adaptiveSettingsArea-\(line.family.rawValue)")
                            if canRemove {
                                Button("Remove") { viewModel.requestRemoval(of: line.family) }
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(ColorTokens.palette().textMuted)
                                    .accessibilityIdentifier("adaptiveSettingsRemove-\(line.family.rawValue)")
                            }
                        }
                        .frame(minHeight: 54)
                        .padding(.horizontal, 16)
                        .overlay(alignment: .top) {
                            if index > 0 { divider }
                        }
                    }
                }
                .background(ColorTokens.palette().backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var addAreaRow: some View {
        SettingsRow(icon: "add", title: "Add an area", iconColor: trainingPurple,
                    showsChevron: true, action: viewModel.addArea)
            .background(ColorTokens.palette().backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("adaptiveSettingsAddAreaButton")
    }

    private var recalibration: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(title: "Recalibrate", identifier: "adaptiveSettingsRecalibrate") {
                SettingsRow(icon: "refresh", title: "Recalibrate", iconColor: trainingPurple,
                            showsChevron: true, action: viewModel.recalibrate)
                    .accessibilityIdentifier("adaptiveSettingsRecalibrateButton")
                    .background(ColorTokens.palette().backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                footer(AdaptiveTrainingSettingsCopy.recalibrationFooter,
                       identifier: "adaptiveSettingsRecalibrationFooter")
            }
        }
    }

    private func equipmentSection(_ items: [TrainingEquipment]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            section(title: "Equipment", identifier: "adaptiveSettingsEquipment") {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        equipmentRow(item, separator: index > 0)
                    }
                }
                .background(ColorTokens.palette().backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                footer(AdaptiveTrainingSettingsCopy.equipmentFooter,
                       identifier: "adaptiveSettingsEquipmentFooter")
            }
        }
    }

    private func equipmentRow(_ item: TrainingEquipment, separator: Bool) -> some View {
        SettingsRow(
            icon: "fitness_center",
            title: CalibrationCopy.equipmentName(item),
            iconColor: trainingPurple,
            toggle: Binding(
                get: { viewModel.equipment.contains(item) },
                set: { viewModel.setEquipment(item, isOn: $0) }
            ),
            showsSeparator: separator
        )
        .accessibilityIdentifier("adaptiveSettingsEquipment-\(item.rawValue)")
    }

    private func section<Content: View>(title: String, identifier: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(0.85)
                .foregroundStyle(ColorTokens.palette().textMuted)
                .padding(.horizontal, 4)
                .accessibilityIdentifier(identifier)
            content()
        }
    }

    private func primaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(ColorTokens.palette().tabActive, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func message(_ value: String, identifier: String) -> some View {
        Text(value)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(ColorTokens.palette().textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier(identifier)
    }

    private func footer(_ value: String, identifier: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineSpacing(2)
            .foregroundStyle(ColorTokens.palette().textSubtle)
            .padding(.horizontal, 4)
            .accessibilityIdentifier(identifier)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { viewModel.pendingRemoval != nil }, set: { if !$0 { viewModel.cancelRemoval() } })
    }

    private let trainingPurple = Color(hex: 0x7C4DFF, alpha: 0.9)
}
