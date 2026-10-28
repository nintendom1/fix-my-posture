import Foundation

/// The deterministic per-evidence rules for policy V1.
struct RecommendationPolicyV1 {
    let catalog: ProgressionCatalog
    let parameters: PolicyParameters
    let calendar: Calendar

    func apply(_ evidence: AdaptiveEvidence, role: PrescriptionItemRole?, state original: MovementState?,
               isActive: Bool, streakFactIDs: [UUID], availability: Availability, at: Date) -> PolicyOutcome {
        guard var state = original, isActive,
              let family = catalog.family(evidence.family),
              let rung = catalog.rung(evidence.variant),
              family.index(of: evidence.variant) != nil else {
            return unchanged(evidence, state: original, code: .familyInactive,
                             why: "This family has no active starting point.")
        }

        let returnedAfterAbsence = isAbsent(state, at: evidence.recordedAt)
        if evidence.completion != .notAttempted { state.lastPerformedAt = evidence.recordedAt }

        guard evidence.calibrationID == nil else {
            return outcome(state, from: original?.current, kind: .recordOnly,
                           codes: [.calibrationNotCommitted] + bonusCodes(evidence),
                           target: state.current, why: "This calibration has not been committed.", factIDs: [evidence.id],
                           openStreak: streakFactIDs)
        }
        guard evidence.completion != .notAttempted else {
            var codes: [ReasonCode] = [.notAttempted]
            if role == .harderSample { codes.append(.harderSampleDeclined) }
            return outcome(state, from: original?.current, kind: .recordOnly, codes: codes + bonusCodes(evidence),
                           target: state.current,
                           why: role == .harderSample ? "The optional sample was declined." : "The item was not attempted.",
                           factIDs: [evidence.id], openStreak: streakFactIDs)
        }
        guard let effort = evidence.effort else {
            var codes: [ReasonCode] = [.unrated]
            if evidence.confirmation == .none { codes.append(.trackingOnly) }
            return outcome(state, from: original?.current, kind: .recordOnly, codes: codes + bonusCodes(evidence),
                           target: state.current, why: "Unrated work does not change the recommendation.",
                           factIDs: [evidence.id], openStreak: streakFactIDs)
        }

        if effort != .tooHard {
            guard let confirmed = evidence.confirmed else {
                return outcome(state, from: original?.current, kind: .recordOnly,
                               codes: [.unconfirmedRating] + bonusCodes(evidence), target: state.current,
                               why: "A rating without confirmed work does not change the recommendation.",
                               factIDs: [evidence.id], openStreak: streakFactIDs)
            }
            guard !confirmed.isZero, let confirmedDose = confirmed.dose else {
                return outcome(state, from: original?.current, kind: .recordOnly,
                               codes: [.nothingCompleted] + bonusCodes(evidence), target: state.current,
                               why: "No completed work was confirmed.", factIDs: [evidence.id],
                               openStreak: streakFactIDs)
            }
            putComfortableDose(confirmedDose, on: evidence.variant, at: evidence.recordedAt, in: &state)
        }

        if effort == .tooHard {
            removeComfortableDoses(atOrAbove: tooHardDose(evidence, state: state, rung: rung),
                                   on: evidence.variant, from: &state)
        }

        // Rule 9 comes before every Okay/Easy rule, including a harder sample: the first return only holds.
        if returnedAfterAbsence, effort != .tooHard {
            state.easyStreak = 0
            state.lastEasyAt = nil
            state.confidence = .medium
            return outcome(state, from: original?.current, kind: .hold,
                           codes: [.returnedAfterAbsence]
                            + (role == .easierSwap ? [.easierSwapRecorded] : []) + bonusCodes(evidence), target: state.current,
                           why: "After time away, this session holds the current dose.", factIDs: [evidence.id])
        }

        if role == .harderSample {
            return applyHarderSample(evidence, effort: effort, state: state, original: original,
                                     at: at, returnedAfterAbsence: returnedAfterAbsence)
        }

        if role == .easierSwap {
            if effort == .tooHard {
                let result = tooHardResult(evidence, state: state, rung: rung, availability: availability)
                guard prescriptionOrder(result.target, isEasierThan: state.current) else {
                    return outcome(state, from: original?.current, kind: .recordOnly,
                                   codes: [.easierSwapRecorded] + result.codes + absenceCodes(returnedAfterAbsence)
                                    + bonusCodes(evidence), target: state.current,
                                   why: "The easier swap did not change the current dose.", factIDs: [evidence.id])
                }
                applyTooHard(result, to: &state, at: at, family: family)
                return outcome(state, from: original?.current, kind: result.kind,
                               codes: result.codes + [.easierSwapRecorded] + absenceCodes(returnedAfterAbsence)
                                + bonusCodes(evidence), target: state.current,
                               why: reason(result.codes.first ?? .tooHardAtFloor), factIDs: [evidence.id])
            }
            return outcome(state, from: original?.current, kind: .recordOnly,
                           codes: [.easierSwapRecorded] + absenceCodes(returnedAfterAbsence) + bonusCodes(evidence), target: state.current,
                           why: "The easier swap was recorded without changing the current dose.",
                           factIDs: [evidence.id])
        }

        // Rule 5's exception, for any source: Too Hard on something harder than `current` (a harder rung, or a
        // higher dose on the same rung, such as an older prescription) never moves `current` up or down.
        if effort == .tooHard,
           isHarder(RungDose(variant: evidence.variant, dose: tooHardDose(evidence, state: state, rung: rung)),
                    than: state.current, in: family) {
            if returnedAfterAbsence {
                state.easyStreak = 0
                state.lastEasyAt = nil
            }
            return outcome(state, from: original?.current, kind: .recordOnly,
                           codes: [.manualOtherRungRecorded] + absenceCodes(returnedAfterAbsence)
                            + bonusCodes(evidence), target: state.current,
                           why: "Too Hard on something harder than the current prescription does not move it.",
                           factIDs: [evidence.id])
        }

        if evidence.source == .manual {
            let currentIndex = family.index(of: state.current.variant) ?? 0
            let performedIndex = family.index(of: evidence.variant) ?? currentIndex
            if effort == .tooHard {
                let result = tooHardResult(evidence, state: state, rung: rung, availability: availability)
                applyTooHard(result, to: &state, at: at, family: family)
                return outcome(state, from: original?.current, kind: result.kind,
                               codes: result.codes + absenceCodes(returnedAfterAbsence) + bonusCodes(evidence),
                               target: state.current, why: reason(result.codes.first ?? .tooHardAtFloor),
                               factIDs: [evidence.id])
            }
            if performedIndex > currentIndex {
                // Never past the rung that was performed, even when a rung in between is unavailable.
                guard let next = catalog.harder(than: state.current.variant, availability: availability),
                      let nextIndex = family.index(of: next.id), nextIndex <= performedIndex else {
                    return outcome(state, from: original?.current, kind: .recordOnly,
                                   codes: [.manualOtherRungRecorded] + bonusCodes(evidence), target: state.current,
                                   why: "No harder available rung can be offered.", factIDs: [evidence.id])
                }
                let basis = manualDose(evidence, rung: rung, fallback: state.current.dose)
                let target = RungDose(variant: next.id, dose: next.doseRange.clamped(basis))
                state.current = target
                state.confidence = .medium
                state.easyStreak = 0
                state.lastEasyAt = nil
                state.harderSampleDue = false
                state.harderSampleBlockedUntil = nil
                state.lastChangedAt = at
                return outcome(state, from: original?.current, kind: .harderVariant,
                               codes: [.manualHarderRungUp] + bonusCodes(evidence), target: target,
                               why: "Manual work advances one available rung.", factIDs: [evidence.id])
            }
            if performedIndex < currentIndex {
                return outcome(state, from: original?.current, kind: .recordOnly,
                               codes: [.manualOtherRungRecorded] + bonusCodes(evidence), target: state.current,
                               why: "An easier manual rung does not change the current dose.", factIDs: [evidence.id])
            }

            let basis = manualDose(evidence, rung: rung, fallback: state.current.dose)
            if basis.kind != state.current.dose.kind || basis.amount < state.current.dose.amount {
                return outcome(state, from: original?.current, kind: .recordOnly,
                               codes: [.manualSameRung] + bonusCodes(evidence), target: state.current,
                               why: "Manual work below the current dose does not change the streak.",
                               factIDs: [evidence.id])
            }
            return applyOkayOrEasy(evidence, interpretedEffort: effort, state: state, original: original,
                                   family: family, rung: catalog.rung(state.current.variant) ?? rung,
                                   availability: availability, at: at, extraCodes: [.manualSameRung],
                                   streakFactIDs: streakFactIDs)
        }

        if effort == .tooHard {
            let result = tooHardResult(evidence, state: state, rung: rung, availability: availability)
            applyTooHard(result, to: &state, at: at, family: family)
            return outcome(state, from: original?.current, kind: result.kind,
                           codes: result.codes + absenceCodes(returnedAfterAbsence) + bonusCodes(evidence),
                           target: state.current, why: reason(result.codes.first ?? .tooHardAtFloor),
                           factIDs: [evidence.id])
        }

        return applyOkayOrEasy(evidence, interpretedEffort: effort, state: state, original: original,
                               family: family, rung: catalog.rung(state.current.variant) ?? rung,
                               availability: availability, at: at, extraCodes: [], streakFactIDs: streakFactIDs)
    }

