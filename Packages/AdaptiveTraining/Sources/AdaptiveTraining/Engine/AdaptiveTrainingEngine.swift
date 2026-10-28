import Foundation

/// Why the engine refused to save a prescription.
public enum AdaptiveTrainingEngineError: Error, Equatable, Sendable {
    /// An easier swap must stay in the item's own movement family.
    case easierSwapOutsideFamily(MovementFamilyID)
    /// A calibration can be committed only from its summary, with at least one starting point.
    case calibrationNotAtSummary(UUID)
}

/// The only way app code reaches adaptive training: record facts, read the interpretation, and ask for Today's
/// Session. Every rule about what is easier or harder stays inside the package. Ids and times always come from the
/// caller, so the engine stays deterministic.
@MainActor
public final class AdaptiveTrainingEngine {
    public let catalog: ProgressionCatalog
    public let parameters: PolicyParameters
    public let policyVersion = PolicyVersion.v1
    private let store: any AdaptiveTrainingStoring
    private let builtExerciseIDs: Set<String>
    private let calendar: Calendar
    private var memo: (watermark: String, profile: AdaptiveProfile)?

    public init(store: any AdaptiveTrainingStoring, builtExerciseIDs: Set<String>, calendar: Calendar,
                catalog: ProgressionCatalog = .v1, parameters: PolicyParameters = .standard) {
        self.store = store
        self.builtExerciseIDs = builtExerciseIDs
        self.calendar = calendar
        self.catalog = catalog
        self.parameters = parameters
    }

