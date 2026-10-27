import XCTest
@testable import AdaptiveTraining

final class AdaptiveFactsTests: XCTestCase {
    func testEveryFactTypeRoundTripsWithOptionalValuesSet() throws {
        try assertRoundTrip(prescription)
        try assertRoundTrip(evidence(confirmed: .reps(4), confirmation: .user))
        try assertRoundTrip(CalibrationSessionRecord(id: id(3), kind: .recalibration, startedAt: date(3),
                                                     endedAt: date(4), status: .committed, families: [.push, .squat],
                                                     equipment: [.band, .dumbbells], startingPoints: [calibrationStart]))
        try assertRoundTrip(EngagementFact(id: id(4), recordedAt: date(4), kind: .notificationOpened, family: .push,
                                           prescriptionID: id(1)))
        try assertRoundTrip(SettingsFact(id: id(5), recordedAt: date(5), kind: .equipmentChanged,
                                         equipment: [.dumbbells, .band], family: .row))
        try assertRoundTrip(AdaptiveFacts(prescriptions: [prescription], evidence: [evidence(confirmed: .reps(4), confirmation: .user)],
                                          calibrations: [makeCalibration(id: id(3), at: date(3))]))
        try assertRoundTrip(CachedProfile(policyVersion: .v1, catalogVersion: "ladders-1", factsWatermark: "stable",
                                          payload: Data([1, 2]), builtAt: date(5)))
        try assertRoundTrip(evidence(confirmed: .reps(4), confirmation: .user))
        try assertRoundTrip(TrackerObservation(status: .tracked, observed: .reps(4), rejectionReasons: ["shortRange"],
                                               signals: [TrackingSignal(kind: .rangeOfMotion, value: 0.75, isReliable: true)]))
        try assertRoundTrip(BonusRecord(offered: .reps(2), accepted: true, completed: .reps(1), effort: .easy))
        try assertRoundTrip(TrackingSignal(kind: .tempo, value: 0.5, isReliable: false))
        try assertRoundTrip(try XCTUnwrap(prescription.items.first))
        try assertRoundTrip(calibrationStart)
    }

    func testEveryFactTypeRoundTripsWithOptionalValuesNil() throws {
        try assertRoundTrip(evidenceWithoutOptionals)
        try assertRoundTrip(TrackerObservation(status: .notTracked))
        try assertRoundTrip(BonusRecord(offered: .reps(2), accepted: true))
        try assertRoundTrip(CalibrationSessionRecord(id: id(6), kind: .initial, startedAt: date(6)))
        try assertRoundTrip(EngagementFact(id: id(7), recordedAt: date(7), kind: .sessionSkipped))
        try assertRoundTrip(SettingsFact(id: id(8), recordedAt: date(8), kind: .equipmentChanged))
    }

    func testAdaptiveEvidenceNormalizesConfirmationAndSetAmounts() {
        let dose = WorkAmount.reps(3)
        let noConfirmation = evidence(confirmed: dose, confirmation: .none)
        XCTAssertNil(noConfirmation.confirmed)
        XCTAssertEqual(noConfirmation.confirmation, .none)

        let missingDose = evidence(confirmed: nil, confirmation: .user)
        XCTAssertNil(missingDose.confirmed)
        XCTAssertEqual(missingDose.confirmation, .none)

        let oneConfirmedSet = evidence(confirmed: dose, confirmation: .user)
        XCTAssertEqual(oneConfirmedSet.setAmounts, [dose])
        XCTAssertEqual(missingDose.setAmounts, [])
    }

    func testDeclinedBonusDropsCompletionAndEffort() {
        let bonus = BonusRecord(offered: .reps(2), accepted: false, completed: .reps(1), effort: .tooHard)
        XCTAssertNil(bonus.completed)
        XCTAssertNil(bonus.effort)
    }

    func testNotTrackedObservationDropsObservedAmount() {
        let observation = TrackerObservation(status: .notTracked, observed: .reps(5))
        XCTAssertNil(observation.observed)
    }

