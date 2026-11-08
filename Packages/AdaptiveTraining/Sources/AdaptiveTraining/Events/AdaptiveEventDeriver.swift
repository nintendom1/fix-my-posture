import Foundation

/// Derives semantic events from facts and replayed transitions.
enum AdaptiveEventDeriver {
    static func events(facts: AdaptiveFacts, profile: AdaptiveProfile) -> [AdaptiveEvent] {
        var result = EventList()
        let prescriptions = Dictionary(facts.prescriptions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = Dictionary(facts.prescriptions.flatMap { prescription in
            prescription.items.map { ($0.id, (item: $0, prescriptionID: prescription.id,
                                             kind: prescription.kind)) }
        }, uniquingKeysWith: { first, _ in first })

        for calibration in facts.calibrations where calibration.status == .committed {
            guard let start = profile.transitions.first(where: { $0.id == calibration.id && $0.kind == .start }) else {
                continue
            }
            let kind: AdaptiveEventKind = calibration.kind == .recalibration
                ? .recalibrationCompleted : .calibrationCompleted
            append(kind, family: nil, at: start.at, factID: calibration.id, into: &result)
        }

        for transition in profile.transitions {
            switch transition.kind {
            case .increaseDose, .harderVariant:
                append(.progressed, family: transition.family, at: transition.at, factID: transition.id,
                       from: transition.from, to: transition.to, into: &result)
            case .decreaseDose, .easierVariant:
                append(.regressed, family: transition.family, at: transition.at, factID: transition.id,
                       from: transition.from, to: transition.to, into: &result)
            default:
                break
            }
            if transition.rationale.codes.contains(.returnedAfterAbsence) {
                append(.returnedAfterAbsence, family: transition.family, at: transition.at,
                       factID: transition.id, into: &result)
            }
        }

        for evidence in facts.evidence {
            if evidence.calibrationID == nil, let effort = evidence.effort {
                let kind: AdaptiveEventKind
                switch effort {
                case .tooHard: kind = .effortTooHard
                case .okay: kind = .effortOkay
                case .easy: kind = .effortEasy
                }
                append(kind, family: evidence.family, at: evidence.recordedAt, factID: evidence.id, into: &result)
            }

            if isTodaySessionMain(evidence, items: items, prescriptions: prescriptions),
               [.completed, .stoppedEarly, .switchedToEasier].contains(evidence.completion) {
                append(.sessionCompleted, family: evidence.family, at: evidence.recordedAt,
                       factID: evidence.id, into: &result)
            }

            if let bonus = evidence.bonus {
                append(.bonusOffered, family: evidence.family, at: evidence.recordedAt,
                       factID: evidence.id, into: &result)
                append(bonus.accepted ? .bonusAccepted : .bonusDeclined, family: evidence.family,
                       at: evidence.recordedAt, factID: evidence.id, into: &result)
            }
        }

        let order = Dictionary(uniqueKeysWithValues: AdaptiveEventKind.allCases.enumerated().map { ($0.element, $0.offset) })
        return result.events.sorted { left, right in
            if left.at != right.at { return left.at < right.at }
            if left.factID.uuidString != right.factID.uuidString { return left.factID.uuidString < right.factID.uuidString }
            let leftOrder = order[left.kind] ?? Int.max
            let rightOrder = order[right.kind] ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return (left.family?.rawValue ?? "") < (right.family?.rawValue ?? "")
        }
    }

    private static func isTodaySessionMain(_ evidence: AdaptiveEvidence,
                                           items: [UUID: (item: PrescriptionItem, prescriptionID: UUID,
                                                         kind: PrescriptionKind)],
                                           prescriptions: [UUID: Prescription]) -> Bool {
        guard evidence.source == .adaptive, let itemID = evidence.prescriptionItemID,
              let entry = items[itemID], entry.item.role == .main, entry.item.family == evidence.family,
              entry.prescriptionID == evidence.prescriptionID,
              entry.kind == .todaySession, prescriptions[entry.prescriptionID] != nil else { return false }
        return true
    }

    private static func append(_ kind: AdaptiveEventKind, family: MovementFamilyID?, at: Date, factID: UUID,
                               from: RungDose? = nil, to: RungDose? = nil, into list: inout EventList) {
        let key = "\(kind.rawValue)|\(family?.rawValue ?? "")|\(factID.uuidString)"
        guard list.keys.insert(key).inserted else { return }
        list.events.append(AdaptiveEvent(kind: kind, family: family, at: at, factID: factID, from: from, to: to))
    }

    /// Events plus the (kind, family, fact) keys already derived, so each is derived once.
    private struct EventList {
        var events: [AdaptiveEvent] = []
        var keys: Set<String> = []
    }
}
