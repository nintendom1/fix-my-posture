import XCTest
@testable import PostureAnalysisApp

final class SitToStandAnalyzerTests: XCTestCase {
    private let exercise = SitToStandExercise.definition()
    private let partialExercise = SitToStandExercise.definition(configuration: .partialRange)
    private var motion: ArmMotion { exercise.guide.motion }

    /// Standing shoulder-to-ankle height divided by the same figure's locked ruler.
    private static let standingSignal = 1.0

    /// (scale, thigh, shin) cases for the guide figure, each changing one thing.
    private static let proportions: [(CGFloat, CGFloat, CGFloat)] = [
        (1, 1, 1), (0.5, 1, 1), (2, 1, 1), (1, 0.85, 1), (1, 1.15, 1), (1, 1, 0.85), (1, 1, 1.15)
    ]

    // MARK: - Counting

    /// The instructed start is seated, and the analyzer has never seen anyone stand.
    func testStartingSeatedCountsEveryLoopAtAnyScaleAndProportions() {
        for (scale, thigh, shin) in Self.proportions {
            let player = Player(exercise, body: Body(scale: scale, thigh: thigh, shin: shin))
            player.play(motion, loops: 3)
            let label = "scale \(scale), thigh \(thigh), shin \(shin)"
            XCTAssertEqual(player.reps.count, 3, label)
            XCTAssertEqual(player.forms.count, 3, "Every attempt is judged once: \(label)")
            XCTAssertTrue(player.forms.allSatisfy { $0.flags.isEmpty }, "The demonstration raises no cues: \(player.forms)")
            for (form, rep) in zip(player.forms, player.reps) {
                XCTAssertLessThan(form.timestamp, rep, "A rep's form is reported before the rep: \(label)")
            }
        }
    }

    func testDeviceShapedBodyCountsQuickRepsWithSeatedKneesAtLowConfidence() throws {
        let bodies = [
            Body(scale: 0.85, thigh: 0.85, shin: 1.15, realistic: true, hipToAnkleSeatRatio: 0.70),
            Body(scale: 1.15, thigh: 1.15, shin: 0.85, realistic: true, hipToAnkleSeatRatio: 0.81)
        ]
        for body in bodies {
            let standing = body.joints(.standing, kneesIn: 0)
            let seated = body.joints(LegPose(hipDrop: 0.9), kneesIn: 0)
            let standShoulder = try XCTUnwrap(standing[.leftShoulder])
            let seatedShoulder = try XCTUnwrap(seated[.leftShoulder])
            let standAnkle = try XCTUnwrap(standing[.leftAnkle])
            let seatedAnkle = try XCTUnwrap(seated[.leftAnkle])
            let standHip = try XCTUnwrap(standing[.leftHip])
            let seatedHip = try XCTUnwrap(seated[.leftHip])
            let standingU = standAnkle.y - standShoulder.y
            let seatedU = seatedAnkle.y - seatedShoulder.y
            XCTAssertEqual(seatedU / standingU, 0.73, accuracy: 0.01)
            let standingHipHeight = standAnkle.y - standHip.y
            let seatedHipHeight = seatedAnkle.y - seatedHip.y
            let hipRatio = seatedHipHeight / standingHipHeight
            XCTAssertEqual(hipRatio, body.hipToAnkleSeatRatio ?? .nan, accuracy: 0.01)
            XCTAssertEqual(try XCTUnwrap(seated[.leftKnee]).y,
                           try XCTUnwrap(seated[.leftHip]).y, accuracy: 1)

            let player = Player(exercise, body: body)
            player.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
            for _ in 0..<3 {
                player.feed(.standing, count: 8, kneesIn: 12, kneeConfidence: 0.3)
                player.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
            }
            XCTAssertEqual(player.reps.count, 3, "The planted realistic shape counts at ±15% proportions")
            XCTAssertTrue(player.framingBecameReliable, "Required joints remain shoulders, hips, and ankles")
            XCTAssertFalse(player.forms.contains { $0.flags.contains(.sitToStandKnees) },
                           "Knees below 0.4 confidence cannot trigger the optional cue")
        }
    }

    func testDeviceShapedStandingStartAndLongSeatCountAfterTheFirstSit() {
        let player = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        player.stand()
        XCTAssertFalse(player.startHeld.contains(true), "A standing start is not a seated checkpoint")
        player.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
        player.feed(.standing, count: 8, kneeConfidence: 0.3)
        player.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
        XCTAssertEqual(player.reps.count, 1)

        player.feed(LegPose(hipDrop: 0.9), count: 45, kneeConfidence: 0.3)
        player.feed(.standing, count: 8, kneeConfidence: 0.3)
        player.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
        XCTAssertEqual(player.reps.count, 2, "A long seated hold keeps the standing ruler")
    }

    func testWalkingTowardCameraCannotEstablishAStandOrCount() {
        let player = Player(exercise, body: Body(realistic: true))
        player.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
        player.feed(LegPose(hipDrop: 0.9), count: 3, kneeConfidence: 0.3, approachingCamera: true)
        player.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
        XCTAssertEqual(player.reps.count, 0)
        XCTAssertFalse(player.endPositionWasReached, "The upper-body scale changed while both ankles moved")
    }

    func testRobustRulersIgnoreInitialAndPostReturnHighOutliersAcrossCleanReps() {
        let initial = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        initial.feed(.standing, count: 1, shoulderSignalRatio: 1.5, hipSignalRatio: 1.5)
        initial.feed(.standing, count: 12)
        initial.feed(seated, count: 8)
        initial.feed(.standing, count: 8)
        initial.feed(seated, count: 8)
        XCTAssertEqual(initial.reps.count, 1, "The initial ruler comes from a stable robust window")

        let returned = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        returned.stand()
        returned.feed(seated, count: 8)
        returned.feed(.standing, count: 1)
        returned.feed(.standing, count: 1, shoulderSignalRatio: 1.5, hipSignalRatio: 1.5)
        returned.feed(seated, count: 8)
        returned.feed(.standing, count: 8)
        returned.feed(seated, count: 8)
        returned.feed(.standing, count: 8)
        returned.feed(seated, count: 8)
        XCTAssertEqual(returned.reps.count, 2, "Clean reps after a single high frame still count without a gap")
    }

