import Foundation

/// Chooses today's family and prescription from the profile. Context only changes the returned session.
struct TodaySessionPlanner {
    let catalog: ProgressionCatalog
    let builtExerciseIDs: Set<String>
    let parameters: PolicyParameters
    let calendar: Calendar

    func status(profile: AdaptiveProfile, facts: AdaptiveFacts, asOf now: Date,
                context: SessionContext) -> TodaySessionStatus {
        guard !profile.states.isEmpty else { return .needsCalibration }
        guard !profile.activeFamilies.isEmpty else { return .nothingOffered }

        if let completed = completedFamily(facts: facts, on: now) {
            return .completedToday(family: completed, next: makeSession(profile: profile, family: nextFamily(
                profile: profile, mostRecent: completed, at: now), asOf: now, context: context))
        }

        guard let family = nextFamily(profile: profile, mostRecent: nil, at: now),
              let session = makeSession(profile: profile, family: family, asOf: now, context: context) else {
            return .nothingOffered
        }
        return .ready(session)
    }

    private func completedFamily(facts: AdaptiveFacts, on date: Date) -> MovementFamilyID? {
        let prescriptions = Dictionary(facts.prescriptions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = Dictionary(facts.prescriptions.flatMap { prescription in
            prescription.items.map { ($0.id, ($0, prescription.id)) }
        }, uniquingKeysWith: { first, _ in first })
        let completed = facts.evidence.filter { evidence in
            guard evidence.source == .adaptive, calendar.isDate(evidence.recordedAt, inSameDayAs: date),
                  [.completed, .stoppedEarly, .switchedToEasier].contains(evidence.completion),
                  let itemID = evidence.prescriptionItemID, let (item, prescriptionID) = items[itemID],
                  item.role == .main, item.family == evidence.family, evidence.prescriptionID == prescriptionID,
                  prescriptions[prescriptionID]?.kind == .todaySession else { return false }
            return true
        }
        // The latest one, independent of the order the store returned.
        return completed.max { ($0.recordedAt, $0.id.uuidString) < ($1.recordedAt, $1.id.uuidString) }?.family
    }

    private func nextFamily(profile: AdaptiveProfile, mostRecent: MovementFamilyID?, at date: Date) -> MovementFamilyID? {
        let positions = Dictionary(uniqueKeysWithValues: catalog.families.enumerated().map { ($0.element.id, $0.offset) })
        return profile.activeFamilies.min { left, right in
            let leftDate = left == mostRecent ? date : profile.state(left)?.lastPerformedAt
            let rightDate = right == mostRecent ? date : profile.state(right)?.lastPerformedAt
            switch (leftDate, rightDate) {
            case (nil, nil): return (positions[left] ?? Int.max) < (positions[right] ?? Int.max)
            case (nil, _): return true
            case (_, nil): return false
            case let (leftDate?, rightDate?):
                if leftDate != rightDate { return leftDate < rightDate }
                return (positions[left] ?? Int.max) < (positions[right] ?? Int.max)
            }
        }
    }

    private func makeSession(profile: AdaptiveProfile, family: MovementFamilyID?, asOf now: Date,
                             context: SessionContext) -> TodaySession? {
        guard let family, let state = profile.state(family),
              let ladder = catalog.family(family),
              let availabilityFamily = catalog.floor(of: family, availability: availability(equipment: profile.equipment))
        else { return nil }

        let availability = availability(equipment: profile.equipment)
        let mainRung: ProgressionRung
        let fallbackDose: Dose?
        if let current = catalog.rung(state.current.variant), availability.isAvailable(current) {
            mainRung = current
            fallbackDose = nil
        } else if let currentIndex = ladder.index(of: state.current.variant),
                  let easier = ladder.rungs[..<currentIndex].last(where: availability.isAvailable) {
            mainRung = easier
            fallbackDose = easier.minimumDose
        } else {
            mainRung = availabilityFamily
            fallbackDose = availabilityFamily.minimumDose
        }
        let baseDose = fallbackDose ?? mainRung.doseRange.clamped(state.current.dose)
        let mainDose = context.tiny ? mainRung.minimumDose : baseDose
        let main = RungDose(variant: mainRung.id, dose: mainDose)

        let blocked = state.harderSampleBlockedUntil.map { $0 > now } ?? false
        let sample: RungDose?
        if !context.tiny, state.harderSampleDue, !blocked,
           let harder = catalog.harder(than: mainRung.id, availability: availability) {
            sample = RungDose(variant: harder.id, dose: harder.minimumDose)
        } else {
            sample = nil
        }

        let latestTransition = profile.transitions.last { $0.family == family && $0.kind != .recordOnly }
        let rationale = latestTransition?.rationale.summary ?? "\(ladder.debugName): starting point from calibration."
        let baseSeconds: Int
        if mainDose.kind == .reps {
            let (scaled, overflow) = mainDose.amount.multipliedReportingOverflow(by: 4)
            baseSeconds = overflow ? Int.max : scaled
        } else {
            baseSeconds = mainDose.amount
        }
        let (withSetup, setupOverflow) = baseSeconds.addingReportingOverflow(45)
        let (estimatedSeconds, sampleOverflow) = withSetup.addingReportingOverflow(sample == nil ? 0 : 25)
        let estimate = setupOverflow || sampleOverflow ? Int.max : estimatedSeconds
        let confidence = profile.confidence(of: family, asOf: now, parameters: parameters) ?? .medium
        return TodaySession(family: family, main: main, harderSample: sample, offersBonus: true,
                            isTiny: mainDose == mainRung.minimumDose, confidence: confidence,
                            estimatedSeconds: estimate,
                            rationale: rationale, basedOnTransitionID: latestTransition?.id)
    }

    private func availability(equipment: [TrainingEquipment]) -> Availability {
        Availability(builtExerciseIDs: builtExerciseIDs, equipment: Set(equipment))
    }
}