    /// Identifies everything besides the facts that the profile depends on, for the stored cache.
    var interpretationKey: String {
        var hasher = StableHasher()
        hasher.combine(catalog.version)
        builtExerciseIDs.sorted().forEach { hasher.combine($0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        hasher.combine(String(decoding: (try? encoder.encode(parameters)) ?? Data(), as: UTF8.self))
        hasher.combine(calendar.timeZone.identifier)
        return "\(catalog.version)-\(hasher.hex)"
    }

    public func facts() throws -> AdaptiveFacts {
        try store.loadFacts()
    }

    /// The current interpretation, from memory, then the stored cache, then a full replay.
    public func profile() throws -> AdaptiveProfile {
        try profile(for: try store.loadFacts())
    }

    public func todaySession(asOf now: Date, context: SessionContext = .normal) throws -> TodaySessionStatus {
        let facts = try store.loadFacts()
        return AdaptiveReplay.todaySession(profile: try profile(for: facts), facts: facts, catalog: catalog,
                                           builtExerciseIDs: builtExerciseIDs, parameters: parameters,
                                           calendar: calendar, asOf: now, context: context)
    }

    /// Saves the prescription the user is starting, so evidence can point at its items.
    @discardableResult
    public func issue(_ session: TodaySession, prescriptionID: UUID, mainItemID: UUID, sampleItemID: UUID?,
                      at now: Date) throws -> Prescription {
        var items = [PrescriptionItem(id: mainItemID, family: session.family, target: session.main, role: .main,
                                      offersBonus: session.offersBonus)]
        if let sample = session.harderSample, let sampleItemID {
            items.append(PrescriptionItem(id: sampleItemID, family: session.family, target: sample,
                                          role: .harderSample, offersBonus: false))
        }
        let prescription = Prescription(id: prescriptionID, issuedAt: now, kind: .todaySession,
                                        policyVersion: policyVersion, catalogVersion: catalog.version,
                                        items: items, rationale: session.rationale)
        try store.record(prescription)
        return prescription
    }

    /// The easier version of a main item that is under way: where policy V1's Too Hard rule would go from the item's
    /// rung and dose. Nil when the item is already at the floor minimum or nothing easier is available. Read-only.
    public func easierSwap(for item: PrescriptionItem, asOf now: Date) throws -> RungDose? {
        let facts = try store.loadFacts()
        return AdaptiveReplay.easierSwap(for: item, profile: try profile(for: facts), catalog: catalog,
                                         builtExerciseIDs: builtExerciseIDs, parameters: parameters,
                                         calendar: calendar, asOf: now)
    }

    /// Saves the easier version the user took mid-item, so its evidence can point at it: a Today's Session
    /// prescription with one `easierSwap` item for the same family. `target` is what `easierSwap(for:asOf:)` returned.
    @discardableResult
    public func issueEasierSwap(replacing item: PrescriptionItem, target: RungDose, prescriptionID: UUID,
                                itemID: UUID, at now: Date) throws -> Prescription {
        guard catalog.family(containing: target.variant)?.id == item.family else {
            throw AdaptiveTrainingEngineError.easierSwapOutsideFamily(item.family)
        }
        let swap = PrescriptionItem(id: itemID, family: item.family, target: target, role: .easierSwap,
                                    offersBonus: false)
        let prescription = Prescription(id: prescriptionID, issuedAt: now, kind: .todaySession,
                                        policyVersion: policyVersion, catalogVersion: catalog.version, items: [swap],
                                        rationale: "Too hard mid-item: \(item.target) became \(target).")
        try store.record(prescription)
        return prescription
    }

    /// Records evidence and returns the events it produced.
    @discardableResult
    public func record(_ evidence: AdaptiveEvidence) throws -> [AdaptiveEvent] {
        try store.record(evidence)
        return try events(for: evidence.id)
    }

    /// Saves a calibration's progress or outcome; only a committed one changes recommendations.
    @discardableResult
    public func save(_ calibration: CalibrationSessionRecord) throws -> [AdaptiveEvent] {
        try store.save(calibration)
        return try events(for: calibration.id)
    }

    // MARK: - Calibration

    /// Begins a calibration and saves it as in progress, which changes no recommendation. `id` and `now` come from the
    /// caller. A recalibration or an added family starts from the current profile; the first calibration doesn't have one.
    public func startCalibration(kind: CalibrationKind, id: UUID, at now: Date) throws -> CalibrationFlow {
        let profile = kind == .initial ? nil : try profile()
        let availability = Availability(builtExerciseIDs: builtExerciseIDs, equipment: Set(profile?.equipment ?? []))
        let flow = CalibrationFlow(id: id, kind: kind, startedAt: now, catalog: catalog, availability: availability,
                                   currentProfile: profile)
        try store.save(flow.inProgressRecord)
        return flow
    }

    /// Saves the quiz answers so far. Only an attempt that is still in progress can change.
    public func saveProgress(_ flow: CalibrationFlow) throws {
        try store.save(flow.inProgressRecord)
    }

    /// Accepts the summary: the starting points now count. Throws `calibrationNotAtSummary` unless the flow is at a
    /// summary with at least one starting point, and saves nothing then.
    @discardableResult
    public func commit(_ flow: CalibrationFlow, at now: Date) throws -> [AdaptiveEvent] {
        guard let record = flow.committedRecord(at: now) else {
            throw AdaptiveTrainingEngineError.calibrationNotAtSummary(flow.id)
        }
        return try save(record)
    }

    /// Leaves without accepting anything. The previous recommendations stay as they were.
    @discardableResult
    public func abandon(_ flow: CalibrationFlow, at now: Date) throws -> [AdaptiveEvent] {
        try save(flow.abandonedRecord(at: now))
    }

    public func record(_ engagement: EngagementFact) throws {
        try store.record(engagement)
    }

    @discardableResult
    public func record(_ setting: SettingsFact) throws -> [AdaptiveEvent] {
        try store.record(setting)
        return try events(for: setting.id)
    }

    /// Everything the developer page and export show, as of `now`. Read-only.
    public func snapshot(asOf now: Date, appVersion: String) throws -> AdaptiveSnapshot {
        AdaptiveReplay.snapshot(facts: try store.loadFacts(), catalog: catalog, builtExerciseIDs: builtExerciseIDs,
                                parameters: parameters, calendar: calendar, asOf: now, appVersion: appVersion)
    }

    private func events(for factID: UUID) throws -> [AdaptiveEvent] {
        let facts = try store.loadFacts()
        return AdaptiveReplay.events(facts: facts, profile: try profile(for: facts)).filter { $0.factID == factID }
    }

    private func profile(for facts: AdaptiveFacts) throws -> AdaptiveProfile {
        let watermark = facts.watermark
        if let memo, memo.watermark == watermark { return memo.profile }
        if let cached = store.loadCachedProfile(),
           cached.isValid(for: policyVersion, catalogVersion: interpretationKey, facts: facts),
           let profile = try? JSONDecoder().decode(AdaptiveProfile.self, from: cached.payload) {
            memo = (watermark, profile)
            return profile
        }
        let profile = AdaptiveReplay.profile(facts: facts, catalog: catalog, builtExerciseIDs: builtExerciseIDs,
                                             parameters: parameters, calendar: calendar)
        memo = (watermark, profile)
        if let payload = try? JSONEncoder().encode(profile) {
            let builtAt = facts.latestFactDate ?? Date(timeIntervalSince1970: 0)
            try? store.saveCachedProfile(CachedProfile(policyVersion: policyVersion, catalogVersion: interpretationKey,
                                                       factsWatermark: watermark, payload: payload, builtAt: builtAt))
        }
        return profile
    }
}

extension AdaptiveFacts {
    /// The newest time any fact carries; used to stamp caches without reading the clock.
    var latestFactDate: Date? {
        (prescriptions.map(\.issuedAt) + evidence.map(\.recordedAt) + calibrations.map { $0.endedAt ?? $0.startedAt }
            + engagement.map(\.recordedAt) + settings.map(\.recordedAt)).max()
    }
}
