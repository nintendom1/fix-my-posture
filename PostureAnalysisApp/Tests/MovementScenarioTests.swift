import CoreGraphics
import Foundation
import XCTest
@testable import PostureAnalysisApp

/// Movement Lab schema, temporal influence, and synthetic Air Squat generation tests.
final class MovementScenarioTests: XCTestCase {
    private let createdAt = "2026-11-07T12:00:00Z"

    func testPlanRoundTripsVersionedRawValueSchema() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt, author: .developer)
        XCTAssertTrue(plan.validate().isEmpty)
        XCTAssertEqual(Set(plan.scenarios.map(\.id)), Set([
            "canonical", "shallow-depth", "slightly-shallow", "knees-caving", "asymmetric-hip-drop",
            "fast-tempo", "slow-pause", "knee-dropout", "low-ankle-confidence", "mid-set-gap",
            "too-close-framing", "raw-impossible-limb"
        ]))

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(MovementPlan.self, from: data)
        XCTAssertEqual(decoded, plan)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        let scenarios = try XCTUnwrap(object["scenarios"] as? [[String: Any]])
        let canonical = try XCTUnwrap(scenarios.first { $0["id"] as? String == "canonical" })
        XCTAssertEqual(canonical["exercise"] as? String, "air_squat")
        XCTAssertNil(canonical["exercise"] as? [String: Any])

        let shallow = try XCTUnwrap(scenarios.first { $0["id"] as? String == "shallow-depth" })
        let mutations = try XCTUnwrap(shallow["mutations"] as? [[String: Any]])
        XCTAssertEqual(mutations.first?["kind"] as? String, "depthScale")
        XCTAssertEqual(canonical["seed"] as? String, "133")
    }

    func testSeedUsesLosslessDecimalStringForUInt64Values() throws {
        let basePlan = MovementPresets.airSquat(createdAt: createdAt)
        let template = try XCTUnwrap(basePlan.scenarios.first { $0.id == "canonical" })
        for seed in [UInt64(9_007_199_254_740_993), UInt64.max] {
            var scenario = template
            scenario.seed = seed
            let plan = planWith([scenario])
            let data = try JSONEncoder().encode(plan)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let scenarios = try XCTUnwrap(object["scenarios"] as? [[String: Any]])
            let encodedScenario = try XCTUnwrap(scenarios.first)
            XCTAssertEqual(encodedScenario["seed"] as? String, String(seed))
            XCTAssertNil(encodedScenario["seed"] as? NSNumber)
            XCTAssertEqual(try JSONDecoder().decode(MovementPlan.self, from: data), plan)
        }

        var malformedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(basePlan)) as? [String: Any])
        let scenarios = try XCTUnwrap(malformedObject["scenarios"] as? [[String: Any]])
        malformedObject["scenarios"] = scenarios.map { scenario in
            var changed = scenario
            changed["seed"] = "18446744073709551616"
            return changed
        }
        let malformedData = try JSONSerialization.data(withJSONObject: malformedObject)
        XCTAssertThrowsError(try JSONDecoder().decode(MovementPlan.self, from: malformedData)) { error in
            XCTAssertEqual(error as? MovementScenarioSchemaError,
                           .invalidSeedRepresentation("18446744073709551616"))
        }
    }

    func testPlanIDsUseTheSafeArtifactIdentifierAllowlist() throws {
        let base = MovementPresets.airSquat(createdAt: createdAt)
        for invalidID in ["", "../outside", "/absolute", "has/slash", "UPPER", "é", String(repeating: "a", count: 65)] {
            var plan = base
            plan.id = invalidID
            XCTAssertTrue(plan.validate().contains { $0.path == "id" }, "\(invalidID.debugDescription)")
        }
        var valid = base
        valid.id = String(repeating: "a", count: 64)
        XCTAssertFalse(valid.validate().contains { $0.path == "id" })
    }

    func testAllAssertionCasesRoundTrip() throws {
        let basePlan = MovementPresets.airSquat(createdAt: createdAt)
        var scenario = try XCTUnwrap(basePlan.scenarios.first { $0.id == "canonical" })
        scenario.assertions = [
            .repCount(equals: nil, min: 2, max: 5),
            .rejection(reasonContains: "partialEnd", countMin: 1),
            .formSignal(id: "squat.knees_in", present: true),
            .framing(state: "reliable", reached: false),
            .spokenCue(textContains: "stand all the way up", present: true)
        ]
        let plan = planWith([scenario])
        XCTAssertTrue(plan.validate().isEmpty)
        let decoded = try JSONDecoder().decode(MovementPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded, plan)
    }

    func testJointArraysRoundTripRegardlessOfInputOrder() throws {
        let basePlan = MovementPresets.airSquat(createdAt: createdAt)
        var scenario = try XCTUnwrap(basePlan.scenarios.first { $0.id == "canonical" })
        scenario.mutations = [.dropout(joints: ["rightKnee", "leftKnee"], from: 3, to: 4)]
        let plan = planWith([scenario])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        var scenarios = try XCTUnwrap(object["scenarios"] as? [[String: Any]])
        guard var encodedScenario = scenarios.first else {
            return XCTFail("Expected the encoded plan to contain its scenario.")
        }
        var mutations = try XCTUnwrap(encodedScenario["mutations"] as? [[String: Any]])
        guard var mutation = mutations.first else {
            return XCTFail("Expected the encoded scenario to contain its dropout mutation.")
        }
        // Inject the noncanonical order after encoding, since the encoder correctly sorts joint arrays.
        mutation["joints"] = ["rightKnee", "leftKnee"]
        mutations = [mutation] + Array(mutations.dropFirst())
        encodedScenario["mutations"] = mutations
        scenarios = [encodedScenario] + Array(scenarios.dropFirst())
        object["scenarios"] = scenarios
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MovementPlan.self, from: data)
        XCTAssertEqual(decoded, plan, "Decoding should normalize unordered joint names to the canonical plan value.")
        guard case .dropout(let jointNames, _, _) = try XCTUnwrap(decoded.scenarios.first).mutations.first else {
            return XCTFail("Expected a dropout mutation.")
        }
        XCTAssertEqual(jointNames, ["leftKnee", "rightKnee"])
    }

    func testInclusiveMutationBoundariesAreValid() throws {
        let basePlan = MovementPresets.airSquat(createdAt: createdAt)
        var scenario = try XCTUnwrap(basePlan.scenarios.first { $0.id == "canonical" })
        let tempoMutations: [MovementMutation] = [
            .tempo(scale: 0.3, reps: [1]), .tempo(scale: 2, reps: [5])
        ]
        let tempoClock = try XCTUnwrap(MovementScenario.timelineDurations(reps: scenario.reps,
                                                                           exercise: scenario.exercise,
                                                                           mutations: tempoMutations))
        let prePauseEnd = tempoClock.prePause
        let pauses: [MovementMutation] = [
            .pause(at: 0, duration: 0), .pause(at: 0, duration: 10),
            .pause(at: prePauseEnd, duration: 10)
        ]
        let outputEnd = try XCTUnwrap(MovementScenario.timelineDurations(
            reps: scenario.reps, exercise: scenario.exercise, mutations: tempoMutations + pauses
        )).output
        scenario.mutations = [
            .jointOffset(joints: ["leftKnee"], dx: 0.5, dy: -0.5, peak: 0, rise: 0, fall: 10, strength: 0),
            .jointOffset(joints: ["rightKnee"], dx: 0.5, dy: -0.5, peak: 11, rise: 10, fall: 0, strength: 1),
            .jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: outputEnd, rise: 0, fall: 0, strength: 1),
            .depthScale(scale: 0.3, reps: [1]),
            .depthScale(scale: 2, reps: [5]),
            .asymmetry(side: .left, amount: -0.5),
            .asymmetry(side: .right, amount: 0.5),
        ] + tempoMutations + pauses + [
            .frameGap(at: 0, duration: 0),
            .frameGap(at: outputEnd - 10, duration: 10),
            .dropout(joints: ["leftKnee"], from: 0, to: 10),
            .dropout(joints: ["rightKnee"], from: outputEnd - 10, to: outputEnd),
            .confidence(joints: ["leftAnkle"], from: 0, to: 10, value: 0),
            .confidence(joints: ["rightAnkle"], from: outputEnd - 10, to: outputEnd, value: 1),
            .framing(scale: 0.3, offsetX: -0.5, offsetY: 0.5),
            .framing(scale: 2, offsetX: 0.5, offsetY: -0.5)
        ]
        XCTAssertTrue(scenario.validate().isEmpty, scenario.validate().map(\.message).joined(separator: ", "))
    }

    func testDecoderRejectsUnknownVersionAndMutationKindWithTypedErrors() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let data = try JSONEncoder().encode(plan)
        var versionObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        versionObject["schemaVersion"] = 99
        let unknownVersion = try JSONSerialization.data(withJSONObject: versionObject)
        XCTAssertThrowsError(try JSONDecoder().decode(MovementPlan.self, from: unknownVersion)) { error in
            XCTAssertEqual(error as? MovementScenarioSchemaError, .unknownSchemaVersion(99))
        }

        var mutationObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let scenarios = try XCTUnwrap(mutationObject["scenarios"] as? [[String: Any]])
        mutationObject["scenarios"] = scenarios.map { scenario in
            guard scenario["id"] as? String == "shallow-depth" else { return scenario }
            var changed = scenario
            var mutations = changed["mutations"] as? [[String: Any]] ?? []
            mutations = mutations.map { mutation in
                var changedMutation = mutation
                changedMutation["kind"] = "teleport"
                return changedMutation
            }
            changed["mutations"] = mutations
            return changed
        }
        let unknownKind = try JSONSerialization.data(withJSONObject: mutationObject)
        XCTAssertThrowsError(try JSONDecoder().decode(MovementPlan.self, from: unknownKind)) { error in
            XCTAssertEqual(error as? MovementScenarioSchemaError, .unknownMutationKind("teleport"))
        }
    }

    func testDecodingRejectsOutOfBoundsValuesAndValidationCollectsProblems() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        var scenario = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        scenario.mutations = [
            .jointOffset(joints: ["leftKnee"], dx: 0.5001, dy: 0, peak: 2, rise: 0.2, fall: 0.2, strength: 1),
            .confidence(joints: ["inventedJoint"], from: -1, to: 21, value: 1.1),
            .framing(scale: 2.1, offsetX: 0.6, offsetY: 0)
        ]
        let invalid = planWith([scenario])
        let issues = invalid.validate()
        XCTAssertGreaterThanOrEqual(issues.count, 7)
        XCTAssertTrue(issues.contains { $0.path.hasSuffix(".dx") })
        XCTAssertTrue(issues.contains { $0.message.contains("unknown LandmarkType") })
        XCTAssertTrue(issues.contains { $0.path.hasSuffix(".from") })
        XCTAssertTrue(issues.contains { $0.path.hasSuffix(".to") })
        XCTAssertTrue(issues.contains { $0.path.hasSuffix(".value") })
        XCTAssertTrue(issues.contains { $0.path.hasSuffix(".scale") })
        XCTAssertTrue(issues.contains { $0.path.hasSuffix(".offsetX") })

        let data = try JSONEncoder().encode(invalid)
        XCTAssertThrowsError(try JSONDecoder().decode(MovementPlan.self, from: data)) { error in
            guard let schemaError = error as? MovementScenarioSchemaError else {
                return XCTFail("Expected a typed schema error.")
            }
            guard case .invalidPlan(let decodedIssues) = schemaError else {
                return XCTFail("Expected the schema decoder to return validation problems.")
            }
            XCTAssertEqual(decodedIssues, issues)
        }
    }

    func testAllNumericMutationBoundsRejectValuesOutsideBothSides() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let canonical = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        let clock = try XCTUnwrap(MovementScenario.timelineDurations(reps: canonical.reps,
                                                                      exercise: canonical.exercise,
                                                                      mutations: []))
        let duration = clock.output
        let pauseClock = clock.prePause
        let invalidCases: [(MovementMutation, String)] = [
            (.jointOffset(joints: ["leftKnee"], dx: -0.5001, dy: 0, peak: 2, rise: 0.2, fall: 0.2, strength: 1), ".dx"),
            (.jointOffset(joints: ["leftKnee"], dx: 0.5001, dy: 0, peak: 2, rise: 0.2, fall: 0.2, strength: 1), ".dx"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: -0.5001, peak: 2, rise: 0.2, fall: 0.2, strength: 1), ".dy"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0.5001, peak: 2, rise: 0.2, fall: 0.2, strength: 1), ".dy"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: -0.01, rise: 0.2, fall: 0.2, strength: 1), ".peak"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: duration + 0.01, rise: 0, fall: 0, strength: 1), ".peak"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: 2, rise: -0.01, fall: 0.2, strength: 1), ".rise"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: 11, rise: 10.01, fall: 0.2, strength: 1), ".rise"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: 2, rise: 0.2, fall: -0.01, strength: 1), ".fall"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: 2, rise: 0.2, fall: 10.01, strength: 1), ".fall"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: 2, rise: 0.2, fall: 0.2, strength: -0.01), ".strength"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: 2, rise: 0.2, fall: 0.2, strength: 1.01), ".strength"),
            (.jointOffset(joints: ["leftKnee"], dx: .nan, dy: 0, peak: 2, rise: 0, fall: 0, strength: 1), ".dx"),
            (.jointOffset(joints: ["leftKnee"], dx: 0, dy: .infinity, peak: 2, rise: 0, fall: 0, strength: 1), ".dy"),
            (.depthScale(scale: 0.299, reps: nil), ".scale"), (.depthScale(scale: 2.001, reps: nil), ".scale"),
            (.depthScale(scale: 1, reps: []), ".reps"),
            (.depthScale(scale: 1, reps: [0]), ".reps"),
            (.depthScale(scale: 1, reps: [6]), ".reps"),
            (.depthScale(scale: 1, reps: [1, 1]), ".reps"),
            (.tempo(scale: 0.299, reps: nil), ".scale"), (.tempo(scale: 2.001, reps: nil), ".scale"),
            (.tempo(scale: 1, reps: []), ".reps"),
            (.tempo(scale: 1, reps: [0]), ".reps"),
            (.tempo(scale: 1, reps: [6]), ".reps"),
            (.tempo(scale: 1, reps: [2, 2]), ".reps"),
            (.asymmetry(side: .left, amount: -0.5001), ".amount"), (.asymmetry(side: .right, amount: 0.5001), ".amount"),
            (.pause(at: -0.01, duration: 1), ".at"), (.pause(at: pauseClock + 0.01, duration: 1), ".at"),
            (.pause(at: 2, duration: -0.01), ".duration"), (.pause(at: 2, duration: 10.01), ".duration"),
            (.frameGap(at: -0.01, duration: 1), ".at"), (.frameGap(at: duration + 0.01, duration: 0.1), ".at"),
            (.frameGap(at: duration - 0.1, duration: 0.2), ".duration"),
            (.frameGap(at: 2, duration: -0.01), ".duration"), (.frameGap(at: 2, duration: 10.01), ".duration"),
            (.dropout(joints: ["leftKnee"], from: -0.01, to: 1), ".from"),
            (.dropout(joints: ["leftKnee"], from: duration - 1, to: duration + 0.01), ".to"),
            (.dropout(joints: ["leftKnee"], from: 0, to: 10.01), ".to"),
            (.dropout(joints: ["leftKnee"], from: duration + 0.01, to: duration + 0.02), ".from"),
            (.dropout(joints: ["leftKnee"], from: 0, to: -0.01), ".to"),
            (.dropout(joints: ["leftKnee"], from: 4, to: 3), ".to"),
            (.confidence(joints: ["leftAnkle"], from: -0.01, to: 1, value: 0.5), ".from"),
            (.confidence(joints: ["leftAnkle"], from: duration - 1, to: duration + 0.01, value: 0.5), ".to"),
            (.confidence(joints: ["leftAnkle"], from: 0, to: 10.01, value: 0.5), ".to"),
            (.confidence(joints: ["leftAnkle"], from: duration + 0.01, to: duration + 0.02, value: 0.5), ".from"),
            (.confidence(joints: ["leftAnkle"], from: 0, to: -0.01, value: 0.5), ".to"),
            (.confidence(joints: ["leftAnkle"], from: 4, to: 3, value: 0.5), ".to"),
            (.confidence(joints: ["leftAnkle"], from: .nan, to: 1, value: 0.5), ".from"),
            (.confidence(joints: ["leftAnkle"], from: 0, to: 1, value: -.infinity), ".value"),
            (.confidence(joints: [], from: 0, to: 1, value: 0.5), ".joints"),
            (.confidence(joints: ["madeUpJoint"], from: 0, to: 1, value: 0.5), ".joints"),
            (.dropout(joints: ["leftKnee", "leftKnee"], from: 0, to: 1), ".joints"),
            (.framing(scale: 0.299, offsetX: 0, offsetY: 0), ".scale"),
            (.framing(scale: 2.001, offsetX: 0, offsetY: 0), ".scale"),
            (.framing(scale: 1, offsetX: -0.5001, offsetY: 0), ".offsetX"),
            (.framing(scale: 1, offsetX: 0.5001, offsetY: 0), ".offsetX"),
            (.framing(scale: 1, offsetX: 0, offsetY: -0.5001), ".offsetY"),
            (.framing(scale: 1, offsetX: 0, offsetY: 0.5001), ".offsetY")
        ]

        for (mutation, expectedSuffix) in invalidCases {
            var changed = canonical
            changed.mutations = [mutation]
            let issues = changed.validate()
            XCTAssertTrue(issues.contains { $0.path.hasSuffix(expectedSuffix) },
                          "\(mutation.kind) should report \(expectedSuffix), got \(issues.map(\.path))")
        }

        let outsideClockCases: [(MovementMutation, String, String)] = [
            (.dropout(joints: ["leftKnee"], from: duration + 0.01, to: duration + 0.02), ".from", "inside the sequence clock"),
            (.dropout(joints: ["leftKnee"], from: 0, to: -0.01), ".to", "inside the sequence clock"),
            (.confidence(joints: ["leftAnkle"], from: duration + 0.01, to: duration + 0.02, value: 0.5), ".from", "inside the sequence clock"),
            (.confidence(joints: ["leftAnkle"], from: 0, to: -0.01, value: 0.5), ".to", "inside the sequence clock")
        ]
        for (mutation, field, message) in outsideClockCases {
            var changed = canonical
            changed.mutations = [mutation]
            XCTAssertTrue(changed.validate().contains { $0.path.hasSuffix(field) && $0.message.contains(message) },
                          "Expected \(field) to report its sequence-clock bound for \(mutation.kind).")
        }

        var overlongRise = canonical
        overlongRise.mutations = [.jointOffset(joints: ["leftKnee"], dx: 0, dy: 0, peak: 11,
                                                rise: 10.01, fall: 0.2, strength: 1)]
        XCTAssertTrue(overlongRise.validate().contains {
            $0.path.hasSuffix(".rise") && $0.message.contains("must be between 0.0 and 10.0")
        }, "An in-sequence rise should report the duration cap itself.")

        var excessiveReps = canonical
        excessiveReps.reps = Int.max
        XCTAssertTrue(excessiveReps.validate().contains { $0.path == "scenario.reps" })
        var zeroReps = canonical
        zeroReps.reps = 0
        XCTAssertTrue(zeroReps.validate().contains { $0.path == "scenario.reps" })
        var tooManyReps = canonical
        tooManyReps.reps = MovementScenario.maximumReps + 1
        XCTAssertTrue(tooManyReps.validate().contains { $0.path == "scenario.reps" })

        var excessiveDuration = canonical
        excessiveDuration.reps = 10
        excessiveDuration.mutations = [.tempo(scale: 2, reps: nil), .tempo(scale: 2, reps: nil)]
        XCTAssertTrue(excessiveDuration.validate().contains { $0.message.contains("120 seconds") })

        var exactMaximum = canonical
        exactMaximum.reps = 16
        exactMaximum.mutations = [.tempo(scale: 2, reps: nil), .pause(at: 0, duration: 0.1)]
        XCTAssertFalse(exactMaximum.validate().contains { $0.message.contains("120 seconds") })
        XCTAssertTrue(exactMaximum.validate().isEmpty)
    }

    func testCompositeTempoNearLimitValidatesAndMaterializesSafely() throws {
        let basePlan = MovementPresets.airSquat(createdAt: createdAt)
        var scenario = try XCTUnwrap(basePlan.scenarios.first { $0.id == "canonical" })
        scenario.reps = 1
        scenario.mutations = Array(repeating: MovementMutation.tempo(scale: 2, reps: nil), count: 5)
            + [.tempo(scale: 0.999, reps: [1])]
        let plan = planWith([scenario])

        let clock = try XCTUnwrap(MovementScenario.timelineDurations(reps: scenario.reps,
                                                                      exercise: scenario.exercise,
                                                                      mutations: scenario.mutations))
        XCTAssertEqual(clock.output, 119.7816, accuracy: 1e-10)
        XCTAssertTrue(scenario.validate().isEmpty)
        let materialized = MovementGenerator.materialize(plan: plan, scenario: scenario)
        XCTAssertTrue(materialized.isValid, materialized.invalidReasons.joined(separator: ", "))
        XCTAssertEqual(materialized.frames.count,
                       Int(ceil(clock.output * MovementGenerator.framesPerSecond)) + 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(materialized.frames.last?.elapsed), 120)

        var overflowing = scenario
        overflowing.mutations = Array(repeating: MovementMutation.tempo(scale: 2, reps: nil), count: 550)
            + Array(repeating: MovementMutation.tempo(scale: 2, reps: [1]), count: 550)
            + Array(repeating: MovementMutation.tempo(scale: 0.3, reps: nil), count: 1_000)
        XCTAssertTrue(overflowing.validate().contains {
            $0.message.contains("tempo-scaled sequence duration must remain finite and positive")
        })
        let rejected = MovementGenerator.materialize(plan: plan, scenario: overflowing)
        XCTAssertFalse(rejected.isValid)
        XCTAssertTrue(rejected.frames.isEmpty)
    }

    func testPlanLimitAndAllValidationIssuesAreReported() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let canonical = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        let acceptedScenarios = (0..<200).map { index -> MovementScenario in
            var scenario = canonical
            scenario.id = "scenario-\(index)"
            return scenario
        }
        var accepted = plan
        accepted.scenarios = acceptedScenarios
        XCTAssertTrue(accepted.validate().isEmpty)

        var excessScenarios = canonical
        excessScenarios.id = "extra"
        var oversized = plan
        oversized.scenarios = acceptedScenarios + [excessScenarios]
        let issues = oversized.validate()
        XCTAssertTrue(issues.contains { $0.path == "scenarios" && $0.message.contains("200") })
    }

    func testInfluenceCurveIsSmoothMonotoneBoundedAndSymmetric() {
        XCTAssertEqual(MovementInfluence.weight(at: 2, peak: 2, rise: 0.5, fall: 0.5), 1)
        XCTAssertEqual(MovementInfluence.weight(at: 1.5, peak: 2, rise: 0.5, fall: 0.5), 0)
        XCTAssertEqual(MovementInfluence.weight(at: 2.5, peak: 2, rise: 0.5, fall: 0.5), 0)
        XCTAssertEqual(MovementInfluence.weight(at: 1.49, peak: 2, rise: 0.5, fall: 0.5), 0)
        XCTAssertEqual(MovementInfluence.weight(at: 2.51, peak: 2, rise: 0.5, fall: 0.5), 0)

        let rising = (0...20).map { index in
            MovementInfluence.weight(at: 1.5 + Double(index) / 40, peak: 2, rise: 0.5, fall: 0.5)
        }
        let falling = (0...20).map { index in
            MovementInfluence.weight(at: 2 + Double(index) / 40, peak: 2, rise: 0.5, fall: 0.5)
        }
        for pair in zip(rising, rising.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0, pair.1)
        }
        for pair in zip(falling, falling.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0, pair.1)
        }
        for index in 0...20 {
            let offset = Double(index) / 40
            XCTAssertEqual(MovementInfluence.weight(at: 2 - offset, peak: 2, rise: 0.5, fall: 0.5),
                           MovementInfluence.weight(at: 2 + offset, peak: 2, rise: 0.5, fall: 0.5), accuracy: 1e-12)
        }
        XCTAssertEqual(MovementInfluence.weight(at: 1.625, peak: 2, rise: 0.5, fall: 0.5),
                       0.1464466094067262, accuracy: 1e-12)
        let epsilon = 0.00001
        let risingEdgeSlope = MovementInfluence.weight(at: 1.5 + epsilon, peak: 2, rise: 0.5, fall: 0.5) / epsilon
        let peakLeftSlope = (1 - MovementInfluence.weight(at: 2 - epsilon, peak: 2, rise: 0.5, fall: 0.5)) / epsilon
        let peakRightSlope = (1 - MovementInfluence.weight(at: 2 + epsilon, peak: 2, rise: 0.5, fall: 0.5)) / epsilon
        let fallingEdgeSlope = MovementInfluence.weight(at: 2.5 - epsilon, peak: 2, rise: 0.5, fall: 0.5) / epsilon
        XCTAssertLessThan(risingEdgeSlope, 0.001)
        XCTAssertLessThan(peakLeftSlope, 0.001)
        XCTAssertLessThan(peakRightSlope, 0.001)
        XCTAssertLessThan(fallingEdgeSlope, 0.001)
        XCTAssertEqual(MovementInfluence.weight(at: 2, peak: 2, rise: 0, fall: 0), 1)
        XCTAssertEqual(MovementInfluence.weight(at: 1.99, peak: 2, rise: 0, fall: 0), 0)
        XCTAssertEqual(MovementInfluence.weight(at: 2.01, peak: 2, rise: 0, fall: 0), 0)
        XCTAssertEqual(MovementInfluence.weight(at: 1.99, peak: 2, rise: 0, fall: 0.5), 0)
        XCTAssertGreaterThan(MovementInfluence.weight(at: 2.25, peak: 2, rise: 0, fall: 0.5), 0)
        XCTAssertGreaterThan(MovementInfluence.weight(at: 1.75, peak: 2, rise: 0.5, fall: 0), 0)
        XCTAssertEqual(MovementInfluence.weight(at: 2.01, peak: 2, rise: 0.5, fall: 0), 0)
        XCTAssertEqual(MovementInfluence.weight(at: 2, peak: 2, rise: -1, fall: 1), 0)
    }

    func testGeneratorIsDeterministicAndSeedChangesOnlyFrameJitter() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let canonical = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        let first = MovementGenerator.materialize(plan: plan, scenario: canonical)
        let repeated = MovementGenerator.materialize(plan: plan, scenario: canonical)
        XCTAssertTrue(first.isValid, first.invalidReasons.joined(separator: ", "))
        XCTAssertEqual(first.recordingLines, repeated.recordingLines)

        var otherSeed = canonical
        otherSeed.seed &+= 1
        let changed = MovementGenerator.materialize(plan: plan, scenario: otherSeed)
        XCTAssertTrue(changed.isValid, changed.invalidReasons.joined(separator: ", "))
        XCTAssertEqual(first.recordingLines.count, changed.recordingLines.count)
        var changedJointRecords = 0
        for (leftLine, rightLine) in zip(first.recordingLines, changed.recordingLines) {
            let left = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(leftLine.utf8)) as? [String: Any])
            let right = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rightLine.utf8)) as? [String: Any])
            if left["k"] as? String == "f" {
                XCTAssertEqual(left["t"] as? Double, right["t"] as? Double)
                XCTAssertEqual(left["ts"] as? Double, right["ts"] as? Double)
                let leftJoints = try XCTUnwrap(left["j"] as? [Any])
                let rightJoints = try XCTUnwrap(right["j"] as? [Any])
                if String(describing: leftJoints) != String(describing: rightJoints) { changedJointRecords += 1 }
                var leftWithoutJoints = left
                var rightWithoutJoints = right
                leftWithoutJoints.removeValue(forKey: "j")
                rightWithoutJoints.removeValue(forKey: "j")
                XCTAssertEqual(try JSONSerialization.data(withJSONObject: leftWithoutJoints, options: [.sortedKeys]),
                               try JSONSerialization.data(withJSONObject: rightWithoutJoints, options: [.sortedKeys]))
            } else {
                XCTAssertEqual(try JSONSerialization.data(withJSONObject: left, options: [.sortedKeys]),
                               try JSONSerialization.data(withJSONObject: right, options: [.sortedKeys]))
            }
        }
        XCTAssertGreaterThan(changedJointRecords, 0)
    }

    func testCanonicalRevisionDistinguishesInheritedAndExplicitZeroTorsoPitch() throws {
        let exercise = try XCTUnwrap(ExerciseCatalog.all.first { $0.id == .airSquat })
        let angles = ArmAngles(upperArmElevation: 0, forearmElevation: 0)
        let inheritedKeyframe = ArmKeyframe(angles: angles, moveDuration: 0, holdDuration: 1, stepIndex: 0,
                                            shape: FigureShape(torsoPitch: nil))
        let explicitZeroKeyframe = ArmKeyframe(angles: angles, moveDuration: 0, holdDuration: 1, stepIndex: 0,
                                               shape: FigureShape(torsoPitch: 0))
        let inheritedMotion = ArmMotion(keyframes: [inheritedKeyframe], torsoPitch: 20)
        let explicitMotion = ArmMotion(keyframes: [explicitZeroKeyframe], torsoPitch: 20)

        XCTAssertEqual(inheritedMotion.sample(of: inheritedKeyframe).shape.torsoPitch, 20)
        XCTAssertEqual(explicitMotion.sample(of: explicitZeroKeyframe).shape.torsoPitch, 0)

        XCTAssertNotEqual(MovementCanonicalRevision.value(for: exercise.id, motion: inheritedMotion),
                          MovementCanonicalRevision.value(for: exercise.id, motion: explicitMotion))
    }

    func testConstraintDiagnosticsUseStableLandmarkOrder() {
        let joints: Set<LandmarkType> = [.rightKnee, .leftKnee]
        XCTAssertEqual(MovementGenerator.orderedLandmarks(in: joints),
                       [.leftKnee, .rightKnee])
    }

    func testConstrainedGeneratorPreservesBoneLengthsAndPlantedAnkles() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let canonical = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        let materialized = MovementGenerator.materialize(plan: plan, scenario: canonical)
        XCTAssertTrue(materialized.isValid, materialized.invalidReasons.joined(separator: ", "))
        let firstFrame = try XCTUnwrap(materialized.frames.first?.frame)
        let expectedLandmarks = Set(firstFrame.pose.landmarks.keys)
        for sample in materialized.frames {
            XCTAssertEqual(Set(sample.referenceFrame.pose.landmarks.keys), expectedLandmarks)
            XCTAssertEqual(Set(sample.frame.pose.landmarks.keys), expectedLandmarks)
            for joint in expectedLandmarks {
                _ = try XCTUnwrap(sample.referenceFrame.pose[joint], "Missing guide \(joint.rawValue) at \(sample.elapsed)")
                _ = try XCTUnwrap(sample.frame.pose[joint], "Missing output \(joint.rawValue) at \(sample.elapsed)")
            }
            for (first, second) in BodyPose.connections {
                guard let referenceFirst = sample.referenceFrame.pose[first]?.imageLocation,
                      let referenceSecond = sample.referenceFrame.pose[second]?.imageLocation else { continue }
                let actualFirst = try XCTUnwrap(sample.frame.pose[first]?.imageLocation)
                let actualSecond = try XCTUnwrap(sample.frame.pose[second]?.imageLocation)
                let expectedLength = ArmGeometry.distance(referenceFirst, referenceSecond)
                guard expectedLength > 0.0001 else { continue }
                let actualLength = ArmGeometry.distance(actualFirst, actualSecond)
                XCTAssertLessThanOrEqual(abs(actualLength - expectedLength) / expectedLength, 0.03,
                                         "\(first.rawValue)–\(second.rawValue) at \(sample.elapsed)")
            }
            for ankle in [LandmarkType.leftAnkle, .rightAnkle] {
                let planted = try XCTUnwrap(firstFrame.pose[ankle]?.imageLocation)
                let current = try XCTUnwrap(sample.frame.pose[ankle]?.imageLocation)
                XCTAssertLessThanOrEqual(ArmGeometry.distance(planted, current), 0.01)
            }
        }
    }

    func testRawModeKeepsImpossibleLandmarkOffsetAndConstrainedModeMarksItInvalid() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let rawScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "raw-impossible-limb" })
        let raw = MovementGenerator.materialize(plan: plan, scenario: rawScenario)
        XCTAssertTrue(raw.isValid, raw.invalidReasons.joined(separator: ", "))
        let peakFrame = try XCTUnwrap(raw.frames.first { abs($0.elapsed - 3.7) < 1e-9 })
        let referenceKnee = try XCTUnwrap(peakFrame.referenceFrame.pose[.leftKnee]?.imageLocation)
        let rawKnee = try XCTUnwrap(peakFrame.frame.pose[.leftKnee]?.imageLocation)
        XCTAssertGreaterThan(ArmGeometry.distance(referenceKnee, rawKnee),
                             0.3 * (try bodyHeight(in: peakFrame.referenceFrame.pose)))

        var constrainedScenario = rawScenario
        constrainedScenario.mode = .constrained
        let constrained = MovementGenerator.materialize(plan: plan, scenario: constrainedScenario)
        XCTAssertFalse(constrained.isValid)
        XCTAssertTrue(constrained.invalidReasons.contains { $0.contains("satisfy") })
        XCTAssertTrue(constrained.frames.isEmpty)
    }

    func testEveryAirSquatPresetMaterializes() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        XCTAssertEqual(plan.scenarios.count, 12)
        for scenario in plan.scenarios {
            let materialized = MovementGenerator.materialize(plan: plan, scenario: scenario)
            XCTAssertTrue(materialized.isValid,
                          "\(scenario.id): \(materialized.invalidReasons.joined(separator: ", "))")
            XCTAssertFalse(materialized.frames.isEmpty, "\(scenario.id) should contain camera frames")
            XCTAssertFalse(materialized.recordingLines.isEmpty, "\(scenario.id) should have recording lines")
        }
    }

    func testPresetEditsAndPauseUseTheGuideMaximumHipDropTimeline() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let exercise = try XCTUnwrap(ExerciseCatalog.all.first { $0.id == .airSquat })
        let motion = exercise.guide.motion
        let maximumDropTime = MovementGuideTimeline.maximumHipDropTime(in: motion)
        XCTAssertEqual(maximumDropTime, 2.2, accuracy: 1e-12)

        let knees = try XCTUnwrap(plan.scenarios.first { $0.id == "knees-caving" })
        let kneeMaterialization = MovementGenerator.materialize(plan: plan, scenario: knees)
        XCTAssertTrue(kneeMaterialization.isValid, kneeMaterialization.invalidReasons.joined(separator: ", "))
        let expectedPeaks = (1...5).map {
            MovementGuideTimeline.maximumHipDropOutputTime(rep: $0, motion: motion, mutations: [],
                                                           readyHold: MovementGenerator.readyHold)
        }
        let peakTimes = knees.mutations.compactMap { mutation -> TimeInterval? in
            guard case .jointOffset(_, _, _, let peak, _, _, _) = mutation else { return nil }
            return peak
        }
        XCTAssertEqual(peakTimes.count, 10)
        for peak in expectedPeaks {
            XCTAssertEqual(peakTimes.filter { abs($0 - peak) < 1e-9 }.count, 2)
            XCTAssertEqual(MovementInfluence.weight(at: peak, peak: peak, rise: 0.35, fall: 0.35), 1)
            let sample = try frame(at: peak, in: kneeMaterialization)
            let maximumGuide = ReadyPoseFixtures.demoFrame(exercise, motionTime: maximumDropTime, at: sample.frame.timestamp)
            for joint in [LandmarkType.leftHip, .rightHip] {
                XCTAssertEqual(sample.referenceFrame.pose[joint]?.imageLocation,
                               maximumGuide.pose[joint]?.imageLocation,
                               "Knee edit peak at \(peak) must coincide with maximum hip drop.")
            }
        }

        let slow = try XCTUnwrap(plan.scenarios.first { $0.id == "slow-pause" })
        let pauseMutation = try XCTUnwrap(slow.mutations.first { if case .pause = $0 { return true }; return false })
        guard case .pause(let pauseAt, let pauseDuration) = pauseMutation else {
            return XCTFail("Expected a pause mutation.")
        }
        let slowTempo = slow.mutations.filter { if case .tempo = $0 { return true }; return false }
        let slowBottom = MovementGuideTimeline.maximumHipDropOutputTime(rep: 1, motion: motion,
                                                                         mutations: slowTempo,
                                                                         readyHold: MovementGenerator.readyHold)
        XCTAssertEqual(pauseAt, slowBottom, accuracy: 1e-12)
        let slowMaterialization = MovementGenerator.materialize(plan: plan, scenario: slow)
        XCTAssertTrue(slowMaterialization.isValid, slowMaterialization.invalidReasons.joined(separator: ", "))
        let maximumGuide = ReadyPoseFixtures.demoFrame(exercise, motionTime: maximumDropTime, at: 0)
        let midpointSampleOffset = floor(pauseDuration * MovementGenerator.framesPerSecond / 2)
            / MovementGenerator.framesPerSecond
        for offset in [0.0, midpointSampleOffset, pauseDuration - 1.0 / MovementGenerator.framesPerSecond] {
            let sample = try frame(at: pauseAt + offset, in: slowMaterialization)
            for joint in [LandmarkType.leftHip, .rightHip] {
                XCTAssertEqual(sample.referenceFrame.pose[joint]?.imageLocation,
                               maximumGuide.pose[joint]?.imageLocation,
                               "Pause samples must hold the guide at maximum hip drop.")
            }
        }
    }

    func testConstrainedPresetEditsRemainVisibleAndKeepGeometry() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let motion = try XCTUnwrap(ExerciseCatalog.all.first { $0.id == .airSquat }).guide.motion
        let bottom = MovementGuideTimeline.maximumHipDropOutputTime(rep: 1, motion: motion, mutations: [],
                                                                     readyHold: MovementGenerator.readyHold)
        let kneeScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "knees-caving" })
        let knees = MovementGenerator.materialize(plan: plan, scenario: kneeScenario)
        XCTAssertTrue(knees.isValid, knees.invalidReasons.joined(separator: ", "))
        try assertConstrainedGeometry(knees)
        let kneePeak = try frame(at: bottom, in: knees)
        let bodyHeight = try XCTUnwrap(kneePeak.referenceFrame.pose.landmarks.values.map(\.imageLocation.y).max())
            - XCTUnwrap(kneePeak.referenceFrame.pose.landmarks.values.map(\.imageLocation.y).min())
        let leftDelta = try XCTUnwrap(kneePeak.frame.pose[.leftKnee]?.imageLocation).x
            - XCTUnwrap(kneePeak.referenceFrame.pose[.leftKnee]?.imageLocation).x
        let rightDelta = try XCTUnwrap(kneePeak.frame.pose[.rightKnee]?.imageLocation).x
            - XCTUnwrap(kneePeak.referenceFrame.pose[.rightKnee]?.imageLocation).x
        XCTAssertLessThan(Double(leftDelta), -Double(bodyHeight) * 0.02)
        XCTAssertGreaterThan(Double(rightDelta), Double(bodyHeight) * 0.02)

        let shallowScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "shallow-depth" })
        let shallow = MovementGenerator.materialize(plan: plan, scenario: shallowScenario)
        XCTAssertTrue(shallow.isValid, shallow.invalidReasons.joined(separator: ", "))
        try assertConstrainedGeometry(shallow)
        let shallowBottom = try frame(at: bottom, in: shallow)
        let shallowHipY = try XCTUnwrap(shallowBottom.frame.pose[.leftHip]?.imageLocation.y)
        let guideHipY = try XCTUnwrap(shallowBottom.referenceFrame.pose[.leftHip]?.imageLocation.y)
        XCTAssertLessThan(shallowHipY, guideHipY - bodyHeight * 0.01,
                          "Depth scaling must visibly reduce the guide's maximum drop.")

        let asymmetricScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "asymmetric-hip-drop" })
        let asymmetric = MovementGenerator.materialize(plan: plan, scenario: asymmetricScenario)
        XCTAssertTrue(asymmetric.isValid, asymmetric.invalidReasons.joined(separator: ", "))
        try assertConstrainedGeometry(asymmetric)
        let asymmetricBottom = try frame(at: bottom, in: asymmetric)
        let leftHipDelta = try XCTUnwrap(asymmetricBottom.frame.pose[.leftHip]?.imageLocation.y)
            - XCTUnwrap(asymmetricBottom.referenceFrame.pose[.leftHip]?.imageLocation.y)
        let rightHipDelta = try XCTUnwrap(asymmetricBottom.frame.pose[.rightHip]?.imageLocation.y)
            - XCTUnwrap(asymmetricBottom.referenceFrame.pose[.rightHip]?.imageLocation.y)
        XCTAssertGreaterThan(leftHipDelta - rightHipDelta, bodyHeight * 0.04)

        var plantedEdit = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        plantedEdit.mutations = [.jointOffset(joints: ["leftAnkle"], dx: 0.1, dy: 0, peak: bottom,
                                              rise: 0.2, fall: 0.2, strength: 1)]
        let rejected = MovementGenerator.materialize(plan: plan, scenario: plantedEdit)
        XCTAssertFalse(rejected.isValid)
        XCTAssertTrue(rejected.invalidReasons.contains { $0.contains("planted landmark leftAnkle") })
    }

    func testTempoPauseFramingAndRawOffsetsHaveIndependentExpectedEffects() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let canonicalScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        let canonical = MovementGenerator.materialize(plan: plan, scenario: canonicalScenario,
                                                       startingTimestamp: 100.25)
        XCTAssertTrue(canonical.isValid)
        for pair in zip(canonical.frames, canonical.frames.dropFirst()) {
            XCTAssertEqual(pair.1.elapsed - pair.0.elapsed, 1.0 / 30.0, accuracy: 1e-12)
            XCTAssertEqual(pair.0.frame.timestamp, 100.25 + pair.0.elapsed, accuracy: 1e-12)
        }

        let fastScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "fast-tempo" })
        let fast = MovementGenerator.materialize(plan: plan, scenario: fastScenario)
        XCTAssertTrue(fast.isValid, fast.invalidReasons.joined(separator: ", "))
        let fastDuration = 1.5 + 5 * 3.7 * 0.5
        XCTAssertEqual(try XCTUnwrap(fast.frames.last).elapsed,
                       ceil(fastDuration * MovementGenerator.framesPerSecond) / MovementGenerator.framesPerSecond,
                       accuracy: 1e-12)

        let slowScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "slow-pause" })
        let slow = MovementGenerator.materialize(plan: plan, scenario: slowScenario)
        XCTAssertTrue(slow.isValid, slow.invalidReasons.joined(separator: ", "))
        let slowDuration = 1.5 + 5 * 3.7 * 2 + 1.5
        XCTAssertEqual(try XCTUnwrap(slow.frames.last).elapsed,
                       ceil(slowDuration * MovementGenerator.framesPerSecond) / MovementGenerator.framesPerSecond,
                       accuracy: 1e-12)

        let closeScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "too-close-framing" })
        let close = MovementGenerator.materialize(plan: plan, scenario: closeScenario)
        XCTAssertTrue(close.isValid, close.invalidReasons.joined(separator: ", "))
        let closeFrame = try frame(at: 0, in: close)
        let baselineFrame = try XCTUnwrap(canonical.frames.first).frame
        let centerX = MovementGenerator.imageSize.width / 2
        let baselinePoint = try XCTUnwrap(baselineFrame.pose[.leftShoulder]?.imageLocation)
        let closePoint = try XCTUnwrap(closeFrame.frame.pose[.leftShoulder]?.imageLocation)
        XCTAssertEqual(closePoint.x, centerX + (baselinePoint.x - centerX) * 1.6, accuracy: 1.0)

        var raw = canonicalScenario
        raw.mode = .raw
        raw.seed = 502
        let rawBaseline = MovementGenerator.materialize(plan: plan, scenario: raw)
        XCTAssertTrue(rawBaseline.isValid)
        raw.mutations = [.jointOffset(joints: ["leftKnee"], dx: 0.04, dy: -0.02, peak: 3.7,
                                      rise: 0.4, fall: 0.4, strength: 0.5)]
        let rawOffset = MovementGenerator.materialize(plan: plan, scenario: raw)
        XCTAssertTrue(rawOffset.isValid)
        let peak = try frame(at: 3.7, in: rawOffset)
        let baselinePeak = try frame(at: 3.7, in: rawBaseline)
        let editedKnee = try XCTUnwrap(peak.frame.pose[.leftKnee]?.imageLocation)
        let uneditedKnee = try XCTUnwrap(baselinePeak.frame.pose[.leftKnee]?.imageLocation)
        let peakBodyHeight = try bodyHeight(in: peak.referenceFrame.pose)
        XCTAssertEqual(Double(editedKnee.x - uneditedKnee.x), 0.04 * peakBodyHeight * 0.5, accuracy: 1e-8)
        XCTAssertEqual(Double(editedKnee.y - uneditedKnee.y), -0.02 * peakBodyHeight * 0.5, accuracy: 1e-8)
        let unaffected = try XCTUnwrap(peak.frame.pose[.rightKnee]?.imageLocation)
        let baselineUnaffected = try XCTUnwrap(baselinePeak.frame.pose[.rightKnee]?.imageLocation)
        XCTAssertEqual(unaffected, baselineUnaffected)
        let outside = try frame(at: 3.3, in: rawOffset)
        let baselineOutside = try frame(at: 3.3, in: rawBaseline)
        XCTAssertEqual(outside.frame.pose[.leftKnee]?.imageLocation,
                       baselineOutside.frame.pose[.leftKnee]?.imageLocation)
        let halfInfluence = try frame(at: 3.5, in: rawOffset)
        let halfBaseline = try frame(at: 3.5, in: rawBaseline)
        let halfBodyHeight = try bodyHeight(in: halfInfluence.referenceFrame.pose)
        XCTAssertEqual(Double(try XCTUnwrap(halfInfluence.frame.pose[.leftKnee]?.imageLocation.x)
            - XCTUnwrap(halfBaseline.frame.pose[.leftKnee]?.imageLocation.x)), 0.04 * halfBodyHeight * 0.25,
                       accuracy: 1e-8)
    }

    func testDropoutConfidenceAndFrameGapAffectTheirRequestedIntervals() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let canonical = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        let baseline = MovementGenerator.materialize(plan: plan, scenario: canonical)

        let dropoutScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "knee-dropout" })
        let dropout = MovementGenerator.materialize(plan: plan, scenario: dropoutScenario)
        XCTAssertTrue(dropout.isValid, dropout.invalidReasons.joined(separator: ", "))
        let dropoutMutation = try XCTUnwrap(dropoutScenario.mutations.first {
            if case .dropout = $0 { return true }
            return false
        })
        guard case .dropout(_, let dropoutFrom, let dropoutTo) = dropoutMutation else {
            return XCTFail("Expected a dropout interval.")
        }
        let expectedDropoutIndices = Set(baseline.frames.filter {
            $0.elapsed >= dropoutFrom && $0.elapsed < dropoutTo
        }.map(frameIndex))
        let dropoutIndices = Set(dropout.frames.map(frameIndex))
        let baselineIndices = Set(baseline.frames.map(frameIndex))
        XCTAssertFalse(expectedDropoutIndices.isEmpty)
        XCTAssertEqual(dropoutIndices, baselineIndices)
        for (expected, actual) in zip(baseline.frames, dropout.frames) {
            XCTAssertEqual(expected.elapsed, actual.elapsed, accuracy: 1e-12)
            if actual.elapsed >= dropoutFrom && actual.elapsed < dropoutTo {
                XCTAssertNil(actual.frame.pose[.leftKnee])
                XCTAssertNil(actual.frame.pose[.rightKnee])
            } else {
                XCTAssertEqual(actual.frame.pose[.leftKnee]?.imageLocation, expected.frame.pose[.leftKnee]?.imageLocation)
                XCTAssertEqual(actual.frame.pose[.rightKnee]?.imageLocation, expected.frame.pose[.rightKnee]?.imageLocation)
            }
        }
        XCTAssertNotNil(dropout.frames.first?.frame.pose[.leftKnee])
        XCTAssertNotNil(dropout.frames.last?.frame.pose[.rightKnee])

        let confidenceScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "low-ankle-confidence" })
        let confidence = MovementGenerator.materialize(plan: plan, scenario: confidenceScenario)
        XCTAssertTrue(confidence.isValid, confidence.invalidReasons.joined(separator: ", "))
        let confidenceMutation = try XCTUnwrap(confidenceScenario.mutations.first {
            if case .confidence = $0 { return true }
            return false
        })
        guard case .confidence(_, let confidenceFrom, let confidenceTo, let setConfidence) = confidenceMutation else {
            return XCTFail("Expected a confidence interval.")
        }
        let expectedConfidenceIndices = Set(baseline.frames.filter {
            $0.elapsed >= confidenceFrom && $0.elapsed < confidenceTo
        }.map(frameIndex))
        let confidenceIndices = Set(confidence.frames.map(frameIndex))
        XCTAssertEqual(confidenceIndices, baselineIndices)
        XCTAssertFalse(expectedConfidenceIndices.isEmpty)
        for (expected, actual) in zip(baseline.frames, confidence.frames) {
            XCTAssertEqual(expected.elapsed, actual.elapsed, accuracy: 1e-12)
            let affected = actual.elapsed >= confidenceFrom && actual.elapsed < confidenceTo
            XCTAssertEqual(actual.frame.pose[.leftAnkle]?.confidence,
                           affected ? setConfidence : expected.frame.pose[.leftAnkle]?.confidence)
            XCTAssertEqual(actual.frame.pose[.rightAnkle]?.confidence,
                           affected ? setConfidence : expected.frame.pose[.rightAnkle]?.confidence)
            XCTAssertEqual(actual.frame.pose[.leftAnkle]?.imageLocation, expected.frame.pose[.leftAnkle]?.imageLocation)
        }

        let gapScenario = try XCTUnwrap(plan.scenarios.first { $0.id == "mid-set-gap" })
        let gap = MovementGenerator.materialize(plan: plan, scenario: gapScenario)
        XCTAssertTrue(gap.isValid, gap.invalidReasons.joined(separator: ", "))
        let gapMutation = try XCTUnwrap(gapScenario.mutations.first {
            if case .frameGap = $0 { return true }
            return false
        })
        guard case .frameGap(let gapAt, let gapDuration) = gapMutation else {
            return XCTFail("Expected a frame-gap interval.")
        }
        let expectedGapIndices = Set(baseline.frames.filter {
            $0.elapsed >= gapAt && $0.elapsed < gapAt + gapDuration
        }.map(frameIndex))
        XCTAssertEqual(expectedGapIndices.count, 15)
        XCTAssertEqual(baselineIndices.subtracting(Set(gap.frames.map(frameIndex))), expectedGapIndices)
        let gapPairs = Array(zip(gap.frames, gap.frames.dropFirst()))
        let longPairs = gapPairs.filter { $0.1.elapsed - $0.0.elapsed > 0.28 }
        XCTAssertEqual(longPairs.count, 1)
        for (previous, next) in gapPairs {
            let crossesGap = previous.elapsed < gapAt && next.elapsed >= gapAt + gapDuration
            let expectedStep = crossesGap
                ? gapDuration + 1.0 / MovementGenerator.framesPerSecond
                : 1.0 / MovementGenerator.framesPerSecond
            XCTAssertEqual(next.elapsed - previous.elapsed, expectedStep, accuracy: 1e-12)
        }
    }

    func testCanonicalPositionsMatchReadyPoseWithinTheJitterBudget() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let scenario = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        let materialized = MovementGenerator.materialize(plan: plan, scenario: scenario)
        XCTAssertTrue(materialized.isValid, materialized.invalidReasons.joined(separator: ", "))
        let exercise = try XCTUnwrap(ExerciseCatalog.all.first { $0.id == scenario.exercise })
        let bodyHeight = 1500.0
        for sample in materialized.frames {
            let motionTime = sample.elapsed < MovementGenerator.readyHold
                ? 0 : (sample.elapsed - MovementGenerator.readyHold).truncatingRemainder(dividingBy: exercise.guide.motion.duration)
            let ready = ReadyPoseFixtures.demoFrame(exercise, motionTime: motionTime, at: sample.frame.timestamp)
            XCTAssertEqual(sample.frame.pose.landmarks.count, ready.pose.landmarks.count)
            for (joint, referenceLandmark) in ready.pose.landmarks {
                let expected = referenceLandmark.imageLocation
                let actual = try XCTUnwrap(sample.frame.pose[joint]?.imageLocation)
                XCTAssertLessThanOrEqual(ArmGeometry.distance(expected, actual), bodyHeight * 0.002 + 0.5,
                                         "\(joint.rawValue) at \(sample.elapsed)")
            }
        }
    }

    func testMaterializedRecordingUsesTheExistingWorkoutSessionParser() throws {
        let plan = MovementPresets.airSquat(createdAt: createdAt)
        let scenario = try XCTUnwrap(plan.scenarios.first { $0.id == "canonical" })
        let materialized = MovementGenerator.materialize(plan: plan, scenario: scenario)
        XCTAssertTrue(materialized.isValid, materialized.invalidReasons.joined(separator: ", "))
        let text = "[\n" + materialized.recordingLines.joined(separator: ",\n") + "\n]"
        let recording = try WorkoutSessionFile(text: text)
        XCTAssertEqual(recording.header["schema"] as? String, "fmp.workout-session/1")
        XCTAssertEqual(recording.header["jointOrder"] as? [String], LandmarkType.allCases.map(\.rawValue))
        let frameRecords = recording.records.filter { $0.record["k"] as? String == "f" }
        XCTAssertEqual(frameRecords.count, materialized.frames.count)
        for record in frameRecords {
            XCTAssertEqual(record.record["p"] as? Bool, true)
            XCTAssertNotNil(record.record["t"] as? Double)
            XCTAssertNotNil(record.record["ts"] as? Double)
            let joints = try XCTUnwrap(record.record["j"] as? [Any])
            XCTAssertEqual(joints.count, LandmarkType.allCases.count)
            for landmark in joints where !(landmark is NSNull) {
                let values = try XCTUnwrap(landmark as? [Double])
                guard values.count == 3 else {
                    return XCTFail("Each serialized landmark tuple must contain x, y, and confidence.")
                }
                XCTAssertTrue((0...1080).contains(values[0]))
                XCTAssertTrue((0...1920).contains(values[1]))
                XCTAssertTrue((0...1).contains(values[2]))
            }
        }
        let pipes = recording.records.compactMap { $0.record["k"] as? String == "pipe" ? $0.record : nil }
        XCTAssertEqual(pipes.count, 5)
        XCTAssertTrue(pipes.contains { $0["control"] as? String == "exercise" && $0["exercise"] as? String == "air_squat" })
        XCTAssertTrue(pipes.contains { $0["control"] as? String == "sessionPhase" && $0["phase"] as? String == "ready" })
        XCTAssertTrue(pipes.contains { $0["control"] as? String == "sessionPhase" && $0["phase"] as? String == "exercising" })
        XCTAssertTrue(pipes.contains { $0["control"] as? String == "counting" && $0["counting"] as? Bool == true })
        XCTAssertTrue(pipes.contains { $0["control"] as? String == "counting" && $0["counting"] as? Bool == false })
        XCTAssertTrue(recording.records.contains { $0.record["k"] as? String == "end" })
    }

    private func frameIndex(_ sample: MovementMaterializedFrame) -> Int {
        Int((sample.elapsed * MovementGenerator.framesPerSecond).rounded())
    }

    private func frame(at elapsed: TimeInterval, in materialization: MovementMaterialization) throws -> MovementMaterializedFrame {
        try XCTUnwrap(materialization.frames.first { abs($0.elapsed - elapsed) < 1e-9 },
                      "Missing 30 fps sample at \(elapsed)")
    }

    private func bodyHeight(in pose: BodyPose) throws -> Double {
        let yCoordinates = pose.landmarks.values.map { Double($0.imageLocation.y) }
        let minimum = try XCTUnwrap(yCoordinates.min())
        let maximum = try XCTUnwrap(yCoordinates.max())
        return maximum - minimum
    }

    private func assertConstrainedGeometry(_ materialization: MovementMaterialization,
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let firstFrame = try XCTUnwrap(materialization.frames.first?.frame, file: file, line: line)
        let expectedLandmarks = Set(firstFrame.pose.landmarks.keys)
        for sample in materialization.frames {
            XCTAssertEqual(Set(sample.referenceFrame.pose.landmarks.keys), expectedLandmarks,
                           file: file, line: line)
            XCTAssertEqual(Set(sample.frame.pose.landmarks.keys), expectedLandmarks, file: file, line: line)
            for joint in expectedLandmarks {
                _ = try XCTUnwrap(sample.referenceFrame.pose[joint],
                                  "Missing guide landmark \(joint.rawValue) at \(sample.elapsed)",
                                  file: file, line: line)
                _ = try XCTUnwrap(sample.frame.pose[joint],
                                  "Missing output landmark \(joint.rawValue) at \(sample.elapsed)",
                                  file: file, line: line)
            }
            for (first, second) in BodyPose.connections {
                guard expectedLandmarks.contains(first), expectedLandmarks.contains(second) else { continue }
                let referenceFirst = try XCTUnwrap(sample.referenceFrame.pose[first]?.imageLocation,
                                                   file: file, line: line)
                let referenceSecond = try XCTUnwrap(sample.referenceFrame.pose[second]?.imageLocation,
                                                    file: file, line: line)
                let actualFirst = try XCTUnwrap(sample.frame.pose[first]?.imageLocation, file: file, line: line)
                let actualSecond = try XCTUnwrap(sample.frame.pose[second]?.imageLocation, file: file, line: line)
                let expectedLength = ArmGeometry.distance(referenceFirst, referenceSecond)
                guard expectedLength > 0.0001 else { continue }
                let actualLength = ArmGeometry.distance(actualFirst, actualSecond)
                XCTAssertLessThanOrEqual(abs(actualLength - expectedLength) / expectedLength, 0.03,
                                         "\(first.rawValue)–\(second.rawValue) at \(sample.elapsed)",
                                         file: file, line: line)
            }
            for ankle in [LandmarkType.leftAnkle, .rightAnkle] {
                let planted = try XCTUnwrap(firstFrame.pose[ankle]?.imageLocation, file: file, line: line)
                let current = try XCTUnwrap(sample.frame.pose[ankle]?.imageLocation, file: file, line: line)
                XCTAssertLessThanOrEqual(ArmGeometry.distance(planted, current), 0.01, file: file, line: line)
            }
        }
    }

    private func planWith(_ scenarios: [MovementScenario]) -> MovementPlan {
        MovementPlan(id: "test-plan", title: "Test plan", purpose: "Validation test plan.",
                     author: .developer, createdAt: createdAt, scenarios: scenarios)
    }
}
