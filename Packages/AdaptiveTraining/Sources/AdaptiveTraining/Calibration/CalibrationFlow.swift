import Foundation

/// What the calibration screen should show next. The flow decides; the app draws it.
public enum CalibrationStep: Hashable, Sendable {
    /// Which equipment the user has. Both answers are optional.
    case equipment
    /// Which movement areas to start with.
    case families
    /// "Which feels closest to what you can do comfortably today?" The options are the family's available rungs, easiest
    /// first. "Not sure" is always allowed and has no rung.
    case closeness(MovementFamilyID, options: [VariantID])
    /// A tiny sample of one rung. A harder offer is optional: declining it is neutral.
    case probe(MovementFamilyID, RungDose, isHarderOffer: Bool)
    /// The starting points the user can accept. Empty when every family was skipped.
    case summary([CalibrationStart])
}

/// The rules of the first calibration: a short quiz, then at most `probeLimit` tiny samples per family, each rated Too
/// Hard / Okay / Easy. It is a pure `Codable` value, advanced by inputs like `WorkoutSession`. It decides the start
/// rung, the probe doses, when to go up or down, and when to stop; the app only shows `step` and reports what happened.
///
/// It is never a test or a score. The user's rating of a sample is authoritative, a single Easy never raises a starting
/// dose, and declining a harder sample is neutral. An input that doesn't fit the current `step` is ignored.
public struct CalibrationFlow: Codable, Hashable, Sendable {
    /// The most samples one family gets.
    public static let probeLimit = 3
    /// A first sample asks for this many reps when the rung allows it; otherwise the rung's minimum.
    static let firstSampleReps = 2
    /// Families the quiz selects before the user changes anything.
    static let defaultFamilies: [MovementFamilyID] = [.push, .squat]

    public let id: UUID
    public let kind: CalibrationKind
    public let startedAt: Date
    public let catalog: ProgressionCatalog

    /// What the device can offer: built exercises plus the equipment answered so far.
    public private(set) var availability: Availability
    /// The quiz's equipment answer, sorted; nil until asked or when the quiz didn't ask.
    public private(set) var equipmentAnswer: [TrainingEquipment]?
    /// Families the quiz selects before the user changes anything, in catalog order.
    public private(set) var suggestedFamilies: [MovementFamilyID]
    /// How many samples were rated, in all families, including families skipped afterward.
    public private(set) var probeCount = 0

    private let asksEquipment: Bool
    private let currentDoses: [MovementFamilyID: RungDose]
    private var hasChosenFamilies = false
    private var entries: [Entry] = []

    /// One chosen family's progress through the quiz and its samples.
    private struct Entry: Codable, Hashable, Sendable {
        let family: MovementFamilyID
        let current: RungDose?
        /// The floor at its minimum: where a family settles when nothing comfortable was found.
        let floor: RungDose
        var asked = false
        var candidate: Candidate?
        var probes: [Probe] = []
        var lastComfortable: RungDose?
        /// After a Too Hard, nothing harder is offered.
        var sawTooHard = false
        var settled: RungDose?

        mutating func settle(at dose: RungDose) {
            settled = dose
            candidate = nil
        }
    }

    private struct Candidate: Codable, Hashable, Sendable {
        var rungDose: RungDose
        var isHarderOffer: Bool
    }

    private struct Probe: Codable, Hashable, Sendable {
        let rungDose: RungDose
        let isHarderOffer: Bool
        let effort: EffortFeedback
        let confirmed: WorkAmount
    }

