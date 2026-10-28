import XCTest
@testable import AdaptiveTraining

final class AdaptiveEventTests: XCTestCase {
    func testDerivesCalibrationProgressRegressionEffortSessionBonusAndReturnEvents() {
        let calibration = Fixtures.calibration(id: 240)
        let secondItem = Fixtures.prescription(id: 241, day: 2, itemID: 242, dose: .reps(3))
        let thirdItem = Fixtures.prescription(id: 243, day: 20, itemID: 244, dose: .reps(4))
        let first = Fixtures.evidence(id: 245, day: 1)
        let second = Fixtures.evidence(id: 246, day: 2, prescribed: .reps(3), confirmed: .reps(3),
                                       itemID: 242, prescriptionID: 241,
                                       bonus: BonusRecord(offered: .reps(1), accepted: true,
                                                          completed: .reps(1), effort: .easy))
        let third = Fixtures.evidence(id: 247, day: 20, prescribed: .reps(4), confirmed: .reps(4),
                                      effort: .tooHard, itemID: 244, prescriptionID: 243,
                                      bonus: BonusRecord(offered: .reps(1), accepted: false))
        let recalibration = Fixtures.calibration(id: 248, day: 21, variant: Fixtures.wall, dose: .reps(3),
                                                 kind: .recalibration)
        let facts = AdaptiveFacts(
            prescriptions: [secondItem, thirdItem],
            evidence: [first, second, third],
            calibrations: [calibration, recalibration]
        )
        let profile = Fixtures.profile(facts)
        let events = AdaptiveReplay.events(facts: facts, profile: profile)
        let kinds = events.map(\.kind)

        XCTAssertEqual(kinds.filter { $0 == .calibrationCompleted }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .recalibrationCompleted }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .progressed }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .regressed }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .effortEasy }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == .effortTooHard }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .sessionCompleted }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == .bonusOffered }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == .bonusAccepted }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .bonusDeclined }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .returnedAfterAbsence }.count, 1)
        XCTAssertFalse(kinds.contains(.tinySessionPrescribed))

        let progress = events.first { $0.kind == .progressed }
        XCTAssertEqual(progress?.factID, second.id)
        XCTAssertEqual(progress?.family, .push)
        XCTAssertEqual(progress?.from?.dose, .reps(3))
        XCTAssertEqual(progress?.to?.dose, .reps(4))
        let declined = events.first { $0.kind == .bonusDeclined }
        XCTAssertEqual(declined?.factID, third.id)
        XCTAssertEqual(declined?.family, .push)
    }

    func testEventOrderUsesTimeThenFactIDThenAdaptiveEventKindOrder() {
        let calibration = Fixtures.calibration(id: 250)
        let first = Fixtures.evidence(id: 252, day: 1, prescribed: .reps(3), confirmed: .reps(3),
                                      bonus: BonusRecord(offered: .reps(1), accepted: false))
        let second = Fixtures.evidence(id: 251, day: 1, prescribed: .reps(3), confirmed: .reps(3), effort: .okay)
        let facts = AdaptiveFacts(
            evidence: [first, second],
            calibrations: [calibration]
        )
        let profile = Fixtures.profile(facts)
        let events = AdaptiveReplay.events(facts: facts, profile: profile)
        let sameTime = events.filter { $0.at == Fixtures.date(day: 1) }
        XCTAssertEqual(sameTime.first?.factID, second.id)
        let firstFactEvents = sameTime.filter { $0.factID == first.id }
        XCTAssertEqual(firstFactEvents.map(\.kind), [.effortEasy, .bonusOffered, .bonusDeclined])
    }

    func testUncommittedProbeProducesNoEffortEvent() {
        let calibration = Fixtures.calibration(id: 253, status: .abandoned)
        let probe = Fixtures.evidence(id: 254, day: 0, hour: 11, source: .calibration,
                                      confirmed: .reps(3), effort: .easy, calibrationID: 253)
        let facts = AdaptiveFacts(
            evidence: [probe],
            calibrations: [calibration]
        )
        let profile = Fixtures.profile(facts)
        XCTAssertFalse(AdaptiveReplay.events(facts: facts, profile: profile).contains { $0.kind == .effortEasy })
    }
}
