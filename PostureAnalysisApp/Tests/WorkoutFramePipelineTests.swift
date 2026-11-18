import XCTest
@testable import PostureAnalysisApp

@MainActor
final class WorkoutFramePipelineTests: XCTestCase {
    func testGuideDemonstrationHasScaleInvariantEventsAndRepCount() {
        let motion = ShoulderPressExercise.definition().guide.motion
        let base = run(motion, scale: 1)

        for scale in [CGFloat(0.5), 2] {
            let scaled = run(motion, scale: scale)
            XCTAssertEqual(scaled.events, base.events, "Reducer events should not depend on pixel scale.")
            XCTAssertEqual(scaled.repCount, base.repCount)
        }
        XCTAssertEqual(base.repCount, 3)
    }

    func testTiltIsReportedOnlyAfterExistingDebounce() {
        var pipeline = WorkoutFramePipeline(exercise: ShoulderPressExercise.definition())

        XCTAssertNil(pipeline.processTiltSample(pitchDegrees: 20, at: 0))
        XCTAssertNil(pipeline.processTiltSample(pitchDegrees: 20, at: 0.99))
        XCTAssertEqual(pipeline.processTiltSample(pitchDegrees: 20, at: 1), .phoneTiltChanged(true))
    }

    func testChangingViewRebuildsAnalyzerWithoutCompletingOldRep() {
        let exercise = ShoulderPressExercise.definition()
        let motion = exercise.guide.motion
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)

        for index in 0...15 {
            _ = pipeline.process(frame: frame(motion: motion, at: Double(index) / 10), at: Double(index) / 10)
        }
        var sideView = exercise
        sideView.cameraView = .side
        pipeline.exerciseChanged(to: sideView, analyzerEpoch: 2)

        var events: [WorkoutEvent] = []
        let end = motion.duration
        for index in 16...Int(end * 10) {
            let time = Double(index) / 10
            events += pipeline.process(frame: frame(motion: motion, at: time), at: time).events
        }