    /// `availability` is what the device can run, with the equipment already known. `currentProfile` is for a later
    /// recalibration or an added family: it skips the equipment question (the profile knows) and changes which
    /// families are suggested.
    public init(id: UUID, kind: CalibrationKind, startedAt: Date, catalog: ProgressionCatalog,
                availability: Availability, currentProfile: AdaptiveProfile? = nil) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.catalog = catalog
        self.availability = availability
        asksEquipment = currentProfile == nil
        currentDoses = Dictionary(uniqueKeysWithValues: (currentProfile?.activeFamilies ?? []).compactMap { family in
            guard let state = currentProfile?.state(family) else { return nil }
            return (family, state.current)
        })
        suggestedFamilies = Self.suggestions(kind: kind, catalog: catalog, availability: availability,
                                             profile: currentProfile)
    }

    // MARK: - Reading

    /// Families that can be offered with the equipment answered so far, in catalog order.
    public var offeredFamilies: [MovementFamilyID] {
        let offered = catalog.offerableFamilies(availability: availability)
        guard kind == .addFamily else { return offered }
        let active = Set(currentDoses.keys)
        return offered.filter { !active.contains($0) }
    }

    /// The family's rungs this device and equipment can run, easiest first.
    public func availableRungs(of family: MovementFamilyID) -> [ProgressionRung] {
        (catalog.family(family)?.rungs ?? []).filter(availability.isAvailable)
    }

    /// The families chosen in the quiz and not skipped, in catalog order.
    public var families: [MovementFamilyID] { entries.map(\.family) }

    /// Settled families with their starting points, in catalog order.
    public var startingPoints: [CalibrationStart] {
        entries.compactMap { entry in entry.settled.map { CalibrationStart(family: entry.family, start: $0) } }
    }

    /// How many samples one family has been rated on.
    public func probeCount(of family: MovementFamilyID) -> Int {
        entries.first { $0.family == family }?.probes.count ?? 0
    }

    public var step: CalibrationStep {
        if asksEquipment, equipmentAnswer == nil { return .equipment }
        guard hasChosenFamilies else { return .families }
        if let entry = entries.first(where: { !$0.asked }) {
            return .closeness(entry.family, options: availableRungs(of: entry.family).map(\.id))
        }
        if let entry = entries.first(where: { $0.settled == nil }), let candidate = entry.candidate {
            return .probe(entry.family, candidate.rungDose, isHarderOffer: candidate.isHarderOffer)
        }
        return .summary(startingPoints)
    }

    // MARK: - Quiz

    /// Records the equipment answer. Only at `.equipment`.
    public mutating func setEquipment(_ equipment: Set<TrainingEquipment>) {
        guard step == .equipment else { return }
        availability.equipment = equipment
        equipmentAnswer = equipment.sorted()
        suggestedFamilies = Self.suggestions(kind: kind, catalog: catalog, availability: availability, profile: nil)
    }

    /// Chooses the areas to start with. Only at `.families`. Families that can't be offered are dropped; an empty
    /// choice is ignored so the quiz can't end with nothing.
    public mutating func setFamilies(_ chosen: [MovementFamilyID]) {
        guard step == .families else { return }
        let offered = Set(offeredFamilies)
        let wanted = Set(chosen).intersection(offered)
        let ordered = catalog.families.map(\.id).filter(wanted.contains)
        guard !ordered.isEmpty else { return }
        entries = ordered.compactMap(makeEntry)
        hasChosenFamilies = true
    }

    /// Answers "Which feels closest?" for the family being asked. `variant` nil means "Not sure", which starts at the
    /// floor. An answer starts no higher than the middle rung of the available ladder: the samples can go up from
    /// there, but the quiz alone never starts someone high.
    public mutating func answerCloseness(family: MovementFamilyID, variant: VariantID?) {
        guard case .closeness(let asked, let options) = step, asked == family,
              let index = entries.firstIndex(where: { $0.family == family }) else { return }
        let rungs = availableRungs(of: family)
        let start: ProgressionRung?
        if let variant {
            guard options.contains(variant), let answered = rungs.firstIndex(where: { $0.id == variant }) else { return }
            start = rungs[min(answered, Self.middleIndex(of: rungs.count))]
        } else {
            start = rungs.first
        }
        guard let start else { return }
        entries[index].asked = true
        entries[index].candidate = Candidate(rungDose: RungDose(variant: start.id, dose: Self.firstSampleDose(for: start)),
                                             isHarderOffer: false)
    }

    // MARK: - Samples

    /// Reports how the sample went. `confirmed` is the amount the user stands behind (zero when nobody confirmed any).
    ///
    /// - Okay settles at the sample's dose.
    /// - Easy offers the next harder rung at its minimum, unless a Too Hard was already seen, the limit is reached, or
    ///   nothing is harder; then it settles at the sample's dose. Easy never raises the dose.
    /// - Too Hard is authoritative even when the sample was finished. A harder offer settles at the last comfortable
    ///   sample; anything else steps down one rung at its minimum, or settles at the floor's minimum.
    /// - Okay or Easy with nothing confirmed proves nothing, so the same sample is offered again.
    ///
    /// After `probeLimit` samples a family settles at its last comfortable sample, or the floor's minimum.
    public mutating func probeResult(family: MovementFamilyID, effort: EffortFeedback, confirmed: WorkAmount) {
        guard case .probe(let current, let dose, let isHarderOffer) = step, current == family,
              let index = entries.firstIndex(where: { $0.family == family }) else { return }
        var entry = entries[index]
        entry.probes.append(Probe(rungDose: dose, isHarderOffer: isHarderOffer, effort: effort, confirmed: confirmed))
        probeCount += 1
        let atLimit = entry.probes.count >= Self.probeLimit
        let fallback = entry.lastComfortable ?? entry.floor

        switch effort {
        case .tooHard:
            entry.sawTooHard = true
            if !isHarderOffer, !atLimit, let easier = catalog.easier(than: dose.variant, availability: availability) {
                entry.candidate = Candidate(rungDose: RungDose(variant: easier.id, dose: easier.minimumDose),
                                            isHarderOffer: false)
            } else {
                entry.settle(at: fallback)
            }
        case .okay, .easy:
            if confirmed.isZero {
                // Nothing was confirmed, so the rating can't say the dose was comfortable.
                if atLimit {
                    entry.settle(at: fallback)
                } else {
                    entry.candidate = Candidate(rungDose: dose, isHarderOffer: isHarderOffer)
                }
            } else {
                let comfortableDose: RungDose
                if kind == .recalibration, let current = entry.current, current.variant == dose.variant {
                    comfortableDose = RungDose(variant: dose.variant, dose: max(dose.dose, current.dose))
                } else {
                    comfortableDose = dose
                }
                entry.lastComfortable = comfortableDose
                if effort == .easy, !entry.sawTooHard, !atLimit,
                   let harder = catalog.harder(than: dose.variant, availability: availability) {
                    entry.candidate = Candidate(rungDose: RungDose(variant: harder.id, dose: harder.minimumDose),
                                                isHarderOffer: true)
                } else {
                    entry.settle(at: comfortableDose)
                }
            }
        }
        entries[index] = entry
    }

    /// The user said no to the optional harder sample. That means "stop here", not "harder failed": the family settles
    /// at the last Okay or Easy sample. Only while a harder offer is showing.
    public mutating func declineHarderProbe(family: MovementFamilyID) {
        guard case .probe(let current, _, true) = step, current == family,
              let index = entries.firstIndex(where: { $0.family == family }) else { return }
        let settledAt = entries[index].lastComfortable ?? entries[index].floor
        entries[index].settle(at: settledAt)
    }

    /// Leaves one family out. Allowed until it settles; its samples stay recorded but it gets no starting point.
    public mutating func skipFamily(family: MovementFamilyID) {
        guard hasChosenFamilies, let index = entries.firstIndex(where: { $0.family == family }),
              entries[index].settled == nil else { return }
        entries.remove(at: index)
    }

    // MARK: - Facts

    /// The record while the user is still answering. It changes no recommendation.
    public var inProgressRecord: CalibrationSessionRecord {
        record(status: .inProgress, endedAt: nil, startingPoints: [])
    }

    /// The record that makes the summary's starting points count. Nil unless the flow is at a summary with at least one
    /// starting point.
    public func committedRecord(at now: Date) -> CalibrationSessionRecord? {
        guard case .summary(let points) = step, !points.isEmpty else { return nil }
        return record(status: .committed, endedAt: now, startingPoints: points)
    }

    /// The record for leaving early. It carries no starting points, so nothing changes.
    public func abandonedRecord(at now: Date) -> CalibrationSessionRecord {
        record(status: .abandoned, endedAt: now, startingPoints: [])
    }

    private func record(status: CalibrationStatus, endedAt: Date?,
                        startingPoints: [CalibrationStart]) -> CalibrationSessionRecord {
        CalibrationSessionRecord(id: id, kind: kind, startedAt: startedAt, endedAt: endedAt, status: status,
                                 families: families, equipment: equipmentAnswer, startingPoints: startingPoints)
    }

    // MARK: - Helpers

    private func makeEntry(_ family: MovementFamilyID) -> Entry? {
        guard let floor = catalog.floorPrescription(of: family, availability: availability) else { return nil }
        let current = currentDoses[family]
        var entry = Entry(family: family, current: current, floor: floor)
        if kind == .recalibration, let current,
           let rung = catalog.rung(current.variant), availability.isAvailable(rung) {
            entry.asked = true
            entry.candidate = Candidate(rungDose: RungDose(variant: rung.id, dose: Self.firstSampleDose(for: rung)),
                                        isHarderOffer: false)
            return entry
        }
        // With one rung there is nothing to be closest to, so the quiz skips the question.
        let rungs = availableRungs(of: family)
        if let only = rungs.first, rungs.count == 1 {
            entry.asked = true
            entry.candidate = Candidate(rungDose: RungDose(variant: only.id, dose: Self.firstSampleDose(for: only)),
                                        isHarderOffer: false)
        }
        return entry
    }

    /// The middle rung of an available ladder; the lower middle when the count is even.
    static func middleIndex(of count: Int) -> Int { max(0, (count - 1) / 2) }

    /// 2 reps for a rep rung whose range allows it; otherwise the rung's minimum.
    static func firstSampleDose(for rung: ProgressionRung) -> Dose {
        let reps = Dose.reps(firstSampleReps)
        return rung.doseRange.contains(reps) ? reps : rung.minimumDose
    }

    private static func suggestions(kind: CalibrationKind, catalog: ProgressionCatalog, availability: Availability,
                                    profile: AdaptiveProfile?) -> [MovementFamilyID] {
        let offered = catalog.offerableFamilies(availability: availability)
        guard kind != .addFamily else { return [] }
        guard let profile else { return offered.filter(defaultFamilies.contains) }
        switch kind {
        case .initial: return offered.filter(defaultFamilies.contains)
        case .recalibration: return offered.filter(profile.activeFamilies.contains)
        case .addFamily: return []
        }
    }
}