    func applyProbe(_ evidence: AdaptiveEvidence, state: MovementState?) -> PolicyOutcome {
        var next = state
        if var value = next, evidence.completion != .notAttempted {
            // Probes are applied at commit time, so an older probe never moves this back.
            value.lastPerformedAt = max(value.lastPerformedAt ?? evidence.recordedAt, evidence.recordedAt)
            next = value
        }
        return outcome(next, from: state?.current, kind: .recordOnly,
                       codes: [.calibrationProbe] + bonusCodes(evidence),
                       target: state?.current ?? evidenceTarget(evidence),
                       why: "Calibration probe recorded at commit.", factIDs: [evidence.id])
    }

    /// Rule 7 for a committed calibration probe, applied at commit time but ordered by the probe's own time: an
    /// Okay/Easy never replaces a newer comfortable dose, and a Too Hard only removes doses rated before it.
    func applyProbeComfort(_ evidence: AdaptiveEvidence, to doses: inout [VariantID: ComfortableDose]) {
        guard evidence.completion != .notAttempted, let effort = evidence.effort,
              let rung = catalog.rung(evidence.variant),
              catalog.family(evidence.family)?.index(of: evidence.variant) != nil else { return }
        let existing = doses[evidence.variant]
        if effort == .tooHard {
            let dose = evidence.prescribed ?? evidence.confirmed?.dose ?? rung.minimumDose
            if let existing, existing.ratedAt <= evidence.recordedAt, existing.dose.kind == dose.kind,
               existing.dose.amount >= dose.amount {
                doses[evidence.variant] = nil
            }
            return
        }
        guard let dose = evidence.confirmed?.dose else { return }
        if let existing, existing.ratedAt > evidence.recordedAt { return }
        doses[evidence.variant] = ComfortableDose(variant: evidence.variant, dose: dose, ratedAt: evidence.recordedAt)
    }