    func testBootstrapIgnoresOneLowStandingOutlierAndCountsAfterARealSeat() {
        let player = Player(exercise)
        player.feed(.standing, count: 10)
        player.feed(.standing, count: 1, shoulderSignalRatio: 0.5, hipSignalRatio: 0.5)
        player.feed(.standing, count: 8)
        XCTAssertFalse(player.startHeld.contains(true), "One low frame cannot set the standing-start checkpoint")
        XCTAssertEqual(player.reps.count, 0)
        player.feed(seated, count: 8)
        player.feed(.standing, count: 8)
        player.feed(seated, count: 8)
        XCTAssertEqual(player.reps.count, 1)
    }

    func testBootstrapDoesNotAcceptAGradualDescentWithoutAContinuousHold() {
        let player = Player(exercise)
        player.feed(.standing, count: 10)
        for step in 1...30 {
            let ratio = CGFloat(1 - Double(step) * 0.012)
            player.feed(.standing, shoulderSignalRatio: ratio, hipSignalRatio: ratio)
        }
        for step in 1...30 {
            let ratio = CGFloat(0.64 + Double(step) * 0.012)
            player.feed(.standing, shoulderSignalRatio: ratio, hipSignalRatio: ratio)
        }
        XCTAssertEqual(player.reps.count, 0, "A moving candidate never becomes a held seat")
        player.feed(seated, count: 8)
        player.feed(.standing, count: 8)
        player.feed(seated, count: 8)
        XCTAssertEqual(player.reps.count, 1, "A subsequent stable seat is accepted")
    }

    func testFixedHipsAndAnklesRejectATorsoOnlyBendAsASeat() {
        let player = Player(exercise)
        player.stand()
        player.feed(seated, count: 8)
        player.feed(.standing, count: 8)
        player.feed(.standing, count: 8, shoulderSignalRatio: 0.73, hipSignalRatio: 1.0)
        XCTAssertEqual(player.reps.count, 0, "Shoulder flexion without hip descent is not a seat")
        player.feed(.standing, count: 8)
        player.feed(.standing, count: 8, shoulderSignalRatio: 0.73, hipSignalRatio: 1.0)
        XCTAssertEqual(player.reps.count, 0)
    }

    func testRealisticHipRatiosHaveMarginAtBothEndsOfTheFullAndPartialLines() {
        for hipSeatRatio: CGFloat in [0.70, 0.755, 0.81] {
            let body = Body(realistic: true, hipToAnkleSeatRatio: hipSeatRatio)
            let standing = body.joints(.standing, kneesIn: 0)
            let fullSeat = body.joints(LegPose(hipDrop: 0.9), kneesIn: 0)
            let partialSeat = body.joints(LegPose(hipDrop: 0.61), kneesIn: 0)
            guard let standAnkle = standing[.leftAnkle], let standHip = standing[.leftHip],
                  let fullAnkle = fullSeat[.leftAnkle], let fullHip = fullSeat[.leftHip],
                  let partialAnkle = partialSeat[.leftAnkle], let partialHip = partialSeat[.leftHip] else {
                return XCTFail("Expected hip and ankle landmarks")
            }
            let standingHipHeight = standAnkle.y - standHip.y
            let fullRatio = (fullAnkle.y - fullHip.y) / standingHipHeight
            let partialRatio = (partialAnkle.y - partialHip.y) / standingHipHeight
            let fullMargin = 0.88 - Double(fullRatio)
            let partialMargin = 0.92 - Double(partialRatio)
            XCTAssertGreaterThanOrEqual(fullMargin, 0.069, "Full hip margin at seated ratio \(hipSeatRatio)")
            XCTAssertGreaterThanOrEqual(partialMargin, 0.048, "Partial hip margin at seated ratio \(hipSeatRatio)")
        }
    }

    func testShoulderOnlyPartialFluctuationCannotCompleteTheRequiredExcursion() {
        let player = Player(partialExercise)
        player.play(partialExercise.guide.motion, loops: 1)
        let startingCount = player.reps.count
        // Each phase lasts 1 s, so the minimum rep duration doesn't hide a missing excursion check.
        for _ in 0..<3 {
            player.feed(.standing, count: 10, shoulderSignalRatio: 0.85, hipSignalRatio: 0.80)
            player.feed(.standing, count: 10, shoulderSignalRatio: 0.91, hipSignalRatio: 1.0)
        }
        XCTAssertEqual(player.reps.count, startingCount, "The 0.06 shoulder swing is below the 0.08 excursion")
    }

    func testSettledRelocationClearsBothRulersAndCountsAtTheNewScaleWithoutAGap() {
        let player = Player(exercise)
        player.play(motion, loops: 1)
        XCTAssertEqual(player.reps.count, 1)
        player.feed(.standing, count: 8)
        player.body = Body(scale: 0.72, offset: CGPoint(x: 650, y: 115))
        player.feed(.standing, count: 18)
        player.play(motion, loops: 2)
        XCTAssertEqual(player.reps.count, 3, "The settled new position is bootstrapped without a tracking gap")
    }

    func testSingleTopSpikeDoesNotRestartControlledDescentTimerOrDelayForm() {
        let player = Player(exercise)
        player.stand()
        player.feed(seated, count: 8)
        player.feed(standingPose, count: 8)
        player.feed(midway, count: 4)
        player.feed(standingPose, count: 1)
        player.feed(midway, count: 1)
        player.feed(seated, count: 8)
        guard player.reps.count == 1, player.forms.count == 1,
              let form = player.forms.first, let rep = player.reps.first else {
            return XCTFail("Expected one completed rep and its form result")
        }
        XCTAssertFalse(form.flags.contains(.sitToStandControl), "The descent lasted longer than the cue limit")
        XCTAssertLessThan(form.timestamp, rep, "Form remains available before the rep completes")
    }

