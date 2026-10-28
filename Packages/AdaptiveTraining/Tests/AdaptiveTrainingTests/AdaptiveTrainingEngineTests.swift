import XCTest
@testable import AdaptiveTraining

@MainActor
final class AdaptiveTrainingEngineTests: XCTestCase {
    func testRecordReturnsEventsForTheNewFact() throws {
        let store = InMemoryAdaptiveTrainingStore()
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                            calendar: Fixtures.calendar)
        let calibration = Fixtures.calibration(id: 260)
        let calibrationEvents = try engine.save(calibration)
        XCTAssertEqual(calibrationEvents.map(\.kind), [.calibrationCompleted])

        let evidence = Fixtures.evidence(id: 261, day: 1, effort: .okay)
        let events = try engine.record(evidence)
        XCTAssertEqual(events.map(\.kind), [.effortOkay])
        XCTAssertEqual(events.first?.factID, evidence.id)
    }

    func testIssueStoresPrescriptionAndCallerProvidedIDs() throws {
        let store = InMemoryAdaptiveTrainingStore()
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                            calendar: Fixtures.calendar)
        let session = TodaySession(family: .push, main: RungDose(variant: Fixtures.wall, dose: .reps(4)),
                                   harderSample: RungDose(variant: Fixtures.incline, dose: .reps(1)),
                                   offersBonus: true, isTiny: false, confidence: .medium,
                                   estimatedSeconds: 86, rationale: "Known rationale.", basedOnTransitionID: Fixtures.id(262))
        let prescription = try engine.issue(session, prescriptionID: Fixtures.id(263), mainItemID: Fixtures.id(264),
                                            sampleItemID: Fixtures.id(265), at: Fixtures.date(day: 1))
        XCTAssertEqual(prescription.id, Fixtures.id(263))
        XCTAssertEqual(prescription.items.map(\.id), [Fixtures.id(264), Fixtures.id(265)])
        XCTAssertEqual(prescription.items.last?.role, .harderSample)
        XCTAssertEqual(try store.loadFacts().prescriptions, [prescription])
    }

    func testEasierSwapAsksThePolicyAndNeverWritesAFact() throws {
        let facts = Fixtures.seededFacts(dose: .reps(8))
        let store = InMemoryAdaptiveTrainingStore(facts: facts)
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                            calendar: Fixtures.calendar)
        let item = PrescriptionItem(id: Fixtures.id(270), family: .push,
                                    target: RungDose(variant: Fixtures.wall, dose: .reps(8)))

        let target = try engine.easierSwap(for: item, asOf: Fixtures.date(day: 1))

        XCTAssertEqual(target, RungDose(variant: Fixtures.wall, dose: .reps(6)))
        XCTAssertEqual(try store.loadFacts(), facts, "Asking is read-only.")

        let floor = PrescriptionItem(id: Fixtures.id(271), family: .push,
                                     target: RungDose(variant: Fixtures.shallowWall, dose: .reps(1)))
        XCTAssertNil(try engine.easierSwap(for: floor, asOf: Fixtures.date(day: 1)))
    }

    func testIssueEasierSwapSavesATodaySessionPrescriptionWithOneEasierSwapItem() throws {
        let store = InMemoryAdaptiveTrainingStore(facts: Fixtures.seededFacts(dose: .reps(8)))
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                            calendar: Fixtures.calendar)
        let item = PrescriptionItem(id: Fixtures.id(272), family: .push,
                                    target: RungDose(variant: Fixtures.wall, dose: .reps(8)))
        let target = try XCTUnwrap(try engine.easierSwap(for: item, asOf: Fixtures.date(day: 1)))

        let prescription = try engine.issueEasierSwap(replacing: item, target: target, prescriptionID: Fixtures.id(273),
                                                      itemID: Fixtures.id(274), at: Fixtures.date(day: 1))

        XCTAssertEqual(prescription.id, Fixtures.id(273))
        XCTAssertEqual(prescription.kind, .todaySession)
        XCTAssertEqual(prescription.issuedAt, Fixtures.date(day: 1))
        XCTAssertEqual(prescription.policyVersion, .v1)
        XCTAssertEqual(prescription.catalogVersion, Fixtures.catalog.version)
        XCTAssertEqual(prescription.items, [PrescriptionItem(id: Fixtures.id(274), family: .push, target: target,
                                                            role: .easierSwap, offersBonus: false)])
        XCTAssertEqual(try store.loadFacts().prescriptions, [prescription])
        XCTAssertFalse(prescription.rationale.isEmpty)

        // Saving the same ids again is a no-op, like every fact.
        _ = try engine.issueEasierSwap(replacing: item, target: target, prescriptionID: Fixtures.id(273),
                                       itemID: Fixtures.id(274), at: Fixtures.date(day: 1))
        XCTAssertEqual(try store.loadFacts().prescriptions.count, 1)
    }

    func testIssueEasierSwapRefusesATargetOutsideTheItemsFamily() throws {
        let store = InMemoryAdaptiveTrainingStore(facts: Fixtures.seededFacts(dose: .reps(8)))
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                            calendar: Fixtures.calendar)
        let item = PrescriptionItem(id: Fixtures.id(275), family: .push,
                                    target: RungDose(variant: Fixtures.wall, dose: .reps(8)))
        let foreign = RungDose(variant: VariantID(rawValue: "squat.sit_to_stand"), dose: .reps(3))

        XCTAssertThrowsError(try engine.issueEasierSwap(replacing: item, target: foreign, prescriptionID: Fixtures.id(276),
                                                        itemID: Fixtures.id(277), at: Fixtures.date(day: 1))) { error in
            XCTAssertEqual(error as? AdaptiveTrainingEngineError, .easierSwapOutsideFamily(.push))
        }
        XCTAssertTrue(try store.loadFacts().prescriptions.isEmpty)
    }

    func testTheSwapsEvidenceAndTheMainItemsEvidenceReplayThroughTheEngine() throws {
        let store = InMemoryAdaptiveTrainingStore(facts: Fixtures.seededFacts(dose: .reps(8)))
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                            calendar: Fixtures.calendar)
        let main = Fixtures.prescription(id: 278, day: 1, itemID: 279, variant: Fixtures.wall, dose: .reps(8))
        try store.record(main)
        let item = try XCTUnwrap(main.items.first)
        let target = try XCTUnwrap(try engine.easierSwap(for: item, asOf: Fixtures.date(day: 1)))
        _ = try engine.issueEasierSwap(replacing: item, target: target, prescriptionID: Fixtures.id(280),
                                       itemID: Fixtures.id(281), at: Fixtures.date(day: 1))

        let mainEvents = try engine.record(Fixtures.evidence(id: 282, day: 1, prescribed: .reps(8), confirmed: .reps(3),
                                                             effort: .tooHard, completion: .switchedToEasier,
                                                             itemID: 279, prescriptionID: 278, midSetTooHard: true))
        XCTAssertTrue(mainEvents.contains { $0.kind == .effortTooHard })
        XCTAssertEqual(try engine.profile().state(.push)?.current, target)

        let swapEvents = try engine.record(Fixtures.evidence(id: 283, day: 1, hour: 13, variant: target.variant,
                                                             prescribed: target.dose, confirmed: WorkAmount(target.dose),
                                                             effort: .okay, itemID: 281, prescriptionID: 280))
        XCTAssertEqual(swapEvents.map(\.kind), [.effortOkay])
        let profile = try engine.profile()
        XCTAssertEqual(profile.state(.push)?.current, target, "The swap's own rating never moves the prescription again.")
        XCTAssertTrue(profile.transitions.last?.rationale.codes.contains(.easierSwapRecorded) == true)
    }

    func testValidStoredCachePayloadIsReturnedAsIs() throws {
        let facts = AdaptiveFacts()
        let store = InMemoryAdaptiveTrainingStore(facts: facts)
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                            calendar: Fixtures.calendar)
        let cachedProfile = AdaptiveProfile(policyVersion: .v1, catalogVersion: "deliberately-cached-profile",
                                            states: [], activeFamilies: [], equipment: [], transitions: [])
        let payload = try JSONEncoder().encode(cachedProfile)
        try store.saveCachedProfile(CachedProfile(policyVersion: .v1,
                                                  catalogVersion: engine.interpretationKey,
                                                  factsWatermark: facts.watermark, payload: payload,
                                                  builtAt: Fixtures.date()))
        XCTAssertEqual(try engine.profile(), cachedProfile)
    }

    func testCacheIsIgnoredWhenFactsBuiltExercisesOrParametersChange() throws {
        let calibration = Fixtures.calibration(id: 266)
        let facts = AdaptiveFacts(calibrations: [calibration])
        let deliberatelyDifferent = AdaptiveProfile(policyVersion: .v1, catalogVersion: "cache-sentinel",
                                                    states: [], activeFamilies: [], equipment: [], transitions: [])
        let payload = try JSONEncoder().encode(deliberatelyDifferent)

        let factsStore = InMemoryAdaptiveTrainingStore(facts: facts)
        let originalEngine = AdaptiveTrainingEngine(store: factsStore, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                   calendar: Fixtures.calendar)
        try factsStore.saveCachedProfile(CachedProfile(policyVersion: .v1,
                                                      catalogVersion: originalEngine.interpretationKey,
                                                      factsWatermark: facts.watermark, payload: payload,
                                                      builtAt: Fixtures.date()))
        try factsStore.record(Fixtures.evidence(id: 267, day: 1, effort: .okay))
        let changedFactsEngine = AdaptiveTrainingEngine(store: factsStore, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                        calendar: Fixtures.calendar)
        XCTAssertNotEqual(try changedFactsEngine.profile().catalogVersion, "cache-sentinel")

        let builtStore = InMemoryAdaptiveTrainingStore(facts: facts)
        let builtEngine = AdaptiveTrainingEngine(store: builtStore, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                 calendar: Fixtures.calendar)
        try builtStore.saveCachedProfile(CachedProfile(policyVersion: .v1,
                                                      catalogVersion: builtEngine.interpretationKey,
                                                      factsWatermark: facts.watermark, payload: payload,
                                                      builtAt: Fixtures.date()))
        var fewerBuilt = Fixtures.allBuiltExerciseIDs
        fewerBuilt.remove("push_up")
        let changedBuildEngine = AdaptiveTrainingEngine(store: builtStore, builtExerciseIDs: fewerBuilt,
                                                        calendar: Fixtures.calendar)
        XCTAssertNotEqual(try changedBuildEngine.profile().catalogVersion, "cache-sentinel")

        let parameterStore = InMemoryAdaptiveTrainingStore(facts: facts)
        let parameterEngine = AdaptiveTrainingEngine(store: parameterStore,
                                                     builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                     calendar: Fixtures.calendar)
        try parameterStore.saveCachedProfile(CachedProfile(policyVersion: .v1,
                                                          catalogVersion: parameterEngine.interpretationKey,
                                                          factsWatermark: facts.watermark, payload: payload,
                                                          builtAt: Fixtures.date()))
        var parameters = PolicyParameters.standard
        parameters.absenceDays += 1
        let changedParametersEngine = AdaptiveTrainingEngine(store: parameterStore,
                                                             builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                             calendar: Fixtures.calendar, parameters: parameters)
        XCTAssertNotEqual(try changedParametersEngine.profile().catalogVersion, "cache-sentinel")
    }
}