    func testTrackingSignalClampsToUnitInterval() {
        XCTAssertEqual(TrackingSignal(kind: .tempo, value: -0.25, isReliable: true).value, 0)
        XCTAssertEqual(TrackingSignal(kind: .tempo, value: 1.25, isReliable: true).value, 1)
        XCTAssertEqual(TrackingSignal(kind: .tempo, value: 0.4, isReliable: true).value, 0.4)
    }

    func testSettingsEquipmentIsSortedAndUnique() {
        let setting = SettingsFact(id: id(9), recordedAt: date(9), kind: .equipmentChanged,
                                   equipment: [.dumbbells, .band, .dumbbells])
        XCTAssertEqual(setting.equipment, [.band, .dumbbells])
    }

    func testAdaptiveFactsSortsEveryKindByTimeThenUUIDStringIncludingAfterDecode() throws {
        let earlier = date(10)
        let later = date(11)
        let highID = id(20)
        let lowID = id(19)
        let facts = AdaptiveFacts(
            prescriptions: [makePrescription(id: highID, at: earlier), makePrescription(id: lowID, at: earlier),
                            makePrescription(id: id(21), at: later)],
            evidence: [makeEvidence(id: highID, at: earlier), makeEvidence(id: lowID, at: earlier)],
            calibrations: [makeCalibration(id: highID, at: earlier), makeCalibration(id: lowID, at: earlier)],
            engagement: [makeEngagement(id: highID, at: earlier), makeEngagement(id: lowID, at: earlier)],
            settings: [makeSetting(id: highID, at: earlier), makeSetting(id: lowID, at: earlier)]
        )

        XCTAssertEqual(facts.prescriptions.map(\.id), [lowID, highID, id(21)])
        XCTAssertEqual(facts.evidence.map(\.id), [lowID, highID])
        XCTAssertEqual(facts.calibrations.map(\.id), [lowID, highID])
        XCTAssertEqual(facts.engagement.map(\.id), [lowID, highID])
        XCTAssertEqual(facts.settings.map(\.id), [lowID, highID])

        let decoded = try JSONDecoder().decode(AdaptiveFacts.self, from: JSONEncoder().encode(facts))
        XCTAssertEqual(decoded.prescriptions.map(\.id), facts.prescriptions.map(\.id))
        XCTAssertEqual(decoded.evidence.map(\.id), facts.evidence.map(\.id))
        XCTAssertEqual(decoded.calibrations.map(\.id), facts.calibrations.map(\.id))
        XCTAssertEqual(decoded.engagement.map(\.id), facts.engagement.map(\.id))
        XCTAssertEqual(decoded.settings.map(\.id), facts.settings.map(\.id))
    }

