import Foundation

/// Replays facts in time order under policy V1 to rebuild the profile.
struct AdaptiveProjector {
    let catalog: ProgressionCatalog
    let builtExerciseIDs: Set<String>
    let parameters: PolicyParameters
    let calendar: Calendar

    func replay(_ facts: AdaptiveFacts) -> AdaptiveProfile {
        let policy = RecommendationPolicyV1(catalog: catalog, parameters: parameters, calendar: calendar)
        let items = Dictionary(facts.prescriptions.flatMap { prescription in
            prescription.items.map { ($0.id, ($0, prescription.id)) }
        }, uniquingKeysWith: { first, _ in first })
        let committedCalibrationIDs = Set(facts.calibrations.filter { $0.status == .committed }.map(\.id))

        var timeline: [ReplayItem] = facts.calibrations.map { .calibration($0) }
        timeline += facts.evidence.compactMap { evidence in
            if let calibrationID = evidence.calibrationID, committedCalibrationIDs.contains(calibrationID) {
                return nil
            }
            return .evidence(evidence)
        }
        timeline += facts.settings.map(ReplayItem.setting)
        timeline += facts.engagement.map(ReplayItem.engagement)
        timeline.sort(by: ReplayItem.precedes)

        var states: [MovementFamilyID: MovementState] = [:]
        var active = Set<MovementFamilyID>()
        var streakIDs: [MovementFamilyID: [UUID]] = [:]
        var equipment = Set<TrainingEquipment>()
        var transitions: [Transition] = []

        for event in timeline {
            switch event {
            case .evidence(let evidence):
                let role = evidence.prescriptionItemID.flatMap { itemID -> PrescriptionItemRole? in
                    guard let (item, prescriptionID) = items[itemID], prescriptionID == evidence.prescriptionID,
                          item.family == evidence.family else { return nil }
                    return item.role
                }
                if evidence.calibrationID != nil {
                    let state = states[evidence.family]
                    let target = state?.current ?? evidenceTarget(evidence, catalog: catalog)
                    appendTransition(id: evidence.id, at: evidence.recordedAt, family: evidence.family,
                                     kind: .recordOnly, from: state?.current, to: state?.current,
                                     confidence: state?.confidence, target: target,
                                     codes: [.calibrationNotCommitted] + (evidence.bonus == nil ? [] : [.bonusRecordedOnly]),
                                     factIDs: [evidence.id],
                                     why: "This calibration has not been committed.",
                                     catalog: catalog, transitions: &transitions)
                    continue
                }
                let state = states[evidence.family]
                let outcome = policy.apply(evidence, role: role, state: state,
                                           isActive: active.contains(evidence.family),
                                           streakFactIDs: streakIDs[evidence.family] ?? [],
                                           availability: currentAvailability(equipment), at: evidence.recordedAt)
                if let next = outcome.state, state != nil { states[evidence.family] = next }
                updateStreak(for: evidence, previous: state, outcome: outcome, in: &streakIDs)
                appendTransition(id: evidence.id, at: evidence.recordedAt, family: evidence.family,
                                 kind: outcome.kind, from: outcome.from, to: outcome.state?.current,
                                 confidence: outcome.state?.confidence, target: outcome.target,
                                 codes: outcome.codes, factIDs: outcome.factIDs, why: outcome.why,
                                 catalog: catalog, transitions: &transitions)

            case .calibration(let calibration):
                guard calibration.status == .committed else {
                    for familyID in catalogOrdered(calibration.families) {
                        let state = states[familyID]
                        let target = state?.current ?? calibrationTarget(for: familyID, starts: calibration.startingPoints,
                                                                         availability: currentAvailability(equipment))
                            ?? calibration.startingPoints.first(where: { $0.family == familyID })?.start
                            ?? catalog.family(familyID)?.floor.map { RungDose(variant: $0.id, dose: $0.minimumDose) }
                            ?? RungDose(variant: VariantID(rawValue: "\(familyID.rawValue).unavailable"), dose: .reps(1))
                        appendTransition(id: calibration.id, at: calibration.endedAt ?? calibration.startedAt,
                                         family: familyID, kind: .recordOnly, from: state?.current, to: state?.current,
                                         confidence: state?.confidence, target: target,
                                         codes: [.calibrationNotCommitted], factIDs: [calibration.id],
                                         why: "This calibration was not committed.", catalog: catalog,
                                         transitions: &transitions)
                    }
                    continue
                }

                let committedAt = calibration.endedAt ?? calibration.startedAt
                if let newEquipment = calibration.equipment { equipment = Set(newEquipment) }
                let probeEvidence = facts.evidence.filter { $0.calibrationID == calibration.id }
                    .sorted(by: evidencePrecedes)
                var latestProbe: [MovementFamilyID: Date] = [:]
                // Comfortable doses per family as the probes update them, seeded from any existing state.
                var probeComfort: [MovementFamilyID: [VariantID: ComfortableDose]] = [:]
                for probe in probeEvidence {
                    let old = states[probe.family]
                    let outcome = policy.applyProbe(probe, state: old)
                    if probe.completion != .notAttempted {
                        latestProbe[probe.family] = max(latestProbe[probe.family] ?? probe.recordedAt, probe.recordedAt)
                    }
                    var comfort = probeComfort[probe.family] ?? comfortByVariant(old?.comfortableDoses ?? [])
                    policy.applyProbeComfort(probe, to: &comfort)
                    probeComfort[probe.family] = comfort
                    if var next = outcome.state, old != nil {
                        next.comfortableDoses = comfort.values.sorted { $0.variant < $1.variant }
                        states[probe.family] = next
                    }
                    let target = outcome.state?.current ?? outcome.target
                    appendTransition(id: probe.id, at: committedAt, family: probe.family,
                                     kind: .recordOnly, from: old?.current, to: outcome.state?.current,
                                     confidence: outcome.state?.confidence, target: target,
                                     codes: outcome.codes, factIDs: outcome.factIDs, why: outcome.why,
                                     catalog: catalog, transitions: &transitions)
                }

                let starts = calibration.startingPoints.sorted { left, right in
                    catalogIndex(left.family) == catalogIndex(right.family)
                        ? left.start.variant < right.start.variant
                        : catalogIndex(left.family) < catalogIndex(right.family)
                }
                for start in starts {
                    let old = states[start.family]
                    guard let target = resolvedCalibrationTarget(start, availability: currentAvailability(equipment)) else {
                        let fallback = old?.current ?? RungDose(variant: start.start.variant, dose: start.start.dose)
                        appendTransition(id: calibration.id, at: committedAt, family: start.family,
                                         kind: .recordOnly, from: old?.current, to: old?.current,
                                         confidence: old?.confidence, target: fallback,
                                         codes: [.rungUnavailable], factIDs: [calibration.id],
                                         why: "No available starting rung can be offered.", catalog: catalog,
                                         transitions: &transitions)
                        continue
                    }

                    let comfortable = probeComfort[start.family] ?? comfortByVariant(old?.comfortableDoses ?? [])
                    let state = MovementState(family: start.family, current: target, confidence: .medium,
                                              lastPerformedAt: [latestProbe[start.family], old?.lastPerformedAt]
                                                .compactMap { $0 }.max(),
                                              lastChangedAt: committedAt,
                                              comfortableDoses: Array(comfortable.values), easyStreak: 0,
                                              lastEasyAt: nil, harderSampleDue: false,
                                              harderSampleBlockedUntil: nil)
                    states[start.family] = state
                    active.insert(start.family)
                    streakIDs[start.family] = []
                    appendTransition(id: calibration.id, at: committedAt, family: start.family, kind: .start,
                                     from: old?.current, to: target, confidence: state.confidence, target: target,
                                     codes: [.calibrationCommitted], factIDs: [calibration.id],
                                     why: "Starting point from calibration.", catalog: catalog,
                                     transitions: &transitions)
                }

            case .setting(let setting):
                if setting.kind == .familyRemoved {
                    guard let family = setting.family else { continue }
                    let state = states[family]
                    active.remove(family)
                    streakIDs[family] = []
                    let target = state?.current ?? catalog.floorPrescription(of: family,
                                                                             availability: currentAvailability(equipment))
                        ?? catalog.family(family)?.floor.map { RungDose(variant: $0.id, dose: $0.minimumDose) }
                        ?? RungDose(variant: VariantID(rawValue: "\(family.rawValue).unavailable"), dose: .reps(1))
                    appendTransition(id: setting.id, at: setting.recordedAt, family: family, kind: .deactivate,
                                     from: state?.current, to: state?.current, confidence: state?.confidence,
                                     target: target, codes: [.familyRemoved], factIDs: [setting.id],
                                     why: "This family was removed from the rotation.", catalog: catalog,
                                     transitions: &transitions)
                    continue
                }

                equipment = Set(setting.equipment ?? [])
                let availability = currentAvailability(equipment)
                for family in catalog.families where active.contains(family.id) {
                    guard var state = states[family.id],
                          let currentRung = catalog.rung(state.current.variant),
                          !availability.isAvailable(currentRung) else { continue }
                    guard let target = equipmentFallback(for: state, family: family, availability: availability) else {
                        appendTransition(id: setting.id, at: setting.recordedAt, family: family.id,
                                         kind: .recordOnly, from: state.current, to: state.current,
                                         confidence: state.confidence, target: state.current,
                                         codes: [.equipmentChanged, .rungUnavailable], factIDs: [setting.id],
                                         why: "The current rung is unavailable and no fallback is built.",
                                         catalog: catalog, transitions: &transitions)
                        continue
                    }
                    let old = state.current
                    state.current = target
                    state.lastChangedAt = setting.recordedAt
                    state.easyStreak = 0
                    state.lastEasyAt = nil
                    state.harderSampleDue = false
                    states[family.id] = state
                    streakIDs[family.id] = []
                    appendTransition(id: setting.id, at: setting.recordedAt, family: family.id,
                                     kind: .easierVariant, from: old, to: target, confidence: state.confidence,
                                     target: target, codes: [.equipmentChanged, .rungUnavailable],
                                     factIDs: [setting.id], why: "Equipment changed; move to the nearest available easier rung.",
                                     catalog: catalog, transitions: &transitions)
                }

            case .engagement(let engagement):
                guard let family = engagement.family else { continue }
                let state = states[family]
                let target = state?.current ?? catalog.floorPrescription(of: family,
                                                                         availability: currentAvailability(equipment))
                    ?? RungDose(variant: VariantID(rawValue: "\(family.rawValue).unavailable"), dose: .reps(1))
                appendTransition(id: engagement.id, at: engagement.recordedAt, family: family, kind: .recordOnly,
                                 from: state?.current, to: state?.current, confidence: state?.confidence,
                                 target: target, codes: [], factIDs: [engagement.id],
                                 why: "Engagement is recorded without changing capacity.", catalog: catalog,
                                 transitions: &transitions)
            }
        }

        let finalAvailability = currentAvailability(equipment)
        let orderedStates = catalog.families.compactMap { states[$0.id] }
        let activeFamilies = catalog.families.map(\.id).filter {
            active.contains($0) && catalog.floor(of: $0, availability: finalAvailability) != nil
        }
        return AdaptiveProfile(policyVersion: .v1, catalogVersion: catalog.version, states: orderedStates,
                               activeFamilies: activeFamilies, equipment: equipment.sorted(), transitions: transitions)
    }