    func testLeaningForwardDoesNotCountAsStandingAndPartialSeatUsesItsOwnLine() {
        let leaning = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        leaning.stand()
        leaning.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
        leaning.feed(.standing, count: 2, kneeConfidence: 0.3, leaningForward: true)
        leaning.feed(LegPose(hipDrop: 0.9), count: 8, kneeConfidence: 0.3)
        XCTAssertEqual(leaning.reps.count, 0, "A forward lean does not reach the Stand line")

        let partial = Player(partialExercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        partial.stand()
        partial.feed(LegPose(hipDrop: 0.61), count: 8, kneeConfidence: 0.3)
        partial.feed(.standing, count: 8, kneeConfidence: 0.3)
        partial.feed(LegPose(hipDrop: 0.61), count: 8, kneeConfidence: 0.3)
        XCTAssertEqual(partial.reps.count, 1, "The higher-seat guide shape sits at about 0.82 of standing u")

        let full = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        full.stand()
        full.feed(LegPose(hipDrop: 0.61), count: 8, kneeConfidence: 0.3)
        full.feed(.standing, count: 8, kneeConfidence: 0.3)
        full.feed(LegPose(hipDrop: 0.61), count: 8, kneeConfidence: 0.3)
        XCTAssertEqual(full.reps.count, 0, "The full Seat line remains deeper than the higher seat")
    }

    func testGuideDemonstrationReadsTheDocumentedSignalValues() {
        // The first seat has no ruler yet. Later loops use the guide's shoulder-to-ankle ratio.
        for (definition, seated) in [(exercise, 0.74), (partialExercise, 0.82)] {
            let player = Player(definition)
            let guide = definition.guide.motion
            player.play(guide, loops: 2)
            let perLoop = Int((guide.duration * 10).rounded())
            XCTAssertTrue(player.signals.prefix(9).allSatisfy(\.isFinite))
            let secondLoop = player.signals.dropFirst(perLoop)
            XCTAssertEqual(secondLoop.min() ?? .nan, seated, accuracy: 0.01, definition.displayName)
            XCTAssertEqual(secondLoop.max() ?? .nan, Self.standingSignal, accuracy: 0.01, definition.displayName)
        }
    }

    func testPartialDemonstrationCountsItsOwnLoopAndAFullRepCountsForIt() throws {
        let partial = try XCTUnwrap(exercise.reducedRange?())
        XCTAssertEqual(partial.id, .sitToStand)
        for (scale, thigh, shin) in Self.proportions {
            let body = Body(scale: scale, thigh: thigh, shin: shin)
            let label = "scale \(scale), thigh \(thigh), shin \(shin)"

            let own = Player(partial, body: body)
            own.play(partial.guide.motion, loops: 3)
            XCTAssertEqual(own.reps.count, 3, "The partial demonstration counts for the partial variant: \(label)")
            XCTAssertTrue(own.forms.allSatisfy { $0.flags.isEmpty }, "\(own.forms)")

            let full = Player(partial, body: body)
            full.play(motion, loops: 3)
            XCTAssertEqual(full.reps.count, 3, "A full rep also counts for the partial variant: \(label)")

            let tooShallow = Player(exercise, body: body)
            tooShallow.play(partial.guide.motion, loops: 3)
            XCTAssertEqual(tooShallow.reps.count, 0, "The full variant needs the lower Seat line: \(label)")
        }
    }

    /// With the ruler already measured standing, so the custom depths are judged only by the Seat and Stand lines.
    func testSeatedAndStandingLinesCountOnBothSidesOfEachBoundary() {
        // (variant, seated u/R, standing u/R, reps in one loop)
        let cases: [(ExerciseDefinition, Double, Double, Int)] = [
            (exercise, 0.76, 1.0, 1), (exercise, 0.79, 1.0, 1),
            (exercise, 0.82, 1.0, 0),
            (exercise, 0.76, 0.91, 1), (exercise, 0.76, 0.88, 0),
            (partialExercise, 0.84, 1.0, 1), (partialExercise, 0.85, 1.0, 1),
            (partialExercise, 0.87, 1.0, 0)
        ]
        for (definition, seated, standing, expected) in cases {
            let player = Player(definition)
            player.stand()
            player.play(line(seated: seated, standing: standing), loops: 1)
            XCTAssertEqual(player.reps.count, expected, "\(definition.displayName): seated \(seated), standing \(standing)")
        }
    }

    func testEightRepsWithNearThresholdReturnsDoNotRatchetTheRuler() {
        // Standing only just past its line shortens the shoulder-to-ankle span on screen. Re-measuring would shrink the
        // ruler, so the seated d of 0.33 would read 0.38 and stop counting. The ruler is measured first so the
        // custom depths are judged only by the lines.
        let player = Player(exercise)
        player.stand()
        player.play(line(seated: 0.60, standing: 0.91), loops: 8)
        XCTAssertEqual(player.reps.count, 8)
        XCTAssertTrue(player.forms.allSatisfy { $0.flags.isEmpty }, "\(player.forms)")
    }

    func testLongSeatedHoldKeepsTheRulerLockedFromStanding() {
        // A seated upper body looks short. A ruler that followed the last second would shrink and read the seat as
        // standing.
        let player = Player(exercise)
        player.play(motion, loops: 1)
        XCTAssertEqual(player.reps.count, 1)
        player.feed(seated, count: 40)
        XCTAssertEqual(player.signals.last ?? .nan, 0.74, accuracy: 0.02)
        player.play(motion, loops: 1)
        XCTAssertEqual(player.reps.count, 2)
    }

    func testReacquiresAfterAGapWhenTheUserReturnsStandingAtANewScaleOrPlace() {
        for body in [Body(scale: 0.6, offset: CGPoint(x: 420, y: 330)), Body(scale: 1.5, offset: CGPoint(x: 150, y: 120))] {
            let player = Player(exercise)
            player.play(motion, loops: 1)
            XCTAssertEqual(player.reps.count, 1)

            player.gap(1.0)
            player.body = body
            player.stand()
            player.play(motion, loops: 2)
            XCTAssertEqual(player.reps.count, 3, "scale \(body.scale), offset \(body.offset)")
        }
    }

    /// A dropout while seated clears the ruler. The bootstrap measures the seat again, so the next rep still counts.
    func testSeatedReacquisitionAfterAGapCountsTheNextRepAtANewScaleOrPlace() {
        for definition in [exercise, partialExercise] {
            for body in [Body(scale: 0.6, offset: CGPoint(x: 420, y: 330)), Body(scale: 1.5, offset: CGPoint(x: 150, y: 120))] {
                let player = Player(definition)
                player.play(definition.guide.motion, loops: 1)
                XCTAssertEqual(player.reps.count, 1, definition.displayName)

                player.gap(1.0)
                player.body = body
                player.play(definition.guide.motion, loops: 2)
                XCTAssertEqual(player.reps.count, 3, "\(definition.displayName), scale \(body.scale), offset \(body.offset)")
            }
        }
    }

    func testAGapInTheMiddleOfARepDropsItAndReportsWhyWithoutCounting() {
        let player = Player(exercise)
        player.feed(seated, count: 5)
        player.feed(midway, count: 5)
        player.feed(standingPose, count: 5)
        player.gap(0.5)
        player.feed(midway, count: 5)
        player.feed(seated, count: 6)
        XCTAssertEqual(player.reps.count, 0, "Movement across a gap never counts")
        XCTAssertTrue(player.rejections.contains { reason in
            if case .trackingGap = reason.reason { return true }
            return false
        }, "\(player.rejections)")
    }

    func testFormIsReportedBeforeTheRepItBelongsToWithExactlyTheConfirmationSamples() {
        let player = Player(exercise)
        let samples = SitToStandConfiguration.standard.confirmationSamples
        player.stand()
        player.feed(seated, count: 5)
        player.feed(midway, count: 5)
        player.feed(standingPose, count: samples)
        player.feed(midway, count: 5)
        player.feed(seated, count: samples)
        guard player.reps.count == 1, player.forms.count == 1, let rep = player.reps.first, let form = player.forms.first else {
            return XCTFail("Expected one rep and one form, got \(player.reps) and \(player.forms)")
        }
        XCTAssertLessThan(form.timestamp, rep, "The last rep's cue must reach the set before the rep completes it")
        XCTAssertTrue(form.flags.isEmpty)
    }

    func testStartingStandingNeverInventsASeatedCheckpoint() {
        let standing = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        standing.feed(standingPose, count: 30)
        XCTAssertFalse(standing.startHeld.contains(true), "Standing is not the start position")
        XCTAssertEqual(standing.reps.count, 0)
        standing.play(motion, loops: 3)
        XCTAssertEqual(standing.reps.count, 3, "Sitting down after standing still counts every loop")

        let halfway = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        halfway.feed(midway, count: 30)
        XCTAssertFalse(halfway.startHeld.contains(true), "Halfway up is not the start position")
        XCTAssertEqual(halfway.reps.count, 0)
        halfway.feed(standingPose, count: 5)
        halfway.play(motion, loops: 2)
        XCTAssertEqual(halfway.reps.count, 2)
    }

    func testAStartingSeatThatMissesTheSeatLineAgainstTheLockedRulerDoesNotCount() {
        // This partial seat falls outside the full variant's locked Seat line.
        let player = Player(exercise)
        player.play(trip(from: LegPose(hipDrop: 0.50), to: seated), loops: 1)
        XCTAssertEqual(player.reps.count, 0, "The cycle began on a seat that wasn't low enough")
        player.play(motion, loops: 1)
        XCTAssertEqual(player.reps.count, 1, "The next cycle starts from the seat the last one ended on")
    }

    // MARK: - Coaching

    func testRisingWithoutStandingAsksToStandAllTheWayUp() {
        let player = Player(exercise)
        player.play(line(seated: 0.60, standing: 0.73), loops: 2)
        XCTAssertEqual(player.reps.count, 0)
        XCTAssertEqual(player.forms.count, 2, "\(player.forms); measurements \(player.signals); form \(player.formReadings)")
        XCTAssertTrue(player.forms.allSatisfy { $0.flags == [.sitToStandTall] }, "\(player.forms)")

        // A small shoulder rise is a lean, not a meaningful attempt.
        let lean = Player(exercise)
        lean.play(line(seated: 0.60, standing: 0.68), loops: 2)
        XCTAssertEqual(lean.reps.count, 0)
        XCTAssertTrue(lean.forms.isEmpty, "A rise under 0.12 of the ruler is leaning, not an attempt: \(lean.forms)")
    }

    func testPlopIntoTheSeatAsksToSitDownSlowly() {
        let plop = Player(exercise)
        plop.play(line(seated: 0.52, standing: Self.standingSignal, descent: 0.3), loops: 2)
        XCTAssertEqual(plop.reps.count, 2, "Form never affects counting")
        XCTAssertTrue(plop.forms.allSatisfy { $0.flags == [.sitToStandControl] }, "\(plop.forms)")

        // The guide's own 1.5 s descent takes 0.66 s from the standing line to the seat line.
        let slow = Player(exercise)
        slow.play(motion, loops: 2)
        XCTAssertFalse(slow.forms.contains { $0.flags.contains(.sitToStandControl) })
    }

    func testSitDownCueUsesDurationThresholdsForEachSeatLine() {
        for (definition, seated, quickDescent, controlledDescent) in [
            (exercise, 0.76, 0.5, 1.0), (partialExercise, 0.84, 0.3, 1.2)
        ] {
            let quick = Player(definition)
            quick.stand()
            quick.play(line(seated: seated, standing: 1.0, descent: quickDescent), loops: 1)
            XCTAssertTrue(quick.forms.contains { $0.flags.contains(.sitToStandControl) },
                          "The faster descent should cue for \(definition.displayName): \(quick.forms)")

            let controlled = Player(definition)
            controlled.stand()
            controlled.play(line(seated: seated, standing: 1.0, descent: controlledDescent), loops: 1)
            XCTAssertFalse(controlled.forms.contains { $0.flags.contains(.sitToStandControl) },
                           "The slower descent should be clear for \(definition.displayName): \(controlled.forms)")
        }
    }

    func testKneesFallingTowardEachOtherWhileRisingAsksToKeepThemApart() {
        let caving = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        caving.play(motion, loops: 1, kneesIn: { (1.0..<2.2).contains($0) ? 12 : 0 })
        XCTAssertEqual(caving.reps.count, 1, "Form never affects counting")
        XCTAssertEqual(caving.forms.map(\.flags), [[.sitToStandKnees]], "caving while rising")

        let steady = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        steady.play(motion, loops: 1, kneesIn: { (1.0..<2.2).contains($0) ? 6 : 0 })
        XCTAssertEqual(steady.reps.count, 1)
        XCTAssertEqual(steady.forms.map(\.flags), [[]], "The 78% knee gap is not a cave")

        // Knees that come together only after standing aren't "while rising".
        let later = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        later.play(motion, loops: 1, kneesIn: { $0 >= 2.3 ? 12 : 0 })
        XCTAssertEqual(later.forms.map(\.flags), [[]], "Knee movement after standing is outside the rise")
    }

    /// The streak starts on the first sample away from the seat, before the attempt is confirmed.
    func testTwoCloseKneeSamplesAtTheStartOfARiseAskToKeepThemApart() {
        let player = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        player.feed(seated, count: 5)
        player.feed(midway, count: 2, kneesIn: 12)
        player.feed(midway, count: 3)
        player.feed(standingPose, count: 5)
        player.feed(midway, count: 5)
        player.feed(seated, count: 3)
        XCTAssertEqual(player.reps.count, 1, "Form never affects counting")
        XCTAssertEqual(player.forms.map(\.flags), [[.sitToStandKnees]])

        // One close sample, then wide again, isn't two in a row.
        let single = Player(exercise, body: Body(realistic: true, hipToAnkleSeatRatio: 0.76))
        single.feed(seated, count: 5)
        single.feed(midway, count: 1, kneesIn: 12)
        single.feed(midway, count: 4)
        single.feed(standingPose, count: 5)
        single.feed(midway, count: 5)
        single.feed(seated, count: 3)
        XCTAssertEqual(single.reps.count, 1)
        XCTAssertEqual(single.forms.map(\.flags), [[]])
    }

    func testEstimatedAnklesSkipFormButStillCountTheRep() {
        let caving: (TimeInterval) -> CGFloat = { (1.0..<2.2).contains($0) ? 12 : 0 }
        let observed = Player(exercise)
        observed.play(motion, loops: 1, kneesIn: caving)
        XCTAssertEqual(observed.reps.count, 1)
        XCTAssertEqual(observed.forms.map(\.flags), [[.sitToStandKnees]])

        let estimated = Player(exercise)
        estimated.play(motion, loops: 1, kneesIn: caving, estimatedDuring: 1.0...2.2)
        XCTAssertEqual(estimated.reps.count, 1, "An estimated joint never stops counting")
        XCTAssertTrue(estimated.forms.isEmpty, "No form is judged from an estimated joint: \(estimated.forms)")
        XCTAssertTrue(estimated.signals.allSatisfy { $0.isFinite })
    }

    func testSeatedKneesAtPointTwoFiveKeepFramingAndCountingButCannotTriggerTheKneeCue() {
        let lowConfidence = Player(exercise)
        lowConfidence.play(motion, loops: 1,
                           kneesIn: { (1.0..<2.2).contains($0) ? 12 : 0 }, kneeConfidence: 0.25)
        XCTAssertEqual(lowConfidence.reps.count, 1)
        XCTAssertTrue(lowConfidence.framingBecameReliable,
                      "Knees are optional; hips, ankles, and shoulders keep framing reliable.")
        XCTAssertFalse(lowConfidence.forms.contains { $0.flags.contains(.sitToStandKnees) },
                       "A low-confidence knee must be silent for the form cue.")

        let visibleKnees = Player(exercise)
        visibleKnees.play(motion, loops: 1, kneesIn: { (1.0..<2.2).contains($0) ? 12 : 0 })
        XCTAssertTrue(visibleKnees.forms.contains { $0.flags.contains(.sitToStandKnees) },
                      "The knee cue still works when both knees are visible.")
    }

    // MARK: - Definition

    func testDefinitionDescribesTheChairSetupAndItsPartialVariant() throws {
        XCTAssertEqual(exercise.id, .sitToStand)
        XCTAssertEqual(exercise.id.rawValue, "sit_to_stand")
        XCTAssertEqual(exercise.displayName, "Sit-to-Stand")
        XCTAssertEqual(exercise.presentation.shortName, "Sit-to-Stand")
        XCTAssertEqual(exercise.spokenName, "sit to stand")
        XCTAssertEqual(exercise.sets, 2)
        XCTAssertEqual(exercise.targetReps, 5...10)
        XCTAssertEqual(exercise.autoCompleteReps, 10)
        XCTAssertEqual(exercise.restSeconds, 60)
        XCTAssertEqual(exercise.cameraView, .front)
        XCTAssertFalse(exercise.startsByHolding)
        XCTAssertEqual(exercise.equipment, .bodyweight)
        XCTAssertEqual(exercise.presentation.filterGroups, AirSquatExercise.definition().presentation.filterGroups)
        XCTAssertEqual(exercise.requiredJoints,
                       [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle])
        XCTAssertEqual(exercise.plantedJoints, [.leftAnkle, .rightAnkle])
        XCTAssertEqual(exercise.guide.startPositionInstruction, "Sit near the front of the chair")
        XCTAssertEqual(exercise.guide.steps.count, 4)
        XCTAssertEqual(exercise.coachingCues.map(\.id), [.sitToStandTall, .sitToStandControl, .sitToStandKnees])
        XCTAssertEqual(exercise.coachingCues.map(\.text), ["Stand all the way up.", "Sit down slowly.", "Keep your knees apart."])
        XCTAssertEqual(exercise.reminders.map(\.text), ["Feet flat on the floor.", "Lean forward to stand."])
        XCTAssertEqual(ExercisePhotography.placeholders[.sitToStand], "figure.seated.side")
        XCTAssertNil(ExercisePhotography.photograph(for: .sitToStand))
        XCTAssertTrue(motion.chair)
        XCTAssertTrue(motion.animatesLegs)
        XCTAssertGreaterThan(motion.startLegs.hipDrop, 0, "The guide starts seated")
        XCTAssertEqual(motion.topLegs, .standing, "The other end of the rep is standing")

        let partial = try XCTUnwrap(exercise.reducedRange?())
        XCTAssertEqual(partial.displayName, "Partial Sit-to-Stand")
        XCTAssertEqual(partial.spokenName, "partial sit to stand")
        XCTAssertTrue(partial.guide.steps.contains { $0.detail.lowercased().contains("use a higher seat, or lower only until you touch it") })
        XCTAssertLessThan(partial.guide.motion.startLegs.hipDrop, motion.startLegs.hipDrop, "A shallower seated pose")
        XCTAssertNil(partial.reducedRange)
    }

    func testVoiceAliasesSelectTheSitToStandWithoutStealingTheAirSquat() {
        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        XCTAssertEqual(exercise.voiceAliases, ["sit to stand", "sit-to-stand", "sit to stands", "chair stand",
                                               "chair stands", "chair squat", "chair squats"])
        for alias in exercise.voiceAliases {
            XCTAssertEqual(parser.parse(alias)?.command, .selectExercise(.sitToStand), alias)
            XCTAssertEqual(parser.parse("switch to \(alias)")?.command, .selectExercise(.sitToStand), alias)
        }
        XCTAssertEqual(parser.parse("squats")?.command, .selectExercise(.airSquat))
        XCTAssertEqual(parser.parse("air squat")?.command, .selectExercise(.airSquat))
    }

    // MARK: - Chair figure and ghost

    func testSeatedGhostUsesTheTorsoAndEstimatesKneesFromGuideProportions() throws {
        let containerSize = CGSize(width: 393, height: 852)
        let variant = try XCTUnwrap(ReadyPoseFixtures.variants(for: exercise).first { $0.name == "full" })
        let frame = ReadyPoseFixtures.frame(variant, at: 0)
        let overlay = WorkoutOverlayState(
            imageSize: frame.imageSize,
            joints: frame.pose.landmarks.mapValues { OverlayJoint(location: $0.normalizedLocation, isStale: false) },
            segments: [], endPositionSides: [], pose: frame.pose)
        var chairOverlay = overlay
        chairOverlay.joints[.leftKnee] = nil
        chairOverlay.joints[.rightKnee] = nil
        let sample = motion.startSample
        XCTAssertTrue(GhostCalibration.canFit(overlay: chairOverlay, metrics: nil, motion: motion,
                                              cameraView: .front, sample: sample),
                      "The seated ghost calibrates from shoulders, hips, and ankles without knees.")
        let figure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: chairOverlay, metrics: nil, motion: motion, cameraView: .front,
            containerSize: containerSize, sample: sample))

