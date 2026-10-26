import XCTest
@testable import PostureAnalysisApp

/// Every analyzer says why it let a rep attempt go, so a recording shows whether form or tracking lost the rep.
final class RepRejectionTests: XCTestCase {
    private let rate = 10.0

    func testTheGuideDemonstrationCountsWithoutRejections() {
        for exercise in ExerciseCatalog.all {
            let run = analyze(exercise, loops: 2)
            XCTAssertGreaterThan(run.reps, 0, "\(exercise.id.rawValue): the demonstration counts.")
            XCTAssertEqual(run.rejections, [], "\(exercise.id.rawValue): a clean demonstration is never rejected.")
        }
    }

    func testATrackingGapPartwayThroughARepSaysSo() {
        for exercise in ExerciseCatalog.all {
            let baseline = analyze(exercise, loops: 2)
            guard let firstRep = baseline.firstRepTime else { continue }
            // Drop 0.6 s just before the first rep would have counted, while the attempt is underway.
            let run = analyze(exercise, loops: 2, dropping: (firstRep - 0.9)...(firstRep - 0.3))
            let attempts = Self.attemptsPerRep(exercise)
            XCTAssertEqual(run.rejections.map(\.side).sorted(by: Self.sideOrder), Self.expectedSides(exercise),
                           "\(exercise.id.rawValue): one report per lost attempt: \(run.rejections)")
            for gap in run.rejections {
                guard case .trackingGap(let seconds, let maximum, let stage) = gap.reason else {
                    XCTFail("\(exercise.id.rawValue): \(gap.reason)")
                    continue
                }
                XCTAssertGreaterThan(seconds, maximum)
                XCTAssertNotEqual(stage, .atStart, "\(exercise.id.rawValue): nothing is reported for a gap at the start.")
            }
            XCTAssertEqual(baseline.reps - run.reps, attempts, "\(exercise.id.rawValue): exactly the interrupted rep is lost.")
        }
    }

    func testCountingStoppingPartwayThroughARepSaysSo() {
        for exercise in ExerciseCatalog.all {
            let baseline = analyze(exercise, loops: 2)
            guard let firstRep = baseline.firstRepTime else { continue }
            let run = analyze(exercise, loops: 2, countingOff: (firstRep - 0.4)...(firstRep + 1))
            XCTAssertEqual(run.rejections.map(\.side).sorted(by: Self.sideOrder), Self.expectedSides(exercise),
                           "\(exercise.id.rawValue): one report per lost attempt: \(run.rejections)")
            XCTAssertEqual(baseline.reps - run.reps, Self.attemptsPerRep(exercise), "\(exercise.id.rawValue): exactly that rep is lost.")
            XCTAssertTrue(run.rejections.allSatisfy { $0.reason == .countingStopped(stage: .moving)
                || $0.reason == .countingStopped(stage: .reachedEnd) },
                          "\(exercise.id.rawValue): \(run.rejections)")
        }
    }

    func testSwitchingToTheOtherSidePartwayThroughARepSaysSo() {
        let sideOn: [ExerciseDefinition] = [DumbbellRowExercise.definition(), TricepsExtensionExercise.definition(),
                                             GluteBridgeExercise.definition(), RearLungeExercise.definition(),
                                             StiffLegDeadliftExercise.definition()]
        for exercise in sideOn {
            guard let firstRep = analyze(exercise, loops: 2).firstRepTime else {
                XCTFail("\(exercise.id.rawValue): the demonstration counts.")
                continue
            }
            // The figure turns around partway through the first rep, so the analyzer must follow the other side.
            let run = analyze(exercise, loops: 2, mirroredFrom: firstRep - 0.6)
            let switches = run.rejections.filter { if case .sideSwitched = $0.reason { true } else { false } }
            XCTAssertEqual(switches.count, 1, "\(exercise.id.rawValue): \(run.rejections)")
            XCTAssertNotEqual(switches.first?.reason, .sideSwitched(stage: .atStart))
            XCTAssertFalse(run.rejections.contains { if case .trackingGap = $0.reason { true } else { false } },
                           "\(exercise.id.rawValue): one report for one lost attempt.")
        }
    }

    func testAShrugHeldAtTheTopTooLongSaysItsReferenceExpired() {
        let exercise = DumbbellShrugExercise.definition()
        let keyframes = exercise.guide.motion.keyframes
        let top = keyframes[0].moveDuration + keyframes[0].holdDuration + keyframes[1].moveDuration + 0.05
        let analyzer = exercise.makeAnalyzer(1)
        var rejections: [RepRejection] = []
        let hold = DumbbellShrugConfiguration.standard.referenceTimeout + 1
        for index in 0...Int((top + hold) * rate) {
            let time = Double(index) / rate
            let frame = ReadyPoseFixtures.demoFrame(exercise, motionTime: min(time, top), at: time)
            rejections += analyzer.process(frame, counting: true).rejections
        }
        XCTAssertEqual(rejections.map(\.reason), [.referenceExpired(stage: .reachedEnd)])
    }

    func testAPushUpThatComesBackTooFastSaysHowFast() {
        let analyzer = PushUpAnalyzer(epoch: 1)
        var rejections: [RepRejection] = []
        var reps = 0
        let exercise = PushUpExercise.definition()
        // The guide's push-up at three times speed, sampled at 30 Hz: deep and complete, but too quick.
        for index in 0...240 {
            let time = Double(index) / 30
            let analysis = analyzer.process(ReadyPoseFixtures.demoFrame(exercise, motionTime: time * 3, at: time), counting: true)
            reps += analysis.repEvents.count
            rejections += analysis.rejections
        }
        XCTAssertEqual(reps, 0)
        let tooFast = rejections.compactMap { rejection -> (TimeInterval, TimeInterval)? in
            guard case .tooFast(let duration, let minimum) = rejection.reason else { return nil }
            return (duration, minimum)
        }
        XCTAssertFalse(tooFast.isEmpty, "\(rejections)")
        for (duration, minimum) in tooFast { XCTAssertLessThan(duration, minimum) }
    }