    func testWatermarkIsStableAcrossConstructionAndJSONRoundTrip() throws {
        let firstPrescription = makePrescription(id: id(33), at: date(33))
        let secondPrescription = makePrescription(id: id(34), at: date(34))
        let firstEvidence = makeEvidence(id: id(35), at: date(35))
        let secondEvidence = makeEvidence(id: id(36), at: date(36))
        let first = AdaptiveFacts(prescriptions: [firstPrescription, secondPrescription],
                                  evidence: [firstEvidence, secondEvidence])
        let sameFactsDifferentInputOrder = AdaptiveFacts(
            prescriptions: [secondPrescription, firstPrescription], evidence: [secondEvidence, firstEvidence])
        XCTAssertEqual(first.watermark, sameFactsDifferentInputOrder.watermark)

        let decoded = try JSONDecoder().decode(AdaptiveFacts.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(first.watermark, decoded.watermark)
        XCTAssertEqual(first.watermark, decoded.watermark)
    }

    func testWatermarkChangesWhenAnyFactKindIsAdded() {
        let empty = AdaptiveFacts.empty
        let evidenceFacts = AdaptiveFacts(evidence: [evidence(confirmed: .reps(1), confirmation: .user)])
        let calibrationFacts = AdaptiveFacts(calibrations: [makeCalibration(id: id(22), at: date(22))])
        let engagementFacts = AdaptiveFacts(engagement: [makeEngagement(id: id(23), at: date(23))])
        let settingFacts = AdaptiveFacts(settings: [makeSetting(id: id(24), at: date(24))])

        XCTAssertNotEqual(empty.watermark, AdaptiveFacts(prescriptions: [prescription]).watermark)
        XCTAssertNotEqual(empty.watermark, evidenceFacts.watermark)
        XCTAssertNotEqual(empty.watermark, calibrationFacts.watermark)
        XCTAssertNotEqual(empty.watermark, engagementFacts.watermark)
        XCTAssertNotEqual(empty.watermark, settingFacts.watermark)
    }

    func testWatermarkChangesWhenCalibrationStatusChangesAndNotOtherwise() {
        let initial = makeCalibration(id: id(25), at: date(25), status: .inProgress)
        let unchanged = makeCalibration(id: id(25), at: date(25), status: .inProgress)
        let committed = makeCalibration(id: id(25), at: date(25), status: .committed)

        XCTAssertEqual(AdaptiveFacts(calibrations: [initial]).watermark, AdaptiveFacts(calibrations: [unchanged]).watermark)
        XCTAssertNotEqual(AdaptiveFacts(calibrations: [initial]).watermark, AdaptiveFacts(calibrations: [committed]).watermark)
    }

    @MainActor
    func testInMemoryStoreIgnoresDuplicateFactIDsAndUpsertsCalibrations() throws {
        let store = InMemoryAdaptiveTrainingStore()
        let originalPrescription = prescription
        let duplicatePrescription = makePrescription(id: originalPrescription.id, at: date(30))
        try store.record(originalPrescription)
        try store.record(duplicatePrescription)
        XCTAssertEqual(try store.loadFacts().prescriptions, [originalPrescription])

        let originalEvidence = evidence(confirmed: .reps(3), confirmation: .user)
        let duplicateEvidence = makeEvidence(id: originalEvidence.id, at: date(31))
        try store.record(originalEvidence)
        try store.record(duplicateEvidence)
        XCTAssertEqual(try store.loadFacts().evidence, [originalEvidence])

        let originalEngagement = EngagementFact(id: id(26), recordedAt: date(26), kind: .sessionSkipped)
        let duplicateEngagement = EngagementFact(id: id(26), recordedAt: date(27), kind: .notificationOpened)
        try store.record(originalEngagement)
        try store.record(duplicateEngagement)
        XCTAssertEqual(try store.loadFacts().engagement, [originalEngagement])

        let originalSetting = SettingsFact(id: id(27), recordedAt: date(27), kind: .equipmentChanged, equipment: [.band])
        let duplicateSetting = SettingsFact(id: id(27), recordedAt: date(28), kind: .familyRemoved, family: .push)
        try store.record(originalSetting)
        try store.record(duplicateSetting)
        XCTAssertEqual(try store.loadFacts().settings, [originalSetting])

        let inProgress = makeCalibration(id: id(28), at: date(28), status: .inProgress)
        let committed = makeCalibration(id: id(28), at: date(28), status: .committed)
        try store.save(inProgress)
        try store.save(committed)
        let calibrations = try store.loadFacts().calibrations
        XCTAssertEqual(calibrations.count, 1)
        XCTAssertEqual(calibrations.first?.status, .committed)
    }

    func testConfirmedZeroIsKeptAndDiffersFromNothingConfirmed() throws {
        let confirmedZero = evidence(confirmed: .reps(0), confirmation: .user)
        XCTAssertEqual(confirmedZero.confirmed, .reps(0))
        XCTAssertEqual(confirmedZero.confirmation, .user)
        XCTAssertEqual(confirmedZero.setAmounts, [.reps(0)])
        XCTAssertNil(confirmedZero.confirmed?.dose)

        let unconfirmed = evidence(confirmed: nil, confirmation: .user)
        XCTAssertNotEqual(confirmedZero, unconfirmed)
        try assertRoundTrip(confirmedZero)

        let trackerZero = TrackerObservation(status: .tracked, observed: .reps(0))
        XCTAssertEqual(trackerZero.observed, .reps(0))
        XCTAssertNotEqual(trackerZero, TrackerObservation(status: .lost))
        XCTAssertThrowsError(try JSONDecoder().decode(WorkAmount.self, from: Data(#"{"kind":"reps","amount":-1}"#.utf8)))
    }

    func testUnconfirmedEvidenceNeverHoldsConfirmedSets() {
        let explicitSets = AdaptiveEvidence(id: id(40), recordedAt: date(40), source: .manual, family: .push,
                                            variant: VariantID(rawValue: "push.push_up"), confirmed: .reps(5),
                                            confirmation: .none, setAmounts: [.reps(5), .reps(4)],
                                            tracker: TrackerObservation(status: .tracked, observed: .reps(9)),
                                            effort: nil, completion: .completed)
        XCTAssertNil(explicitSets.confirmed)
        XCTAssertEqual(explicitSets.setAmounts, [])
        XCTAssertEqual(explicitSets.tracker.observed, .reps(9), "the tracker's own count is kept")
        XCTAssertEqual(evidence(confirmed: .reps(3), confirmation: .none).setAmounts, [])
    }

    func testDecodingNormalizesContradictoryJSON() throws {
        let evidenceJSON = """
        {"id":"00000000-0000-0000-0000-000000000029","recordedAt":29,"source":"manual","family":"push",
         "variant":"push.push_up","confirmed":{"kind":"reps","amount":5},"confirmation":"none",
         "setAmounts":[{"kind":"reps","amount":5}],
         "tracker":{"status":"notTracked","observed":{"kind":"reps","amount":4},"rejectionReasons":[],
                    "signals":[{"kind":"tempo","value":3.5,"isReliable":true}]},
         "midSetTooHard":false,"completion":"completed",
         "bonus":{"offered":{"kind":"reps","amount":1},"accepted":false,"completed":{"kind":"reps","amount":1},
                  "effort":"tooHard"}}
        """
        let decoded = try JSONDecoder().decode(AdaptiveEvidence.self, from: Data(evidenceJSON.utf8))
        XCTAssertNil(decoded.confirmed)
        XCTAssertEqual(decoded.confirmation, .none)
        XCTAssertEqual(decoded.setAmounts, [])
        XCTAssertNil(decoded.tracker.observed)
        XCTAssertEqual(decoded.tracker.signals.first?.value, 1)
        XCTAssertNil(decoded.bonus?.completed)
        XCTAssertNil(decoded.bonus?.effort)
    }

    func testDecodingSortsFactsStoredOutOfOrder() throws {
        let early = makeEvidence(id: id(9), at: date(10))
        let tieLow = makeEvidence(id: id(1), at: date(20))
        let tieHigh = makeEvidence(id: id(2), at: date(20))
        let sorted = AdaptiveFacts(evidence: [early, tieLow, tieHigh])
        let encoded = try JSONEncoder().encode(sorted)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["evidence"] = Array(try XCTUnwrap(object["evidence"] as? [Any]).reversed())
        let reversed = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AdaptiveFacts.self, from: reversed)
        XCTAssertEqual(decoded.evidence.map(\.id), [id(9), id(1), id(2)])
        XCTAssertEqual(decoded.watermark, sorted.watermark)
    }

    func testWatermarkIsAFixedValueForFixedFacts() {
        // Pins the algorithm: a cached profile written by one launch must validate on the next.
        let facts = AdaptiveFacts(prescriptions: [makePrescription(id: id(1), at: date(1))],
                                  evidence: [makeEvidence(id: id(2), at: date(2))],
                                  calibrations: [makeCalibration(id: id(3), at: date(3), status: .committed)])
        XCTAssertEqual(facts.watermark, "1.1.1.0.0-9dcf916984eb8eef")
    }

    func testWatermarkChangesWhenACalibrationsContentsChangeUnderTheSameIDAndStatus() {
        let start = CalibrationStart(family: .push, start: RungDose(variant: VariantID(rawValue: "push.wall_push_up"),
                                                                    dose: .reps(3)))
        let lower = CalibrationStart(family: .push, start: RungDose(
            variant: VariantID(rawValue: "push.wall_push_up.shallow"), dose: .reps(1)))
        let original = CalibrationSessionRecord(id: id(3), kind: .initial, startedAt: date(3), endedAt: date(4),
                                                status: .committed, families: [.push], startingPoints: [start])
        var changedStart = original
        changedStart.startingPoints = [lower]
        var changedEquipment = original
        changedEquipment.equipment = [.dumbbells]

        let base = AdaptiveFacts(calibrations: [original]).watermark
        XCTAssertNotEqual(AdaptiveFacts(calibrations: [changedStart]).watermark, base)
        XCTAssertNotEqual(AdaptiveFacts(calibrations: [changedEquipment]).watermark, base)
    }

    func testOnlyAnInProgressCalibrationCanBeReplaced() {
        let inProgress = CalibrationSessionRecord(id: id(3), kind: .initial, startedAt: date(3))
        var committed = inProgress
        committed.status = .committed
        committed.endedAt = date(4)
        var abandoned = committed
        abandoned.status = .abandoned
        var otherStart = inProgress
        otherStart.families = [.push]

        XCTAssertTrue(inProgress.canBeReplaced(by: otherStart))
        XCTAssertTrue(inProgress.canBeReplaced(by: committed))
        XCTAssertTrue(committed.canBeReplaced(by: committed), "an identical resave is idempotent")
        XCTAssertFalse(committed.canBeReplaced(by: inProgress))
        XCTAssertFalse(committed.canBeReplaced(by: abandoned))
        XCTAssertFalse(inProgress.canBeReplaced(by: CalibrationSessionRecord(id: id(3), kind: .recalibration,
                                                                             startedAt: date(3))))
        XCTAssertFalse(inProgress.canBeReplaced(by: CalibrationSessionRecord(id: id(3), kind: .initial,
                                                                             startedAt: date(9))))
    }

    @MainActor
    func testInMemoryStoreTreatsIDsAsOneNamespaceAndEnforcesCalibrationChanges() throws {
        let store = InMemoryAdaptiveTrainingStore()
        try store.record(makeEvidence(id: id(1), at: date(1)))
        XCTAssertThrowsError(try store.save(CalibrationSessionRecord(id: id(1), kind: .initial, startedAt: date(2)))) {
            XCTAssertEqual($0 as? AdaptiveTrainingStoreError, .idBelongsToAnotherFact(id(1)))
        }
        XCTAssertThrowsError(try store.record(EngagementFact(id: id(1), recordedAt: date(2), kind: .sessionSkipped)))

        var calibration = CalibrationSessionRecord(id: id(5), kind: .initial, startedAt: date(5))
        try store.save(calibration)
        calibration.status = .committed
        try store.save(calibration)
        try store.save(calibration)
        var demoted = calibration
        demoted.status = .inProgress
        XCTAssertThrowsError(try store.save(demoted)) {
            XCTAssertEqual($0 as? AdaptiveTrainingStoreError, .calibrationChangeNotAllowed(id(5)))
        }
        try store.save(CalibrationSessionRecord(id: id(6), kind: .recalibration, startedAt: date(6)))

        XCTAssertEqual(try store.loadFacts().calibrations.map(\.status), [.committed, .inProgress])
        XCTAssertEqual(try store.loadFacts().evidence.map(\.id), [id(1)])
    }

    @MainActor
    func testInMemoryStoreRoundTripsCachedProfileAndValidatesItsInputs() throws {
        let facts = AdaptiveFacts(evidence: [evidence(confirmed: .reps(2), confirmation: .user)])
        let profile = CachedProfile(policyVersion: .v1, catalogVersion: "ladders-1", factsWatermark: facts.watermark,
                                    payload: Data([1, 2, 3]), builtAt: date(29))
        let store = InMemoryAdaptiveTrainingStore()
        try store.saveCachedProfile(profile)

        XCTAssertEqual(store.loadCachedProfile(), profile)
        XCTAssertTrue(profile.isValid(for: .v1, catalogVersion: "ladders-1", facts: facts))
        XCTAssertFalse(profile.isValid(for: PolicyVersion(rawValue: "adaptive-policy-2"), catalogVersion: "ladders-1",
                                       facts: facts))
        XCTAssertFalse(profile.isValid(for: .v1, catalogVersion: "ladders-2", facts: facts))
        XCTAssertFalse(profile.isValid(for: .v1, catalogVersion: "ladders-1", facts: .empty))
    }

    private var prescription: Prescription {
        makePrescription(id: id(1), at: date(1))
    }

    private var calibrationStart: CalibrationStart {
        CalibrationStart(family: .push, start: RungDose(variant: VariantID(rawValue: "push.wall_push_up"), dose: .reps(3)))
    }

    private var evidenceWithoutOptionals: AdaptiveEvidence {
        AdaptiveEvidence(id: id(32), recordedAt: date(32), source: .manual, family: .push,
                         variant: VariantID(rawValue: "push.wall_push_up"), confirmed: nil, confirmation: .none,
                         tracker: .notTracked, effort: nil, completion: .notAttempted)
    }

    private func evidence(confirmed: WorkAmount?, confirmation: ConfirmationSource) -> AdaptiveEvidence {
        AdaptiveEvidence(id: id(2), recordedAt: date(2), source: .adaptive, family: .push,
                         variant: VariantID(rawValue: "push.wall_push_up"), prescriptionID: id(1),
                         prescriptionItemID: id(11), workoutID: id(12), calibrationID: id(13),
                         prescribed: .reps(4), confirmed: confirmed, confirmation: confirmation,
                         setAmounts: nil,
                         tracker: TrackerObservation(status: .tracked, observed: .reps(3),
                                                     rejectionReasons: ["shortRange"],
                                                     signals: [TrackingSignal(kind: .rangeOfMotion, value: 0.8,
                                                                              isReliable: true)]),
                         effort: .okay, midSetTooHard: true,
                         bonus: BonusRecord(offered: .reps(2), accepted: true, completed: .reps(1), effort: .easy),
                         completion: .completed, weightNote: "5 lb")
    }

    private func makePrescription(id: UUID, at: Date) -> Prescription {
        Prescription(id: id, issuedAt: at, kind: .todaySession, policyVersion: .v1, catalogVersion: "ladders-1",
                     items: [PrescriptionItem(id: self.id(30), family: .push,
                                              target: RungDose(variant: VariantID(rawValue: "push.wall_push_up"),
                                                               dose: .reps(4)), role: .main, offersBonus: true)],
                     rationale: "Continue with a comfortable set.")
    }

    private func makeEvidence(id factID: UUID, at: Date) -> AdaptiveEvidence {
        AdaptiveEvidence(id: factID, recordedAt: at, source: .manual, family: .squat,
                         variant: VariantID(rawValue: "squat.sit_to_stand"), confirmed: .reps(2), confirmation: .user,
                         tracker: .notTracked, effort: .okay, completion: .completed)
    }

    private func makeCalibration(id factID: UUID, at: Date,
                                 status: CalibrationStatus = .inProgress) -> CalibrationSessionRecord {
        CalibrationSessionRecord(id: factID, kind: .initial, startedAt: at, status: status)
    }

    private func makeEngagement(id factID: UUID, at: Date) -> EngagementFact {
        EngagementFact(id: factID, recordedAt: at, kind: .sessionSkipped, family: .push)
    }

    private func makeSetting(id factID: UUID, at: Date) -> SettingsFact {
        SettingsFact(id: factID, recordedAt: at, kind: .familyRemoved, family: .push)
    }

    private func assertRoundTrip<Value: Codable & Equatable>(_ value: Value,
                                                             file: StaticString = #filePath,
                                                             line: UInt = #line) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    private func id(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