    private func applyHarderSample(_ evidence: AdaptiveEvidence, effort: EffortFeedback, state originalState: MovementState,
                                   original: MovementState?, at: Date,
                                   returnedAfterAbsence: Bool) -> PolicyOutcome {
        var state = originalState
        if effort == .tooHard {
            state.easyStreak = 0
            state.lastEasyAt = nil
            state.harderSampleDue = false
            state.harderSampleBlockedUntil = evidence.recordedAt.addingTimeInterval(
                TimeInterval(parameters.harderSampleCooldownDays) * 86_400)
            return outcome(state, from: original?.current, kind: .hold,
                           codes: [.harderSampleTooHard] + absenceCodes(returnedAfterAbsence) + bonusCodes(evidence),
                           target: state.current, why: "The harder sample was too hard; pause samples for a while.",
                           factIDs: [evidence.id])
        }
        guard evidence.confirmed?.dose != nil, let harder = catalog.rung(evidence.variant) else {
            return outcome(state, from: original?.current, kind: .recordOnly,
                           codes: [.unconfirmedRating] + bonusCodes(evidence), target: state.current,
                           why: "The harder sample had no confirmed work.", factIDs: [evidence.id])
        }
        let target = RungDose(variant: harder.id, dose: harder.minimumDose)
        state.current = target
        state.confidence = .medium
        state.easyStreak = 0
        state.lastEasyAt = nil
        state.harderSampleDue = false
        state.harderSampleBlockedUntil = nil
        if target != original?.current { state.lastChangedAt = at }
        return outcome(state, from: original?.current, kind: .harderVariant,
                       codes: [.harderSampleAccepted] + bonusCodes(evidence), target: target,
                       why: "The harder sample was accepted at its minimum dose.", factIDs: [evidence.id])
    }