    func testAPressWithOneArmShortOfTheTopSaysWhichArmGotThere() {
        let exercise = ShoulderPressExercise.definition()
        let analyzer = exercise.makeAnalyzer(1)
        var rejections: [RepRejection] = []
        for index in 0...120 {
            let time = Double(index) / rate
            var frame = ReadyPoseFixtures.demoFrame(exercise, motionTime: time, at: time)
            // The right wrist stays at the start height while the left presses.
            let start = ReadyPoseFixtures.demoFrame(exercise, motionTime: 0, at: time)
            for joint in [LandmarkType.rightElbow, .rightWrist] { frame.pose.landmarks[joint] = start.pose.landmarks[joint] }
            rejections += analyzer.process(frame, counting: true).rejections
        }
        XCTAssertTrue(rejections.contains { $0.reason == .partialEnd(reached: [.left]) }, "\(rejections)")
    }

    func testRecordingsWriteEachReasonWithItsNumbers() throws {
        func line(_ rejection: RepRejection) throws -> [String: Any] {
            let data = Data(WorkoutSessionLines.rejection(rejection).serialized.utf8)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let tooFast = try line(RepRejection(timestamp: 81.5, reason: .tooFast(duration: 0.6234, minimum: 0.8)))
        XCTAssertEqual(tooFast["reason"] as? String, "tooFast")
        XCTAssertEqual(tooFast["duration"] as? Double, 0.623)
        XCTAssertEqual(tooFast["minimum"] as? Double, 0.8)
        XCTAssertEqual(tooFast["ts"] as? Double, 81.5)
        XCTAssertNil(tooFast["side"], "Whole-body exercises have no side.")

        let gap = try line(RepRejection(timestamp: 3, side: .left,
                                        reason: .trackingGap(seconds: 0.9, maximum: 0.28, stage: .reachedEnd)))
        XCTAssertEqual(gap["side"] as? String, "left")
        XCTAssertEqual(gap["stage"] as? String, "reachedEnd")
        XCTAssertEqual(gap["seconds"] as? Double, 0.9)

        let partial = try line(RepRejection(timestamp: 3, reason: .partialEnd(reached: [.right])))
        XCTAssertEqual(partial["reached"] as? [String], ["right"])
    }

    func testNothingIsReportedWhenAnAttemptHadNotLeftTheStart() {
        XCTAssertNil(RepRejection.lost(at: 1, .trackingGap(seconds: 1, maximum: 0.28, stage: .atStart)))
        XCTAssertNil(RepRejection.lost(at: 1, .countingStopped(stage: .atStart)))
        XCTAssertNotNil(RepRejection.lost(at: 1, .countingStopped(stage: .moving)))
        XCTAssertEqual(RepAttemptStage.of(reachedEnd: false, zones: [.bottom, .middle]), .moving)
        XCTAssertEqual(RepAttemptStage.of(reachedEnd: false, zones: [.bottom]), .atStart)
        XCTAssertEqual(RepAttemptStage.of(reachedEnd: true, zones: [.bottom]), .reachedEnd)
    }

    // MARK: - Running the demonstration

    private struct Run {
        var reps = 0
        var firstRepTime: TimeInterval?
        var rejections: [RepRejection] = []
    }

    /// Attempts one interrupted rep loses: one per arm when arms count separately.
    private static func attemptsPerRep(_ exercise: ExerciseDefinition) -> Int {
        expectedSides(exercise).count
    }

    /// Each arm once when arms count separately; otherwise one report for the whole body.
    private static func expectedSides(_ exercise: ExerciseDefinition) -> [BodySide?] {
        exercise.countsArmsIndependently ? BodySide.allCases.map(Optional.some) : [nil]
    }

    private static func sideOrder(_ a: BodySide?, _ b: BodySide?) -> Bool {
        (a?.rawValue ?? "") < (b?.rawValue ?? "")
    }

    /// The demonstration at 10 Hz for `loops` loops, optionally with frames removed, counting off for a while, or the
    /// figure turned around from some time on.
    private func analyze(_ exercise: ExerciseDefinition, loops: Int,
                         dropping dropped: ClosedRange<TimeInterval>? = nil,
                         countingOff: ClosedRange<TimeInterval>? = nil,
                         mirroredFrom: TimeInterval? = nil) -> Run {
        let analyzer = exercise.makeAnalyzer(1)
        var run = Run()
        let end = exercise.guide.motion.duration * Double(loops)
        for index in 0...Int(end * rate) {
            let time = Double(index) / rate
            if let dropped, dropped.contains(time) { continue }
            let counting = !(countingOff?.contains(time) ?? false)
            let mirrored = mirroredFrom.map { time >= $0 } ?? false
            let frame = ReadyPoseFixtures.demoFrame(exercise, motionTime: time, at: time, mirrored: mirrored)
            let analysis = analyzer.process(frame, counting: counting)
            if !analysis.repEvents.isEmpty, run.firstRepTime == nil { run.firstRepTime = time }
            run.reps += analysis.repEvents.count
            run.rejections += analysis.rejections
        }
        return run
    }
}
