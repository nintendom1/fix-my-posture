import AdaptiveTraining
import Foundation
import Observation

enum AdaptiveTrainingSettingsCopy {
    static let initialDescription = "Find a comfortable starting point in a few minutes. A few tiny samples, then a short session each day."
    static let unavailable = "Adaptive Training isn't available right now."
    static let calibrationUnavailable = "Finding a starting point isn't available right now."
    static let saveFailed = "We couldn't save that change. Please try again."
    static let recalibrationFooter = "Recalibrating checks each area with a tiny sample. Nothing changes unless you tap Use these."
    static let equipmentFooter = "Exercises that need equipment you don't have are never offered."
    static let notSetUp = "Not set up"
    static let sampleRemovalPrompt = "Remove Push from Today's Session? Its history stays."

    /// Every fixed user-facing string in the Adaptive Training Settings page and model.
    static let all: [String] = [
        initialDescription, unavailable, calibrationUnavailable, saveFailed, recalibrationFooter, equipmentFooter,
        notSetUp, sampleRemovalPrompt, "Adaptive Training", "Your areas", "Remove", "Add an area", "Recalibrate",
        "Equipment", "Find your starting point"
    ]
}

/// The state of Settings › Adaptive Training: each area in plain words, calibration, areas, and equipment.
@MainActor
@Observable
final class AdaptiveTrainingSettingsViewModel {
    struct AreaLine: Hashable, Identifiable {
        let family: MovementFamilyID
        let text: String
        var id: MovementFamilyID { family }
    }

    enum PageSection: Equatable, Identifiable {
        case unavailable
        case notCalibrated
        case areas([AreaLine], canRemove: Bool)
        case addArea
        case recalibrate
        case equipment([TrainingEquipment])
        case notice(String)

        var id: String {
            switch self {
            case .unavailable: return "unavailable"
            case .notCalibrated: return "notCalibrated"
            case .areas: return "areas"
            case .addArea: return "addArea"
            case .recalibrate: return "recalibrate"
            case .equipment: return "equipment"
            case .notice: return "notice"
            }
        }
    }

    @ObservationIgnored private let provider: any AdaptiveTrainingSettingsProviding
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let openCalibration: @MainActor (CalibrationKind) -> Void

    private(set) var overview: AdaptiveTrainingOverview?
    private(set) var notice: String?
    private(set) var pendingRemoval: MovementFamilyID?

    init(provider: any AdaptiveTrainingSettingsProviding, now: @escaping () -> Date = Date.init,
         openCalibration: @escaping @MainActor (CalibrationKind) -> Void) {
        self.provider = provider
        self.now = now
        self.openCalibration = openCalibration
    }

    var isAvailable: Bool { overview != nil }
    var needsCalibration: Bool { overview?.needsCalibration ?? true }
    var canRemoveAreas: Bool { overview?.canRemoveAreas ?? false }
    var showsAddArea: Bool { !(overview?.addableFamilies.isEmpty ?? true) }
    var equipment: Set<TrainingEquipment> { Set(overview?.equipment ?? []) }

    var rowValue: String {
        guard let overview, !overview.needsCalibration else { return AdaptiveTrainingSettingsCopy.notSetUp }
        return overview.areas.map { CalibrationCopy.areaName($0.family) }.joined(separator: " · ")
    }

    var areaLines: [AreaLine] {
        (overview?.areas ?? []).map { area in
            AreaLine(family: area.family,
                     text: CalibrationCopy.summaryLine(area: CalibrationCopy.areaName(area.family),
                                                       exercise: provider.displayName(of: area.current.variant),
                                                       dose: area.current.dose))
        }
    }

    /// The page's rendered sections, in display order, from the current package overview.
    var pageSections: [PageSection] {
        var sections: [PageSection]
        guard let overview else {
            sections = [.unavailable]
            if let notice { sections.append(.notice(notice)) }
            return sections
        }
        if overview.needsCalibration {
            sections = [.notCalibrated]
        } else {
            sections = [.areas(areaLines, canRemove: overview.canRemoveAreas)]
            if !overview.addableFamilies.isEmpty { sections.append(.addArea) }
            sections.append(.recalibrate)
            sections.append(.equipment(TrainingEquipment.allCases))
        }
        if let notice { sections.append(.notice(notice)) }
        return sections
    }

    var removalConfirmationTitle: String {
        guard let pendingRemoval else { return "" }
        return "Remove \(CalibrationCopy.areaName(pendingRemoval)) from Today's Session? Its history stays."
    }

    func refresh() {
        overview = provider.overview()
    }

    func findStartingPoint() {
        requestCalibration(.initial)
    }

    func addArea() {
        requestCalibration(.addFamily)
    }

    func recalibrate() {
        requestCalibration(.recalibration)
    }

    func requestRemoval(of family: MovementFamilyID) {
        guard canRemoveAreas, overview?.areas.contains(where: { $0.family == family }) == true else { return }
        pendingRemoval = family
        notice = nil
    }

    func confirmRemoval() {
        guard let family = pendingRemoval else { return }
        pendingRemoval = nil
        guard provider.removeArea(family, asOf: now()) else {
            failSave()
            return
        }
        notice = nil
        refresh()
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    func setEquipment(_ item: TrainingEquipment, isOn: Bool) {
        guard let overview else { return }
        var next = Set(overview.equipment)
        if isOn { next.insert(item) } else { next.remove(item) }
        guard provider.setEquipment(next, asOf: now()) else {
            failSave()
            return
        }
        notice = nil
        refresh()
    }

    func showCalibrationUnavailableNotice() {
        notice = AdaptiveTrainingSettingsCopy.calibrationUnavailable
    }

    private func requestCalibration(_ kind: CalibrationKind) {
        notice = nil
        openCalibration(kind)
    }

    private func failSave() {
        notice = AdaptiveTrainingSettingsCopy.saveFailed
        refresh()
    }
}