    private func applyOkayOrEasy(_ evidence: AdaptiveEvidence, interpretedEffort: EffortFeedback,
                                 state originalState: MovementState, original: MovementState?, family: MovementFamily,
                                 rung: ProgressionRung, availability: Availability, at: Date,
                                 extraCodes: [ReasonCode], streakFactIDs: [UUID]) -> PolicyOutcome {
        var state = originalState
        let completedLess = evidence.completion == .stoppedEarly || evidence.completion == .endedWorkout ||
            (evidence.confirmed.map { amount in
                guard let prescribed = evidence.prescribed, amount.kind == prescribed.kind else { return false }
                return amount.amount < prescribed.amount
            } ?? false)
        if completedLess {
            state.easyStreak = 0
            state.lastEasyAt = nil
            return outcome(state, from: original?.current, kind: .hold,
                           codes: extraCodes + [.stoppedEarlyHold] + bonusCodes(evidence), target: state.current,
                           why: "Less than the prescribed dose was completed; keep this dose.", factIDs: [evidence.id])
        }

        if interpretedEffort == .okay {
            state.easyStreak = 0
            state.lastEasyAt = nil
            state.confidence = state.confidence.raised
            return outcome(state, from: original?.current, kind: .hold,
                           codes: extraCodes + [.okayHold] + bonusCodes(evidence), target: state.current,
                           why: "Okay keeps this dose.", factIDs: [evidence.id])
        }

        var codes = extraCodes
        var supportingIDs = streakFactIDs
        if let lastEasyAt = state.lastEasyAt {
            let recent = abs(evidence.recordedAt.timeIntervalSince(lastEasyAt)) <=
                TimeInterval(parameters.recencyWindowDays) * 86_400
            if recent, !calendar.isDate(lastEasyAt, inSameDayAs: evidence.recordedAt) {
                state.easyStreak += 1
                supportingIDs.append(evidence.id)
            } else if recent {
                supportingIDs.append(evidence.id)
            } else {
                state.easyStreak = 1
                supportingIDs = [evidence.id]
                codes.append(.staleHistoryIgnored)
            }
        } else {
            state.easyStreak = 1
            supportingIDs = [evidence.id]
        }
        state.lastEasyAt = evidence.recordedAt
        state.confidence = state.confidence.raised

        guard state.easyStreak >= parameters.easyStreakToIncrease else {
            return outcome(state, from: original?.current, kind: .hold,
                           codes: codes + [.easyOnceHold] + bonusCodes(evidence), target: state.current,
                           why: "One Easy rating keeps this dose.", factIDs: [evidence.id], openStreak: supportingIDs)
        }
        if let increased = rung.doseRange.increased(state.current.dose), rung.id == state.current.variant {
            let target = RungDose(variant: rung.id, dose: increased)
            state.current = target
            state.easyStreak = 0
            state.lastEasyAt = nil
            state.harderSampleDue = false
            state.lastChangedAt = at
            return outcome(state, from: original?.current, kind: .increaseDose,
                           codes: codes + [.easyStreakIncrease] + bonusCodes(evidence), target: target,
                           why: "Easy twice on different days: increase the dose by one step.",
                           factIDs: supportingIDs)
        }
        if let _ = catalog.harder(than: state.current.variant, availability: availability),
           state.harderSampleBlockedUntil.map({ $0 <= evidence.recordedAt }) ?? true {
            state.harderSampleDue = true
            state.easyStreak = 0
            state.lastEasyAt = nil
            return outcome(state, from: original?.current, kind: .offerHarderSample,
                           codes: codes + [.topOfRangeSampleOffered] + bonusCodes(evidence), target: state.current,
                           why: "Easy at the top of the dose range: offer one sample of the next rung.",
                           factIDs: [evidence.id])
        }
        state.easyStreak = 0
        state.lastEasyAt = nil
        return outcome(state, from: original?.current, kind: .hold,
                       codes: codes + [.easyOnceHold] + bonusCodes(evidence), target: state.current,
                       why: "This rung is at its top dose; keep it for now.", factIDs: [evidence.id])
    }

