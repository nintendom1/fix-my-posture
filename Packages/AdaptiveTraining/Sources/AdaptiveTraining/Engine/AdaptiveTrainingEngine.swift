import Foundation

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

    public func record(_ engagement: EngagementFact) throws {
        try store.record(engagement)
    }

    @discardableResult
    public func record(_ setting: SettingsFact) throws -> [AdaptiveEvent] {
        try store.record(setting)
        return try events(for: setting.id)
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
