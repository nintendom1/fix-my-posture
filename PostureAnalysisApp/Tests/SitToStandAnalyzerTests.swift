import XCTest
@testable import PostureAnalysisApp

final class SitToStandAnalyzerTests: XCTestCase {
    private let exercise = SitToStandExercise.definition()
    private let partialExercise = SitToStandExercise.definition(configuration: .partialRange)
    private var motion: ArmMotion { exercise.guide.motion }

    /// The signal `d` of a standing figure measured against its own thigh: the 2-unit sideways lean of the
    /// guide's thigh makes it a little under 1.
    private static let standingSignal = 0.9997

    /// (scale, thigh, shin) cases for the guide figure, each changing one thing.
    private static let proportions: [(CGFloat, CGFloat, CGFloat)] = [
        (1, 1, 1), (0.5, 1, 1), (2, 1, 1), (1, 0.85, 1), (1, 1.15, 1), (1, 1, 0.85), (1, 1, 1.15)
    ]

    // MARK: - Counting

    /// The instructed start is seated, and the analyzer has never seen anyone stand. Every case still counts its
    /// first loop, because the bootstrap measures hip height in shin lengths until the first stand.
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

    func testGuideDemonstrationReadsTheDocumentedSignalValues() {
        // (variant, first-loop seated reading in shin lengths, later seated reading in thigh lengths)
        for (definition, bootstrapSeated, seated) in [(exercise, 0.24, 0.19), (partialExercise, 0.55, 0.45)] {
            let player = Player(definition)
            let guide = definition.guide.motion
            player.play(guide, loops: 2)
            let perLoop = Int((guide.duration * 10).rounded())
            let seatedHold = player.signals.prefix(9)
            XCTAssertEqual(seatedHold.count, 9)
            XCTAssertTrue(seatedHold.allSatisfy { abs($0 - bootstrapSeated) < 0.01 },
                          "\(definition.displayName) reads \(bootstrapSeated) shin lengths before the first stand: \(seatedHold)")
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
        // (variant, seated d, standing d, reps in one loop)
        let cases: [(ExerciseDefinition, Double, Double, Int)] = [
            (exercise, 0.33, 0.9997, 1), (exercise, 0.37, 0.9997, 0),
            (exercise, 0.19, 0.87, 1), (exercise, 0.19, 0.83, 0),
            (partialExercise, 0.53, 0.9997, 1), (partialExercise, 0.57, 0.9997, 0)
        ]
        for (definition, seated, standing, expected) in cases {
            let player = Player(definition)
            player.stand()
            player.play(line(seated: seated, standing: standing), loops: 1)
            XCTAssertEqual(player.reps.count, expected, "\(definition.displayName): seated \(seated), standing \(standing)")
        }
    }

    func testEightRepsWithNearThresholdReturnsDoNotRatchetTheRuler() {
        // Standing only just past its line shortens the thigh on screen. Re-measuring from it would shrink the
        // ruler, so the seated d of 0.33 would read 0.38 and stop counting. The ruler is measured first so the
        // custom depths are judged only by the lines.
        let player = Player(exercise)
        player.stand()
        player.play(line(seated: 0.33, standing: 0.87), loops: 8)
        XCTAssertEqual(player.reps.count, 8)
        XCTAssertTrue(player.forms.allSatisfy { $0.flags.isEmpty }, "\(player.forms)")
    }

    func testLongSeatedHoldKeepsTheRulerLockedFromStanding() {
        // A seated thigh looks short. A ruler that followed the last second would shrink and read the seated hips as
        // standing.
        let player = Player(exercise)
        player.play(motion, loops: 1)
        XCTAssertEqual(player.reps.count, 1)
        player.feed(seated, count: 40)
        XCTAssertEqual(player.signals.last ?? .nan, 0.19, accuracy: 0.02)
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
        player.feed(standingPose, count: 4)
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
        player.feed(seated, count: samples)
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
        let standing = Player(exercise)
        standing.feed(standingPose, count: 30)
        XCTAssertFalse(standing.startHeld.contains(true), "Standing is not the start position")
        XCTAssertEqual(standing.reps.count, 0)
        standing.play(motion, loops: 3)
        XCTAssertEqual(standing.reps.count, 3, "Sitting down after standing still counts every loop")

        let halfway = Player(exercise)
        halfway.feed(midway, count: 30)
        XCTAssertFalse(halfway.startHeld.contains(true), "Halfway up is not the start position")
        XCTAssertEqual(halfway.reps.count, 0)
        halfway.feed(standingPose, count: 5)
        halfway.play(motion, loops: 2)
        XCTAssertEqual(halfway.reps.count, 2)
    }

    func testAStartingSeatThatMissesTheSeatLineAgainstTheMeasuredThighDoesNotCount() {
        // Thigh 15% short: a shallow seat reads 0.38 shin lengths (inside the 0.4 bootstrap gate) but 0.37 thigh
        // lengths once the thigh is measured (outside the 0.35 Seat line), so a rep that began there isn't counted.
        let player = Player(exercise, body: Body(thigh: 0.85))
        player.play(trip(from: LegPose(hipDrop: 0.7), to: seated), loops: 1)
        XCTAssertEqual(player.reps.count, 0, "The cycle began on a seat that wasn't low enough")
        player.play(motion, loops: 1)
        XCTAssertEqual(player.reps.count, 1, "The next cycle starts from the seat the last one ended on")
    }

    // MARK: - Coaching

    func testRisingWithoutStandingAsksToStandAllTheWayUp() {
        let player = Player(exercise)
        player.play(line(seated: 0.19, standing: 0.7), loops: 2)
        XCTAssertEqual(player.reps.count, 0)
        XCTAssertEqual(player.forms.count, 2)
        XCTAssertTrue(player.forms.allSatisfy { $0.flags == [.sitToStandTall] }, "\(player.forms)")

        // Before the first stand, a rise reads in shin lengths, which is a little larger than in thigh lengths.
        let lean = Player(exercise)
        lean.play(line(seated: 0.19, standing: 0.38), loops: 2)
        XCTAssertEqual(lean.reps.count, 0)
        XCTAssertTrue(lean.forms.isEmpty, "A rise under 0.25 is leaning forward, not an attempt: \(lean.forms)")
    }

    func testPlopIntoTheSeatAsksToSitDownSlowly() {
        let plop = Player(exercise)
        plop.play(line(seated: 0.19, standing: Self.standingSignal, descent: 0.3), loops: 2)
        XCTAssertEqual(plop.reps.count, 2, "Form never affects counting")
        XCTAssertTrue(plop.forms.allSatisfy { $0.flags == [.sitToStandControl] }, "\(plop.forms)")

        // The guide's own 1.5 s descent takes 0.66 s from the standing line to the seat line.
        let slow = Player(exercise)
        slow.play(motion, loops: 2)
        XCTAssertFalse(slow.forms.contains { $0.flags.contains(.sitToStandControl) })
    }

    func testKneesFallingTowardEachOtherWhileRisingAsksToKeepThemApart() {
        let caving = Player(exercise)
        caving.play(motion, loops: 1, kneesIn: { (1.0..<2.2).contains($0) ? 12 : 0 })
        XCTAssertEqual(caving.reps.count, 1, "Form never affects counting")
        XCTAssertEqual(caving.forms.map(\.flags), [[.sitToStandKnees]])

        let steady = Player(exercise)
        steady.play(motion, loops: 1, kneesIn: { (1.0..<2.2).contains($0) ? 6 : 0 })
        XCTAssertEqual(steady.reps.count, 1)
        XCTAssertEqual(steady.forms.map(\.flags), [[]], "A gap of 78% of the ankle gap is fine")

        // Knees that come together only after standing aren't "while rising".
        let later = Player(exercise)
        later.play(motion, loops: 1, kneesIn: { $0 >= 2.3 ? 12 : 0 })
        XCTAssertEqual(later.forms.map(\.flags), [[]])
    }

    /// The streak starts on the first sample away from the seat, before the attempt is confirmed.
    func testTwoCloseKneeSamplesAtTheStartOfARiseAskToKeepThemApart() {
        let player = Player(exercise)
        player.feed(seated, count: 3)
        player.feed(midway, count: 2, kneesIn: 12)
        player.feed(midway, count: 3)
        player.feed(standingPose, count: 3)
        player.feed(midway, count: 5)
        player.feed(seated, count: 3)
        XCTAssertEqual(player.reps.count, 1, "Form never affects counting")
        XCTAssertEqual(player.forms.map(\.flags), [[.sitToStandKnees]])

        // One close sample, then wide again, isn't two in a row.
        let single = Player(exercise)
        single.feed(seated, count: 3)
        single.feed(midway, count: 1, kneesIn: 12)
        single.feed(midway, count: 4)
        single.feed(standingPose, count: 3)
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
        XCTAssertEqual(exercise.requiredJoints, AirSquatExercise.definition().requiredJoints)
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

    func testSeatedGhostIsSizedFromTheShinsAndDrawsTheSeat() throws {
        let containerSize = CGSize(width: 393, height: 852)
        let variant = try XCTUnwrap(ReadyPoseFixtures.variants(for: exercise).first { $0.name == "full" })
        let frame = ReadyPoseFixtures.frame(variant, at: 0)
        let overlay = WorkoutOverlayState(
            imageSize: frame.imageSize,
            joints: frame.pose.landmarks.mapValues { OverlayJoint(location: $0.normalizedLocation, isStale: false) },
            segments: [], endPositionSides: [], pose: frame.pose)
        let sample = motion.startSample
        let figure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
            fitOverlay: overlay, metrics: nil, motion: motion, cameraView: .front,
            containerSize: containerSize, sample: sample))

        func container(_ joint: LandmarkType) throws -> CGPoint {
            let landmark = try XCTUnwrap(overlay.joints[joint])
            return CoordinateConverter.normalizedToContainer(normalized: landmark.location, imageSize: overlay.imageSize,
                                                             containerSize: containerSize)
        }
        let figureShin = ArmGeometry.distance(try XCTUnwrap(ExerciseDemoFigureView.figureJoints[.leftAnkle]),
                                              try XCTUnwrap(ExerciseDemoFigureView.figureJoints[.leftKnee]))
        let userShin = ArmGeometry.distance(try container(.leftAnkle), try container(.leftKnee))
        XCTAssertEqual(figure.bodyScale, userShin / figureShin, accuracy: 1e-6,
                       "A seated thigh points at the camera, so only the shin sizes the ghost")

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
        XCTAssertNil(AirSquatExercise.definition().guide.motion.chairSeat)
        XCTAssertNotNil(motion.chairSeat)
    }