    private func tooHardResult(_ evidence: AdaptiveEvidence, state: MovementState, rung: ProgressionRung,
                               availability: Availability) -> TooHardResult {
        let dose = tooHardDose(evidence, state: state, rung: rung)
        if let comfortable = state.comfortableDose(on: rung.id),
           isRecent(comfortable.ratedAt, relativeTo: evidence.recordedAt),
           comfortable.dose.kind == dose.kind, comfortable.dose.amount < dose.amount {
            let target = RungDose(variant: rung.id, dose: rung.doseRange.clamped(comfortable.dose))
            return TooHardResult(target: target, kind: .decreaseDose, codes: [.tooHardBackToComfortable])
        }
        if dose.kind == rung.doseRange.kind, dose.amount > rung.doseRange.lower {
            let reduction = reductionAmount(dose: dose.amount, range: rung.doseRange)
            let targetDose = Dose(kind: rung.doseRange.kind, amount: max(rung.doseRange.lower, dose.amount - reduction))
            return TooHardResult(target: RungDose(variant: rung.id, dose: targetDose), kind: .decreaseDose,
                                 codes: [.tooHardReducedDose])
        }
        if let easier = catalog.easier(than: rung.id, availability: availability) {
            let comfortable = state.comfortableDose(on: easier.id).flatMap { value in
                isRecent(value.ratedAt, relativeTo: evidence.recordedAt) ? value : nil
            }
            let target = comfortable.map { RungDose(variant: easier.id, dose: easier.doseRange.clamped($0.dose)) }
                ?? RungDose(variant: easier.id, dose: easier.minimumDose)
            return TooHardResult(target: target, kind: .easierVariant, codes: [.tooHardEasierRung])
        }
        let target = RungDose(variant: rung.id, dose: rung.minimumDose)
        let kind: DecisionKind = target == state.current ? .hold : .decreaseDose
        return TooHardResult(target: target, kind: kind, codes: [.tooHardAtFloor])
    }

    private func applyTooHard(_ result: TooHardResult, to state: inout MovementState, at: Date,
                              family: MovementFamily) {
        state.easyStreak = 0
        state.lastEasyAt = nil
        state.harderSampleDue = false
        if result.target != state.current { state.lastChangedAt = at }
        state.current = result.target
        if let floor = family.floor, floor.id == result.target.variant, result.target.dose == floor.minimumDose {
            state.confidence = .low
        } else {
            state.confidence = state.confidence.lowered
        }
    }

    private func tooHardDose(_ evidence: AdaptiveEvidence, state: MovementState, rung: ProgressionRung) -> Dose {
        if evidence.source == .manual {
            // No positive work: the performed rung's minimum, never another rung's current dose.
            return manualDose(evidence, rung: rung, fallback: rung.minimumDose)
        }
        return evidence.prescribed ?? evidence.confirmed?.dose ?? state.current.dose
    }

    private func manualDose(_ evidence: AdaptiveEvidence, rung: ProgressionRung, fallback: Dose) -> Dose {
        evidence.setAmounts.compactMap(\.dose).min() ?? evidence.confirmed?.dose ?? rung.doseRange.clamped(fallback)
    }

    private func reductionAmount(dose: Int, range: DoseRange) -> Int {
        let maxReduction = max(0, dose - range.lower)
        let rawSteps = ceil(Double(dose) * parameters.tooHardReduction / Double(range.step))
        guard rawSteps.isFinite else { return maxReduction }
        let steps = max(1, rawSteps)
        let rounded = min(Double(maxReduction), steps * Double(range.step))
        if rounded >= Double(Int.max) { return maxReduction }
        return min(maxReduction, max(range.step, Int(rounded)))
    }

