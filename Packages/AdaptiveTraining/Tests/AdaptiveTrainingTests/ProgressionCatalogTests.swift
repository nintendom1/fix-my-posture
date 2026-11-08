import XCTest
@testable import AdaptiveTraining

final class ProgressionCatalogTests: XCTestCase {
    private let catalog = ProgressionCatalog.v1
    private var everything: Availability {
        Availability(builtExerciseIDs: Set(catalog.families.flatMap(\.rungs).map(\.exerciseID)),
                     equipment: Set(TrainingEquipment.allCases))
    }

    func testV1CatalogHasNoStructuralProblems() {
        XCTAssertEqual(catalog.problems, [])
    }

    func testEveryFamilyHasExactlyOneFloorAndItIsFirstAndNeedsNoEquipment() {
        for family in catalog.families {
            XCTAssertEqual(family.rungs.filter(\.isFloor).count, 1, "\(family.id)")
            XCTAssertEqual(family.rungs.first?.isFloor, true, "\(family.id)")
            XCTAssertEqual(family.floor?.requiredEquipment, [], "\(family.id)")
        }
    }

    func testV1FamiliesAreTheNineAgreedLadders() {
        XCTAssertEqual(catalog.families.map(\.id),
                       [.push, .squat, .row, .overhead, .hinge, .glute, .lunge, .neck, .core])
    }

    /// Freezes every approved ladder: order, exercise, modifiers, dose kind and range, and equipment.
    func testV1LaddersMatchTheApprovedTable() {
        let expected: [MovementFamilyID: [String]] = [
            .push: ["push.wall_push_up.shallow wall_push_up [reducedRange] reps 1-8 []",
                    "push.wall_push_up wall_push_up [] reps 1-12 []",
                    "push.incline_push_up incline_push_up [] reps 1-12 []",
                    "push.push_up push_up [] reps 1-15 []"],
            .squat: ["squat.sit_to_stand.partial sit_to_stand [reducedRange] reps 1-8 []",
                     "squat.sit_to_stand sit_to_stand [] reps 1-12 []",
                     "squat.air_squat air_squat [] reps 1-20 []"],
            .row: ["row.scapular_squeeze.seated scapular_squeeze [] reps 1-12 []",
                   "row.dumbbell_row dumbbell_row [] reps 1-12 [dumbbells]"],
            .overhead: ["overhead.wall_slide.partial wall_slide [reducedRange,supported] reps 1-8 []",
                        "overhead.wall_slide wall_slide [supported] reps 1-12 []",
                        "overhead.shoulder_press shoulder_press [] reps 1-12 [dumbbells]"],
            .hinge: ["hinge.hip_hinge.supported_shallow hip_hinge [reducedRange,supported] reps 1-8 []",
                     "hinge.hip_hinge hip_hinge [] reps 1-12 []",
                     "hinge.stiff_leg_deadlift stiff_leg_deadlift [] reps 1-12 [dumbbells]"],
            .glute: ["glute.glute_squeeze glute_squeeze [] seconds 5-30 []",
                     "glute.glute_bridge glute_bridge [] reps 1-15 []"],
            .lunge: ["lunge.weight_shift.supported weight_shift [supported] reps 1-10 []",
                     "lunge.weight_shift weight_shift [] reps 1-12 []",
                     "lunge.rear_lunge rear_lunge [] reps 1-10 [dumbbells]"],
            .neck: ["neck.chin_tuck chin_tuck [] reps 1-12 []"],
            .core: ["core.abdominal_brace abdominal_brace [] seconds 5-45 []"]
        ]
        for family in catalog.families {
            let actual = family.rungs.map { rung in
                "\(rung.id) \(rung.exerciseID) [\(rung.modifiers.map(\.rawValue).joined(separator: ","))] "
                    + "\(rung.doseRange.kind.rawValue) \(rung.doseRange.lower)-\(rung.doseRange.upper) "
                    + "[\(rung.requiredEquipment.map(\.rawValue).joined(separator: ","))]"
            }
            XCTAssertEqual(actual, expected[family.id], "\(family.id)")
        }
    }

    func testPushLadderRunsShallowWallToWallToInclineToPushUp() {
        XCTAssertEqual(catalog.family(.push)?.rungs.map(\.id.rawValue), [
            "push.wall_push_up.shallow", "push.wall_push_up", "push.incline_push_up", "push.push_up"
        ])
        XCTAssertEqual(catalog.rung(VariantID(rawValue: "push.wall_push_up.shallow"))?.modifiers, [.reducedRange])
    }