        XCTAssertFalse(events.contains { if case .repCompleted = $0 { true } else { false } })
    }

    func testStanceDetectorDoesNotRunForASingleViewExercise() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise)
        pipeline.collectsDiagnostics = true

        let output = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0), at: 0)

        XCTAssertNil(output.diagnostics?.stance)
        XCTAssertFalse(output.events.contains { if case .stanceObserved = $0 { true } else { false } })
    }

    func testSingleViewExerciseDoesNotBufferRawFramesForViewChanges() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise)

        for index in 0...20 {
            let time = Double(index) / 10
            _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: time), at: time)
        }

        XCTAssertEqual(pipeline.bufferedViewChangeFrameCount, 0)
    }

    func testViewChoiceBufferKeepsOnlyTheStanceWindowAndMargin() {
        let exercise = HammerCurlExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise)

        for index in 0...30 {
            let time = Double(index) / 10
            _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: time), at: time)
        }

        XCTAssertLessThanOrEqual(pipeline.bufferedViewChangeFrameCount, 13)
        XCTAssertGreaterThan(pipeline.bufferedViewChangeFrameCount, 0)
    }

    func testStanceDetectorRunsForAnExerciseWithAViewChoice() {
        let exercise = makeViewChoiceHammerCurl(id: ExerciseID(rawValue: "stance.pipeline"))
        var pipeline = WorkoutFramePipeline(exercise: exercise)
        pipeline.collectsDiagnostics = true
        let raw = frameWithShoulderRatio(0.5, motion: exercise.guide.motion, at: 0)

        let output = pipeline.process(frame: raw, at: 0)

        XCTAssertEqual(output.diagnostics?.stance, .facing)
    }

    func testSameIdViewChangePrimesFramingAndKeepsCountingAtTheNewEpoch() throws {
        let exercise = makeViewChoiceHammerCurl(id: ExerciseID(rawValue: "same.id.view"))
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        pipeline.collectsDiagnostics = true

        for index in 0...6 {
            let time = Double(index) / 10
            _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: time), at: time)
        }
        let sideView = exercise.inView(.side)
        XCTAssertEqual(sideView.id, exercise.id)
        pipeline.exerciseChanged(to: sideView, analyzerEpoch: 2)

        let output = pipeline.process(frame: frame(motion: sideView.guide.motion, at: 0.7), at: 0.7)
        let observation = try XCTUnwrap(output.events.compactMap { event -> FormObservation? in
            guard case .formObserved(let value) = event else { return nil }
            return value
        }.first)

        XCTAssertEqual(observation.epoch, 2)
        XCTAssertTrue(output.diagnostics?.framing?.isReliable ?? false)
        XCTAssertTrue(output.diagnostics?.counting ?? false)
        XCTAssertTrue(pipeline.isCounting)
        XCTAssertFalse(output.events.contains {
            guard case .framingChanged(let status) = $0 else { return false }
            return !status.isReliable
        })
    }

    func testSameIdViewChangeWarmsAnalyzerForCurlStartingOnTheFirstLiveFrame() {
        let front = HammerCurlExercise.definition()
        let side = front.inView(.side)
        var pipeline = WorkoutFramePipeline(exercise: front, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)

        for index in 0...12 {
            let time = Double(index) / 10
            let bottom = frame(motion: front.guide.motion, sampledAt: 0, at: time)
            _ = pipeline.process(frame: bottom, at: time)
        }

        XCTAssertGreaterThanOrEqual(pipeline.bufferedViewChangeFrameCount, 10)
        pipeline.exerciseChanged(to: side, analyzerEpoch: 2)

        var repCount = 0
        for index in 0...24 {
            let time = 1.3 + Double(index) / 10
            let poseTime = 1.5 + Double(index) / 10
            let output = pipeline.process(
                frame: frame(motion: side.guide.motion, sampledAt: poseTime, at: time), at: time
            )
            repCount += output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
        }

        XCTAssertEqual(repCount, 1, "The buffered bottom lets the first live curl continue.")
    }

    func testCurlStartedDuringStanceHoldContinuesAfterTheViewSwitch() {
        let front = HammerCurlExercise.definition()
        let side = front.inView(.side)
        var pipeline = WorkoutFramePipeline(exercise: front, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)

        for index in 0...10 {
            let time = Double(index) / 10
            let poseTime = time < 0.5 ? 0 : 1.0 + time - 0.5
            _ = pipeline.process(
                frame: frame(motion: front.guide.motion, sampledAt: poseTime, at: time), at: time
            )
        }

        pipeline.exerciseChanged(to: side, analyzerEpoch: 2)
        var repCount = 0
        for index in 0...23 {
            let time = 1.1 + Double(index) / 10
            let poseTime = 1.6 + Double(index) / 10
            let output = pipeline.process(
                frame: frame(motion: side.guide.motion, sampledAt: poseTime, at: time), at: time
            )
            repCount += output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
        }

        XCTAssertEqual(repCount, 1, "A curl already in progress continues on the new analyzer.")
    }

    func testOldViewRepCountedDuringHoldIsNotCountedAgainWhenFramesWarmNewView() {
        let front = HammerCurlExercise.definition()
        let side = front.inView(.side)
        var pipeline = WorkoutFramePipeline(exercise: front, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        let holdCurl: [(TimeInterval, TimeInterval)] = [
            (0, 0), (0.1, 0), (0.2, 1.5), (0.3, 1.7), (0.4, 1.9),
            (0.5, 2.1), (0.6, 2.3), (0.7, 2.8), (0.8, 3.2), (0.9, 3.6), (1, 3.9)
        ]
        var frontRepEvents = 0
        for (time, poseTime) in holdCurl {
            let output = pipeline.process(
                frame: frame(motion: front.guide.motion, sampledAt: poseTime, at: time), at: time
            )
            frontRepEvents += output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
        }
        XCTAssertEqual(frontRepEvents, 2, "The old view counted the rep before the switch, one event per arm.")

        pipeline.exerciseChanged(to: side, analyzerEpoch: 2)
        var sideRepEvents = 0
        for index in 0...24 {
            let time = 1.1 + Double(index) / 10
            let poseTime = 1.5 + Double(index) / 10
            let output = pipeline.process(
                frame: frame(motion: side.guide.motion, sampledAt: poseTime, at: time), at: time
            )
            sideRepEvents += output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
        }

        // The side view credits both arms with one event.
        XCTAssertEqual(sideRepEvents, 1, "The replayed rep is silent, and the next live rep counts once.")
    }

    func testRepCreditedByTheOldViewJustBeforeASwitchIsNotCreditedAgainByTheWarmedView() {
        let front = HammerCurlExercise.definition()
        let side = front.inView(.side)
        var pipeline = WorkoutFramePipeline(exercise: front, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        func repEvents(_ output: WorkoutFramePipeline.FrameOutput) -> Int {
            output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
        }

        // Forearm elevations in degrees. At -47 the wrist is past the front view's start line (ratio -0.65 of
        // the upper arm) but short of side-on's (-0.73 of the forearm, which needs -0.8), so the views disagree.
        let curl: [Double] = [-90, -90, -90, -90, -90, -90, -20, 30, 50, 50, 50, 0, -47, -47, -47]
        var time: TimeInterval = 0
        var frontRepEvents = 0
        for elevation in curl where frontRepEvents == 0 {
            frontRepEvents += repEvents(pipeline.process(frame: curlFrame(forearmElevation: elevation, at: time),
                                                         at: time))
            time += 0.1
        }
        XCTAssertEqual(frontRepEvents, 2, "The front view credited the curl at -47 degrees, one event per arm.")

        // Switch on the crediting frame, then straighten the arms and let them hang.
        pipeline.exerciseChanged(to: side, analyzerEpoch: 2)
        var sideRepEvents = 0
        for _ in 0..<12 {
            sideRepEvents += repEvents(pipeline.process(frame: curlFrame(forearmElevation: -90, at: time), at: time))
            time += 0.1
        }

        XCTAssertEqual(sideRepEvents, 0, "The warmed side view never credits the curl the front view counted.")
    }

    func testTurningFrontToSideOnMidSetNeverLosesFraming() {
        let turn = TurnPlayer(exercise: HammerCurlExercise.definition())
        turn.play(seconds: 1) { turn.front(at: $0) }
        XCTAssertTrue(turn.pipeline.isCounting, "Front framing is reliable before the turn.")
        let turnStart = turn.outputs.count

        turn.play(seconds: 0.3) { self.withShoulderRatio(0.4, turn.front(at: $0)) }
        turn.play(until: { $0.settled == .sideOn }, limit: 2) { turn.side(at: $0) }
        XCTAssertEqual(turn.observation.settled, .sideOn, "Holding side-on settles the stance.")
        // The reducer switches views on the settled stance; the coach hands the pipeline the side-on definition.
        turn.pipeline.exerciseChanged(to: turn.exercise.inView(.side), analyzerEpoch: 2)
        turn.play(seconds: 1) { turn.side(at: $0) }

        let during = turn.outputs[turnStart...]
        XCTAssertTrue(during.contains { $0.diagnostics?.stance == .unclear }, "The turn passes through a 3/4 stance.")
        XCTAssertFalse(during.contains { $0.events.contains(where: Self.isFramingLost) },
                       "Framing was lost during the turn.")
        XCTAssertTrue(during.allSatisfy { $0.diagnostics?.framing?.isReliable == true && $0.diagnostics?.counting == true })
        XCTAssertTrue(turn.pipeline.isCounting)
    }

    func testFramingFollowsTheCurrentViewAgainOnceTurningEnds() throws {
        // Side-on with the view held at front, as with a front lock: the turn is bridged, then framing is lost.
        let turn = TurnPlayer(exercise: HammerCurlExercise.definition())
        turn.play(seconds: 1) { turn.front(at: $0) }
        let turnStart = turn.outputs.count
        turn.play(seconds: 0.3) { self.withShoulderRatio(0.4, turn.front(at: $0)) }
        turn.play(seconds: 2.5) { turn.side(at: $0) }

        let during = turn.outputs[turnStart...]
        let turnEnded = try XCTUnwrap(during.firstIndex { output in
            output.events.contains { if case .stanceObserved(let observation) = $0 { !observation.turning } else { false } }
        }, "Turning ends once the side-on stance settles.")
        let lost = try XCTUnwrap(during.firstIndex { $0.events.contains(where: Self.isFramingLost) },
                                 "The front view loses a side-on body once turning ends.")
        XCTAssertGreaterThan(lost, turnEnded, "Framing held while turning.")
        let delay = turn.times[lost] - turn.times[turnEnded]
        XCTAssertLessThanOrEqual(delay, FramingConfiguration().unreliableAfter + 0.15,
                                 "Normal framing resumes when turning ends.")
        XCTAssertFalse(turn.pipeline.isCounting)
    }

    func testWalkingOutOfViewMidTurnStillLosesFraming() throws {
        let turn = TurnPlayer(exercise: HammerCurlExercise.definition())
        turn.play(seconds: 1) { turn.front(at: $0) }
        turn.play(seconds: 0.4) { self.withShoulderRatio(0.4, turn.front(at: $0)) }
        XCTAssertTrue(turn.observation.turning, "The user is partway through a turn.")
        let leftAt = turn.outputs.count

        turn.play(seconds: 1) { self.emptyFrame(at: $0) }

        let lost = try XCTUnwrap(turn.outputs[leftAt...].firstIndex { $0.events.contains(where: Self.isFramingLost) },
                                 "Leaving the frame loses framing even while turning.")
        XCTAssertLessThanOrEqual(turn.times[lost] - turn.times[leftAt], FramingConfiguration().unreliableAfter + 0.05)
        XCTAssertFalse(turn.pipeline.isCounting)
    }

    func testOcclusionFromTheFirstUnclearFrameOfATurnNeverStopsCounting() {
        // The last complete front frame is at 1.0 and the far arm is hidden from the first three-quarter frame at 1.1,
        // so framing's grace runs out at 1.3, when 1.3 - 1.1 falls just short of the 0.2 s turning debounce.
        let turn = TurnPlayer(exercise: HammerCurlExercise.definition())
        turn.play(seconds: 1.1) { turn.front(at: $0) }
        XCTAssertTrue(turn.pipeline.isCounting, "Front framing is reliable before the turn.")
        let turnStart = turn.outputs.count

        turn.play(seconds: 1) { self.farArmHidden(turn.front(at: $0)) }

        XCTAssertEqual(turn.outputs[turnStart...].first?.diagnostics?.stance, .unclear)
        assertFramingHeld(turn.outputs[turnStart...])
    }

    func testOcclusionAfterADroppedFrameAtTheStartOfATurnNeverStopsCounting() {
        // A dropped frame puts the first three-quarter frame at 1.15, so framing's grace runs out at 1.3 with only
        // 0.15 s of turn evidence: the turn must be bridged before the debounce confirms it.
        let turn = TurnPlayer(exercise: HammerCurlExercise.definition())
        turn.play(seconds: 1.1) { turn.front(at: $0) }
        let turnStart = turn.outputs.count

        for time in [1.15, 1.3, 1.4, 1.5, 1.6, 1.7] {
            turn.feed(farArmHidden(turn.front(at: time)))
        }

        XCTAssertEqual(turn.outputs[turnStart...].first?.diagnostics?.stance, .unclear)
        assertFramingHeld(turn.outputs[turnStart...])
    }

    func testThresholdJitterWithAHiddenArmLosesFramingOnceTheTurnBudgetRunsOut() throws {
        // The far arm stays hidden while the shoulder ratio flickers either side of the facing threshold. Each unclear
        // frame suggests a turn that the side-on view accepts; each facing frame clears that evidence before the
        // debounce, so turning never starts. The bridge still ends a fixed time after the first evidence.
        let stance = StanceDetector.Configuration.standard
        let budget = stance.turningAfter + stance.turningCap
        let turn = TurnPlayer(exercise: HammerCurlExercise.definition())
        turn.play(seconds: 1) { turn.front(at: $0) }
        XCTAssertTrue(turn.pipeline.isCounting, "Front framing is reliable before the jitter.")
        let jitterStart = turn.outputs.count

        turn.play(seconds: 5) { time in
            let ratio = Int((time * 10).rounded()).isMultiple(of: 2) ? 0.49 : 0.51
            return self.withShoulderRatio(ratio, self.without([.rightElbow, .rightWrist], turn.front(at: time)))
        }

        let jitter = turn.outputs[jitterStart...]
        XCTAssertEqual(jitter.first?.diagnostics?.stance, .unclear)
        XCTAssertFalse(jitter.contains { $0.events.contains { if case .stanceObserved = $0 { true } else { false } } },
                       "Turning never starts.")
        let firstEvidence = turn.times[jitterStart]
        let lost = try XCTUnwrap(jitter.firstIndex { $0.events.contains(where: Self.isFramingLost) },
                                 "The front view loses the hidden arm once the turn's budget runs out.")
        assertFramingHeld(turn.outputs[jitterStart..<lost])
        XCTAssertGreaterThanOrEqual(turn.times[lost] - firstEvidence, budget, "Framing held until the budget ran out.")
        XCTAssertLessThanOrEqual(turn.times[lost] - firstEvidence, budget + FramingConfiguration().unreliableAfter + 0.15,
                                 "Normal framing loss follows the budget.")
        XCTAssertTrue(turn.outputs[lost...].allSatisfy { $0.diagnostics?.framing?.isReliable == false },
                      "Flickering evidence doesn't bring framing back.")
        XCTAssertFalse(turn.pipeline.isCounting)

        // Facing the phone with both arms in view settles the stance, so the next turn is bridged again.
        turn.play(seconds: 1) { turn.front(at: $0) }
        XCTAssertTrue(turn.pipeline.isCounting, "Front framing recovers.")
        let nextTurn = turn.outputs.count
        turn.play(seconds: 1) { self.farArmHidden(turn.front(at: $0)) }
        assertFramingHeld(turn.outputs[nextTurn...])
    }

    func testTurningSideOnToFrontWithTheFarWristHiddenAcrossTheSwitchNeverLosesFraming() {
        let turn = TurnPlayer(exercise: HammerCurlExercise.definition(), view: .side)
        turn.play(seconds: 1) { turn.side(at: $0) }
        XCTAssertTrue(turn.pipeline.isCounting, "Side-on framing is reliable before the turn.")
        let turnStart = turn.outputs.count

        // Facing the phone again, the far wrist stays behind the body until just after the view switches.
        let facing = { (time: TimeInterval) in self.without([.rightWrist], turn.front(at: time)) }
        turn.play(until: { $0.settled == .facing }, limit: 2, facing)
        XCTAssertEqual(turn.observation, StanceDetector.Observation(settled: .facing, turning: true),
                       "The view switches as the stance settles, before turning clears.")
        // The reducer switches views on the settled stance; the coach hands the pipeline the front definition.
        turn.pipeline.exerciseChanged(to: turn.exercise, analyzerEpoch: 2)
        turn.play(seconds: 0.2, facing)
        turn.play(seconds: 1) { turn.front(at: $0) }

        assertFramingHeld(turn.outputs[turnStart...])
    }

    func testAViewChangeKeepsFramingsGraceButStillLosesSomeoneWhoLeaves() throws {
        let turn = TurnPlayer(exercise: HammerCurlExercise.definition(), view: .side)
        turn.play(seconds: 1) { turn.side(at: $0) }
        let switchAt = turn.outputs.count
        turn.pipeline.exerciseChanged(to: turn.exercise, analyzerEpoch: 2)

        // The first frame in the new view shows no complete arm, which no view accepts: one missed frame within the
        // grace, as at any other moment.
        turn.play(seconds: 0.1) { self.without([.leftWrist, .rightWrist], turn.front(at: $0)) }
        turn.play(seconds: 1) { turn.front(at: $0) }
        assertFramingHeld(turn.outputs[switchAt...])

        let leftAt = turn.outputs.count
        turn.play(seconds: 1) { self.emptyFrame(at: $0) }
        let lost = try XCTUnwrap(turn.outputs[leftAt...].firstIndex { $0.events.contains(where: Self.isFramingLost) },
                                 "Leaving the frame still loses framing.")
        XCTAssertLessThanOrEqual(turn.times[lost] - turn.times[leftAt], FramingConfiguration().unreliableAfter + 0.05)
        XCTAssertFalse(turn.pipeline.isCounting)
    }

    func testAViewChangeMidTurnPrimesFramingFromAnyViewTheTurnAccepts() {
        // Framing wasn't reliable yet when the view changed to front. The first frame shows a three-quarter stance
        // with one complete arm, the side-on view's requirement, which the turn accepts.
        let exercise = HammerCurlExercise.definition()
        func switchedToFront() -> WorkoutFramePipeline {
            var pipeline = WorkoutFramePipeline(exercise: exercise.inView(.side), analyzerEpoch: 1, isCounting: true)
            pipeline.setSessionPhase(.exercising)
            pipeline.collectsDiagnostics = true
            pipeline.exerciseChanged(to: exercise, analyzerEpoch: 2)
            return pipeline
        }

        var turning = switchedToFront()
        let primed = turning.process(frame: farArmHidden(startFrame(exercise, at: 0)), at: 0)
        XCTAssertEqual(primed.diagnostics?.stance, .unclear)
        XCTAssertEqual(primed.diagnostics?.framing?.isReliable, true, "Priming accepts the turn's alternatives.")

        // Still side-on, nothing suggests a turn, so only the front view's own requirement could prime it.
        var sideOn = switchedToFront()
        let unprimed = sideOn.process(frame: ReadyPoseFixtures.demoFrame(exercise.inView(.side), motionTime: 0, at: 0),
                                      at: 0)
        XCTAssertEqual(unprimed.diagnostics?.stance, .sideOn)
        XCTAssertEqual(unprimed.diagnostics?.framing?.isReliable, false)
    }

    func testStanceDetectionAndTurningAlternativesStayOffWhenDisabled() {
        let exercise = HammerCurlExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        pipeline.collectsDiagnostics = true
        pipeline.detectsStance = false
        var outputs: [WorkoutFramePipeline.FrameOutput] = []
        for index in 0...10 {
            let time = Double(index) / 10
            outputs.append(pipeline.process(frame: startFrame(exercise, at: time), at: time))
        }
        for index in 11...20 {
            let time = Double(index) / 10
            outputs.append(pipeline.process(frame: farArmHidden(startFrame(exercise, at: time)), at: time))
        }

        XCTAssertTrue(outputs.allSatisfy { $0.diagnostics?.stance == nil }, "No stance is read.")
        XCTAssertFalse(outputs.contains { $0.events.contains { if case .stanceObserved = $0 { true } else { false } } })
        XCTAssertTrue(outputs.contains { $0.events.contains(where: Self.isFramingLost) },
                      "Without turning alternatives, the front view loses the hidden arm.")
        XCTAssertFalse(pipeline.isCounting)
    }

    func testIdChangeStillResetsFramingAndSeedsTheNewExerciseView() {
        let exercise = makeViewChoiceHammerCurl(id: ExerciseID(rawValue: "old.choice"))
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        pipeline.collectsDiagnostics = true

        var settledSide = false
        for index in 0...12 {
            let time = Double(index) / 10
            let output = pipeline.process(frame: frameWithShoulderRatio(0.25, motion: exercise.guide.motion, at: time), at: time)
            settledSide = settledSide || output.events.contains {
                guard case .stanceObserved(let observation) = $0 else { return false }
                return observation.settled == .sideOn
            }
        }
        XCTAssertTrue(settledSide)
        let newExercise = makeViewChoiceHammerCurl(id: ExerciseID(rawValue: "new.choice"))
        pipeline.exerciseChanged(to: newExercise, analyzerEpoch: 2)

        let first = pipeline.process(frame: frameWithShoulderRatio(0.5, motion: newExercise.guide.motion, at: 1.3), at: 1.3)
        XCTAssertTrue(first.events.contains {
            guard case .framingChanged(let status) = $0 else { return false }
            return !status.isReliable
        })
        XCTAssertTrue(first.events.contains {
            guard case .formObserved(let observation) = $0 else { return false }
            return observation.epoch == 2
        })

        var stanceEvents: [StanceDetector.Observation] = []
        for index in 14...25 {
            let time = Double(index) / 10
            let output = pipeline.process(frame: frameWithShoulderRatio(0.5, motion: newExercise.guide.motion, at: time), at: time)
            stanceEvents += output.events.compactMap { event in
                guard case .stanceObserved(let observation) = event else { return nil }
                return observation
            }
        }
        XCTAssertTrue(stanceEvents.isEmpty, "A new exercise starts settled at its configured front view.")
    }

    func testStanceEventsAreLastAndOnlyEmittedWhenObservationChanges() {
        let exercise = makeViewChoiceHammerCurl(id: ExerciseID(rawValue: "stance.events"))
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.collectsDiagnostics = true

        let turning = pipeline.process(frame: frameWithShoulderRatio(0.4, motion: exercise.guide.motion, at: 0), at: 0)
        let stillTurning = pipeline.process(frame: frameWithShoulderRatio(0.4, motion: exercise.guide.motion, at: 0.1), at: 0.1)
        let beganTurning = pipeline.process(frame: frameWithShoulderRatio(0.4, motion: exercise.guide.motion, at: 0.2), at: 0.2)
        let unchanged = pipeline.process(frame: frameWithShoulderRatio(0.4, motion: exercise.guide.motion, at: 0.3), at: 0.3)
        let returned = pipeline.process(frame: frameWithShoulderRatio(0.5, motion: exercise.guide.motion, at: 0.4), at: 0.4)
        let stillReturned = pipeline.process(frame: frameWithShoulderRatio(0.5, motion: exercise.guide.motion, at: 0.711), at: 0.711)

        XCTAssertFalse(turning.events.contains { if case .stanceObserved = $0 { true } else { false } })
        XCTAssertFalse(stillTurning.events.contains { if case .stanceObserved = $0 { true } else { false } })
        XCTAssertEqual(beganTurning.events.last, WorkoutEvent.stanceObserved(StanceDetector.Observation(settled: .facing, turning: true)))
        XCTAssertFalse(unchanged.events.contains { if case .stanceObserved = $0 { true } else { false } })
        XCTAssertFalse(returned.events.contains { if case .stanceObserved = $0 { true } else { false } })
        XCTAssertEqual(stillReturned.events.last, WorkoutEvent.stanceObserved(StanceDetector.Observation(settled: .facing, turning: false)))
    }

    func testChangingExerciseRebuildsAnalyzerWithoutCompletingOldRep() {
        let oldExercise = ShoulderPressExercise.definition()
        let newExercise = HammerCurlExercise.definition()
        let motion = oldExercise.guide.motion
        var pipeline = WorkoutFramePipeline(exercise: oldExercise, analyzerEpoch: 1, isCounting: true)

        for index in 0...15 {
            _ = pipeline.process(frame: frame(motion: motion, at: Double(index) / 10), at: Double(index) / 10)
        }
        pipeline.exerciseChanged(to: newExercise, analyzerEpoch: 2)

        var events: [WorkoutEvent] = []
        for index in 16...Int(motion.duration * 10) {
            let time = Double(index) / 10
            events += pipeline.process(frame: frame(motion: motion, at: time), at: time).events
        }

        XCTAssertFalse(events.contains { if case .repCompleted = $0 { true } else { false } })
    }

    func testTricepsMetricsUseUpperArmFallbackWithoutHipOrWrist() throws {
        let shoulder = CGPoint(x: 400, y: 300)
        let elbow = CGPoint(x: 400, y: 420)
        var pipeline = WorkoutFramePipeline(exercise: TricepsExtensionExercise.definition())

        // Read the first frame so no smoothing has been applied yet.
        let output = pipeline.process(frame: measurementFrame([.leftShoulder: shoulder,
                                                                .leftElbow: elbow], at: 0), at: 0)
        let metrics = try XCTUnwrap(output.guideMetrics)
        let upperArmLength = ArmGeometry.distance(shoulder, elbow)

        XCTAssertEqual(GuideMetrics.forearmToUpperArm,
                       GuideMetrics.forearmToTorso / GuideMetrics.upperArmToTorso, accuracy: 0.01)
        XCTAssertEqual(metrics.upperArm, upperArmLength, accuracy: 0.01)
        XCTAssertEqual(metrics.forearm, upperArmLength * GuideMetrics.forearmToUpperArm, accuracy: 0.01)
    }

    func testRowMetricsUseMeasuredArmWhenHipIsOutOfFrame() throws {
        let shoulder = CGPoint(x: 320, y: 260)
        let elbow = CGPoint(x: 400, y: 340)
        let wrist = CGPoint(x: 460, y: 430)
        var pipeline = WorkoutFramePipeline(exercise: DumbbellRowExercise.definition())

        // Read the first frame so no smoothing has been applied yet.
        let output = pipeline.process(frame: measurementFrame([.leftShoulder: shoulder,
                                                                .leftElbow: elbow,
                                                                .leftWrist: wrist], at: 0), at: 0)
        let metrics = try XCTUnwrap(output.guideMetrics)

        XCTAssertEqual(metrics.upperArm, ArmGeometry.distance(shoulder, elbow), accuracy: 0.01)
        XCTAssertEqual(metrics.forearm, ArmGeometry.distance(elbow, wrist), accuracy: 0.01)
    }

    func testRowMetricsKeepTorsoReferenceWhenHipIsVisible() throws {
        let shoulder = CGPoint(x: 320, y: 260)
        let hip = CGPoint(x: 320, y: 460)
        let elbow = CGPoint(x: 390, y: 300)
        let wrist = CGPoint(x: 450, y: 380)
        var pipeline = WorkoutFramePipeline(exercise: DumbbellRowExercise.definition())

        // Read the first frame so no smoothing has been applied yet.
        let output = pipeline.process(frame: measurementFrame([.leftShoulder: shoulder,
                                                                .leftHip: hip,
                                                                .leftElbow: elbow,
                                                                .leftWrist: wrist], at: 0), at: 0)
        let metrics = try XCTUnwrap(output.guideMetrics)
        let torsoLength = ArmGeometry.distance(shoulder, hip)
        let upperArmLength = ArmGeometry.distance(shoulder, elbow)
        let forearmLength = ArmGeometry.distance(elbow, wrist)
        let expectedUpperArm = GuideMetrics.plausibleTorsoRatio.contains(upperArmLength / torsoLength)
            ? upperArmLength : torsoLength * GuideMetrics.upperArmToTorso
        let expectedForearm = GuideMetrics.plausibleTorsoRatio.contains(forearmLength / torsoLength)
            ? forearmLength : torsoLength * GuideMetrics.forearmToTorso

        XCTAssertEqual(metrics.upperArm, expectedUpperArm, accuracy: 0.01)
        XCTAssertEqual(metrics.forearm, expectedForearm, accuracy: 0.01)
    }

    func testSideBodyMetricsReferenceUsesOnlyReadyJoints() throws {
        let angles = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        let motion = ArmMotion(keyframes: [
            ArmKeyframe(angles: angles, moveDuration: 0, holdDuration: 0.5, stepIndex: 0),
            ArmKeyframe(angles: angles, moveDuration: 1, holdDuration: 0.5, stepIndex: 1,
                        shape: FigureShape(torsoPitch: 60, hipShift: 1, hipDrop: 0.2))
        ])
        let required: [LandmarkType] = [.leftShoulder, .leftHip, .leftKnee, .leftAnkle]
        let landmarks = Dictionary(uniqueKeysWithValues: required.compactMap { joint in
            ExerciseDemoFigureView.sideFigureJoints[joint].map { point in
                (joint, Landmark(type: joint, normalizedLocation: .zero,
                                 imageLocation: point, confidence: 0.9))
            }
        })
        let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 300, imageHeight: 470), timestamp: 0)
        let pipeline = WorkoutFramePipeline(exercise: TricepsExtensionExercise.definition())

        let reference = try XCTUnwrap(pipeline.metricsReference(frame, confidence: 0.8,
                                                               cameraView: .side, motion: motion))
        let hip = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftHip])
        let knee = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftKnee])
        let ankle = try XCTUnwrap(ExerciseDemoFigureView.sideFigureJoints[.leftAnkle])
        let legLength = ArmGeometry.distance(hip, knee) + ArmGeometry.distance(knee, ankle)
        XCTAssertEqual(reference.length, legLength, accuracy: 0.001)
        XCTAssertEqual(reference.length * reference.upperArm,
                       ExerciseDemoFigureView.upperArm, accuracy: 0.001)
        XCTAssertEqual(reference.length * reference.forearm,
                       ExerciseDemoFigureView.forearm, accuracy: 0.001)
    }

    func testLyingSideBridgeMetricsUseTheLyingGuideLegProportions() throws {
        let bridge = GluteBridgeExercise.definition()
        let hip = CGPoint(x: 250, y: 700)
        let knee = CGPoint(x: 340, y: 760)
        let ankle = CGPoint(x: 430, y: 700)
        let frame = measurementFrame([
            .leftShoulder: CGPoint(x: 170, y: 700),
            .leftHip: hip,
            .leftKnee: knee,
            .leftAnkle: ankle
        ], at: 0)
        let pipeline = WorkoutFramePipeline(exercise: bridge)

        let reference = try XCTUnwrap(pipeline.metricsReference(frame, confidence: 0.8,
                                                               cameraView: .lyingSide,
                                                               motion: bridge.guide.motion))
        let legLength = ArmGeometry.distance(hip, knee) + ArmGeometry.distance(knee, ankle)
        let guideLegLength = ExerciseDemoFigureView.lyingSideThigh + ExerciseDemoFigureView.lyingSideShin

        XCTAssertEqual(reference.length, legLength, accuracy: 0.001)
        XCTAssertEqual(reference.upperArm, ExerciseDemoFigureView.upperArm / guideLegLength, accuracy: 0.001)
        XCTAssertEqual(reference.forearm, ExerciseDemoFigureView.forearm / guideLegLength, accuracy: 0.001)
    }

    func testRowMetricsUseTypicalForearmWhenMeasuredForearmIsImplausible() throws {
        let shoulder = CGPoint(x: 320, y: 260)
        let elbow = CGPoint(x: 420, y: 260)
        let wrist = CGPoint(x: 420, y: 460)
        var pipeline = WorkoutFramePipeline(exercise: DumbbellRowExercise.definition())

        // Read the first frame so no smoothing has been applied yet.
        let output = pipeline.process(frame: measurementFrame([.leftShoulder: shoulder,
                                                                .leftElbow: elbow,
                                                                .leftWrist: wrist], at: 0), at: 0)
        let metrics = try XCTUnwrap(output.guideMetrics)
        let upperArmLength = ArmGeometry.distance(shoulder, elbow)

        XCTAssertEqual(metrics.upperArm, upperArmLength, accuracy: 0.01)
        XCTAssertEqual(metrics.forearm, upperArmLength * GuideMetrics.forearmToUpperArm, accuracy: 0.01)
    }

    func testNoPoseClearsOverlayAndReportsFramingLost() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0), at: 0)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0.6), at: 0.6)

        let noPose = PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: 0.91)
        let output = pipeline.process(frame: noPose, at: 0.91)

        XCTAssertNil(output.overlay)
        XCTAssertTrue(output.events.contains {
            if case .framingChanged(let status) = $0 { return !status.isReliable }
            return false
        })
    }

    func testGhostFitOverlayCalibratesAndSurvivesBriefDropout() throws {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise)

        for index in 0...6 {
            let time = Double(index) / 10
            let output = pipeline.process(frame: frame(motion: exercise.guide.motion, at: time), at: time)
            if index < 6 {
                XCTAssertNil(output.ghostFitOverlay)
            } else {
                XCTAssertNotNil(output.ghostFitOverlay)
            }
        }

        let lastAvailable = try XCTUnwrap(pipeline.ghostFitOverlay)
        for index in 7...11 {
            let time = Double(index) / 10
            let output = pipeline.process(frame: emptyFrame(at: time), at: time)
            XCTAssertNil(output.overlay)
            XCTAssertEqual(output.ghostFitOverlay, lastAvailable)
        }

        for index in 12...15 {
            let time = Double(index) / 10
            XCTAssertEqual(pipeline.process(frame: emptyFrame(at: time), at: time).ghostFitOverlay, lastAvailable)
        }
        XCTAssertNil(pipeline.process(frame: emptyFrame(at: 1.6), at: 1.6).ghostFitOverlay)
    }

    func testResetTrackingClearsGhostFitOverlay() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = calibratedPipeline(for: exercise)
        XCTAssertNotNil(pipeline.ghostFitOverlay)

        _ = pipeline.resetTracking()

        XCTAssertNil(pipeline.ghostFitOverlay)
    }

    func testChangingExerciseClearsGhostFitOverlay() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = calibratedPipeline(for: exercise)
        XCTAssertNotNil(pipeline.ghostFitOverlay)

        pipeline.exerciseChanged(to: HammerCurlExercise.definition(), analyzerEpoch: 2)

        XCTAssertNil(pipeline.ghostFitOverlay)
    }

    func testFramingReliabilityChangesAnalyzerCountingOnThatFrame() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0), at: 0)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 0.6), at: 0.6)
        XCTAssertTrue(pipeline.isCounting)

        let empty = PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: 0.91)
        _ = pipeline.process(frame: empty, at: 0.91)
        XCTAssertFalse(pipeline.isCounting)

        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 1), at: 1)
        _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: 1.6), at: 1.6)
        XCTAssertTrue(pipeline.isCounting)
    }

    func testPushUpCountsThroughABriefBottomFramingLoss() {
        let exercise = PushUpExercise.definition()
        let motion = exercise.guide.motion
        let up = motion.sample(at: 0).angles
        let middle = motion.sample(at: 1.75).angles
        let down = motion.sample(at: 2.5).angles
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        pipeline.collectsDiagnostics = true
        var repCount = 0
        var countingFrames: [Bool] = []

        func send(_ angles: ArmAngles, at time: TimeInterval, shoulderConfidence: Double = 0.9) {
            let output = pipeline.process(frame: floorPushUpFrame(angles, at: time,
                                                                   shoulderConfidence: shoulderConfidence), at: time)
            repCount += output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
            if let diagnostics = output.diagnostics { countingFrames.append(diagnostics.counting) }
        }

        for index in 0...6 { send(up, at: Double(index) / 10) }
        send(middle, at: 0.7)
        send(down, at: 0.8)
        for index in 9...14 { send(down, at: Double(index) / 10, shoulderConfidence: 0.2) }
        send(down, at: 1.5)
        send(down, at: 1.6)
        send(middle, at: 1.7)
        send(up, at: 1.8)
        send(up, at: 1.9)

        XCTAssertEqual(repCount, 1)
        XCTAssertEqual(countingFrames.count, 20)
        XCTAssertTrue(countingFrames.allSatisfy { $0 }, "The 0.7 s bottom loss stays inside push-up framing grace.")
    }

    func testPushUpFramingGraceStopsAfterTheConfiguredBottomGapLimit() {
        let exercise = PushUpExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        pipeline.collectsDiagnostics = true
        for index in 0...6 {
            let time = Double(index) / 10
            _ = pipeline.process(frame: floorPushUpFrame(exercise.guide.motion.sample(at: 0).angles, at: time), at: time)
        }

        let withinGrace = pipeline.process(frame: floorPushUpFrame(exercise.guide.motion.sample(at: 0).angles,
                                                                    at: 1.3, shoulderConfidence: 0.2), at: 1.3)
        let afterLimit = pipeline.process(frame: floorPushUpFrame(exercise.guide.motion.sample(at: 0).angles,
                                                                  at: 1.5, shoulderConfidence: 0.2), at: 1.5)

        XCTAssertEqual(withinGrace.diagnostics?.counting, true)
        XCTAssertEqual(afterLimit.diagnostics?.counting, false)
    }

    func testPushUpKeepsCountingThroughAFaceDownHold() {
        let held = faceDownPushUp(shoulderConfidence: 0.33, armConfidence: 0.75)
        XCTAssertEqual(held.reps, 1)
        XCTAssertEqual(held.counting.count, 67)
        XCTAssertTrue(held.counting.allSatisfy { $0 }, "Counting stays on through the five-second hold.")
        XCTAssertTrue(held.framing.dropFirst(7).allSatisfy { $0.isReliable && $0.guidance == nil },
                      "Framing gives no lost-tracking guidance during the hold.")

        for (shoulders, arms) in [(0.33, 0.59), (0.29, 0.75)] {
            let lost = faceDownPushUp(shoulderConfidence: shoulders, armConfidence: arms)
            XCTAssertEqual(lost.reps, 0, "shoulders \(shoulders), arms \(arms)")
            XCTAssertTrue(lost.counting.contains(false), "shoulders \(shoulders), arms \(arms)")
        }
    }

    func testPushUpKeepsCountingWhenTheFaceStaysDownThroughLockout() {
        let pressed = faceDownPushUp(shoulderConfidence: 0.33, armConfidence: 0.75, faintLockout: 0.5)
        XCTAssertEqual(pressed.reps, 1)
        XCTAssertTrue(pressed.rejections.isEmpty, "\(pressed.rejections)")
        XCTAssertEqual(pressed.counting.count, 74)
        XCTAssertTrue(pressed.counting.allSatisfy { $0 }, "Counting stays on while the face stays down at Up.")
        XCTAssertTrue(pressed.framing.dropFirst(7).allSatisfy { $0.isReliable && $0.guidance == nil },
                      "\(pressed.framing)")
    }

    /// Framing's supported-shoulder references restart with each new analyzer and survive a camera restart, as the
    /// analyzer's do, so counting and framing accept the same faint shoulders.
    func testPushUpFramingKeepsShoulderReferencesInStepWithTheAnalyzer() {
        // A new analyzer just before the face-down Down has seen no confident arm, and neither has framing.
        let newAnalyzer = faceDownPushUp(shoulderConfidence: 0.33, armConfidence: 0.75,
                                         control: (index: 10, control: .resetAnalyzer(epoch: 2)))
        XCTAssertEqual(newAnalyzer.reps, 0)
        // Lost 0.8 s after the last confident frame, through the faint rise.
        XCTAssertTrue(newAnalyzer.framing.dropFirst(18).prefix(44).allSatisfy {
            !$0.isReliable && $0.guidance == .stepBackFloor
        }, "\(newAnalyzer.framing)")
        XCTAssertTrue(newAnalyzer.counting.contains(false))

        // A camera restart resets framing's reliability but keeps the references, as the analyzer keeps its own.
        let restarted = faceDownPushUp(shoulderConfidence: 0.33, armConfidence: 0.75,
                                       control: (index: 10, control: .resetTracking))
        XCTAssertEqual(restarted.reps, 1)
        XCTAssertEqual(restarted.framing.dropFirst(10).first?.isReliable, false)
        XCTAssertTrue(restarted.framing.dropFirst(17).allSatisfy { $0.isReliable && $0.guidance == nil },
                      "\(restarted.framing)")
    }

    func testLateralSideRoomFeedsFramingReliabilityFromPipeline() {
        let exercise = LateralRaiseExercise.definition()
        let closePose: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 680, y: 600), .leftElbow: CGPoint(x: 680, y: 825),
            .leftWrist: CGPoint(x: 680, y: 1050), .rightShoulder: CGPoint(x: 400, y: 600),
            .rightElbow: CGPoint(x: 400, y: 825), .rightWrist: CGPoint(x: 400, y: 1050)
        ]
        var closePipeline = WorkoutFramePipeline(exercise: exercise)
        var closeStatuses: [FramingStatus] = []
        for index in 0...8 {
            let time = Double(index) / 10
            let output = closePipeline.process(frame: measurementFrame(closePose, at: time), at: time)
            closeStatuses += output.events.compactMap { event in
                guard case .framingChanged(let status) = event else { return nil }
                return status
            }
        }
        XCTAssertTrue(closeStatuses.contains {
            !$0.isReliable && $0.guidance == .stepBackSideRoom
        })
        XCTAssertFalse(closeStatuses.contains(where: \.isReliable))

        let fartherPose: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 630, y: 600), .leftElbow: CGPoint(x: 630, y: 750),
            .leftWrist: CGPoint(x: 630, y: 900), .rightShoulder: CGPoint(x: 450, y: 600),
            .rightElbow: CGPoint(x: 450, y: 750), .rightWrist: CGPoint(x: 450, y: 900)
        ]
        var fartherPipeline = WorkoutFramePipeline(exercise: exercise)
        var fartherStatuses: [FramingStatus] = []
        for index in 0...6 {
            let time = Double(index) / 10
            let output = fartherPipeline.process(frame: measurementFrame(fartherPose, at: time), at: time)
            fartherStatuses += output.events.compactMap { event in
                guard case .framingChanged(let status) = event else { return nil }
                return status
            }
        }
        XCTAssertTrue(fartherStatuses.contains { $0.isReliable && $0.guidance == nil })
    }

    func testAWristLimitFlowsThroughThePipelineAndPushUpsSetNone() throws {
        let points: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 637, y: 787), .rightShoulder: CGPoint(x: 443, y: 787),
            .leftElbow: CGPoint(x: 637, y: 1090), .rightElbow: CGPoint(x: 443, y: 1090),
            .leftWrist: CGPoint(x: 637, y: 1402), .rightWrist: CGPoint(x: 443, y: 1402)
        ]
        let pose = measurementFrame(points, at: 0)
        var limited = PushUpExercise.definition()
        limited.maximumWristHeightFraction = 0.64
        func status(_ exercise: ExerciseDefinition) -> FramingStatus? {
            var pipeline = WorkoutFramePipeline(exercise: exercise)
            return pipeline.process(frame: pose, at: 0).events.compactMap { event -> FramingStatus? in
                guard case .framingChanged(let status) = event else { return nil }
                return status
            }.last
        }

        XCTAssertEqual(try XCTUnwrap(status(limited), "Limited framing reported a status.").guidance,
                       .movePhoneFartherFloor, "An exercise's wrist limit reaches framing through the pipeline.")
        XCTAssertNil(try XCTUnwrap(status(PushUpExercise.definition()), "Push-up framing reported a status.").guidance,
                     "Push-ups set no wrist limit, so low hands don't hold setup.")
        XCTAssertNil(try XCTUnwrap(status(ShoulderPressExercise.definition()),
                                   "Shoulder press framing reported a status.").guidance)
    }

    func testLateralRaiseCalibratedGhostAndDumbbellsFitAtAcceptedSideRoomDistance() throws {
        let exercise = LateralRaiseExercise.definition()
        let imageSize = CGSize(width: 1080, height: 1920)
        let containerSize = imageSize
        let points: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 630, y: 600), .leftElbow: CGPoint(x: 630, y: 750),
            .leftWrist: CGPoint(x: 630, y: 900), .rightShoulder: CGPoint(x: 450, y: 600),
            .rightElbow: CGPoint(x: 450, y: 750), .rightWrist: CGPoint(x: 450, y: 900)
        ]
        let frame = measurementFrame(points, at: 0)
        let overlay = WorkoutOverlayState(
            imageSize: imageSize,
            joints: frame.pose.landmarks.mapValues { OverlayJoint(location: $0.normalizedLocation, isStale: false) },
            segments: [],
            endPositionSides: [],
            pose: frame.pose
        )
        let metrics = GuideMetrics(upperArm: 150, forearm: 150)
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let shoulderEdgeRoom: CGFloat = 450
        let requiredEdgeRoom = try XCTUnwrap(exercise.sideroomArmLengths) * 300 + 0.02 * imageSize.width
        XCTAssertGreaterThan(shoulderEdgeRoom, requiredEdgeRoom)

        for (index, keyframe) in exercise.guide.motion.keyframes.enumerated() {
            let figure = try XCTUnwrap(WorkoutGhostGeometry.calibrated(
                fitOverlay: overlay,
                metrics: metrics,
                motion: exercise.guide.motion,
                cameraView: exercise.cameraView,
                containerSize: containerSize,
                sample: exercise.guide.motion.sample(of: keyframe)
            ), "Keyframe \(index) did not calibrate")
            XCTAssertTrue(figure.isCalibrated)
            XCTAssertEqual(figure.dumbbells.count, 2, "Keyframe \(index) must include both dumbbells")
            for (joint, point) in figure.joints {
                XCTAssertTrue(imageBounds.contains(point), "Keyframe \(index) \(joint) fell outside the image: \(point)")
            }
            if let nose = figure.joints[.nose] {
                let headRadius = figure.bodyScale * ExerciseDemoFigureView.canvasSize.width * 0.05
                let headBounds = CGRect(x: nose.x - headRadius,
                                        y: nose.y - headRadius * 1.2,
                                        width: headRadius * 2,
                                        height: headRadius * 2.4)
                XCTAssertTrue(imageBounds.contains(headBounds), "Keyframe \(index) head fell outside the image")
            }
            for (dumbbellIndex, dumbbell) in figure.dumbbells.enumerated() {
                let bounds = DumbbellDrawing.bounds(elbow: dumbbell.elbow, wrist: dumbbell.wrist,
                                                    forearmLength: figure.forearmLength)
                XCTAssertTrue(imageBounds.contains(bounds),
                              "Keyframe \(index) dumbbell \(dumbbellIndex) fell outside the image: \(bounds)")
            }
        }
    }

    func testOffscreenWristsKeepSetFramingReliableAndDoNotEnterOverlay() {
        let exercise = ShoulderPressExercise.definition()
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        var repCount = 0
        var sawDropout = false
        var becameReliable = false

        for index in 0...Int(exercise.guide.motion.duration * 10) {
            let time = Double(index) / 10
            let raw = pressFrame(exercise.guide.motion, at: time)
            let output = pipeline.process(frame: raw, at: time)
            repCount += output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
            XCTAssertTrue(pipeline.isCounting)
            for event in output.events {
                guard case .framingChanged(let status) = event else { continue }
                if status.isReliable {
                    becameReliable = true
                } else if becameReliable {
                    XCTFail("Framing became unreliable during the set at \(time)s.")
                }
            }

            if raw.pose[.leftWrist] == nil {
                sawDropout = true
                XCTAssertNil(output.overlay?.pose[.leftWrist])
                XCTAssertNil(output.overlay?.pose[.rightWrist])
                XCTAssertTrue(output.overlay?.joints[.leftWrist]?.isStale ?? true)
                XCTAssertTrue(output.overlay?.joints[.rightWrist]?.isStale ?? true)
            }
        }

        XCTAssertTrue(sawDropout)
        XCTAssertTrue(becameReliable)
        XCTAssertGreaterThan(repCount, 0, "Completed wrist estimates should keep the rep cycle alive.")
    }

    func testOffscreenWristsStillLoseFramingBeforeAndAtReady() {
        let exercise = ShoulderPressExercise.definition()
        for phase in [WorkoutPhase.framing, .ready] {
            var pipeline = WorkoutFramePipeline(exercise: exercise)
            pipeline.setSessionPhase(phase)
            var becameReliable = false
            var lostReliability = false
            for index in 0...Int(exercise.guide.motion.duration * 10) {
                let time = Double(index) / 10
                let output = pipeline.process(frame: pressFrame(exercise.guide.motion, at: time), at: time)
                for event in output.events {
                    guard case .framingChanged(let status) = event else { continue }
                    if status.isReliable {
                        becameReliable = true
                    } else if becameReliable {
                        lostReliability = true
                    }
                }
            }
            XCTAssertTrue(becameReliable, "\(phase) framing should first become reliable.")
            XCTAssertTrue(lostReliability, "Raw wrist loss must then make \(phase) framing unreliable.")
        }
    }

    func testDiagnosticsAreAttachedOnlyWhenARecordingAsksForThem() {
        let exercise = ShoulderPressExercise.definition()
        let motion = exercise.guide.motion
        var plain = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        XCTAssertNil(plain.process(frame: frame(motion: motion, at: 0), at: 0).diagnostics)

        var recorded = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        recorded.collectsDiagnostics = true
        let output = recorded.process(frame: frame(motion: motion, at: 0), at: 0)
        let diagnostics = output.diagnostics
        XCTAssertNotNil(diagnostics?.framing)
        XCTAssertEqual(diagnostics?.counting, true)
        XCTAssertEqual(diagnostics?.analysis?.readings, output.readings)
        XCTAssertEqual(diagnostics?.analyzedFrame.timestamp, 0)
    }

    func testControlsApplyExactlyLikeTheDirectCalls() {
        let press = ShoulderPressExercise.definition()
        let curl = HammerCurlExercise.definition()
        var direct = WorkoutFramePipeline()
        var controlled = WorkoutFramePipeline()

        direct.setSessionPhase(.ready)
        direct.exerciseChanged(to: press, analyzerEpoch: 1)
        direct.setCounting(true)
        direct.resetAnalyzer(epoch: 2)
        direct.exerciseChanged(to: curl, analyzerEpoch: 2)
        let directEvents = direct.resetTracking()

        var controlledEvents: [WorkoutEvent] = []
        for control: WorkoutFramePipeline.Control in [.sessionPhase(.ready), .exercise(press, analyzerEpoch: 1),
                                                       .counting(true), .resetAnalyzer(epoch: 2),
                                                       .exercise(curl, analyzerEpoch: 2), .resetTracking] {
            controlledEvents = controlled.apply(control)
        }

        XCTAssertEqual(controlled.controlState, direct.controlState)
        XCTAssertEqual(controlledEvents, directEvents)
        XCTAssertEqual(controlled.controlState.exerciseID, curl.id)
        XCTAssertEqual(controlled.controlState.analyzerEpoch, 2)
    }

    func testRepeatingAControlLeavesTheStateUnchanged() {
        var pipeline = WorkoutFramePipeline(exercise: ShoulderPressExercise.definition(), analyzerEpoch: 3)
        let before = pipeline.controlState

        _ = pipeline.apply(.exercise(ShoulderPressExercise.definition(), analyzerEpoch: 3))
        _ = pipeline.apply(.resetAnalyzer(epoch: 3))
        _ = pipeline.apply(.counting(false))

        XCTAssertEqual(pipeline.controlState, before)
    }

    private func run(_ motion: ArmMotion, scale: CGFloat) -> (events: [WorkoutEvent], repCount: Int) {
        let exercise = ShoulderPressExercise.definition()
        var session = WorkoutSession(exercises: [exercise], initialExercise: exercise.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 0)
        _ = session.handle(.command(.start), at: 0)
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: session.analyzerEpoch, isCounting: true)
        var events: [WorkoutEvent] = []

        for index in 0..<(Int(motion.duration * 10) * 3) {
            let time = Double(index) / 10
            let output = pipeline.process(frame: frame(motion: motion, at: time, scale: scale), at: time)
            events += output.events
            for event in output.events {
                if case .repCompleted = event {
                    _ = session.handle(event, at: time)
                }
            }
        }
        return (events, session.repCount)
    }

    private func calibratedPipeline(for exercise: ExerciseDefinition) -> WorkoutFramePipeline {
        var pipeline = WorkoutFramePipeline(exercise: exercise)
        for index in 0...6 {
            let time = Double(index) / 10
            _ = pipeline.process(frame: frame(motion: exercise.guide.motion, at: time), at: time)
        }
        return pipeline
    }

    private func frame(motion: ArmMotion, at time: TimeInterval, scale: CGFloat = 1) -> PoseFrame {
        let sample = motion.sample(at: time)
        let reference = ExerciseDemoFigureView.pose(for: sample.angles, legs: sample.legs,
                                                     forearmPlane: motion.forearmPlane)
        let width = 1080 * scale
        let height = 1920 * scale
        let landmarks = Dictionary(uniqueKeysWithValues: reference.jointLocations.map { type, point in
            let pixel = CGPoint(x: point.x * scale, y: point.y * scale)
            return (type, Landmark(type: type,
                                   normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                    pixel: pixel, imageWidth: width, imageHeight: height),
                                   imageLocation: pixel,
                                   confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height), timestamp: time)
    }

    /// A front-view hammer-curl pose with hanging upper arms and the given forearm elevation in degrees.
    private func curlFrame(forearmElevation: Double, at time: TimeInterval) -> PoseFrame {
        let motion = ArmMotion(keyframes: [
            ArmKeyframe(angles: ArmAngles(upperArmElevation: -90, forearmElevation: forearmElevation),
                        moveDuration: 0, holdDuration: 1, stepIndex: 0)
        ], forearmPlane: .sagittal)
        return frame(motion: motion, sampledAt: 0, at: time)
    }

    private func frame(motion: ArmMotion, sampledAt poseTime: TimeInterval, at time: TimeInterval) -> PoseFrame {
        let sampled = frame(motion: motion, at: poseTime)
        return PoseFrame(pose: sampled.pose, timestamp: time)
    }

    private func frameWithShoulderRatio(_ ratio: Double, motion: ArmMotion, at time: TimeInterval) -> PoseFrame {
        withShoulderRatio(ratio, frame(motion: motion, at: time))
    }

    /// `frame` with its shoulders moved to span `ratio` torso lengths around their midpoint.
    private func withShoulderRatio(_ ratio: Double, _ frame: PoseFrame) -> PoseFrame {
        var result = frame
        guard let left = result.point(.leftShoulder, minimumConfidence: 0.3),
              let right = result.point(.rightShoulder, minimumConfidence: 0.3),
              let leftHip = result.point(.leftHip, minimumConfidence: 0.3),
              let rightHip = result.point(.rightHip, minimumConfidence: 0.3) else { return result }
        let shoulderMidpoint = ArmGeometry.midpoint(left, right)
        let hipMidpoint = ArmGeometry.midpoint(leftHip, rightHip)
        let torsoLength = ArmGeometry.distance(shoulderMidpoint, hipMidpoint)
        guard torsoLength > 1 else { return result }
        let width = torsoLength * CGFloat(ratio)
        let target = [CGPoint(x: shoulderMidpoint.x - width / 2, y: shoulderMidpoint.y),
                      CGPoint(x: shoulderMidpoint.x + width / 2, y: shoulderMidpoint.y)]

        for (joint, point) in zip([LandmarkType.leftShoulder, .rightShoulder], target) {
            guard var landmark = result.pose[joint] else { return result }
            landmark.imageLocation = point
            landmark.normalizedLocation = CoordinateConverter.imagePixelToNormalized(
                pixel: point, imageWidth: result.pose.imageWidth, imageHeight: result.pose.imageHeight)
            result.pose.landmarks[joint] = landmark
        }
        return result
    }

    private func pressFrame(_ motion: ArmMotion, at time: TimeInterval) -> PoseFrame {
        let sample = motion.sample(at: time)
        let reference = ExerciseDemoFigureView.pose(for: sample.angles, legs: sample.legs,
                                                     forearmPlane: motion.forearmPlane)
        let landmarks = Dictionary(uniqueKeysWithValues: reference.jointLocations.compactMap { type, point -> (LandmarkType, Landmark)? in
            let pixel = CGPoint(x: point.x, y: point.y - 50)
            if [.leftWrist, .rightWrist].contains(type), pixel.y < 0 { return nil }
            return (type, Landmark(type: type,
                                   normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                    pixel: pixel, imageWidth: 1080, imageHeight: 1920),
                                   imageLocation: pixel,
                                   confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }

    private func measurementFrame(_ points: [LandmarkType: CGPoint], at time: TimeInterval) -> PoseFrame {
        let width: CGFloat = 1080
        let height: CGFloat = 1920
        let landmarks = Dictionary(uniqueKeysWithValues: points.map { type, pixel in
            (type, Landmark(type: type,
                            normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                pixel: pixel, imageWidth: width, imageHeight: height),
                            imageLocation: pixel,
                            confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height), timestamp: time)
    }

    /// A push-up set at 10 Hz: Up, a confident descent, then a five-second face-down hold and half the press with the
    /// given confidences, then Up.
    /// Frames at 10 Hz: 8 Up, 2 confident descent, 50 face-down Down, 2 face-down rise, and 5 Up. With a
    /// `faintLockout`, 2 confident straight-arm frames a little below Up (elbows at 152°) open the descent, and the
    /// face-down rise goes on through Up for that long. `control` is applied just before the frame at its index.
    private func faceDownPushUp(shoulderConfidence: Double, armConfidence: Double, faintLockout: TimeInterval = 0,
                                control: (index: Int, control: WorkoutFramePipeline.Control)? = nil)
        -> (reps: Int, rejections: [RepRejection], counting: [Bool], framing: [FramingStatus]) {
        let exercise = PushUpExercise.definition()
        let motion = exercise.guide.motion
        let up = motion.sample(at: 0).angles
        let nearUp = ArmAngles(upperArmElevation: -76, forearmElevation: -104)
        let middle = motion.sample(at: 1.75).angles
        let down = motion.sample(at: 2.5).angles
        let lockoutFrames = Int((faintLockout * 10).rounded())
        var pipeline = WorkoutFramePipeline(exercise: exercise, analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        pipeline.collectsDiagnostics = true
        var reps = 0
        var rejections: [RepRejection] = []
        var counting: [Bool] = []
        var framing: [FramingStatus] = []
        var poses: [(angles: ArmAngles, faceDown: Bool)] = []
        for (angles, faceDown, count) in [(up, false, 8), (nearUp, false, lockoutFrames > 0 ? 2 : 0),
                                          (middle, false, 2), (down, true, 50), (middle, true, 2),
                                          (up, true, lockoutFrames), (up, false, 5)] {
            poses += Array(repeating: (angles: angles, faceDown: faceDown), count: count)
        }
        for (index, pose) in poses.enumerated() {
            let time = Double(index) / 10
            if let control, control.index == index { _ = pipeline.apply(control.control) }
            let frame = pose.faceDown
                ? floorPushUpFrame(pose.angles, at: time, shoulderConfidence: shoulderConfidence,
                                   armConfidence: armConfidence)
                : floorPushUpFrame(pose.angles, at: time)
            let output = pipeline.process(frame: frame, at: time)
            reps += output.events.filter { if case .repCompleted = $0 { true } else { false } }.count
            if let diagnostics = output.diagnostics {
                counting.append(diagnostics.counting)
                rejections += diagnostics.analysis?.rejections ?? []
                if let status = diagnostics.framing { framing.append(status) }
            }
        }
        return (reps, rejections, counting, framing)
    }

    private func floorPushUpFrame(_ angles: ArmAngles, at time: TimeInterval,
                                  shoulderConfidence: Double = 0.9, armConfidence: Double = 0.9) -> PoseFrame {
        var joints: [LandmarkType: (CGPoint, Double)] = [:]
        for side in BodySide.allCases {
            guard let hand = ExerciseDemoFigureView.floorHands[side] else { continue }
            let arm = ArmMotion.place(shoulder: .zero, outward: side == .left ? 1 : -1,
                                      upperArm: ExerciseDemoFigureView.upperArm,
                                      forearm: ExerciseDemoFigureView.forearm, angles: angles)
            let shoulder = CGPoint(x: hand.x - arm.wrist.x, y: hand.y - arm.wrist.y)
            let elbow = CGPoint(x: shoulder.x + arm.elbow.x, y: shoulder.y + arm.elbow.y)
            for (joint, point, confidence) in [(side.shoulder, shoulder, shoulderConfidence),
                                                (side.elbow, elbow, armConfidence), (side.wrist, hand, armConfidence)] {
                let pixel = CGPoint(x: point.x + 300, y: point.y + 200)
                joints[joint] = (pixel, confidence)
            }
        }
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, value in
            (type, Landmark(type: type,
                            normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                pixel: value.0, imageWidth: 1080, imageHeight: 1920),
                            imageLocation: value.0, confidence: value.1))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }

    private func emptyFrame(at time: TimeInterval) -> PoseFrame {
        PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }

    private static func isFramingLost(_ event: WorkoutEvent) -> Bool {
        guard case .framingChanged(let status) = event else { return false }
        return !status.isReliable
    }

    /// Framing stayed reliable and the analyzer kept counting on every one of `outputs`.
    private func assertFramingHeld(_ outputs: ArraySlice<WorkoutFramePipeline.FrameOutput>,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(outputs.isEmpty, file: file, line: line)
        XCTAssertFalse(outputs.contains { $0.events.contains(where: Self.isFramingLost) }, "Framing was lost.",
                       file: file, line: line)
        let stopped = outputs.filter { $0.diagnostics?.framing?.isReliable != true || $0.diagnostics?.counting != true }
        XCTAssertTrue(stopped.isEmpty, "Counting stopped at \(stopped.compactMap { $0.diagnostics?.analyzedFrame.timestamp })",
                      file: file, line: line)
    }

    /// The guide's start pose in `exercise`'s camera view.
    private func startFrame(_ exercise: ExerciseDefinition, at time: TimeInterval) -> PoseFrame {
        ReadyPoseFixtures.demoFrame(exercise, motionTime: 0, at: time)
    }

    /// A front frame partway through a turn: a three-quarter stance whose far arm is hidden behind the body.
    private func farArmHidden(_ frame: PoseFrame) -> PoseFrame {
        withShoulderRatio(0.4, without([.rightElbow, .rightWrist], frame))
    }

    /// `frame` without `joints`, as when the body hides them.
    private func without(_ joints: Set<LandmarkType>, _ frame: PoseFrame) -> PoseFrame {
        var result = frame
        for joint in joints { result.pose.landmarks[joint] = nil }
        return result
    }
}

/// A pipeline counting a set of a view-choice exercise, fed the guide's start pose at 10 Hz.
private final class TurnPlayer {
    let exercise: ExerciseDefinition
    private let sideView: ExerciseDefinition
    var pipeline: WorkoutFramePipeline
    private(set) var outputs: [WorkoutFramePipeline.FrameOutput] = []
    private(set) var times: [TimeInterval] = []
    private(set) var observation = StanceDetector.Observation(settled: .facing, turning: false)

    /// `exercise` is the front definition; the set starts in `view`.
    init(exercise: ExerciseDefinition, view: ExerciseCameraView = .front) {
        self.exercise = exercise
        sideView = exercise.inView(.side)
        pipeline = WorkoutFramePipeline(exercise: exercise.inView(view), analyzerEpoch: 1, isCounting: true)
        pipeline.setSessionPhase(.exercising)
        pipeline.collectsDiagnostics = true
        observation = StanceDetector.Observation(settled: view.stance, turning: false)
    }

    func front(at time: TimeInterval) -> PoseFrame {
        ReadyPoseFixtures.demoFrame(exercise, motionTime: 0, at: time)
    }

    func side(at time: TimeInterval) -> PoseFrame {
        ReadyPoseFixtures.demoFrame(sideView, motionTime: 0, at: time)
    }

    func play(seconds: TimeInterval, _ make: (TimeInterval) -> PoseFrame) {
        play(until: { _ in false }, limit: seconds, make)
    }

    /// Feeds frames until `done` holds for the latest stance observation or `limit` seconds pass.
    func play(until done: (StanceDetector.Observation) -> Bool, limit: TimeInterval,
              _ make: (TimeInterval) -> PoseFrame) {
        for _ in 0..<Int((limit * 10).rounded()) where !done(observation) {
            feed(make(Double(times.count) / 10))
        }
    }

    /// Feeds one frame at its own timestamp, for a timeline that isn't a steady 10 Hz.
    func feed(_ frame: PoseFrame) {
        let output = pipeline.process(frame: frame, at: frame.timestamp)
        for case .stanceObserved(let observed) in output.events { observation = observed }
        outputs.append(output)
        times.append(frame.timestamp)
    }
}

private func makeViewChoiceHammerCurl(id: ExerciseID,
                                      cameraView: ExerciseCameraView = .front) -> ExerciseDefinition {
    let base = HammerCurlExercise.definition()
    return ExerciseDefinition(
        id: id,
        displayName: base.displayName,
        presentation: base.presentation,
        spokenName: base.spokenName,
        sets: base.sets,
        targetReps: base.targetReps,
        autoCompleteReps: base.autoCompleteReps,
        targetRangeAnnouncementReps: base.targetRangeAnnouncementReps,
        restSeconds: base.restSeconds,
        requiredJoints: base.requiredJoints,
        focusSegments: base.focusSegments,
        headroomArmLengths: base.headroomArmLengths,
        sideroomArmLengths: base.sideroomArmLengths,
        maximumShoulderSpan: base.maximumShoulderSpan,
        maximumWristHeightFraction: base.maximumWristHeightFraction,
        supportedShoulders: base.supportedShoulders,
        framingUnreliableAfter: base.framingUnreliableAfter,
        centersInFrame: base.centersInFrame,
        countsArmsIndependently: base.countsArmsIndependently,
        setupLine: base.setupLine,
        voiceAliases: base.voiceAliases,
        guide: base.guide,
        coachingCues: base.coachingCues,
        reminders: base.reminders,
        motionEnvelope: base.motionEnvelope,
        cameraView: cameraView,
        anyOfRequiredJoints: base.anyOfRequiredJoints,
        startsByHolding: base.startsByHolding,
        perSide: base.perSide,
        sideLimb: base.sideLimb,
        warnsAboutTilt: base.warnsAboutTilt,
        equipment: base.equipment,
        plantedJoints: base.plantedJoints,
        tracking: base.tracking,
        doseUnit: base.doseUnit,
        makeAnalyzer: { epoch in base.makeAnalyzer(epoch) },
        diagnostics: base.diagnostics,
        reducedRange: base.reducedRange,
        views: [.front, .side],
        buildView: { selectedView in
            makeViewChoiceHammerCurl(id: id, cameraView: selectedView)
        })
}