    private func updateStreak(for evidence: AdaptiveEvidence, previous: MovementState?, outcome: PolicyOutcome,
                              in streakIDs: inout [MovementFamilyID: [UUID]]) {
        guard let next = outcome.state else { return }
        if next.easyStreak == 0 {
            streakIDs[evidence.family] = []
        } else if !outcome.openStreakFactIDs.isEmpty {
            streakIDs[evidence.family] = outcome.openStreakFactIDs
        } else if previous?.easyStreak != next.easyStreak {
            streakIDs[evidence.family] = [evidence.id]
        }
    }

    private func resolvedCalibrationTarget(_ start: CalibrationStart, availability: Availability) -> RungDose? {
        guard let family = catalog.family(start.family) else { return nil }
        if let rung = catalog.rung(start.start.variant), family.index(of: rung.id) != nil {
            if availability.isAvailable(rung) {
                return RungDose(variant: rung.id, dose: rung.doseRange.clamped(start.start.dose))
            }
            if let easier = catalog.easier(than: rung.id, availability: availability) {
                return RungDose(variant: easier.id, dose: easier.minimumDose)
            }
        }
        return catalog.floorPrescription(of: start.family, availability: availability)
    }

    private func calibrationTarget(for family: MovementFamilyID, starts: [CalibrationStart],
                                   availability: Availability) -> RungDose? {
        guard let start = starts.first(where: { $0.family == family }) else {
            return catalog.floorPrescription(of: family, availability: availability)
        }
        return resolvedCalibrationTarget(start, availability: availability)
    }

