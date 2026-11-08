import XCTest
@testable import AdaptiveTraining

final class CalibrationFlowTests: XCTestCase {
    private let shallow = Fixtures.shallowWall
    private let wall = Fixtures.wall
    private let incline = Fixtures.incline
    private let pushUp = Fixtures.pushUp
    private let partialSit = VariantID(rawValue: "squat.sit_to_stand.partial")
    private let sit = VariantID(rawValue: "squat.sit_to_stand")
    private let air = VariantID(rawValue: "squat.air_squat")
    private let partialSlide = VariantID(rawValue: "overhead.wall_slide.partial")
    private let slide = VariantID(rawValue: "overhead.wall_slide")
    private let press = VariantID(rawValue: "overhead.shoulder_press")

    // MARK: - Helpers

    private func makeFlow(kind: CalibrationKind = .initial, catalog: ProgressionCatalog = Fixtures.catalog,
                          profile: AdaptiveProfile? = nil, equipment: Set<TrainingEquipment> = []) -> CalibrationFlow {
        let builtIDs = Set(catalog.families.flatMap { $0.rungs.map(\.exerciseID) })
        return CalibrationFlow(id: Fixtures.id(1), kind: kind, startedAt: Fixtures.date(day: 0, hour: 10),
                               catalog: catalog,
                               availability: Availability(builtExerciseIDs: builtIDs, equipment: equipment),
                               currentProfile: profile)
    }

    /// Runs the quiz. A family missing from `closest` answers "Not sure".
    private func quiz(equipment: Set<TrainingEquipment> = [], families: [MovementFamilyID] = [.push, .squat],
                      closest: [MovementFamilyID: VariantID] = [:],
                      from start: CalibrationFlow? = nil) -> CalibrationFlow {
        var flow = start ?? makeFlow()
        flow.setEquipment(equipment)
        flow.setFamilies(families)
        for _ in 0..<20 {
            guard case .closeness(let family, _) = flow.step else { break }
            flow.answerCloseness(family: family, variant: closest[family])
        }
        return flow
    }

    private func rate(_ flow: inout CalibrationFlow, _ effort: EffortFeedback, confirmed: WorkAmount? = nil,
                      file: StaticString = #filePath, line: UInt = #line) {
        guard case .probe(let family, let rungDose, _) = flow.step else {
            return XCTFail("Not at a probe: \(flow.step)", file: file, line: line)
        }
        flow.probeResult(family: family, effort: effort, confirmed: confirmed ?? WorkAmount(rungDose.dose))
    }

    private func assertProbe(_ flow: CalibrationFlow, _ family: MovementFamilyID, _ variant: VariantID, _ dose: Dose,
                             harder: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(flow.step, .probe(family, RungDose(variant: variant, dose: dose), isHarderOffer: harder),
                       file: file, line: line)
    }

