import Foundation

/// A cached interpretation, valid only for the facts, policy, and ladders it was built from.
public struct CachedProfile: Codable, Hashable, Sendable {
    public let policyVersion: PolicyVersion
    public let catalogVersion: String
    public let factsWatermark: String
    /// The encoded profile; opaque to storage.
    public let payload: Data
    public let builtAt: Date

    public init(policyVersion: PolicyVersion, catalogVersion: String, factsWatermark: String, payload: Data,
                builtAt: Date) {
        self.policyVersion = policyVersion
        self.catalogVersion = catalogVersion
        self.factsWatermark = factsWatermark
        self.payload = payload
        self.builtAt = builtAt
    }

    public func isValid(for policy: PolicyVersion, catalogVersion: String, facts: AdaptiveFacts) -> Bool {
        policyVersion == policy && self.catalogVersion == catalogVersion && factsWatermark == facts.watermark
    }
}

/// Why a store refused a fact.
public enum AdaptiveTrainingStoreError: Error, Equatable, Sendable {
    /// Fact ids are one namespace across every kind; this id already belongs to a different kind of fact.
    case idBelongsToAnotherFact(UUID)
    /// A committed or abandoned calibration can't change, and an attempt's id, kind, and start time never change.
    case calibrationChangeNotAllowed(UUID)
}

/// Where adaptive-training facts live. The package declares it and the app implements it with SwiftData, so the
/// engine never sees a database.
///
/// Identity rules, the same in every implementation: fact ids are one namespace across all five kinds. Recording a
/// fact whose id is already stored as the same kind is a no-op (facts are append-only); an id stored as another kind
/// throws `idBelongsToAnotherFact`. `save(_:)` for calibrations inserts a new attempt or replaces one that is still in
/// progress (`CalibrationSessionRecord.canBeReplaced(by:)`); anything else throws `calibrationChangeNotAllowed`. A
/// failed write leaves nothing behind, so retrying it records the fact.
@MainActor
public protocol AdaptiveTrainingStoring: AnyObject {
    func loadFacts() throws -> AdaptiveFacts
    func record(_ prescription: Prescription) throws
    func record(_ evidence: AdaptiveEvidence) throws
    func save(_ calibration: CalibrationSessionRecord) throws
    func record(_ engagement: EngagementFact) throws
    func record(_ setting: SettingsFact) throws
    func loadCachedProfile() -> CachedProfile?
    func saveCachedProfile(_ profile: CachedProfile) throws
}

/// An in-memory store for tests, previews, and in-memory app environments. It follows the same identity rules as
/// the app's SwiftData store.
@MainActor
public final class InMemoryAdaptiveTrainingStore: AdaptiveTrainingStoring {
    public private(set) var facts: AdaptiveFacts
    public private(set) var cachedProfile: CachedProfile?

    public init(facts: AdaptiveFacts = .empty) {
        self.facts = facts
    }

    public func loadFacts() throws -> AdaptiveFacts { facts }

    public func record(_ prescription: Prescription) throws {
        guard try isNew(prescription.id, kind: .prescription) else { return }
        replace(prescriptions: facts.prescriptions + [prescription])
    }

    public func record(_ evidence: AdaptiveEvidence) throws {
        guard try isNew(evidence.id, kind: .evidence) else { return }
        replace(evidence: facts.evidence + [evidence])
    }

    public func save(_ calibration: CalibrationSessionRecord) throws {
        if let existing = facts.calibrations.first(where: { $0.id == calibration.id }) {
            guard existing.canBeReplaced(by: calibration) else {
                throw AdaptiveTrainingStoreError.calibrationChangeNotAllowed(calibration.id)
            }
        } else if kind(of: calibration.id) != nil {
            throw AdaptiveTrainingStoreError.idBelongsToAnotherFact(calibration.id)
        }
        replace(calibrations: facts.calibrations.filter { $0.id != calibration.id } + [calibration])
    }

    public func record(_ engagement: EngagementFact) throws {
        guard try isNew(engagement.id, kind: .engagement) else { return }
        replace(engagement: facts.engagement + [engagement])
    }

    public func record(_ setting: SettingsFact) throws {
        guard try isNew(setting.id, kind: .setting) else { return }
        replace(settings: facts.settings + [setting])
    }

    public func loadCachedProfile() -> CachedProfile? { cachedProfile }

    public func saveCachedProfile(_ profile: CachedProfile) throws {
        cachedProfile = profile
    }

    private enum Kind {
        case prescription, evidence, calibration, engagement, setting
    }

    private func kind(of id: UUID) -> Kind? {
        if facts.prescriptions.contains(where: { $0.id == id }) { return .prescription }
        if facts.evidence.contains(where: { $0.id == id }) { return .evidence }
        if facts.calibrations.contains(where: { $0.id == id }) { return .calibration }
        if facts.engagement.contains(where: { $0.id == id }) { return .engagement }
        if facts.settings.contains(where: { $0.id == id }) { return .setting }
        return nil
    }

    /// True when the id is unused; false when it is already this kind (a no-op); throws for another kind.
    private func isNew(_ id: UUID, kind expected: Kind) throws -> Bool {
        guard let existing = kind(of: id) else { return true }
        guard existing == expected else { throw AdaptiveTrainingStoreError.idBelongsToAnotherFact(id) }
        return false
    }

    private func replace(prescriptions: [Prescription]? = nil, evidence: [AdaptiveEvidence]? = nil,
                         calibrations: [CalibrationSessionRecord]? = nil, engagement: [EngagementFact]? = nil,
                         settings: [SettingsFact]? = nil) {
        facts = AdaptiveFacts(prescriptions: prescriptions ?? facts.prescriptions, evidence: evidence ?? facts.evidence,
                              calibrations: calibrations ?? facts.calibrations,
                              engagement: engagement ?? facts.engagement, settings: settings ?? facts.settings)
    }
}
