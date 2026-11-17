import Foundation
import AdaptiveTraining

/// Turns package-owned adaptive facts into persona observations. It never derives progression or rewrites an event.
enum AdaptiveEventDetector: PersonaDetecting {
    /// The runtime content keys required for supported package event kinds.
    static let contentKeys = [
        "adaptive.tinySessionPrescribed",
        "adaptive.sessionCompleted",
        "adaptive.effortTooHard",
        "adaptive.effortOkay",
        "adaptive.effortEasy",
        "adaptive.bonusOffered",
        "adaptive.bonusAccepted",
        "adaptive.bonusDeclined",
        "adaptive.progressed",
        "adaptive.regressed",
        "adaptive.calibrationCompleted",
        "adaptive.recalibrationCompleted",
    ]

    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy _: PersonaPolicy
    ) -> [PersonaObservation] {
        guard !projected else {
            return []
        }

        let events = context.trigger.adaptiveEventBatch.filter { $0.at <= asOf }
        let bonusOutcomes = Set(events.compactMap { event -> BonusFact? in
            guard event.kind == .bonusAccepted || event.kind == .bonusDeclined else { return nil }
            return BonusFact(family: event.family?.rawValue, factID: event.factID)
        })

        var seenKeys = Set<PersonaObservationKey>()
        var observations: [PersonaObservation] = []
        for event in events {
            guard let contentKey = contentKey(for: event.kind) else { continue }
            if event.kind == .bonusOffered,
               bonusOutcomes.contains(BonusFact(family: event.family?.rawValue, factID: event.factID)) {
                continue
            }

            let key = PersonaObservationKey(
                family: .adaptive,
                kind: event.kind.rawValue,
                subject: event.family?.rawValue ?? "-",
                period: event.factID.uuidString
            )
            guard seenKeys.insert(key).inserted else { continue }

            observations.append(PersonaObservation(
                key: key,
                salience: .medium,
                evidence: PersonaEvidence(
                    strength: 3,
                    lines: ["Adaptive event \(event.kind.rawValue)"]
                ),
                contentKey: contentKey
            ))
        }
        return PersonaDetectorSupport.ordered(observations)
    }

    private static func contentKey(for kind: AdaptiveEventKind) -> String? {
        switch kind {
        case .tinySessionPrescribed,
             .sessionCompleted,
             .effortTooHard,
             .effortOkay,
             .effortEasy,
             .bonusOffered,
             .bonusAccepted,
             .bonusDeclined,
             .progressed,
             .regressed,
             .calibrationCompleted,
             .recalibrationCompleted:
            return "adaptive.\(kind.rawValue)"
        case .returnedAfterAbsence:
            // LapseDetector already announces this fact through lapse.comeback.
            return nil
        }
    }

    private struct BonusFact: Hashable {
        let family: String?
        let factID: UUID
    }
}