    private func summary(_ flow: CalibrationFlow, file: StaticString = #filePath, line: UInt = #line)
        -> [CalibrationStart] {
        guard case .summary(let points) = flow.step else {
            XCTFail("Not at the summary: \(flow.step)", file: file, line: line)
            return []
        }
        return points
    }

    private func start(_ points: [CalibrationStart], _ family: MovementFamilyID) -> RungDose? {
        points.first { $0.family == family }?.start
    }

    // MARK: - The quiz

    func testTheQuizAsksEquipmentThenAreasThenWhichFeelsClosestThenProbes() {
        var flow = makeFlow()
        XCTAssertEqual(flow.step, .equipment)

        flow.setEquipment([.dumbbells])
        XCTAssertEqual(flow.step, .families)
        XCTAssertEqual(flow.equipmentAnswer, [.dumbbells])

        flow.setFamilies([.push, .squat])
        XCTAssertEqual(flow.step, .closeness(.push, options: [shallow, wall, incline, pushUp]))

        flow.answerCloseness(family: .push, variant: nil)
        XCTAssertEqual(flow.step, .closeness(.squat, options: [partialSit, sit, air]))

        flow.answerCloseness(family: .squat, variant: nil)
        assertProbe(flow, .push, shallow, .reps(2))
    }

    func testPushAndSquatAreSuggestedAndTheOthersCanBeAdded() {
        var flow = makeFlow()
        flow.setEquipment([])

        XCTAssertEqual(flow.suggestedFamilies, [.push, .squat])
        XCTAssertEqual(flow.offeredFamilies, Fixtures.catalog.families.map(\.id))

        flow.setFamilies([.core, .squat, .push])
        XCTAssertEqual(flow.families, [.push, .squat, .core], "Chosen areas keep catalog order.")
    }

    func testAnEmptyOrUnknownChoiceOfAreasIsIgnored() {
        var flow = makeFlow()
        flow.setEquipment([])
        let before = flow

        flow.setFamilies([])
        XCTAssertEqual(flow, before)
        flow.setFamilies([MovementFamilyID(rawValue: "swim")])
        XCTAssertEqual(flow, before)
        XCTAssertEqual(flow.step, .families)

        flow.setFamilies([MovementFamilyID(rawValue: "swim"), .squat])
        XCTAssertEqual(flow.families, [.squat], "Unknown areas are dropped; the rest stays.")
    }

    func testNoDumbbellRungsAreOfferedWithoutDumbbells() {
        var without = makeFlow()
        without.setEquipment([.band])
        without.setFamilies([.overhead, .hinge, .lunge])
        XCTAssertEqual(without.step, .closeness(.overhead, options: [partialSlide, slide]),
                       "Areas are asked in catalog order, and the shoulder press needs dumbbells.")
        XCTAssertEqual(without.availableRungs(of: .hinge).map(\.id), [VariantID(rawValue: "hinge.hip_hinge.supported_shallow"),
                                                                       VariantID(rawValue: "hinge.hip_hinge")])
        XCTAssertFalse(without.availableRungs(of: .lunge).contains { $0.requiredEquipment.contains(.dumbbells) })

        var with = makeFlow()
        with.setEquipment([.dumbbells])
        with.setFamilies([.overhead])
        XCTAssertEqual(with.step, .closeness(.overhead, options: [partialSlide, slide, press]))
    }

    func testNoDumbbellRungIsOfferedAsAHarderSampleEither() {
        var without = quiz(families: [.overhead])
        rate(&without, .easy)
        assertProbe(without, .overhead, slide, .reps(1), harder: true)
        rate(&without, .easy)
        XCTAssertEqual(summary(without), [CalibrationStart(family: .overhead, start: RungDose(variant: slide, dose: .reps(1)))],
                       "Nothing harder than the wall slide without dumbbells, so it settles there.")

        var with = quiz(equipment: [.dumbbells], families: [.overhead])
        rate(&with, .easy)
        assertProbe(with, .overhead, slide, .reps(1), harder: true)
        rate(&with, .easy)
        assertProbe(with, .overhead, press, .reps(1), harder: true)
    }

    func testAFamilyWithOneAvailableRungSkipsTheClosenessQuestion() {
        var flow = makeFlow()
        flow.setEquipment([])
        flow.setFamilies([.neck, .push])

        XCTAssertEqual(flow.step, .closeness(.push, options: [shallow, wall, incline, pushUp]),
                       "Neck has one rung, so only push is asked.")
        flow.answerCloseness(family: .push, variant: nil)
        assertProbe(flow, .push, shallow, .reps(2))
        rate(&flow, .okay)
        assertProbe(flow, .neck, VariantID(rawValue: "neck.chin_tuck"), .reps(2))

        var rows = makeFlow()
        rows.setEquipment([])
        rows.setFamilies([.row])
        assertProbe(rows, .row, VariantID(rawValue: "row.scapular_squeeze.seated"), .reps(2))
    }

    // MARK: - Start rung

    func testNotSureStartsAtTheFloor() {
        let flow = quiz(closest: [:])
        assertProbe(flow, .push, shallow, .reps(2))
    }

    func testAnAnswerIsCappedAtTheMiddleRungOfTheAvailableLadder() {
        let capped = quiz(families: [.push], closest: [.push: pushUp])
        assertProbe(capped, .push, wall, .reps(2))

        let alsoCapped = quiz(families: [.push], closest: [.push: incline])
        assertProbe(alsoCapped, .push, wall, .reps(2))

        let squat = quiz(families: [.squat], closest: [.squat: air])
        assertProbe(squat, .squat, sit, .reps(2))

        let belowTheCap = quiz(families: [.push], closest: [.push: shallow])
        assertProbe(belowTheCap, .push, shallow, .reps(2))

        let atTheCap = quiz(families: [.push], closest: [.push: wall])
        assertProbe(atTheCap, .push, wall, .reps(2))
    }

    func testTheMiddleRungFollowsWhatIsAvailable() {
        XCTAssertEqual([1, 2, 3, 4, 5].map(CalibrationFlow.middleIndex(of:)), [0, 0, 1, 1, 2])

        let withoutDumbbells = quiz(families: [.overhead], closest: [.overhead: slide])
        assertProbe(withoutDumbbells, .overhead, partialSlide, .reps(2), harder: false)

        let withDumbbells = quiz(equipment: [.dumbbells], families: [.overhead], closest: [.overhead: press])
        assertProbe(withDumbbells, .overhead, slide, .reps(2))
    }

    func testAnAnswerThatIsNotAnOptionIsIgnored() {
        var flow = makeFlow()
        flow.setEquipment([])
        flow.setFamilies([.push])
        let before = flow

        flow.answerCloseness(family: .push, variant: press)
        XCTAssertEqual(flow, before)
        flow.answerCloseness(family: .squat, variant: sit)
        XCTAssertEqual(flow, before, "Only the family being asked can answer.")
    }

    // MARK: - Probe dose

    func testAFirstSampleIsTwoRepsWhenTheRangeAllowsItOtherwiseTheMinimum() {
        let flow = quiz(families: [.push, .glute])
        assertProbe(flow, .push, shallow, .reps(2))

        let hold = quiz(families: [.glute])
        assertProbe(hold, .glute, VariantID(rawValue: "glute.glute_squeeze"), .seconds(5))

        for (range, expected) in [(DoseRange.reps(5...10), Dose.reps(5)), (.reps(1...1), .reps(1)),
                                  (.reps(2...6), .reps(2)), (.reps(1...8), .reps(2))] {
            let rung = ProgressionRung(id: VariantID(rawValue: "push.test"), exerciseID: "wall_push_up",
                                       doseRange: range, isFloor: true)
            let catalog = ProgressionCatalog(version: "test", families: [MovementFamily(id: .push, debugName: "Push",
                                                                                         rungs: [rung])])
            let custom = quiz(families: [.push], from: makeFlow(catalog: catalog))
            assertProbe(custom, .push, rung.id, expected)
        }
    }

    // MARK: - Ratings

    func testOkaySettlesAtTheProbeDose() {
        var flow = quiz(families: [.push], closest: [.push: wall])
        rate(&flow, .okay)

        XCTAssertEqual(summary(flow), [CalibrationStart(family: .push, start: RungDose(variant: wall, dose: .reps(2)))])
        XCTAssertEqual(flow.probeCount(of: .push), 1)
    }

    func testEasyOffersTheNextHarderRungAtItsMinimumAndOkaySettlesThere() {
        var flow = quiz(families: [.push])
        rate(&flow, .easy)
        assertProbe(flow, .push, wall, .reps(1), harder: true)

        rate(&flow, .okay)
        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: wall, dose: .reps(1)))
        XCTAssertEqual(flow.probeCount(of: .push), 2)
    }

    func testDecliningAHarderOfferSettlesAtTheLastComfortableProbeAndIsNeutral() {
        var flow = quiz(families: [.push])
        rate(&flow, .easy)
        assertProbe(flow, .push, wall, .reps(1), harder: true)

        flow.declineHarderProbe(family: .push)

        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: shallow, dose: .reps(2)),
                       "It settles at the Easy sample's own dose, on its own rung.")
        XCTAssertEqual(flow.probeCount(of: .push), 1, "Declining is not a sample and counts as nothing.")
    }

    func testASingleEasyNeverRaisesTheStartingDose() {
        // Easy, then the user stops: the start is exactly what was sampled, whatever the rung or the range.
        for (family, answer, rung) in [(MovementFamilyID.push, wall, wall), (.squat, sit, sit), (.push, shallow, shallow)] {
            var flow = quiz(families: [family], closest: [family: answer])
            rate(&flow, .easy)
            flow.declineHarderProbe(family: family)
            XCTAssertEqual(start(summary(flow), family), RungDose(variant: rung, dose: .reps(2)))
        }

        // Easy at the top of a ladder settles at the sampled dose too.
        var top = quiz(families: [.squat], closest: [.squat: sit])
        rate(&top, .easy)
        rate(&top, .easy)
        XCTAssertEqual(start(summary(top), .squat), RungDose(variant: air, dose: .reps(1)))
    }

    func testTooHardStepsDownOneRungAtItsMinimum() {
        var flow = quiz(families: [.push], closest: [.push: wall])
        rate(&flow, .tooHard)
        assertProbe(flow, .push, shallow, .reps(1))

        rate(&flow, .okay)
        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: shallow, dose: .reps(1)))
        XCTAssertEqual(flow.probeCount(of: .push), 2)
    }

    func testTooHardIsAuthoritativeEvenWhenTheWorkWasFinished() {
        var flow = quiz(families: [.squat], closest: [.squat: sit])
        rate(&flow, .tooHard, confirmed: .reps(2))
        assertProbe(flow, .squat, partialSit, .reps(1))
    }

    func testTooHardAtTheFloorSettlesAtTheFloorMinimumWithoutAnotherSample() {
        var flow = quiz(families: [.push])
        rate(&flow, .tooHard)

        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: shallow, dose: .reps(1)))
        XCTAssertEqual(flow.probeCount(of: .push), 1)

        var hold = quiz(families: [.glute])
        rate(&hold, .tooHard)
        XCTAssertEqual(start(summary(hold), .glute), RungDose(variant: VariantID(rawValue: "glute.glute_squeeze"),
                                                              dose: .seconds(5)))
    }

    func testTooHardOnAHarderOfferSettlesAtTheLastComfortableProbe() {
        var flow = quiz(families: [.push])
        rate(&flow, .easy)
        assertProbe(flow, .push, wall, .reps(1), harder: true)

        rate(&flow, .tooHard)

        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: shallow, dose: .reps(2)),
                       "The easier rung was already comfortable, so it isn't sampled again.")
        XCTAssertEqual(flow.probeCount(of: .push), 2)
    }

    func testNothingHarderIsOfferedAfterATooHard() {
        var flow = quiz(families: [.push], closest: [.push: wall])
        rate(&flow, .tooHard)
        rate(&flow, .easy)

        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: shallow, dose: .reps(1)),
                       "Wall push-ups were too hard a moment ago, so an Easy on the step down just settles.")
    }

    func testNothingHarderAtTheTopOfTheLadderSettlesAtTheSample() {
        var flow = quiz(families: [.squat], closest: [.squat: sit])
        rate(&flow, .easy)
        assertProbe(flow, .squat, air, .reps(1), harder: true)
        rate(&flow, .easy)

        XCTAssertEqual(start(summary(flow), .squat), RungDose(variant: air, dose: .reps(1)))
        XCTAssertEqual(flow.probeCount(of: .squat), 2)
    }

    // MARK: - The probe limit

    func testAFamilyGetsAtMostThreeProbes() {
        var flow = quiz(families: [.push])
        rate(&flow, .easy)
        assertProbe(flow, .push, wall, .reps(1), harder: true)
        rate(&flow, .easy)
        assertProbe(flow, .push, incline, .reps(1), harder: true)
        rate(&flow, .easy)

        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: incline, dose: .reps(1)),
                       "Push-ups are harder still, but three samples is the limit.")
        XCTAssertEqual(flow.probeCount(of: .push), CalibrationFlow.probeLimit)
    }

    func testTheLimitSettlesAtTheLastComfortableProbeAfterATooHard() {
        var flow = quiz(families: [.push])
        rate(&flow, .easy)
        rate(&flow, .easy)
        assertProbe(flow, .push, incline, .reps(1), harder: true)
        rate(&flow, .tooHard)

        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: wall, dose: .reps(1)))
    }

    func testOkayOrEasyWithNothingConfirmedOffersTheSameSampleAgain() {
        var flow = quiz(families: [.push], closest: [.push: wall])
        rate(&flow, .okay, confirmed: .reps(0))
        assertProbe(flow, .push, wall, .reps(2))
        rate(&flow, .easy, confirmed: .reps(0))
        assertProbe(flow, .push, wall, .reps(2))

        rate(&flow, .okay, confirmed: .reps(1))
        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: wall, dose: .reps(2)),
                       "Once any work is confirmed, Okay settles at the probe dose.")
        XCTAssertEqual(flow.probeCount(of: .push), 3)
    }

    func testNothingConfirmedThreeTimesSettlesAtTheFloorMinimum() {
        var flow = quiz(families: [.push], closest: [.push: wall])
        for _ in 0..<3 { rate(&flow, .okay, confirmed: .reps(0)) }

        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: shallow, dose: .reps(1)))
    }

    // MARK: - Skipping and ignored inputs

    func testSkippingAFamilyLeavesItOutOfTheSummary() {
        var flow = quiz()
        flow.skipFamily(family: .squat)
        XCTAssertEqual(flow.families, [.push])
        assertProbe(flow, .push, shallow, .reps(2))
        rate(&flow, .okay)

        XCTAssertEqual(summary(flow).map(\.family), [.push])
    }

    func testSkippingAFamilyAfterASampleKeepsTheCountButGivesNoStartingPoint() {
        var flow = quiz()
        rate(&flow, .okay)
        assertProbe(flow, .squat, partialSit, .reps(2))
        rate(&flow, .easy)
        assertProbe(flow, .squat, sit, .reps(1), harder: true)
        flow.skipFamily(family: .squat)

        XCTAssertEqual(summary(flow).map(\.family), [.push])
        XCTAssertEqual(flow.probeCount, 2, "Both samples were rated, even though squat was left out.")
    }

    func testSkippingEveryFamilyEndsAtAnEmptySummaryThatCannotBeCommitted() {
        var flow = quiz()
        flow.skipFamily(family: .push)
        flow.skipFamily(family: .squat)

        XCTAssertEqual(summary(flow), [])
        XCTAssertNil(flow.committedRecord(at: Fixtures.date()))
    }

    func testASettledFamilyCannotBeSkipped() {
        var flow = quiz(families: [.push, .squat])
        rate(&flow, .okay)
        flow.skipFamily(family: .push)

        XCTAssertEqual(flow.families, [.push, .squat])
    }

    func testInputsOutsideTheirStepAreIgnored() {
        var flow = makeFlow()
        let fresh = flow
        flow.setFamilies([.push])
        flow.answerCloseness(family: .push, variant: nil)
        flow.probeResult(family: .push, effort: .easy, confirmed: .reps(2))
        flow.declineHarderProbe(family: .push)
        flow.skipFamily(family: .push)
        XCTAssertEqual(flow, fresh, "Nothing applies at the equipment step except the equipment answer.")

        flow.setEquipment([.dumbbells])
        let afterEquipment = flow
        flow.setEquipment([])
        XCTAssertEqual(flow, afterEquipment, "The equipment answer is taken once.")

        flow.setFamilies([.push])
        flow.setFamilies([.squat])
        XCTAssertEqual(flow.families, [.push], "The areas are chosen once.")

        flow.answerCloseness(family: .push, variant: nil)
        let atProbe = flow
        flow.declineHarderProbe(family: .push)
        XCTAssertEqual(flow, atProbe, "Only a harder offer can be declined.")
        flow.probeResult(family: .squat, effort: .okay, confirmed: .reps(2))
        XCTAssertEqual(flow, atProbe, "Only the family being sampled can be rated.")
    }

    // MARK: - Facts

    func testTheRecordsFollowTheFlow() throws {
        var flow = makeFlow()
        let fresh = flow.inProgressRecord
        XCTAssertEqual(fresh.id, Fixtures.id(1))
        XCTAssertEqual(fresh.kind, .initial)
        XCTAssertEqual(fresh.startedAt, Fixtures.date(day: 0, hour: 10))
        XCTAssertEqual(fresh.status, .inProgress)
        XCTAssertNil(fresh.endedAt)
        XCTAssertNil(fresh.equipment)
        XCTAssertEqual(fresh.families, [])
        XCTAssertEqual(fresh.startingPoints, [])

        flow = quiz(equipment: [.dumbbells, .band], families: [.squat, .push])
        let answered = flow.inProgressRecord
        XCTAssertEqual(answered.equipment, [.band, .dumbbells])
        XCTAssertEqual(answered.families, [.push, .squat])
        XCTAssertEqual(answered.startingPoints, [])
        XCTAssertNil(flow.committedRecord(at: Fixtures.date()), "Not at the summary yet.")

        rate(&flow, .okay)
        rate(&flow, .okay)
        let committed = try XCTUnwrap(flow.committedRecord(at: Fixtures.date(day: 0, hour: 12)))
        XCTAssertEqual(committed.status, .committed)
        XCTAssertEqual(committed.endedAt, Fixtures.date(day: 0, hour: 12))
        XCTAssertEqual(committed.startingPoints, summary(flow))
        XCTAssertEqual(committed.families, [.push, .squat])
        XCTAssertEqual(committed.equipment, [.band, .dumbbells])

        let abandoned = flow.abandonedRecord(at: Fixtures.date(day: 0, hour: 12))
        XCTAssertEqual(abandoned.status, .abandoned)
        XCTAssertEqual(abandoned.startingPoints, [], "Leaving accepts nothing, even from the summary.")
        XCTAssertTrue(fresh.canBeReplaced(by: abandoned), "An attempt in progress can end.")
        XCTAssertFalse(committed.canBeReplaced(by: abandoned), "A committed attempt never changes.")
    }

    // MARK: - Codable and profiles

    func testTheFlowSurvivesEncodingMidwayAndFinishesTheSame() throws {
        var flow = quiz()
        rate(&flow, .easy)

        let decoded = try JSONDecoder().decode(CalibrationFlow.self, from: JSONEncoder().encode(flow))
        XCTAssertEqual(decoded, flow)
        XCTAssertEqual(decoded.step, flow.step)

        var original = flow
        var copy = decoded
        for _ in 0..<6 {
            guard case .probe = original.step else { break }
            rate(&original, .okay)
            rate(&copy, .okay)
        }
        XCTAssertEqual(copy, original)
        XCTAssertEqual(summary(copy), summary(original))
    }

    func testAProfileSkipsTheEquipmentQuestionAndChangesTheSuggestions() {
        let profile = Fixtures.profile(Fixtures.seededFacts())
        XCTAssertEqual(profile.activeFamilies, [.push])

        let recalibration = makeFlow(kind: .recalibration, profile: profile)
        XCTAssertEqual(recalibration.step, .families)
        XCTAssertEqual(recalibration.suggestedFamilies, [.push])
        XCTAssertNil(recalibration.equipmentAnswer)

        let adding = makeFlow(kind: .addFamily, profile: profile)
        XCTAssertEqual(adding.step, .families)
        XCTAssertEqual(adding.suggestedFamilies, [])
        XCTAssertFalse(adding.offeredFamilies.contains(.push))
        XCTAssertTrue(adding.offeredFamilies.contains(.squat))

        var run = recalibration
        run.setFamilies([.push])
        assertProbe(run, .push, wall, .reps(2))
        rate(&run, .okay)
        XCTAssertNil(run.inProgressRecord.equipment, "The quiz didn't ask, so it records no equipment answer.")
        XCTAssertEqual(run.committedRecord(at: Fixtures.date())?.kind, .recalibration)
    }

    func testAddFamilySuggestionsStayEmptyWithoutAProfileBeforeAndAfterEquipment() {
        var flow = makeFlow(kind: .addFamily)

        XCTAssertEqual(flow.step, .equipment)
        XCTAssertEqual(flow.suggestedFamilies, [])

        flow.setEquipment([.dumbbells])

        XCTAssertEqual(flow.step, .families)
        XCTAssertEqual(flow.suggestedFamilies, [])
    }

    func testRecalibrationStartsOnTheCurrentRungAtTheFirstSampleDose() {
        let profile = Fixtures.profile(Fixtures.seededFacts(dose: .reps(6)))
        var flow = makeFlow(kind: .recalibration, profile: profile)
        flow.setFamilies([.push])

        assertProbe(flow, .push, wall, .reps(2))
    }

    func testOkayKeepsTheCurrentDoseWhenItIsAboveOrBelowTheFirstSampleDose() {
        for (currentDose, expectedDose) in [(Dose.reps(6), Dose.reps(6)), (.reps(1), .reps(2))] {
            let profile = Fixtures.profile(Fixtures.seededFacts(dose: currentDose))
            var flow = makeFlow(kind: .recalibration, profile: profile)
            flow.setFamilies([.push])
            rate(&flow, .okay)

            XCTAssertEqual(start(summary(flow), .push), RungDose(variant: wall, dose: expectedDose))
        }
    }

    func testDecliningAHarderRecalibrationOfferKeepsTheCurrentDose() {
        let profile = Fixtures.profile(Fixtures.seededFacts(dose: .reps(6)))
        var flow = makeFlow(kind: .recalibration, profile: profile)
        flow.setFamilies([.push])
        rate(&flow, .easy)
        assertProbe(flow, .push, incline, .reps(1), harder: true)

        flow.declineHarderProbe(family: .push)

        XCTAssertEqual(start(summary(flow), .push), RungDose(variant: wall, dose: .reps(6)))
    }

    func testTooHardOnTheCurrentRecalibrationRungStepsDownAtItsMinimum() {
        let profile = Fixtures.profile(Fixtures.seededFacts(dose: .reps(6)))
        var flow = makeFlow(kind: .recalibration, profile: profile)
        flow.setFamilies([.push])
        rate(&flow, .tooHard)

        assertProbe(flow, .push, shallow, .reps(1))
    }

    func testARecalibrationFamilyAddedDuringTheFlowGetsAClosenessQuestion() {
        let profile = Fixtures.profile(Fixtures.seededFacts(dose: .reps(4)))
        var flow = makeFlow(kind: .recalibration, profile: profile)
        flow.setFamilies([.push, .squat])
        XCTAssertEqual(flow.step, .closeness(.squat, options: [partialSit, sit, air]))
        flow.answerCloseness(family: .squat, variant: nil)
        assertProbe(flow, .push, wall, .reps(2))
        rate(&flow, .okay)
        assertProbe(flow, .squat, partialSit, .reps(2))
    }

    func testRecalibrationFlowRoundTripsMidSampleWithItsCurrentDose() throws {
        let profile = Fixtures.profile(Fixtures.seededFacts(dose: .reps(6)))
        var flow = makeFlow(kind: .recalibration, profile: profile)
        flow.setFamilies([.push])

        let decoded = try JSONDecoder().decode(CalibrationFlow.self, from: JSONEncoder().encode(flow))

        XCTAssertEqual(decoded, flow)
        rate(&flow, .okay)
        var resumed = decoded
        rate(&resumed, .okay)
        XCTAssertEqual(summary(resumed), summary(flow))
        XCTAssertEqual(start(summary(resumed), .push), RungDose(variant: wall, dose: .reps(6)))
    }

    func testNoFamilyEverStartsAboveItsMiddleRung() {
        // Whatever the answer, the first sample is on an available rung no higher than the middle one.
        for family in Fixtures.catalog.families {
            let answers: [ProgressionRung?] = [nil] + family.rungs.map { Optional($0) }
            for answer in answers {
                var flow = makeFlow()
                flow.setEquipment([.dumbbells])
                flow.setFamilies([family.id])
                if case .closeness = flow.step { flow.answerCloseness(family: family.id, variant: answer?.id) }
                guard case .probe(_, let rungDose, _) = flow.step else {
                    XCTFail("\(family.id): no probe after the quiz")
                    continue
                }
                let rungs = flow.availableRungs(of: family.id)
                let index = rungs.firstIndex { $0.id == rungDose.variant }
                XCTAssertNotNil(index, "\(family.id): the probe is on an available rung")
                XCTAssertLessThanOrEqual(index ?? Int.max, CalibrationFlow.middleIndex(of: rungs.count))
            }
        }
    }
}
