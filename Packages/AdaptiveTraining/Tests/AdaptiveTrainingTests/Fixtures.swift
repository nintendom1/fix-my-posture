import Foundation
@testable import AdaptiveTraining

enum Fixtures {
    static let catalog = ProgressionCatalog.v1
    static let wall = VariantID(rawValue: "push.wall_push_up")
    static let shallowWall = VariantID(rawValue: "push.wall_push_up.shallow")
    static let incline = VariantID(rawValue: "push.incline_push_up")
    static let pushUp = VariantID(rawValue: "push.push_up")
    static let gluteHold = VariantID(rawValue: "glute.glute_squeeze")
    static let allBuiltExerciseIDs = Set(catalog.families.flatMap { $0.rungs.map(\.exerciseID) })

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }

    /// 2025-01-15 12:00 in Los Angeles. Test dates remain in standard time.
    static let anchor = Date(timeIntervalSince1970: 1_736_971_200)

    static func date(day: Int = 0, hour: Int = 12) -> Date {
        anchor.addingTimeInterval(TimeInterval(day * 86_400 + (hour - 12) * 3_600))
    }

    static func id(_ number: Int) -> UUID {
        let value = UInt8(truncatingIfNeeded: number)
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    static func calibration(id: Int = 1, day: Int = 0, family: MovementFamilyID = .push,
                            variant: VariantID = wall, dose: Dose = .reps(3),
                            status: CalibrationStatus = .committed,
                            kind: CalibrationKind = .initial,
                            families: [MovementFamilyID]? = nil,
                            starts: [CalibrationStart]? = nil,
                            equipment: [TrainingEquipment]? = nil) -> CalibrationSessionRecord {
        CalibrationSessionRecord(id: self.id(id), kind: kind, startedAt: date(day: day, hour: 10),
                                  endedAt: date(day: day, hour: 12), status: status,
                                  families: families ?? [family], equipment: equipment,
                                  startingPoints: starts ?? [CalibrationStart(family: family,
                                                                              start: RungDose(variant: variant,
                                                                                              dose: dose))])
    }

    static func evidence(id: Int, day: Int = 1, hour: Int = 12,
                         family: MovementFamilyID = .push, variant: VariantID = wall,
                         source: EvidenceSource = .adaptive, prescribed: Dose? = .reps(3),
                         confirmed: WorkAmount? = .reps(3), confirmation: ConfirmationSource? = nil,
                         setAmounts: [WorkAmount]? = nil, tracker: TrackerObservation = .notTracked,
                         effort: EffortFeedback? = .easy, completion: CompletionReason = .completed,
                         itemID: Int? = nil, prescriptionID: Int? = nil, calibrationID: Int? = nil,
                         bonus: BonusRecord? = nil, midSetTooHard: Bool = false) -> AdaptiveEvidence {
        let idValue = self.id(id)
        let confirmationValue = confirmation ?? (confirmed == nil ? .none : .user)
        return AdaptiveEvidence(id: idValue, recordedAt: date(day: day, hour: hour), source: source,
                                family: family, variant: variant, prescriptionID: prescriptionID.map(self.id),
                                prescriptionItemID: itemID.map(self.id), calibrationID: calibrationID.map(self.id),
                                prescribed: prescribed, confirmed: confirmed, confirmation: confirmationValue,
                                setAmounts: setAmounts, tracker: tracker, effort: effort,
                                midSetTooHard: midSetTooHard, bonus: bonus, completion: completion)
    }

    static func prescription(id: Int, day: Int = 0, itemID: Int, family: MovementFamilyID = .push,
                             variant: VariantID = wall, dose: Dose = .reps(3),
                             role: PrescriptionItemRole = .main, kind: PrescriptionKind = .todaySession,
                             offersBonus: Bool = true) -> Prescription {
        Prescription(id: self.id(id), issuedAt: date(day: day, hour: 9), kind: kind,
                     policyVersion: .v1, catalogVersion: catalog.version,
                     items: [PrescriptionItem(id: self.id(itemID), family: family,
                                              target: RungDose(variant: variant, dose: dose),
                                              role: role, offersBonus: offersBonus)],
                     rationale: "Fixed test prescription.")
    }

    static func profile(_ facts: AdaptiveFacts, builtExerciseIDs: Set<String> = allBuiltExerciseIDs,
                        parameters: PolicyParameters = .standard) -> AdaptiveProfile {
        AdaptiveReplay.profile(facts: facts, catalog: catalog, builtExerciseIDs: builtExerciseIDs,
                              parameters: parameters, calendar: calendar)
    }

    static func seededFacts(family: MovementFamilyID = .push, variant: VariantID = wall,
                            dose: Dose = .reps(3), day: Int = 0,
                            calibrationID: Int = 1) -> AdaptiveFacts {
        AdaptiveFacts(calibrations: [calibration(id: calibrationID, day: day, family: family,
                                                  variant: variant, dose: dose)])
    }

    static func lastTransition(_ profile: AdaptiveProfile, factID: UUID) -> Transition? {
        profile.transitions.last { $0.id == factID }
    }
}
