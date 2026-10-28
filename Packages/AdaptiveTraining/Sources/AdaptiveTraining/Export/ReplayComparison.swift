import Foundation

/// Replays an export's facts under its own or candidate parameters and lists the decisions that would change.
public struct ReplayComparison: Sendable {
    /// Deterministic plain text for the `adaptive-replay` tool.
    public let report: String

    public init(report: String) {
        self.report = report
    }

    public static func compare(_ snapshot: AdaptiveSnapshot, parameters: PolicyParameters?) -> ReplayComparison {
        let selectedParameters = parameters ?? snapshot.parameters
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let resolvedTimeZone = TimeZone(identifier: snapshot.timeZone)
        calendar.timeZone = resolvedTimeZone ?? TimeZone(secondsFromGMT: 0) ?? .gmt
        let replayed = AdaptiveReplay.profile(facts: snapshot.facts, catalog: snapshot.catalog,
                                              builtExerciseIDs: snapshot.availability.builtExerciseIDs,
                                              parameters: selectedParameters, calendar: calendar)

        var lines = [
            "Adaptive replay",
            "Format: \(snapshot.format) v\(snapshot.formatVersion)",
            "Policy version: \(snapshot.policyVersion.rawValue)"
        ]
        if let parameters {
            let differences = parameterDifferences(exported: snapshot.parameters, candidate: parameters)
            lines.append(differences.isEmpty ? "Parameters: exported and candidate match" : "Parameters: exported vs candidate")
            lines.append(contentsOf: differences.map { "  \($0)" })
        } else {
            lines.append("Parameters: exported")
        }
        if resolvedTimeZone == nil {
            lines.append("Time zone: \(snapshot.timeZone) is unknown; replayed with UTC.")
        }

        var changedPrescriptions = 0
        lines.append("Current prescriptions:")
        for family in snapshot.families {
            let exported = family.current
            let replayedCurrent = replayed.state(family.family)?.current
            if exported == replayedCurrent {
                lines.append("  \(family.family.rawValue): same (\(prescriptionLabel(exported)))")
            } else {
                changedPrescriptions += 1
                lines.append("  \(family.family.rawValue): \(prescriptionLabel(exported)) → \(prescriptionLabel(replayedCurrent))")
            }
        }

        // Pair transitions by (fact id, family) and occurrence, so a key that appears twice on both sides matches in
        // order. Replayed transitions come first in replay order, then exported ones the replay no longer makes.
        var exportedByKey: [TransitionKey: [Transition]] = [:]
        for transition in snapshot.profile.transitions {
            exportedByKey[TransitionKey(id: transition.id, family: transition.family), default: []].append(transition)
        }
        var replayedCounts: [TransitionKey: Int] = [:]
        var changedTransitions = 0
        lines.append("Changed transitions:")
        for transition in replayed.transitions {
            let key = TransitionKey(id: transition.id, family: transition.family)
            let occurrence = replayedCounts[key, default: 0]
            replayedCounts[key] = occurrence + 1
            guard let exported = exportedByKey[key]?.dropFirst(occurrence).first else {
                changedTransitions += 1
                lines.append("  \(timestamp(transition.at)) \(transition.family.rawValue) \(idPrefix(transition.id)): none → \(transitionLabel(transition))")
                continue
            }
            guard exported.kind != transition.kind || exported.to != transition.to else { continue }
            changedTransitions += 1
            lines.append("  \(timestamp(transition.at)) \(transition.family.rawValue) \(idPrefix(transition.id)): \(transitionLabel(exported)) → \(transitionLabel(transition))")
        }
        var exportedCounts: [TransitionKey: Int] = [:]
        for transition in snapshot.profile.transitions {
            let key = TransitionKey(id: transition.id, family: transition.family)
            let occurrence = exportedCounts[key, default: 0]
            exportedCounts[key] = occurrence + 1
            guard occurrence >= replayedCounts[key, default: 0] else { continue }
            changedTransitions += 1
            lines.append("  \(timestamp(transition.at)) \(transition.family.rawValue) \(idPrefix(transition.id)): \(transitionLabel(transition)) → none")
        }

        if changedPrescriptions == 0 && changedTransitions == 0 {
            return ReplayComparison(report: (lines + ["No decisions change."]).joined(separator: "\n"))
        }
        lines.append("Total: \(changedTransitions) transition decisions and \(changedPrescriptions) current prescriptions changed.")
        return ReplayComparison(report: lines.joined(separator: "\n"))
    }

    private static func parameterDifferences(exported: PolicyParameters, candidate: PolicyParameters) -> [String] {
        var result: [String] = []
        if exported.easyStreakToIncrease != candidate.easyStreakToIncrease {
            result.append("easyStreakToIncrease: \(exported.easyStreakToIncrease) → \(candidate.easyStreakToIncrease)")
        }
        if exported.tooHardReduction != candidate.tooHardReduction {
            result.append("tooHardReduction: \(exported.tooHardReduction) → \(candidate.tooHardReduction)")
        }
        if exported.recencyWindowDays != candidate.recencyWindowDays {
            result.append("recencyWindowDays: \(exported.recencyWindowDays) → \(candidate.recencyWindowDays)")
        }
        if exported.absenceDays != candidate.absenceDays {
            result.append("absenceDays: \(exported.absenceDays) → \(candidate.absenceDays)")
        }
        if exported.harderSampleCooldownDays != candidate.harderSampleCooldownDays {
            result.append("harderSampleCooldownDays: \(exported.harderSampleCooldownDays) → \(candidate.harderSampleCooldownDays)")
        }
        return result
    }

    private static func prescriptionLabel(_ dose: RungDose?) -> String { dose?.description ?? "none" }

    private static func transitionLabel(_ transition: Transition) -> String {
        "\(transition.kind.rawValue)/\(prescriptionLabel(transition.to))"
    }

    private static func timestamp(_ date: Date) -> String { ExportDate.string(date, fractionDigits: 3) }

    private static func idPrefix(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    private struct TransitionKey: Hashable {
        let id: UUID
        let family: MovementFamilyID
    }
}
