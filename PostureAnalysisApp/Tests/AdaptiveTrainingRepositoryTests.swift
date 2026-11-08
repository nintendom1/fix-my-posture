import AdaptiveTraining
import Foundation
import SwiftData
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AdaptiveTrainingRepositoryTests: XCTestCase {
    func testEveryFactKindRoundTripsThroughSwiftData() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext)
        let prescription = makePrescription(id: id(1), at: date(1))
        let evidence = makeEvidence(id: id(2), at: date(2))
        let calibration = makeCalibration(id: id(3), at: date(3), status: .committed)
        let engagement = EngagementFact(id: id(4), recordedAt: date(4), kind: .notificationOpened, family: .push,
                                        prescriptionID: id(1))
        let setting = SettingsFact(id: id(5), recordedAt: date(5), kind: .equipmentChanged,
                                   equipment: [.dumbbells, .band], family: .row)

        try repository.record(prescription)
        try repository.record(evidence)
        try repository.save(calibration)
        try repository.record(engagement)
        try repository.record(setting)

        let facts = try repository.loadFacts()
        XCTAssertEqual(facts.prescriptions, [prescription])
        XCTAssertEqual(facts.evidence, [evidence])
        XCTAssertEqual(facts.calibrations, [calibration])
        XCTAssertEqual(facts.engagement, [engagement])
        XCTAssertEqual(facts.settings, [setting])

        let rows = try container.mainContext.fetch(FetchDescriptor<AdaptiveFactEntity>())
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.first(where: { $0.id == evidence.id })?.familyID, MovementFamilyID.push.rawValue)
        XCTAssertEqual(rows.first(where: { $0.id == prescription.id })?.recordedAt, prescription.issuedAt)
        XCTAssertNil(rows.first(where: { $0.id == calibration.id })?.familyID)
    }

    func testDuplicateFactIDsAreIgnored() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext)

        let prescription = makePrescription(id: id(10), at: date(10))
        try repository.record(prescription)
        try repository.record(makePrescription(id: id(10), at: date(11)))

        let evidence = makeEvidence(id: id(11), at: date(11))
        try repository.record(evidence)
        try repository.record(makeEvidence(id: id(11), at: date(12)))

        let engagement = EngagementFact(id: id(12), recordedAt: date(12), kind: .sessionSkipped)
        try repository.record(engagement)
        try repository.record(EngagementFact(id: id(12), recordedAt: date(13), kind: .notificationOpened))

        let setting = SettingsFact(id: id(13), recordedAt: date(13), kind: .equipmentChanged, equipment: [.band])
        try repository.record(setting)
        try repository.record(SettingsFact(id: id(13), recordedAt: date(14), kind: .familyRemoved, family: .push))

        let facts = try repository.loadFacts()
        XCTAssertEqual(facts.prescriptions, [prescription])
        XCTAssertEqual(facts.evidence, [evidence])
        XCTAssertEqual(facts.engagement, [engagement])
        XCTAssertEqual(facts.settings, [setting])
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<AdaptiveFactEntity>()).count, 4)
    }

    func testCalibrationStatusUpdatesInPlace() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext)
        let inProgress = makeCalibration(id: id(20), at: date(20), status: .inProgress)
        let committed = makeCalibration(id: id(20), at: date(20), status: .committed)

        try repository.save(inProgress)
        try repository.save(committed)

        let rows = try container.mainContext.fetch(FetchDescriptor<AdaptiveFactEntity>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try repository.loadFacts().calibrations, [committed])
    }

    func testLoadedFactsAreOrderedByTimeThenID() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext)
        let tiedTime = date(30)
        let laterTime = date(31)
        let laterID = makePrescription(id: id(22), at: tiedTime)
        let earlierID = makePrescription(id: id(21), at: tiedTime)
        let last = makePrescription(id: id(23), at: laterTime)

        try repository.record(laterID)
        try repository.record(last)
        try repository.record(earlierID)

        XCTAssertEqual(try repository.loadFacts().prescriptions.map(\.id), [id(21), id(22), id(23)])
    }

    func testCachedProfileSavesOverwritesAndLoads() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext)
        let first = CachedProfile(policyVersion: .v1, catalogVersion: "ladders-1", factsWatermark: "one",
                                  payload: Data([1]), builtAt: date(40))
        let second = CachedProfile(policyVersion: PolicyVersion(rawValue: "adaptive-policy-2"),
                                   catalogVersion: "ladders-2", factsWatermark: "two", payload: Data([2, 3]),
                                   builtAt: date(41))

        try repository.saveCachedProfile(first)
        XCTAssertEqual(repository.loadCachedProfile(), first)
        try repository.saveCachedProfile(second)

        XCTAssertEqual(repository.loadCachedProfile(), second)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<AdaptiveProfileCacheEntity>()).count, 1)
    }

    func testCorruptAndUnknownFactRowsAreSkippedAndPreserved() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataAdaptiveTrainingRepository(context: context)
        let valid = makeEvidence(id: id(50), at: date(50))
        try repository.record(valid)
        context.insert(AdaptiveFactEntity(id: id(51), kindRawValue: AdaptiveFactKind.evidence.rawValue,
                                          recordedAt: date(51), familyID: "push", payload: Data("{bad".utf8)))
        context.insert(AdaptiveFactEntity(id: id(52), kindRawValue: "futureFactKind",
                                          recordedAt: date(52), familyID: nil, payload: Data("{}".utf8)))
        try context.save()

        XCTAssertEqual(try repository.loadFacts().evidence, [valid])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AdaptiveFactEntity>()).count, 3)
    }

    func testIDsAreOneNamespaceAcrossFactKinds() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext)
        let evidence = makeEvidence(id: id(70), at: date(70))
        try repository.record(evidence)

        XCTAssertThrowsError(try repository.save(CalibrationSessionRecord(id: id(70), kind: .initial,
                                                                          startedAt: date(71)))) {
            XCTAssertEqual($0 as? AdaptiveTrainingStoreError, .idBelongsToAnotherFact(id(70)))
        }
        XCTAssertThrowsError(try repository.record(EngagementFact(id: id(70), recordedAt: date(72),
                                                                  kind: .sessionSkipped)))
        try repository.record(evidence)

        let facts = try repository.loadFacts()
        XCTAssertEqual(facts.evidence, [evidence])
        XCTAssertEqual(facts.calibrations, [])
        XCTAssertEqual(facts.engagement, [])
    }

    func testCommittedCalibrationCannotBeDemotedOrRewritten() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext)
        var calibration = CalibrationSessionRecord(id: id(80), kind: .initial, startedAt: date(80))
        try repository.save(calibration)
        calibration.status = .committed
        calibration.endedAt = date(81)
        try repository.save(calibration)
        try repository.save(calibration)

        var demoted = calibration
        demoted.status = .inProgress
        var abandoned = calibration
        abandoned.status = .abandoned
        for rewrite in [demoted, abandoned] {
            XCTAssertThrowsError(try repository.save(rewrite)) {
                XCTAssertEqual($0 as? AdaptiveTrainingStoreError, .calibrationChangeNotAllowed(id(80)))
            }
        }
        let next = CalibrationSessionRecord(id: id(82), kind: .recalibration, startedAt: date(82))
        try repository.save(next)

        XCTAssertEqual(try repository.loadFacts().calibrations, [calibration, next])
    }

    func testFailedSaveLeavesNothingBehindAndARetryRecordsTheFact() throws {
        let container = try AppModelContainer.make(inMemory: true)
        var failNext = true
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext) { context in
            if failNext {
                failNext = false
                throw CocoaError(.fileWriteUnknown)
            }
            try context.save()
        }
        let evidence = makeEvidence(id: id(90), at: date(90))

        XCTAssertThrowsError(try repository.record(evidence))
        XCTAssertEqual(try repository.loadFacts().evidence, [], "a failed write is not visible")
        try repository.record(evidence)

        let fresh = ModelContext(container)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<AdaptiveFactEntity>()).map(\.id), [id(90)])
    }

    func testFailedCalibrationAndCacheUpdatesAreNotVisible() throws {
        let container = try AppModelContainer.make(inMemory: true)
        var fail = false
        let repository = SwiftDataAdaptiveTrainingRepository(context: container.mainContext) { context in
            if fail { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        }
        let calibration = CalibrationSessionRecord(id: id(91), kind: .initial, startedAt: date(91))
        try repository.save(calibration)
        let cache = CachedProfile(policyVersion: .v1, catalogVersion: "a", factsWatermark: "w1", payload: Data([1]),
                                  builtAt: date(91))
        try repository.saveCachedProfile(cache)

        fail = true
        var committed = calibration
        committed.status = .committed
        XCTAssertThrowsError(try repository.save(committed))
        XCTAssertThrowsError(try repository.saveCachedProfile(
            CachedProfile(policyVersion: .v1, catalogVersion: "b", factsWatermark: "w2", payload: Data([2]),
                          builtAt: date(92))))

        XCTAssertEqual(try repository.loadFacts().calibrations, [calibration])
        XCTAssertEqual(repository.loadCachedProfile(), cache)
    }

    func testPayloadNamingAnotherIDIsSkippedAndKept() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataAdaptiveTrainingRepository(context: context)
        let payload = try JSONEncoder().encode(makeEvidence(id: id(93), at: date(93)))
        context.insert(AdaptiveFactEntity(id: id(94), kindRawValue: AdaptiveFactKind.evidence.rawValue,
                                          recordedAt: date(93), familyID: "squat", payload: payload))
        try context.save()

        XCTAssertEqual(try repository.loadFacts().evidence, [])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AdaptiveFactEntity>()).count, 1)
    }

    private func makePrescription(id factID: UUID, at: Date) -> Prescription {
        Prescription(id: factID, issuedAt: at, kind: .todaySession, policyVersion: .v1, catalogVersion: "ladders-1",
                     items: [PrescriptionItem(id: id(60), family: .push,
                                              target: RungDose(variant: VariantID(rawValue: "push.wall_push_up"),
                                                               dose: .reps(4)))],
                     rationale: "Continue with a comfortable set.")
    }

    private func makeEvidence(id factID: UUID, at: Date) -> AdaptiveEvidence {
        AdaptiveEvidence(id: factID, recordedAt: at, source: .adaptive, family: .push,
                         variant: VariantID(rawValue: "push.wall_push_up"), prescriptionID: id(10),
                         prescriptionItemID: id(61), workoutID: id(62), calibrationID: id(63),
                         prescribed: .reps(4), confirmed: .reps(3), confirmation: .user,
                         tracker: TrackerObservation(status: .tracked, observed: .reps(3),
                                                     signals: [TrackingSignal(kind: .rangeOfMotion, value: 0.8,
                                                                              isReliable: true)]),
                         effort: .okay, completion: .completed)
    }

    private func makeCalibration(id factID: UUID, at: Date, status: CalibrationStatus) -> CalibrationSessionRecord {
        CalibrationSessionRecord(id: factID, kind: .initial, startedAt: at, status: status)
    }

    private func id(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
