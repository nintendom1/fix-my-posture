import CoreGraphics
import XCTest
@testable import PostureAnalysisApp

final class WorkoutSessionTests: XCTestCase {
    private let press = ShoulderPressExercise.definition()

    func testHoldingStartPositionAutoStartsSet() {
        var session = readySession()
        _ = session.handle(.startPositionChanged(true), at: 2)
        _ = session.handle(.tick, at: 2.5)
        XCTAssertEqual(session.phase, .ready)

        let effects = session.handle(.tick, at: 3)
        XCTAssertEqual(session.phase, .exercising)
        XCTAssertTrue(effects.contains(.setCounting(true)))
        XCTAssertTrue(spoken(effects).contains("Set 1 of 2. Go."))
    }

    func testAStartHoldCountsOnlyUpToTheLatestAnalyzedFrame() {
        var session = readySession()
        _ = session.handle(.startPositionChanged(true), at: 2)
        _ = session.handle(.poseObserved, at: 2.8)

        // Frames stopped arriving (a stall); the clock alone can't finish the hold.
        _ = session.handle(.tick, at: 3.5)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.startHoldProgress(at: 3.5) ?? 0, 0.8, accuracy: 1e-9)

        _ = session.handle(.poseObserved, at: 3)
        let effects = session.handle(.tick, at: 3.5)
        XCTAssertEqual(session.phase, .exercising, "A frame captured a full second into the hold completes it.")
        XCTAssertTrue(effects.contains(.setCounting(true)))
    }

    func testRaisedStraightArmsDoNotStartShrugSetHoldTimer() {
        let shrug = DumbbellShrugExercise.definition()
        var session = readySession(exercise: shrug)
        let analyzer = DumbbellShrugAnalyzer(epoch: session.analyzerEpoch)

        for index in 0...12 {
            let time = 1.1 + Double(index) / 10
            let analysis = analyzer.process(shrugFrame(time: time, armAngleBelowHorizontal: 5), counting: false)
            _ = session.handle(.startPositionChanged(analysis.startPositionHeld), at: time)
        }

        XCTAssertNil(session.startHoldProgress(at: 2.3), "Raised arms must not begin the hold timer.")
        let effects = session.handle(.tick, at: 2.3)
        XCTAssertEqual(session.phase, .ready, "A held straight-arm pose below horizontal is not the shrug start.")
        XCTAssertFalse(effects.contains(.setCounting(true)))
    }

    func testStartHoldProgressFillsOverOneSecond() {
        var session = readySession()
        XCTAssertNil(session.startHoldProgress(at: 2))
        _ = session.handle(.startPositionChanged(true), at: 2)
        XCTAssertEqual(session.startHoldProgress(at: 2.5) ?? -1, 0.5, accuracy: 0.001)
        _ = session.handle(.startPositionChanged(false), at: 2.6)
        XCTAssertNil(session.startHoldProgress(at: 2.7), "Letting go hides the ring.")
    }

    func testSuggestedCommandsFollowThePhase() {
        var session = readySession()
        XCTAssertTrue(session.suggestedCommands.contains(.start))
        _ = session.handle(.command(.start), at: 2)
        XCTAssertTrue(session.suggestedCommands.contains(.pause))
        XCTAssertFalse(session.suggestedCommands.contains(.start))
    }

    func testRestWaitsForTimerBeforeAutoStart() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 10)
        XCTAssertEqual(session.phase, .resting)

        // Rest is 90 s, so it ends at t = 100. Holding the start earlier must not skip it.
        _ = session.handle(.startPositionChanged(true), at: 20)
        _ = session.handle(.tick, at: 99)
        _ = session.handle(.tick, at: 100.5)
        XCTAssertEqual(session.phase, .resting)
        _ = session.handle(.tick, at: 101)
        XCTAssertEqual(session.phase, .exercising)
        XCTAssertEqual(session.currentSetNumber, 2)
    }

    func testSetupGuidanceAtTheEndOfRestSetsUpAgainBeforeAnAutomaticStart() throws {
        var session = readySession(exercise: PushUpExercise.definition())
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 10)
        XCTAssertEqual(session.phase, .resting)

        // The phone moved closer during rest; the user holds the plank as rest ends.
        let tooClose = FramingStatus(isReliable: true, guidance: .movePhoneFartherFloor)
        _ = session.handle(.framingChanged(tooClose), at: 60)
        _ = session.handle(.startPositionChanged(true), at: 60)
        let restEnd = try XCTUnwrap(session.restEndsAt)
        let effects = session.handle(.tick, at: restEnd + 1.5)
        XCTAssertEqual(session.phase, .framing, "No automatic start while the coach asks for the phone farther away.")
        XCTAssertTrue(spoken(effects).contains("Rest is up. Move the phone farther from your hands, so you stay in view at the bottom."))
        XCTAssertTrue(spoken(session.handle(.tick, at: restEnd + 3)).isEmpty, "Said once, not repeated straight away.")

        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: restEnd + 4)
        XCTAssertEqual(session.phase, .ready)
        _ = session.handle(.tick, at: restEnd + 5.5)
        XCTAssertEqual(session.phase, .exercising)
        XCTAssertEqual(session.currentSetNumber, 2)
    }

    func testStartStillBeginsASetWhileTheCoachAsksForThePhoneFarther() {
        var session = readySession(exercise: PushUpExercise.definition())
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: .movePhoneFartherFloor)), at: 2)
        XCTAssertEqual(session.phase, .framing)
        _ = session.handle(.command(.start), at: 3)
        XCTAssertEqual(session.phase, .exercising)
    }

    func testExerciseDefaultRestUsesEachExercisesDuration() {
        var pressSession = readySession()
        _ = pressSession.handle(.command(.start), at: 2)
        _ = pressSession.handle(.command(.nextSet), at: 10)
        XCTAssertEqual(pressSession.restEndsAt, 100)

        let curl = HammerCurlExercise.definition()
        var curlSession = readySession(exercise: curl)
        _ = curlSession.handle(.command(.start), at: 2)
        _ = curlSession.handle(.command(.nextSet), at: 10)
        XCTAssertEqual(curlSession.restEndsAt, 70)
    }

    func testFixedRestAppliesToEveryExerciseAndDrivesRestCountdown() {
        let settings = WorkoutSettings(restPolicy: .fixed(seconds: 45))
        var pressSession = readySession(settings: settings)
        _ = pressSession.handle(.command(.start), at: 2)
        _ = pressSession.handle(.command(.nextSet), at: 10)
        XCTAssertEqual(pressSession.restEndsAt, 55)
        XCTAssertEqual(pressSession.restRemaining(at: 30), 25)
        _ = pressSession.handle(.tick, at: 54.9)
        XCTAssertEqual(pressSession.phase, .resting)

        let curl = HammerCurlExercise.definition()
        var curlSession = readySession(exercise: curl, settings: settings)
        _ = curlSession.handle(.command(.start), at: 2)
        _ = curlSession.handle(.command(.nextSet), at: 10)
        XCTAssertEqual(curlSession.restEndsAt, 55)
    }

    func testStaleRepsAreIgnored() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        let epoch = session.analyzerEpoch
        _ = session.handle(.repCompleted(rep(epoch: epoch - 1)), at: 3)
        XCTAssertEqual(session.repCount, 0)
        _ = session.handle(.repCompleted(rep(epoch: epoch)), at: 4)
        XCTAssertEqual(session.repCount, 1)
    }

    func testTenRepsAnnounceTargetRangeAndCompleteSet() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        var lines: [String] = []
        for count in 1...10 {
            lines += spoken(session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 2 + Double(count)))
        }
        XCTAssertTrue(lines.contains("8. You're in the target range."))
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.progress[press.id]?.setReps, [10])
    }

    func testOneSidedDeadliftTrackingReachesTheTargetAndCompletesTheSet() throws {
        let deadlift = StiffLegDeadliftExercise.definition()
        var session = readySession(exercise: deadlift)
        _ = session.handle(.command(.start), at: 2)
        let analyzer = StiffLegDeadliftAnalyzer(epoch: session.analyzerEpoch)
        let motion = deadlift.guide.motion
        let sampleCount = Int(motion.duration * Double(deadlift.autoCompleteReps ?? 10) * 10)
        var trackedSides = Set<BodySide>()

        for index in 0..<sampleCount {
            let time = Double(index) / 10
            let sample = motion.sample(at: time)
            let joints = ExerciseDemoFigureView.pose(for: sample, cameraView: .side).jointLocations
            trackedSides.formUnion(joints.keys.compactMap(BodySide.side(of:)))
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
            })
            let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                                  timestamp: time)

            for event in analyzer.process(frame, counting: true).repEvents {
                _ = session.handle(.repCompleted(event), at: time + 2)
            }
        }

        XCTAssertEqual(trackedSides, [.left], "The guide only supplies one tracked side.")
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.progress[deadlift.id]?.setReps, [deadlift.autoCompleteReps ?? 10])
    }

    func testLateralRaiseCreditsBothSidesAndCompletesItsSessionTarget() {
        let lateralRaise = LateralRaiseExercise.definition()
        var session = readySession(exercise: lateralRaise)
        _ = session.handle(.command(.start), at: 2)

        let analyzer = LateralRaiseAnalyzer(epoch: session.analyzerEpoch)
        let motion = lateralRaise.guide.motion
        let sampleCount = Int(motion.duration * Double(lateralRaise.autoCompleteReps) * 10)
        var creditedSides = Set<BodySide>()
        for index in 0..<sampleCount {
            let time = Double(index) / 10
            let joints = ExerciseDemoFigureView.pose(for: motion.sample(at: time), cameraView: .front).jointLocations
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
            })
            let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)

            for event in analyzer.process(frame, counting: true).repEvents {
                creditedSides.formUnion(event.sides)
                XCTAssertEqual(event.sides, Set(BodySide.allCases))
                _ = session.handle(.repCompleted(event), at: time + 2)
            }
        }

        XCTAssertEqual(creditedSides, Set(BodySide.allCases))
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.progress[lateralRaise.id]?.setReps, [lateralRaise.autoCompleteReps])
    }

    func testDumbbellShrugCreditsBothSidesAndCompletesItsSessionTarget() {
        let shrug = DumbbellShrugExercise.definition()
        var session = readySession(exercise: shrug)
        _ = session.handle(.command(.start), at: 2)

        let analyzer = DumbbellShrugAnalyzer(epoch: session.analyzerEpoch)
        let motion = shrug.guide.motion
        let sampleCount = Int(motion.duration * Double(shrug.autoCompleteReps) * 10) + 10
        var creditedSides = Set<BodySide>()
        for index in 0..<sampleCount {
            let time = Double(index) / 10
            let joints = ExerciseDemoFigureView.pose(for: motion.sample(at: time), cameraView: .front).jointLocations
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
            })
            let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)

            for event in analyzer.process(frame, counting: true).repEvents {
                creditedSides.formUnion(event.sides)
                XCTAssertEqual(event.sides, Set(BodySide.allCases))
                _ = session.handle(.repCompleted(event), at: time + 2)
            }
        }

        XCTAssertEqual(creditedSides, Set(BodySide.allCases))
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.progress[shrug.id]?.setReps, [shrug.autoCompleteReps])
    }

    func testGluteBridgeCreditsBothSidesAndCompletesItsSessionTarget() {
        let bridge = GluteBridgeExercise.definition()
        var session = readySession(exercise: bridge)
        _ = session.handle(.command(.start), at: 2)

        let analyzer = GluteBridgeAnalyzer(epoch: session.analyzerEpoch)
        let motion = bridge.guide.motion
        let sampleCount = Int(motion.duration * Double(bridge.autoCompleteReps) * 10)
        var creditedSides = Set<BodySide>()
        for index in 0..<sampleCount {
            let time = Double(index) / 10
            let joints = ExerciseDemoFigureView.pose(for: motion.sample(at: time),
                                                     cameraView: .lyingSide).jointLocations
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
            })
            let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 800, imageHeight: 900),
                                  timestamp: time)

            for event in analyzer.process(frame, counting: true).repEvents {
                creditedSides.formUnion(event.sides)
                XCTAssertEqual(event.sides, Set(BodySide.allCases))
                _ = session.handle(.repCompleted(event), at: time + 2)
            }
        }

        XCTAssertEqual(creditedSides, Set(BodySide.allCases))
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.progress[bridge.id]?.setReps, [bridge.autoCompleteReps])
    }

    func testWallPushUpCreditsBothSidesAndCompletesItsSessionTarget() {
        let wallPushUp = WallPushUpExercise.definition()
        var session = readySession(exercise: wallPushUp)
        _ = session.handle(.command(.start), at: 2)

        let analyzer = WallPushUpAnalyzer(epoch: session.analyzerEpoch)
        let motion = wallPushUp.guide.motion
        let sampleCount = Int(motion.duration * Double(wallPushUp.autoCompleteReps) * 10)
        var creditedSides = Set<BodySide>()
        for index in 0..<sampleCount {
            let time = Double(index) / 10
            let frame = ReadyPoseFixtures.demoFrame(wallPushUp, motionTime: time, at: time)
            let analysis = analyzer.process(frame, counting: true)
            for event in analysis.repEvents {
                creditedSides.formUnion(event.sides)
                XCTAssertEqual(event.sides, Set(BodySide.allCases))
                _ = session.handle(.repCompleted(event), at: time + 2)
            }
            if session.phase == .resting { break }
        }

        XCTAssertEqual(creditedSides, Set(BodySide.allCases))
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.progress[wallPushUp.id]?.setReps, [wallPushUp.autoCompleteReps])
    }

    func testGluteBridgeFinalTargetPeakFaultReachesTheSessionBeforeCompletion() {
        var bridge = GluteBridgeExercise.definition()
        bridge.autoCompleteReps = 2
        var session = readySession(exercise: bridge)
        _ = session.handle(.command(.start), at: 2)
        let analyzer = GluteBridgeAnalyzer(epoch: session.analyzerEpoch)
        let attempt = [130, 130, 155] + Array(repeating: 200.0, count: 10)
            + [160, 160, 172, 155, 130, 130]
        var time: TimeInterval = 4.5
        var finalPeakFaultReachedSet = false
        var showedStraightLineCue = false

        for attemptIndex in 0..<2 {
            for angle in attempt {
                let analysis = analyzer.process(bridgeFrame(angle: angle, time: time), counting: true)
                for event in analysis.repEvents {
                    _ = session.handle(.repCompleted(event), at: time)
                }
                if let form = analysis.repForms.first {
                    let observation = FormObservation(epoch: analyzer.epoch, repForms: analysis.repForms)
                    let effects = session.handle(.formObserved(observation), at: time)
                    if attemptIndex == 1, form.flags.contains(.bridgeStraightLine) {
                        finalPeakFaultReachedSet = true
                    }
                    showedStraightLineCue = showedStraightLineCue
                        || tips(effects).contains { $0.cue.id == .bridgeStraightLine }
                }
                time += 0.1
            }
        }

        XCTAssertTrue(finalPeakFaultReachedSet, "The target attempt's peak fault must reach form observation.")
        XCTAssertTrue(showedStraightLineCue, "The session must accept the final attempt before completing the set.")
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.progress[bridge.id]?.setReps, [2])
    }

    func testTiltWarningIsRateLimited() {
        var session = readySession()
        XCTAssertEqual(spoken(session.handle(.phoneTiltChanged(true), at: 5)).count, 1)
        _ = session.handle(.phoneTiltChanged(false), at: 6)
        XCTAssertTrue(spoken(session.handle(.phoneTiltChanged(true), at: 20)).isEmpty)
        XCTAssertEqual(spoken(session.handle(.phoneTiltChanged(true), at: 36)).count, 1)
    }

    func testSetStartShowsReminderWithoutSpeakingIt() throws {
        var session = readySession()
        let effects = session.handle(.command(.start), at: 2)
        let tip = try XCTUnwrap(tips(effects).first)
        XCTAssertEqual(tip.cue.kind, .reminder)
        XCTAssertFalse(spoken(effects).contains(tip.cue.text), "Reminders are visual only.")
    }

    func testCorrectiveCueIsSpokenAndShownForCurrentAnalyzerOnly() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        let flagged = RepForm(timestamp: 0, flags: [.pressFullExtension])
        let stale = FormObservation(epoch: session.analyzerEpoch - 1, repForms: [flagged, flagged])
        XCTAssertTrue(session.handle(.formObserved(stale), at: 8).isEmpty)

        _ = session.handle(.formObserved(FormObservation(epoch: session.analyzerEpoch, repForms: [flagged])), at: 9)
        let effects = session.handle(.formObserved(FormObservation(epoch: session.analyzerEpoch, repForms: [flagged])), at: 10)
        XCTAssertEqual(tips(effects).map(\.cue.id), [.pressFullExtension])
        XCTAssertEqual(spoken(effects), ["Press all the way up."])
    }

    func testRestartingSetForgetsCoachingHistory() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        let flagged = RepForm(timestamp: 0, flags: [.pressFullExtension])
        _ = session.handle(.formObserved(FormObservation(epoch: session.analyzerEpoch, repForms: [flagged])), at: 8)
        _ = session.handle(.command(.restartSet), at: 9)
        let effects = session.handle(.formObserved(FormObservation(epoch: session.analyzerEpoch, repForms: [flagged])), at: 10)
        XCTAssertTrue(tips(effects).isEmpty, "One flagged attempt after a restart isn't 2 of the last 3.")
    }

    func testPausingRestartsTheHoldForContinuousCues() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        let leaning = FormObservation(epoch: session.analyzerEpoch, signals: [.pressTorsoCentered])
        _ = session.handle(.formObserved(leaning), at: 8)
        _ = session.handle(.command(.pause), at: 8.3)
        _ = session.handle(.command(.resume), at: 8.4)
        XCTAssertTrue(tips(session.handle(.formObserved(leaning), at: 8.6)).isEmpty, "The hold starts over after a pause.")
        XCTAssertTrue(tips(session.handle(.formObserved(leaning), at: 9.0)).isEmpty)
        XCTAssertEqual(tips(session.handle(.formObserved(leaning), at: 9.1)).map(\.cue.id), [.pressTorsoCentered])
    }

    func testSwitchingMidSetKeepsFinishedSetsAndRestartsTheSetInProgress() {
        let curl = HammerCurlExercise.definition()
        let reliable = FramingStatus(isReliable: true, guidance: nil)
        var session = WorkoutSession(exercises: [press, curl], initialExercise: press.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(reliable), at: 1)
        _ = session.handle(.command(.start), at: 2)
        for time in 3...5 { _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: Double(time)) }
        _ = session.handle(.command(.nextSet), at: 6)
        _ = session.handle(.command(.start), at: 7)
        _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 8)

        let epoch = session.analyzerEpoch
        let effects = session.handle(.command(.selectExercise(curl.id)), at: 9)
        XCTAssertEqual(session.exerciseID, curl.id)
        XCTAssertEqual(session.repCount, 0, "The set in progress is discarded.")
        XCTAssertTrue(effects.contains(.clearFeedback), "Tips and highlights clear.")
        XCTAssertGreaterThan(session.analyzerEpoch, epoch, "A fresh analyzer starts.")
        XCTAssertEqual(session.progress[press.id]?.setReps, [3], "Finished sets are kept.")

        // Curl arms count separately; the count is what both have done.
        _ = session.handle(.framingChanged(reliable), at: 10)
        _ = session.handle(.command(.start), at: 11)
        _ = session.handle(.repCompleted(RepEvent(epoch: session.analyzerEpoch, timestamp: 0, sides: [.left])), at: 12)
        XCTAssertEqual(session.repCount, 0)
        _ = session.handle(.repCompleted(RepEvent(epoch: session.analyzerEpoch, timestamp: 0, sides: [.right])), at: 13)
        XCTAssertEqual(session.repCount, 1)

        _ = session.handle(.command(.selectExercise(press.id)), at: 14)
        XCTAssertEqual(session.currentSetNumber, 2, "The press picks up at its next set.")
    }

    func testLastSetOffersAnotherRoundAndEndingThereSkipsTheSummary() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 3)
        _ = session.handle(.command(.nextSet), at: 4)
        let effects = session.handle(.command(.nextSet), at: 5)
        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertTrue(spoken(effects).last?.hasSuffix("Tap Another Round or End Workout.") ?? false, "Names the real buttons.")
        XCTAssertEqual(session.suggestedCommands, [.anotherRound, .endWorkout])

        _ = session.handle(.command(.anotherRound), at: 6)
        XCTAssertEqual(session.phase, .ready, "Framing is still good, so the next round is ready to start.")
        XCTAssertEqual(session.currentSetNumber, 1)
        XCTAssertEqual(session.progress[press.id]?.setReps.count, 2, "Earlier rounds are kept for the summary.")
        XCTAssertEqual(session.progress[press.id]?.round, 2)

        _ = session.handle(.command(.start), at: 7)
        _ = session.handle(.command(.endWorkout), at: 8)
        XCTAssertFalse(session.endedAfterCompletion, "Ending mid-set still shows the summary.")

        var finished = readySession()
        _ = finished.handle(.command(.start), at: 2)
        _ = finished.handle(.command(.nextSet), at: 3)
        _ = finished.handle(.command(.nextSet), at: 4)
        _ = finished.handle(.command(.nextSet), at: 5)
        _ = finished.handle(.command(.endWorkout), at: 6)
        XCTAssertTrue(finished.endedAfterCompletion, "The card already showed the results.")
    }

    func testOneArmAtATimeSwitchesArmsThenRests() {
        var oneArm = press
        oneArm.perSide = true
        var session = WorkoutSession(exercises: [oneArm], initialExercise: oneArm.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        XCTAssertEqual(session.currentSide, .left)
        _ = session.handle(.command(.start), at: 2)
        let leftDone = session.handle(.command(.nextSet), at: 3)
        XCTAssertEqual(session.phase, .ready, "No rest between arms.")
        XCTAssertEqual(session.currentSide, .right)
        XCTAssertEqual(session.currentSetNumber, 1)
        XCTAssertTrue(spoken(leftDone).last?.contains("Switch to your right arm.") ?? false)

        _ = session.handle(.command(.start), at: 4)
        _ = session.handle(.command(.nextSet), at: 5)
        XCTAssertEqual(session.phase, .resting, "Both arms done: rest.")
        XCTAssertEqual(session.currentSetNumber, 2)
        XCTAssertEqual(session.currentSide, .left)

        for time in stride(from: 100.0, through: 103, by: 1) {
            _ = session.handle(.command(time.truncatingRemainder(dividingBy: 2) == 0 ? .start : .nextSet), at: time)
        }
        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertEqual(session.progress[oneArm.id]?.setReps.count, 4, "One entry per arm per set.")
    }

    func testOneLegAtATimeUsesLegWordingAndKeepsLimbNeutralHistory() {
        let lunge = RearLungeExercise.definition()
        var session = WorkoutSession(exercises: [lunge], initialExercise: lunge.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        XCTAssertEqual(session.currentSide, .left)
        _ = session.handle(.command(.start), at: 2)

        let leftDone = session.handle(.command(.nextSet), at: 3)

        XCTAssertEqual(session.phase, .ready, "No rest between legs.")
        XCTAssertEqual(session.currentSide, .right)
        XCTAssertEqual(session.currentSetNumber, 1)
        XCTAssertTrue(spoken(leftDone).last?.contains(
            "Left leg done, 0 reps. Switch: step back with your right leg."
        ) ?? false)

        _ = session.handle(.command(.start), at: 4)
        _ = session.handle(.command(.nextSet), at: 5)
        XCTAssertEqual(session.phase, .resting, "Both legs done: rest.")
        XCTAssertEqual(session.currentSide, .left)
        XCTAssertEqual(session.progress[lunge.id]?.setReps.count, 2)
    }

    func testFixedRestDoesNotRunBetweenOneArmSides() {
        var oneArm = press
        oneArm.perSide = true
        var session = readySession(exercise: oneArm, settings: WorkoutSettings(restPolicy: .fixed(seconds: 45)))
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 3)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertNil(session.restEndsAt)

        _ = session.handle(.command(.start), at: 4)
        _ = session.handle(.command(.nextSet), at: 5)
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.restEndsAt, 50)
    }

    func testGlobalHoldToStartOffRequiresStartCommandAndLeavesAirSquatUnchanged() {
        let noHoldSettings = WorkoutSettings(startByHolding: false)
        var pressSession = readySession(settings: noHoldSettings)
        _ = pressSession.handle(.startPositionChanged(true), at: 2)
        _ = pressSession.handle(.tick, at: 4)
        XCTAssertEqual(pressSession.phase, .ready)
        XCTAssertNil(pressSession.startHoldProgress(at: 4))
        _ = pressSession.handle(.command(.start), at: 5)
        XCTAssertEqual(pressSession.phase, .exercising)

        let squat = AirSquatExercise.definition()
        var squatSession = readySession(exercise: squat)
        _ = squatSession.handle(.startPositionChanged(true), at: 2)
        _ = squatSession.handle(.tick, at: 4)
        XCTAssertEqual(squatSession.phase, .ready, "Air squat already opts out of hold-to-start.")
        _ = squatSession.handle(.command(.start), at: 5)
        XCTAssertEqual(squatSession.phase, .exercising)
    }

    func testSavedSetRestsThenSelectsTheNextExerciseWithoutCounting() {
        let curl = HammerCurlExercise.definition()
        let plan = WorkoutPlan(name: "Upper Body", items: [
            WorkoutPlanItem(id: UUID(), exerciseID: press.id, sets: 1, targetReps: 2...2),
            WorkoutPlanItem(id: UUID(), exerciseID: curl.id, sets: 1, targetReps: 3...3)
        ])
        let reliable = FramingStatus(isReliable: true, guidance: nil)
        var session = WorkoutSession(exercises: [press, curl], initialExercise: nil, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(reliable), at: 1)
        XCTAssertEqual(session.exercise?.autoCompleteReps, 2, "The Saved Set's reps apply for this workout.")
        XCTAssertEqual(press.autoCompleteReps, 10, "The exercise's own default is unchanged.")
        XCTAssertEqual(session.planPositionLabel, "Exercise 1 of 2")

        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 3)
        let effects = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 4)
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.exerciseID, curl.id, "The next exercise is selected during rest.")
        XCTAssertTrue(session.isRestingBeforeNextExercise)
        XCTAssertTrue(spoken(effects).last?.contains("complete. Up next: hammer curl, 1 set of 3. Rest up.") ?? false)
        XCTAssertEqual(session.planRecords[plan.items[0].id]?.outcome, .completed)

        _ = session.handle(.tick, at: 4 + Double(press.restSeconds) + 1)
        XCTAssertEqual(session.phase, .framing, "Rest ends in the next exercise's setup.")
        _ = session.handle(.framingChanged(reliable), at: 100)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(session.isCounting, "Counting waits for a start.")

        _ = session.handle(.command(.start), at: 101)
        for time in 102...104 { _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: Double(time)) }
        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertEqual(session.planRecords[plan.items[1].id]?.outcome, .completed)
    }

    func testRepEventMetadataUpdatesOnlyWhenDisplayedRepCountIncreases() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)

        _ = session.handle(.repCompleted(RepEvent(epoch: session.analyzerEpoch, timestamp: 3, sides: [.left])), at: 3)
        XCTAssertEqual(session.repEventCount, 0)
        XCTAssertNil(session.lastRepAt)

        _ = session.handle(.repCompleted(RepEvent(epoch: session.analyzerEpoch, timestamp: 4, sides: [.left, .right])), at: 4)
        XCTAssertEqual(session.repEventCount, 1)
        XCTAssertEqual(session.lastRepAt, 4)

        _ = session.handle(.repCompleted(RepEvent(epoch: session.analyzerEpoch - 1, timestamp: 5, sides: [.left, .right])), at: 5)
        XCTAssertEqual(session.repEventCount, 1, "A stale analyzer event isn't a counted rep.")
        XCTAssertEqual(session.lastRepAt, 4)
    }

    func testSavedSetSkipsAndCountsEachOccurrenceSeparately() {
        let curl = HammerCurlExercise.definition()
        let plan = WorkoutPlan(name: "Mixed", items: [
            WorkoutPlanItem(id: UUID(), exerciseID: press.id, sets: 2, targetReps: 8...10),
            WorkoutPlanItem(id: UUID(), exerciseID: curl.id, sets: 1, targetReps: 10...10),
            WorkoutPlanItem(id: UUID(), exerciseID: press.id, sets: 1, targetReps: 12...12)
        ])
        var session = WorkoutSession(exercises: [press, curl], initialExercise: nil, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 3)
        XCTAssertEqual(session.phase, .resting, "Rest between sets of the same exercise is unchanged.")

        _ = session.handle(.command(.selectExercise(curl.id)), at: 4)
        XCTAssertEqual(session.exerciseID, press.id, "Switching away from a Saved Set needs the chooser.")

        _ = session.handle(.command(.nextExercise), at: 5)
        XCTAssertEqual(session.exerciseID, curl.id)
        XCTAssertEqual(session.phase, .framing)
        XCTAssertEqual(session.planRecords[plan.items[0].id], PlanItemRecord(outcome: .skipped, setReps: [0], setWeights: [nil]))

        _ = session.handle(.command(.nextExercise), at: 6)
        XCTAssertEqual(session.exerciseID, press.id)
        XCTAssertEqual(session.currentSetNumber, 1, "The second press occurrence counts its own sets.")
        XCTAssertEqual(session.exercise?.targetReps, 12...12)

        _ = session.handle(.command(.nextExercise), at: 7)
        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertEqual(session.planRecords.values.filter { $0.outcome == .skipped }.count, 3)
    }

    /// Opened and reliably framed, waiting in ready at t = 1.
    private func readySession(
        exercise: ExerciseDefinition? = nil,
        settings: WorkoutSettings = WorkoutSettings()
    ) -> WorkoutSession {
        let selected = exercise ?? press
        var session = WorkoutSession(exercises: [selected], initialExercise: selected.id, settings: settings)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        XCTAssertEqual(session.phase, .ready)
        return session
    }

    private func shrugFrame(time: TimeInterval, armAngleBelowHorizontal: Double) -> PoseFrame {
        let nose = CGPoint(x: 540, y: 500)
        let shoulderY = nose.y + 100
        let radians = armAngleBelowHorizontal * .pi / 180
        let armDX = CGFloat(cos(radians))
        let armDY = CGFloat(sin(radians))
        var joints: [LandmarkType: CGPoint] = [.nose: nose]
        for side in BodySide.allCases {
            let direction: CGFloat = side == .left ? 1 : -1
            let shoulder = CGPoint(x: 540 + direction * 100, y: shoulderY)
            joints[side.shoulder] = shoulder
            joints[side.elbow] = CGPoint(x: shoulder.x + direction * armDX * 120,
                                         y: shoulder.y + armDY * 120)
            joints[side.wrist] = CGPoint(x: shoulder.x + direction * armDX * 220,
                                         y: shoulder.y + armDY * 220)
            joints[side.hip] = CGPoint(x: 540 + direction * 70, y: 900)
        }
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                         timestamp: time)
    }

    private func bridgeFrame(angle: Double, time: TimeInterval) -> PoseFrame {
        let shoulder = CGPoint(x: 100, y: 300)
        let knee = CGPoint(x: 200, y: 300)
        let minorAngle = angle > 180 ? 360 - angle : angle
        let height = 50 / CGFloat(tan(minorAngle * .pi / 360))
        let hip = CGPoint(x: 150, y: angle <= 180 ? 300 + height : 300 - height)
        let joints: [LandmarkType: CGPoint] = [
            .leftShoulder: shoulder, .leftHip: hip, .leftKnee: knee,
            .leftAnkle: CGPoint(x: 230, y: 370)
        ]
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 800, imageHeight: 900),
                         timestamp: time)
    }

    private func rep(epoch: Int) -> RepEvent {
        RepEvent(epoch: epoch, timestamp: 0, sides: [.left, .right])
    }

    private func tips(_ effects: [WorkoutEffect]) -> [CoachingTip] {
        effects.compactMap { effect in
            if case .showTip(let tip) = effect { return tip }
            return nil
        }
    }

    private func spoken(_ effects: [WorkoutEffect]) -> [String] {
        effects.compactMap { effect in
            if case .speak(let utterance) = effect { return utterance.text }
            return nil
        }
    }
}
