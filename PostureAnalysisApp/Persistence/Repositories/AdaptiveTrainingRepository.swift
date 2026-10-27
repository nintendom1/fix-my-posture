import AdaptiveTraining
import Foundation
import OSLog
import SwiftData

/// Stores adaptive-training facts as JSON payloads, following the identity rules in `AdaptiveTrainingStoring`. A failed
/// write undoes its own pending change in the shared context (never anyone else's), so a retry records the fact.
@MainActor
final class SwiftDataAdaptiveTrainingRepository: AdaptiveTrainingStoring {
    private let context: ModelContext
    private let persist: (ModelContext) throws -> Void
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "FixMyPosture", category: "AdaptiveTrainingPersistence")

    /// `persist` saves the context; tests replace it to simulate a failed save.
    init(context: ModelContext, persist: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.persist = persist
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func loadFacts() throws -> AdaptiveFacts {
        let entities: [AdaptiveFactEntity]
        do {
            entities = try context.fetch(FetchDescriptor<AdaptiveFactEntity>())
        } catch {
            PersistenceRepositoryLogging.failed("Load adaptive facts", error: error)
            throw error
        }

        var prescriptions: [Prescription] = []
        var evidence: [AdaptiveEvidence] = []
        var calibrations: [CalibrationSessionRecord] = []
        var engagement: [EngagementFact] = []
        var settings: [SettingsFact] = []

        for entity in entities {
            guard let kind = AdaptiveFactKind(rawValue: entity.kindRawValue) else {
                logSkipped(entity)
                continue
            }
            switch kind {
            case .prescription:
                if let fact = decode(Prescription.self, from: entity, id: \.id) { prescriptions.append(fact) }
            case .evidence:
                if let fact = decode(AdaptiveEvidence.self, from: entity, id: \.id) { evidence.append(fact) }
            case .calibration:
                if let fact = decode(CalibrationSessionRecord.self, from: entity, id: \.id) { calibrations.append(fact) }
            case .engagement:
                if let fact = decode(EngagementFact.self, from: entity, id: \.id) { engagement.append(fact) }
            case .setting:
                if let fact = decode(SettingsFact.self, from: entity, id: \.id) { settings.append(fact) }
            }
        }

        return AdaptiveFacts(prescriptions: prescriptions, evidence: evidence, calibrations: calibrations,
                             engagement: engagement, settings: settings)
    }

    func record(_ prescription: Prescription) throws {
        try recordFact(prescription, id: prescription.id, kind: .prescription, recordedAt: prescription.issuedAt,
                       familyID: nil)
    }

    func record(_ evidence: AdaptiveEvidence) throws {
        try recordFact(evidence, id: evidence.id, kind: .evidence, recordedAt: evidence.recordedAt,
                       familyID: evidence.family.rawValue)
    }

    func save(_ calibration: CalibrationSessionRecord) throws {
        do {
            let payload = try encoder.encode(calibration)
            if let entity = try context.fetch(FetchDescriptor<AdaptiveFactEntity>()).first(where: { $0.id == calibration.id }) {
                guard entity.kindRawValue == AdaptiveFactKind.calibration.rawValue else {
                    throw AdaptiveTrainingStoreError.idBelongsToAnotherFact(calibration.id)
                }
                // An unreadable stored attempt is never overwritten: that would delete the only copy.
                guard let existing = try? decoder.decode(CalibrationSessionRecord.self, from: entity.payload),
                      existing.canBeReplaced(by: calibration) else {
                    throw AdaptiveTrainingStoreError.calibrationChangeNotAllowed(calibration.id)
                }
                let previous = (entity.recordedAt, entity.payload)
                entity.recordedAt = calibration.startedAt
                entity.payload = payload
                do {
                    try persist(context)
                } catch {
                    (entity.recordedAt, entity.payload) = previous
                    throw error
                }
            } else {
                let entity = AdaptiveFactEntity(id: calibration.id, kindRawValue: AdaptiveFactKind.calibration.rawValue,
                                                recordedAt: calibration.startedAt, familyID: nil, payload: payload)
                try insertAndPersist(entity)
            }
        } catch {
            PersistenceRepositoryLogging.failed("Save adaptive calibration", error: error)
            throw error
        }
    }

    func record(_ engagement: EngagementFact) throws {
        try recordFact(engagement, id: engagement.id, kind: .engagement, recordedAt: engagement.recordedAt,
                       familyID: engagement.family?.rawValue)
    }

    func record(_ setting: SettingsFact) throws {
        try recordFact(setting, id: setting.id, kind: .setting, recordedAt: setting.recordedAt,
                       familyID: setting.family?.rawValue)
    }

    func loadCachedProfile() -> CachedProfile? {
        do {
            guard let entity = try context.fetch(FetchDescriptor<AdaptiveProfileCacheEntity>())
                .first(where: { $0.key == "current" }) else {
                return nil
            }
            return CachedProfile(policyVersion: PolicyVersion(rawValue: entity.policyVersion),
                                 catalogVersion: entity.catalogVersion, factsWatermark: entity.factsWatermark,
                                 payload: entity.payload, builtAt: entity.builtAt)
        } catch {
            PersistenceRepositoryLogging.failed("Load cached adaptive profile", error: error)
            return nil
        }
    }

    func saveCachedProfile(_ profile: CachedProfile) throws {
        do {
            if let entity = try context.fetch(FetchDescriptor<AdaptiveProfileCacheEntity>())
                .first(where: { $0.key == "current" }) {
                let previous = (entity.policyVersion, entity.catalogVersion, entity.factsWatermark, entity.payload,
                                entity.builtAt)
                entity.policyVersion = profile.policyVersion.rawValue
                entity.catalogVersion = profile.catalogVersion
                entity.factsWatermark = profile.factsWatermark
                entity.payload = profile.payload
                entity.builtAt = profile.builtAt
                do {
                    try persist(context)
                } catch {
                    (entity.policyVersion, entity.catalogVersion, entity.factsWatermark, entity.payload,
                     entity.builtAt) = previous
                    throw error
                }
            } else {
                let entity = AdaptiveProfileCacheEntity(policyVersion: profile.policyVersion.rawValue,
                                                        catalogVersion: profile.catalogVersion,
                                                        factsWatermark: profile.factsWatermark,
                                                        payload: profile.payload, builtAt: profile.builtAt)
                context.insert(entity)
                do {
                    try persist(context)
                } catch {
                    context.delete(entity)
                    throw error
                }
            }
        } catch {
            PersistenceRepositoryLogging.failed("Save cached adaptive profile", error: error)
            throw error
        }
    }

    private func recordFact<Fact: Encodable>(_ fact: Fact, id: UUID, kind: AdaptiveFactKind,
                                             recordedAt: Date, familyID: String?) throws {
        do {
            if let existing = try context.fetch(FetchDescriptor<AdaptiveFactEntity>()).first(where: { $0.id == id }) {
                guard existing.kindRawValue == kind.rawValue else {
                    throw AdaptiveTrainingStoreError.idBelongsToAnotherFact(id)
                }
                return
            }
            let payload = try encoder.encode(fact)
            try insertAndPersist(AdaptiveFactEntity(id: id, kindRawValue: kind.rawValue, recordedAt: recordedAt,
                                                    familyID: familyID, payload: payload))
        } catch {
            PersistenceRepositoryLogging.failed("Record adaptive \(kind.rawValue)", error: error)
            throw error
        }
    }

    /// Inserts a new row and saves; on failure the pending insertion is removed, so a retry isn't mistaken for a
    /// duplicate of a fact that was never stored.
    private func insertAndPersist(_ entity: AdaptiveFactEntity) throws {
        context.insert(entity)
        do {
            try persist(context)
        } catch {
            context.delete(entity)
            throw error
        }
    }

    /// The decoded fact, or nil (logged, row kept) when the payload is unreadable or names a different id than its row.
    private func decode<Fact: Decodable>(_ type: Fact.Type, from entity: AdaptiveFactEntity,
                                         id: KeyPath<Fact, UUID>) -> Fact? {
        guard let fact = try? decoder.decode(type, from: entity.payload), fact[keyPath: id] == entity.id else {
            logSkipped(entity)
            return nil
        }
        return fact
    }

    private func logSkipped(_ entity: AdaptiveFactEntity) {
        logger.warning("Skipping unreadable adaptive fact id=\(entity.id.uuidString, privacy: .public) kind=\(entity.kindRawValue, privacy: .public)")
    }
}
