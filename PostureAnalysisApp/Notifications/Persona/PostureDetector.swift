import Foundation

/// Posture observations. See the detector table in docs/persona.md and PersonaPolicy for thresholds.
enum PostureDetector: PersonaDetecting {
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let assessments = context.assessments
            .filter { $0.date <= asOf }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        var observations: [PersonaObservation] = []
        if let returned = returnedAssessment(
            assessments: assessments,
            context: context,
            asOf: asOf,
            policy: policy
        ) {
            observations.append(returned)
        }
        if let improvement = improvedAssessment(
            assessments: assessments,
            context: context,
            asOf: asOf,
            policy: policy
        ) {
            observations.append(improvement)
        }
        return PersonaDetectorSupport.ordered(observations)
    }

    private static func returnedAssessment(
        assessments: [PostureAssessment],
        context: PersonaContext,
        asOf: Date,
        policy: PersonaPolicy
    ) -> PersonaObservation? {
        guard assessments.count >= 2,
              let newest = assessments.last,
              asOf.timeIntervalSince(newest.date) <= Double(policy.postureReturnFreshnessHours) * 60 * 60 else {
            return nil
        }
        let previous = assessments[assessments.count - 2]
        guard let days = context.calendar.dateComponents([.day], from: previous.date, to: newest.date).day,
              days >= policy.postureReturnDays else {
            return nil
        }
        let salience: PersonaSalience = days >= policy.postureReturnMediumDays ? .medium : .low
        return PersonaObservation(
            key: PersonaObservationKey(
                family: .posture,
                kind: "returned",
                subject: "-",
                period: PersonaDetectorSupport.dayKey(newest.date, calendar: context.calendar)
            ),
            salience: salience,
            evidence: PersonaEvidence(
                strength: salience == .medium ? 3 : 2,
                lines: ["Last assessment was \(days) days earlier"]
            ),
            contentKey: "posture.returned",
            values: ["days": String(days)]
        )
    }

    private static func improvedAssessment(
        assessments: [PostureAssessment],
        context: PersonaContext,
        asOf: Date,
        policy: PersonaPolicy
    ) -> PersonaObservation? {
        guard let baseline = assessments.last(where: { $0.isBaseline }),
              let freshBoundary = context.calendar.date(
                byAdding: .day,
                value: -policy.postureImprovedFreshnessDays,
                to: asOf
              ) else {
            return nil
        }
        let followUps = assessments.filter {
            !$0.isBaseline && $0.date > baseline.date && $0.view == baseline.view
        }
        guard followUps.count >= 2,
              let newest = followUps.last,
              newest.date >= freshBoundary else {
            return nil
        }
        let previous = followUps[followUps.count - 2]

        var best: Improvement?
        for baselineMeasurement in baseline.measurements where baselineMeasurement.unit == "°" {
            guard let newestMeasurement = measurement(
                with: baselineMeasurement.measurementID,
                in: newest,
                requiringDegrees: true
            ),
            let previousMeasurement = measurement(
                with: baselineMeasurement.measurementID,
                in: previous,
                requiringDegrees: true
            ) else {
                continue
            }
            let baselineMagnitude = abs(baselineMeasurement.value)
            let newestMagnitude = abs(newestMeasurement.value)
            guard newestMagnitude <= baselineMagnitude - policy.postureImprovementDegrees,
                  abs(previousMeasurement.value) <= baselineMagnitude - policy.postureImprovementDegrees else {
                continue
            }
            let candidate = Improvement(
                id: baselineMeasurement.measurementID,
                name: newestMeasurement.name,
                baselineMagnitude: baselineMagnitude,
                newestMagnitude: newestMagnitude,
                date: newest.date
            )
            if let current = best {
                if candidate.improvement > current.improvement
                    || (candidate.improvement == current.improvement && candidate.id.rawValue < current.id.rawValue) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        guard let best else { return nil }
        return PersonaObservation(
            key: PersonaObservationKey(
                family: .posture,
                kind: "improved",
                subject: best.id.rawValue,
                period: PersonaDetectorSupport.dayKey(best.date, calendar: context.calendar)
            ),
            salience: .medium,
            evidence: PersonaEvidence(
                strength: 3,
                lines: ["\(best.name) improved by \(best.improvement)° on two assessments"]
            ),
            contentKey: "posture.improved",
            values: ["measurement": best.name.lowercased()]
        )
    }

    private static func measurement(
        with id: MeasurementID,
        in assessment: PostureAssessment,
        requiringDegrees: Bool
    ) -> PostureMeasurement? {
        assessment.measurements.first {
            $0.measurementID == id && (!requiringDegrees || $0.unit == "°")
        }
    }

    private struct Improvement {
        let id: MeasurementID
        let name: String
        let baselineMagnitude: Double
        let newestMagnitude: Double
        let date: Date

        var improvement: Double { baselineMagnitude - newestMagnitude }
    }
}