    private func isAbsent(_ state: MovementState, at date: Date) -> Bool {
        guard let lastPerformedAt = state.lastPerformedAt else { return false }
        return date.timeIntervalSince(lastPerformedAt) >= TimeInterval(parameters.absenceDays) * 86_400
    }

    private func isRecent(_ date: Date, relativeTo now: Date) -> Bool {
        abs(now.timeIntervalSince(date)) <= TimeInterval(parameters.recencyWindowDays) * 86_400
    }

    private func putComfortableDose(_ dose: Dose, on variant: VariantID, at date: Date, in state: inout MovementState) {
        state.comfortableDoses.removeAll { $0.variant == variant }
        state.comfortableDoses.append(ComfortableDose(variant: variant, dose: dose, ratedAt: date))
        state.comfortableDoses.sort { $0.variant < $1.variant }
    }

    private func removeComfortableDoses(atOrAbove dose: Dose, on variant: VariantID, from state: inout MovementState) {
        state.comfortableDoses.removeAll {
            $0.variant == variant && $0.dose.kind == dose.kind && $0.dose.amount >= dose.amount
        }
    }

    private func isHarder(_ performed: RungDose, than current: RungDose, in family: MovementFamily) -> Bool {
        guard let performedIndex = family.index(of: performed.variant),
              let currentIndex = family.index(of: current.variant) else { return false }
        return performedIndex > currentIndex || (performedIndex == currentIndex &&
            performed.dose.kind == current.dose.kind && performed.dose.amount > current.dose.amount)
    }

    private func prescriptionOrder(_ lhs: RungDose, isEasierThan rhs: RungDose) -> Bool {
        guard let family = catalog.family(containing: lhs.variant),
              let leftIndex = family.index(of: lhs.variant), let rightIndex = family.index(of: rhs.variant) else { return false }
        return leftIndex < rightIndex || (leftIndex == rightIndex && lhs.dose.kind == rhs.dose.kind &&
                                           lhs.dose.amount < rhs.dose.amount)
    }

    private func bonusCodes(_ evidence: AdaptiveEvidence) -> [ReasonCode] {
        evidence.bonus == nil ? [] : [.bonusRecordedOnly]
    }

    private func absenceCodes(_ returned: Bool) -> [ReasonCode] {
        returned ? [.returnedAfterAbsence] : []
    }

    private func evidenceTarget(_ evidence: AdaptiveEvidence) -> RungDose {
        let dose = evidence.prescribed ?? evidence.confirmed?.dose ?? catalog.rung(evidence.variant)?.minimumDose ?? .reps(1)
        return RungDose(variant: evidence.variant, dose: dose)
    }

    private func unchanged(_ evidence: AdaptiveEvidence, state: MovementState?, code: ReasonCode,
                           why: String) -> PolicyOutcome {
        outcome(state, from: state?.current, kind: .recordOnly, codes: [code] + bonusCodes(evidence),
                target: state?.current ?? evidenceTarget(evidence), why: why, factIDs: [evidence.id])
    }

    private func outcome(_ state: MovementState?, from: RungDose?, kind: DecisionKind, codes: [ReasonCode],
                         target: RungDose, why: String, factIDs: [UUID], openStreak: [UUID] = []) -> PolicyOutcome {
        PolicyOutcome(state: state, from: from, kind: kind, codes: codes, factIDs: factIDs,
                      target: target, why: why, openStreakFactIDs: openStreak)
    }

    private func reason(_ code: ReasonCode) -> String {
        switch code {
        case .tooHardBackToComfortable: return "A recent comfortable dose is lower."
        case .tooHardReducedDose: return "Too Hard reduces the dose."
        case .tooHardEasierRung: return "Too Hard at the minimum moves to an easier rung."
        case .tooHardAtFloor: return "Too Hard at the floor keeps the minimum dose."
        default: return "The rating updates the current recommendation."
        }
    }
}

private struct TooHardResult {
    let target: RungDose
    let kind: DecisionKind
    let codes: [ReasonCode]
}

struct PolicyOutcome {
    var state: MovementState?
    let from: RungDose?
    let kind: DecisionKind
    let codes: [ReasonCode]
    let factIDs: [UUID]
    let target: RungDose
    let why: String
    let openStreakFactIDs: [UUID]
}