    func testTraversalMovesOneAvailableRungAtATime() {
        let wall = VariantID(rawValue: "push.wall_push_up")
        XCTAssertEqual(catalog.harder(than: wall, availability: everything)?.id.rawValue, "push.incline_push_up")
        XCTAssertEqual(catalog.easier(than: wall, availability: everything)?.id.rawValue, "push.wall_push_up.shallow")
        XCTAssertNil(catalog.easier(than: VariantID(rawValue: "push.wall_push_up.shallow"), availability: everything))
        XCTAssertNil(catalog.harder(than: VariantID(rawValue: "push.push_up"), availability: everything))
    }

    func testTraversalSkipsRungsTheAppHasNotBuilt() {
        var availability = everything
        availability.builtExerciseIDs.remove("incline_push_up")
        XCTAssertEqual(catalog.harder(than: VariantID(rawValue: "push.wall_push_up"), availability: availability)?.id.rawValue,
                       "push.push_up")
        XCTAssertEqual(catalog.easier(than: VariantID(rawValue: "push.push_up"), availability: availability)?.id.rawValue,
                       "push.wall_push_up")
    }

    func testDumbbellRungsNeedDumbbells() {
        var availability = everything
        availability.equipment = []
        XCTAssertNil(catalog.harder(than: VariantID(rawValue: "row.scapular_squeeze.seated"), availability: availability))
        XCTAssertEqual(catalog.harder(than: VariantID(rawValue: "hinge.hip_hinge"), availability: everything)?.id.rawValue,
                       "hinge.stiff_leg_deadlift")
        XCTAssertNil(catalog.harder(than: VariantID(rawValue: "hinge.hip_hinge"), availability: availability))
    }

    func testTraversalReturnsNothingWhileTheFloorIsMissing() {
        var availability = Availability(builtExerciseIDs: ["incline_push_up", "push_up"])
        XCTAssertNil(catalog.easier(than: VariantID(rawValue: "push.push_up"), availability: availability))
        XCTAssertNil(catalog.harder(than: VariantID(rawValue: "push.incline_push_up"), availability: availability))

        availability.builtExerciseIDs.insert("wall_push_up")
        XCTAssertEqual(catalog.easier(than: VariantID(rawValue: "push.push_up"), availability: availability)?.id.rawValue,
                       "push.incline_push_up")
        XCTAssertEqual(catalog.harder(than: VariantID(rawValue: "push.incline_push_up"), availability: availability)?.id.rawValue,
                       "push.push_up")
    }

    func testFloorPrescriptionIsTheFloorAtItsMinimumDose() {
        XCTAssertEqual(catalog.floorPrescription(of: .push, availability: everything),
                       RungDose(variant: VariantID(rawValue: "push.wall_push_up.shallow"), dose: .reps(1)))
        XCTAssertEqual(catalog.floorPrescription(of: .core, availability: everything),
                       RungDose(variant: VariantID(rawValue: "core.abdominal_brace"), dose: .seconds(5)))
    }

    func testFamilyWithoutItsFloorCannotBeOffered() {
        let today = Availability(builtExerciseIDs: ["push_up", "air_squat", "dumbbell_row"], equipment: [.dumbbells])
        XCTAssertNil(catalog.floor(of: .push, availability: today))
        XCTAssertEqual(catalog.offerableFamilies(availability: today), [])
        var withWall = today
        withWall.builtExerciseIDs.insert("wall_push_up")
        XCTAssertEqual(catalog.offerableFamilies(availability: withWall), [.push])
    }

    func testProblemsReportEveryStructuralDefect() {
        let rung = { (id: String, floor: Bool, equipment: [TrainingEquipment]) in
            ProgressionRung(id: VariantID(rawValue: id), exerciseID: "x", doseRange: .reps(1...5),
                            requiredEquipment: equipment, isFloor: floor)
        }
        let cases: [(String, [MovementFamily], [ProgressionCatalogProblem])] = [
            ("empty family", [MovementFamily(id: .push, debugName: "Push", rungs: [])], [.emptyFamily(.push)]),
            ("two floors", [MovementFamily(id: .push, debugName: "Push",
                                           rungs: [rung("push.a", true, []), rung("push.b", true, [])])],
             [.floorCount(.push, 2)]),
            ("floor needs equipment", [MovementFamily(id: .push, debugName: "Push",
                                                      rungs: [rung("push.a", true, [.dumbbells])])],
             [.floorNeedsEquipment(.push)]),
            ("duplicate family", [MovementFamily(id: .push, debugName: "Push", rungs: [rung("push.a", true, [])]),
                                  MovementFamily(id: .push, debugName: "Push", rungs: [rung("push.b", true, [])])],
             [.duplicateFamily(.push)]),
            ("duplicate variant", [MovementFamily(id: .push, debugName: "Push",
                                                  rungs: [rung("push.a", true, []), rung("push.a", false, [])])],
             [.duplicateVariant(VariantID(rawValue: "push.a"))])
        ]
        for (name, families, problems) in cases {
            XCTAssertEqual(ProgressionCatalog(version: "test", families: families).problems, problems, name)
        }
    }