    // MARK: - Helpers

    private var seated: LegPose { motion.startLegs }
    private var standingPose: LegPose { .standing }
    /// Halfway up: d of about 0.6, between the Seat and Stand lines.
    private var midway: LegPose { LegPose(hipDrop: (Self.standingSignal - 0.6) / 0.9) }

    /// Seated at `seated`, up to `standing`, and back, each given as `d` against a standing-locked ruler.
    private func line(seated: Double, standing: Double, descent: TimeInterval = 1.5) -> ArmMotion {
        func legs(_ signal: Double) -> LegPose {
            LegPose(hipDrop: max(0, (Self.standingSignal - signal) / 0.9))
        }
        let arms = ArmAngles(upperArmElevation: -85, forearmElevation: -85)
        return ArmMotion(keyframes: [
            ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0, legs: legs(seated)),
            ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0.4, stepIndex: 1, legs: legs(standing)),
            // The last loop settles on the seat, so its rep is confirmed before the frames stop.
            ArmKeyframe(angles: arms, moveDuration: descent, holdDuration: 0.5, stepIndex: 2, legs: legs(seated))
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

        /// Joints in pixels for a figure sitting or standing at `legs`, knees pulled `kneesIn` guide units together.
        func joints(_ legs: LegPose, kneesIn: CGFloat) -> [LandmarkType: CGPoint] {
            var standing = ExerciseDemoFigureView.figureJoints
            for side in BodySide.allCases {
                guard let hip = standing[side.hip], let knee = standing[side.knee], let ankle = standing[side.ankle] else { continue }
                let newKnee = CGPoint(x: hip.x + (knee.x - hip.x) * thigh, y: hip.y + (knee.y - hip.y) * thigh)
                standing[side.knee] = newKnee
                standing[side.ankle] = CGPoint(x: newKnee.x + (ankle.x - knee.x) * shin, y: newKnee.y + (ankle.y - knee.y) * shin)
            }
            var joints = ExerciseDemoFigureView.lowered(standing, by: legs)
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
        var body: Body
        private(set) var time: TimeInterval = 0
        private(set) var reps: [TimeInterval] = []
        private(set) var forms: [RepForm] = []
        private(set) var signals: [Double] = []
        private(set) var rejections: [RepRejection] = []
        private(set) var startHeld: [Bool] = []

        init(_ exercise: ExerciseDefinition, body: Body = Body()) {
            analyzer = exercise.makeAnalyzer(1)
            self.body = body
        }

        /// Time with no frames, as when the pose is lost.
        func gap(_ seconds: TimeInterval) {
            time += seconds
        }

        /// Standing still, which measures the thigh before anyone sits.
        func stand(count: Int = 15) {
            feed(.standing, count: count)
        }

        func feed(_ legs: LegPose, count: Int = 1, kneesIn: CGFloat = 0, estimated: Set<LandmarkType> = []) {
            for _ in 0..<count {
                let landmarks = Dictionary(uniqueKeysWithValues: body.joints(legs, kneesIn: kneesIn).map { type, point in
                    (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
                })
                let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                                      timestamp: time, estimatedJoints: estimated)
                let analysis = analyzer.process(frame, counting: true)
                reps += analysis.repEvents.map(\.timestamp)
                forms += analysis.repForms
                rejections += analysis.rejections
                startHeld.append(analysis.startPositionHeld)
                if let signal = analysis.readings[.left]?.signal { signals.append(signal) }
                time += 0.1
            }
        }

        /// Plays `motion` from its start for `loops` loops. `kneesIn` and `estimatedDuring` use the loop's own clock.
        func play(_ motion: ArmMotion, loops: Int, kneesIn: (TimeInterval) -> CGFloat = { _ in 0 },
                  estimatedDuring: ClosedRange<TimeInterval>? = nil) {
            for index in 0..<Int(motion.duration * Double(loops) * 10) {
                let local = Double(index) / 10
                let estimated: Set<LandmarkType> = estimatedDuring?.contains(local) == true ? [.leftAnkle, .rightAnkle] : []
                feed(motion.sample(at: local).legs, kneesIn: kneesIn(local), estimated: estimated)
            }
        }
    }
}