        func container(_ joint: LandmarkType) throws -> CGPoint {
            let landmark = try XCTUnwrap(overlay.joints[joint])
            return CoordinateConverter.normalizedToContainer(normalized: landmark.location, imageSize: overlay.imageSize,
                                                             containerSize: containerSize)
        }
        let guideShoulders = ArmGeometry.midpoint(
            try XCTUnwrap(ExerciseDemoFigureView.figureJoints[.leftShoulder]),
            try XCTUnwrap(ExerciseDemoFigureView.figureJoints[.rightShoulder]))
        let guideHips = ArmGeometry.midpoint(
            try XCTUnwrap(ExerciseDemoFigureView.figureJoints[.leftHip]),
            try XCTUnwrap(ExerciseDemoFigureView.figureJoints[.rightHip]))
        let userShoulders = ArmGeometry.midpoint(try container(.leftShoulder), try container(.rightShoulder))
        let userHips = ArmGeometry.midpoint(try container(.leftHip), try container(.rightHip))
        XCTAssertEqual(figure.bodyScale,
                       ArmGeometry.distance(userShoulders, userHips) / ArmGeometry.distance(guideShoulders, guideHips),
                       accuracy: 1e-6, "The knee-free chair figure sizes from the visible torso")

        let squat = AirSquatExercise.definition().guide.motion
        let squatFigure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: overlay, metrics: nil, motion: squat, cameraView: .front,
            containerSize: containerSize, sample: squat.startSample))
        XCTAssertGreaterThan(figure.bodyScale, squatFigure.bodyScale, "The squat's leg-length scale is the one a seated thigh shrinks")
        XCTAssertNil(squatFigure.seat)

        let seat = try XCTUnwrap(figure.seat)
        let hip = try XCTUnwrap(figure.joints[.leftHip])
        XCTAssertEqual(seat.from.y, seat.to.y, accuracy: 1e-9)
        XCTAssertGreaterThan(seat.from.y, hip.y, "The seat is under the hips")
        XCTAssertLessThan(seat.from.x, hip.x)
        XCTAssertGreaterThan(seat.to.x, hip.x)

        let ideal = WorkoutGhostGeometry.ideal(overlay: nil, motion: motion, cameraView: .front,
                                               containerSize: containerSize, sample: sample)
        XCTAssertNotNil(ideal.seat, "The ideal ghost shows the chair before anyone is in view")
        let blended = WorkoutGhostGeometry.blended(from: ideal, to: figure, progress: 1)
        XCTAssertEqual(blended.seat, figure.seat)
        XCTAssertEqual(Set(blended.joints.keys), Set(figure.joints.keys))
        XCTAssertNotNil(figure.joints[.leftKnee], "The missing knee is estimated from the guide's hip-to-ankle ratio")
        XCTAssertNil(AirSquatExercise.definition().guide.motion.chairSeat)
        XCTAssertNotNil(motion.chairSeat)
    }

    // MARK: - Helpers

    private var seated: LegPose { motion.startLegs }
    private var standingPose: LegPose { .standing }
    /// Between the Seat and Stand lines in standing shoulder-to-ankle lengths.
    private var midway: LegPose { legs(forSignal: 0.87) }

    /// Converts a standing-ruler reading into the guide's 292-point standing shoulder-to-ankle span.
    private func legs(forSignal signal: Double) -> LegPose {
        LegPose(hipDrop: max(0, (292 - CGFloat(signal * 292)) / 85))
    }

    /// Seated at `seated`, up to `standing`, and back, each given as `u/R` against a standing-locked ruler.
    private func line(seated: Double, standing: Double, descent: TimeInterval = 1.5) -> ArmMotion {
        let arms = ArmAngles(upperArmElevation: -85, forearmElevation: -85)
        return ArmMotion(keyframes: [
            ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0,
                        legs: legs(forSignal: seated)),
            ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0.4, stepIndex: 1,
                        legs: legs(forSignal: standing)),
            // The last loop settles on the seat, so its rep is confirmed before the frames stop.
            ArmKeyframe(angles: arms, moveDuration: descent, holdDuration: 0.5, stepIndex: 2,
                        legs: legs(forSignal: seated))
        ], holdsDumbbells: false, chair: true)
    }

    /// Up from one seat and back down to another.
    private func trip(from start: LegPose, to end: LegPose) -> ArmMotion {
        let arms = ArmAngles(upperArmElevation: -85, forearmElevation: -85)
        return ArmMotion(keyframes: [
            ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0, legs: start),
            ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0.4, stepIndex: 1, legs: .standing),
            ArmKeyframe(angles: arms, moveDuration: 1.5, holdDuration: 1.0, stepIndex: 2, legs: end)
        ], holdsDumbbells: false, chair: true)
    }

    /// The demo figure with optional size, place, and leg proportions.
    private struct Body {
        var scale: CGFloat = 1
        var offset = CGPoint(x: 300, y: 200)
        var thigh: CGFloat = 1
        var shin: CGFloat = 1
        var realistic = false
        var hipToAnkleSeatRatio: CGFloat?

        /// Joints in pixels for a figure sitting or standing at `legs`, knees pulled `kneesIn` guide units together.
        func joints(_ legs: LegPose, kneesIn: CGFloat, approachingCamera: Bool = false,
                    leaningForward: Bool = false, shoulderSignalRatio: CGFloat? = nil,
                    hipSignalRatio: CGFloat? = nil) -> [LandmarkType: CGPoint] {
            var standing = ExerciseDemoFigureView.figureJoints
            for side in BodySide.allCases {
                guard let hip = standing[side.hip], let knee = standing[side.knee], let ankle = standing[side.ankle] else { continue }
                let newKnee = CGPoint(x: hip.x + (knee.x - hip.x) * thigh, y: hip.y + (knee.y - hip.y) * thigh)
                standing[side.knee] = newKnee
                standing[side.ankle] = CGPoint(x: newKnee.x + (ankle.x - knee.x) * shin, y: newKnee.y + (ankle.y - knee.y) * shin)
            }
            var joints = standing
            if realistic {
                let progress = min(max(CGFloat(legs.hipDrop / 0.9), 0), 1)
                let ankleY = ((standing[.leftAnkle]?.y ?? 0) + (standing[.rightAnkle]?.y ?? 0)) / 2
                let shoulderY = ((standing[.leftShoulder]?.y ?? 0) + (standing[.rightShoulder]?.y ?? 0)) / 2
                let shoulderScale = 1 - 0.27 * progress
                let seatedShoulderY = ankleY - (ankleY - shoulderY) * shoulderScale
                let shoulderDrop = seatedShoulderY - shoulderY
                let shoulderCenterX = ((standing[.leftShoulder]?.x ?? 0) + (standing[.rightShoulder]?.x ?? 0)) / 2
                for side in BodySide.allCases {
                    if let shoulder = joints[side.shoulder] {
                        joints[side.shoulder] = CGPoint(
                            x: shoulderCenterX + (shoulder.x - shoulderCenterX) * shoulderScale,
                            y: seatedShoulderY + (leaningForward ? 50 : 0))
                    }
                    if let hip = joints[side.hip] {
                        let hipY: CGFloat
                        if let hipToAnkleSeatRatio {
                            let standingHipY = ((standing[.leftHip]?.y ?? 0) + (standing[.rightHip]?.y ?? 0)) / 2
                            let standingHipHeight = ankleY - standingHipY
                            let seatedHipHeight = standingHipHeight * (1 - (1 - hipToAnkleSeatRatio) * progress)
                            hipY = ankleY - seatedHipHeight
                        } else {
                            hipY = hip.y + shoulderDrop * 0.25
                        }
                        joints[side.hip] = CGPoint(x: hip.x, y: hipY)
                    }
                    if let knee = joints[side.knee], let hip = joints[side.hip] {
                        let targetY = hip.y
                        joints[side.knee] = CGPoint(x: knee.x, y: knee.y + (targetY - knee.y) * progress)
                    }
                }
            } else {
                joints = ExerciseDemoFigureView.lowered(standing, by: legs)
            }
            if approachingCamera {
                let ankleY = ((joints[.leftAnkle]?.y ?? 0) + (joints[.rightAnkle]?.y ?? 0)) / 2
                for (joint, point) in joints {
                    let isAnkle = joint == .leftAnkle || joint == .rightAnkle
                    let shiftedY = ankleY - 90 + (isAnkle ? 0 : (point.y - ankleY) * 1.3)
                    joints[joint]?.y = shiftedY
                }
            }
            let ankleY = ((joints[.leftAnkle]?.y ?? 0) + (joints[.rightAnkle]?.y ?? 0)) / 2
            if let shoulderSignalRatio {
                let leftAnkleY = standing[.leftAnkle]?.y ?? 0
                let rightAnkleY = standing[.rightAnkle]?.y ?? 0
                let leftShoulderY = standing[.leftShoulder]?.y ?? 0
                let rightShoulderY = standing[.rightShoulder]?.y ?? 0
                let standingU = (leftAnkleY + rightAnkleY) / 2 - (leftShoulderY + rightShoulderY) / 2
                let shoulderY = ankleY - standingU * shoulderSignalRatio
                for side in BodySide.allCases {
                    if let shoulder = joints[side.shoulder] { joints[side.shoulder] = CGPoint(x: shoulder.x, y: shoulderY) }
                }
            }
            if let hipSignalRatio {
                let leftAnkleY = standing[.leftAnkle]?.y ?? 0
                let rightAnkleY = standing[.rightAnkle]?.y ?? 0
                let leftHipY = standing[.leftHip]?.y ?? 0
                let rightHipY = standing[.rightHip]?.y ?? 0
                let standingHipHeight = (leftAnkleY + rightAnkleY) / 2 - (leftHipY + rightHipY) / 2
                let hipY = ankleY - standingHipHeight * hipSignalRatio
                for side in BodySide.allCases {
                    if let hip = joints[side.hip] { joints[side.hip] = CGPoint(x: hip.x, y: hipY) }
                }
            }
            for side in BodySide.allCases {
                joints[side.knee]?.x -= (side == .left ? 1 : -1) * kneesIn
            }
            return joints.mapValues { CGPoint(x: $0.x * scale + offset.x, y: $0.y * scale + offset.y) }
        }
    }

    /// Feeds an analyzer at 10 Hz, like the camera, and collects what it reports. A new player starts cold, like a
    /// set's fresh analyzer: nothing has been seen standing.
    private final class Player {
        private let analyzer: ExerciseAnalyzing
        private var framing: FramingEvaluator
        var body: Body
        private(set) var time: TimeInterval = 0
        private(set) var reps: [TimeInterval] = []
        private(set) var forms: [RepForm] = []
        private(set) var signals: [Double] = []
        private(set) var rejections: [RepRejection] = []
        private(set) var startHeld: [Bool] = []
        private(set) var framingBecameReliable = false
        private(set) var endPositionWasReached = false
        private(set) var formReadings: [FormReading] = []

        init(_ exercise: ExerciseDefinition, body: Body = Body()) {
            analyzer = exercise.makeAnalyzer(1)
            framing = FramingEvaluator(requiredJoints: exercise.requiredJoints,
                                       anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                                       headroomArmLengths: exercise.headroomArmLengths,
                                       sideroomArmLengths: exercise.sideroomArmLengths,
                                       maximumShoulderSpan: exercise.maximumShoulderSpan,
                                       centersInFrame: exercise.centersInFrame,
                                       cameraView: exercise.cameraView)
            self.body = body
        }

        /// Time with no frames, as when the pose is lost.
        func gap(_ seconds: TimeInterval) {
            time += seconds
        }

        /// Standing still, which measures the hip-to-ankle ruler before anyone sits.
        func stand(count: Int = 15) {
            feed(.standing, count: count)
        }

        func feed(_ legs: LegPose, count: Int = 1, kneesIn: CGFloat = 0, estimated: Set<LandmarkType> = [],
                  kneeConfidence: Double = 0.9, approachingCamera: Bool = false,
                  leaningForward: Bool = false, shoulderSignalRatio: CGFloat? = nil,
                  hipSignalRatio: CGFloat? = nil) {
            for _ in 0..<count {
                let landmarks = Dictionary(uniqueKeysWithValues: body.joints(
                    legs, kneesIn: kneesIn, approachingCamera: approachingCamera,
                    leaningForward: leaningForward, shoulderSignalRatio: shoulderSignalRatio,
                    hipSignalRatio: hipSignalRatio).map { type, point in
                    let confidence = type == .leftKnee || type == .rightKnee ? kneeConfidence : 0.9
                    return (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point,
                                           confidence: confidence))
                })
                let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                                      timestamp: time, estimatedJoints: estimated)
                if framing.evaluate(frame).isReliable { framingBecameReliable = true }
                let analysis = analyzer.process(frame, counting: true)
                if !analysis.endPositionSides.isEmpty { endPositionWasReached = true }
                reps += analysis.repEvents.map(\.timestamp)
                forms += analysis.repForms
                rejections += analysis.rejections
                formReadings = analysis.formReadings
                startHeld.append(analysis.startPositionHeld)
                if let signal = analysis.readings[.left]?.signal { signals.append(signal) }
                time += 0.1
            }
        }

        /// Plays `motion` from its start for `loops` loops. `kneesIn` and `estimatedDuring` use the loop's own clock.
        func play(_ motion: ArmMotion, loops: Int, kneesIn: (TimeInterval) -> CGFloat = { _ in 0 },
                  estimatedDuring: ClosedRange<TimeInterval>? = nil, kneeConfidence: Double = 0.9) {
            for index in 0..<Int(motion.duration * Double(loops) * 10) {
                let local = Double(index) / 10
                let estimated: Set<LandmarkType> = estimatedDuring?.contains(local) == true ? [.leftAnkle, .rightAnkle] : []
                feed(motion.sample(at: local).legs, kneesIn: kneesIn(local), estimated: estimated,
                     kneeConfidence: kneeConfidence)
            }
        }
    }
}