    func testProblemsCatchAMissingOrMisplacedFloor() {
        let rung = { (id: String, floor: Bool) in
            ProgressionRung(id: VariantID(rawValue: id), exerciseID: "x", doseRange: .reps(1...5), isFloor: floor)
        }
        let broken = ProgressionCatalog(version: "test", families: [
            MovementFamily(id: .push, debugName: "Push", rungs: [rung("push.a", false), rung("push.b", true)]),
            MovementFamily(id: .squat, debugName: "Squat", rungs: [rung("squat.a", false)]),
            MovementFamily(id: .neck, debugName: "Neck", rungs: [rung("push.c", true)])
        ])
        XCTAssertEqual(broken.problems, [
            .floorNotFirst(.push), .floorCount(.squat, 0), .variantOutsideFamily(VariantID(rawValue: "push.c"), .neck)
        ])
    }

    func testDoseRangeClampsAndStepsWithinBounds() {
        let holds = DoseRange.seconds(5...30)
        XCTAssertEqual(holds.increased(.seconds(5)), .seconds(10))
        XCTAssertEqual(holds.increased(.seconds(28)), .seconds(30))
        XCTAssertNil(holds.increased(.seconds(30)))
        XCTAssertEqual(holds.clamped(.reps(3)), .seconds(5))
        XCTAssertEqual(DoseRange.reps(1...8).clamped(.reps(12)), .reps(8))
        XCTAssertEqual(Dose.reps(0), .reps(1))
    }

    func testDecodingRejectsInvalidDosesAndRanges() {
        let invalidDoses = [
            #"{"kind":"reps","amount":0}"#,
            #"{"kind":"reps","amount":-3}"#
        ]
        for json in invalidDoses {
            XCTAssertThrowsError(try JSONDecoder().decode(Dose.self, from: Data(json.utf8)), json)
        }
        let invalidRanges = [
            #"{"kind":"seconds","lower":5,"upper":30,"step":0}"#,
            #"{"kind":"seconds","lower":5,"upper":30,"step":-5}"#,
            #"{"kind":"reps","lower":8,"upper":3,"step":1}"#,
            #"{"kind":"reps","lower":0,"upper":3,"step":1}"#
        ]
        for json in invalidRanges {
            XCTAssertThrowsError(try JSONDecoder().decode(DoseRange.self, from: Data(json.utf8)), json)
        }
        XCTAssertEqual(try JSONDecoder().decode(Dose.self, from: Data(#"{"kind":"seconds","amount":20}"#.utf8)),
                       .seconds(20))
    }

    func testSteppingSaturatesAtTheTopInsteadOfOverflowing() {
        let huge = DoseRange(kind: .seconds, lower: 1, upper: Int.max, step: 5)
        XCTAssertEqual(huge.increased(.seconds(Int.max - 1)), .seconds(Int.max))
        XCTAssertNil(huge.increased(.seconds(Int.max)))
    }

    func testDecodedRungsAreNormalizedLikeConstructedOnes() throws {
        let json = #"{"id":"row.x","exerciseID":"x","modifiers":["supported","reducedRange","supported"],"#
            + #""doseRange":{"kind":"reps","lower":1,"upper":5,"step":1},"#
            + #""requiredEquipment":["dumbbells","band","dumbbells"],"isFloor":false}"#
        let rung = try JSONDecoder().decode(ProgressionRung.self, from: Data(json.utf8))
        XCTAssertEqual(rung.modifiers, [.reducedRange, .supported])
        XCTAssertEqual(rung.requiredEquipment, [.band, .dumbbells])
        XCTAssertEqual(rung, ProgressionRung(id: VariantID(rawValue: "row.x"), exerciseID: "x",
                                             modifiers: [.reducedRange, .supported], doseRange: .reps(1...5),
                                             requiredEquipment: [.dumbbells, .band]))
    }

    func testCatalogRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(catalog)
        XCTAssertEqual(try JSONDecoder().decode(ProgressionCatalog.self, from: data), catalog)
    }

    func testAvailabilityEncodesSortedForStableExports() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Availability(builtExerciseIDs: ["b", "a"], equipment: [.dumbbells, .band]))
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"builtExerciseIDs":["a","b"],"equipment":["band","dumbbells"]}"#)
    }
}
