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