    private func equipmentFallback(for state: MovementState, family: MovementFamily,
                                   availability: Availability) -> RungDose? {
        if let easier = catalog.easier(than: state.current.variant, availability: availability) {
            let dose = state.comfortableDose(on: easier.id).map { easier.doseRange.clamped($0.dose) }
                ?? easier.minimumDose
            return RungDose(variant: easier.id, dose: dose)
        }
        if let floor = catalog.floor(of: family.id, availability: availability) {
            return RungDose(variant: floor.id, dose: floor.minimumDose)
        }
        return nil
    }

    private func currentAvailability(_ equipment: Set<TrainingEquipment>) -> Availability {
        Availability(builtExerciseIDs: builtExerciseIDs, equipment: equipment)
    }

    private func comfortByVariant(_ doses: [ComfortableDose]) -> [VariantID: ComfortableDose] {
        Dictionary(doses.map { ($0.variant, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func catalogOrdered(_ families: [MovementFamilyID]) -> [MovementFamilyID] {
        let supplied = Set(families)
        return catalog.families.map(\.id).filter(supplied.contains)
            + families.filter { catalogIndex($0) == Int.max }.sorted()
    }

    private func catalogIndex(_ family: MovementFamilyID) -> Int {
        catalog.families.firstIndex { $0.id == family } ?? Int.max
    }

    private func appendTransition(id: UUID, at: Date, family: MovementFamilyID, kind: DecisionKind,
                                  from: RungDose?, to: RungDose?, confidence: RecommendationConfidence?,
                                  target: RungDose, codes: [ReasonCode], factIDs: [UUID], why: String,
                                  catalog: ProgressionCatalog, transitions: inout [Transition]) {
        let name = catalog.family(family)?.debugName ?? family.rawValue
        let summary = "\(name): \(target.variant.rawValue) × \(target.dose). \(why)"
        transitions.append(Transition(id: id, at: at, family: family, kind: kind, from: from, to: to,
                                       confidence: confidence, rationale: Rationale(codes: codes,
                                                                                  factIDs: factIDs,
                                                                                  summary: summary)))
    }
}

private func evidenceTarget(_ evidence: AdaptiveEvidence, catalog: ProgressionCatalog) -> RungDose {
    let dose = evidence.prescribed ?? evidence.confirmed?.dose ?? catalog.rung(evidence.variant)?.minimumDose ?? .reps(1)
    return RungDose(variant: evidence.variant, dose: dose)
}

private func evidencePrecedes(_ left: AdaptiveEvidence, _ right: AdaptiveEvidence) -> Bool {
    left.recordedAt == right.recordedAt ? left.id.uuidString < right.id.uuidString : left.recordedAt < right.recordedAt
}

private enum ReplayItem {
    case evidence(AdaptiveEvidence)
    case calibration(CalibrationSessionRecord)
    case setting(SettingsFact)
    case engagement(EngagementFact)

    var date: Date {
        switch self {
        case .evidence(let value): return value.recordedAt
        case .calibration(let value): return value.endedAt ?? value.startedAt
        case .setting(let value): return value.recordedAt
        case .engagement(let value): return value.recordedAt
        }
    }

    var id: UUID {
        switch self {
        case .evidence(let value): return value.id
        case .calibration(let value): return value.id
        case .setting(let value): return value.id
        case .engagement(let value): return value.id
        }
    }

    static func precedes(_ left: ReplayItem, _ right: ReplayItem) -> Bool {
        if left.date != right.date { return left.date < right.date }
        if left.id.uuidString != right.id.uuidString { return left.id.uuidString < right.id.uuidString }
        return left.kindOrder < right.kindOrder
    }

    private var kindOrder: Int {
        switch self {
        case .evidence: return 0
        case .calibration: return 1
        case .setting: return 2
        case .engagement: return 3
        }
    }
}
