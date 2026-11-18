import XCTest
@testable import PostureAnalysisApp

/// Turning between front and side-on during a set, end to end through the coach with real frames and the real
/// pipeline: the set and its reps carry across the turn, counting never stops, and the coach stays quiet about it
/// mid-set (#27).
@MainActor
final class CameraViewTurnTests: XCTestCase {
    private let front = HammerCurlExercise.definition()
    private var side: ExerciseDefinition { front.inView(.side) }
    private let stance = StanceDetector.Configuration.standard

    // MARK: - Turning mid-set

    func testTurningFrontToSideOnMidSetKeepsTheSetAndCounting() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        let setStart = rig.log.count
        let spokenAtStart = rig.spoken.count
        XCTAssertNil(rig.session.cameraViewTag, "Auto shows no tag in the usual view.")

        rig.reps(front, count: 3)
        XCTAssertEqual(rig.session.repCount, 3, "Three front reps count before the turn.")

        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time) }
        rig.play(seconds: stance.holdSeconds + 0.5) { _, time in
            ReadyPoseFixtures.demoFrame(self.side, motionTime: 0, at: time)
        }
        XCTAssertEqual(rig.session.exercise?.cameraView, .side, "Holding side-on switches the view.")
        XCTAssertEqual(rig.session.cameraViewTag, "Side-on", "The HUD tag shows the automatic side-on view.")

        rig.reps(side, count: 2)

        assertSetCarriedOn(rig, from: setStart, spokenFrom: spokenAtStart, reps: 5)
    }

    func testTurningSideOnToFrontMidSetKeepsTheSetAndCounting() throws {
        let rig = TurnRig()
        try rig.startSet(standing: side)
        XCTAssertEqual(rig.session.exercise?.cameraView, .side, "The set starts side-on.")
        XCTAssertEqual(rig.session.cameraViewTag, "Side-on")
        let setStart = rig.log.count
        let spokenAtStart = rig.spoken.count

        rig.reps(side, count: 3)
        XCTAssertEqual(rig.session.repCount, 3, "Three side-on reps count before the turn.")

        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time) }
        rig.play(seconds: stance.holdSeconds + 0.5) { _, time in
            ReadyPoseFixtures.demoFrame(self.front, motionTime: 0, at: time)
        }
        XCTAssertEqual(rig.session.exercise?.cameraView, .front, "Holding a facing stance switches the view.")
        XCTAssertNil(rig.session.cameraViewTag, "The HUD tag clears back in the usual view.")

        rig.reps(front, count: 2)

        assertSetCarriedOn(rig, from: setStart, spokenFrom: spokenAtStart, reps: 5)
    }

    func testSideToFrontThenImmediateCurlCounts() throws {
        let rig = TurnRig()
        try rig.startSet(standing: side)

        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time) }
        rig.play(until: { $0.exercise?.cameraView == .front }, limit: stance.holdSeconds + 0.5) { _, time in
            ReadyPoseFixtures.demoFrame(front, motionTime: 0, at: time)
        }
        XCTAssertEqual(rig.session.exercise?.cameraView, .front)

        rig.immediateCurl(front)

        XCTAssertEqual(rig.session.repCount, 1, "The first front curl after the turn counts.")
    }

    func testFrontToSideThenImmediateNearArmCurlCounts() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)

        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time) }
        rig.play(until: { $0.exercise?.cameraView == .side }, limit: stance.holdSeconds + 0.5) { _, time in
            ReadyPoseFixtures.demoFrame(self.side, motionTime: 0, at: time)
        }
        XCTAssertEqual(rig.session.exercise?.cameraView, .side)

        rig.immediateCurl(side)

        XCTAssertEqual(rig.session.repCount, 1, "The first near-arm curl after the turn counts.")
    }

    func testCurlStartedBeforeTheViewSwitchCountsOnce() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time) }
        rig.play(seconds: 0.5) { _, time in ReadyPoseFixtures.demoFrame(self.side, motionTime: 0, at: time) }
        rig.play(until: { $0.exercise?.cameraView == .side }, limit: stance.holdSeconds + 0.5) { local, time in
            ReadyPoseFixtures.demoFrame(self.side, motionTime: 1.0 + local, at: time)
        }
        XCTAssertEqual(rig.session.exercise?.cameraView, .side)

        rig.continueCurl(side, startingAt: 1.6)

        XCTAssertEqual(rig.session.repCount, 1, "A curl begun during the hold finishes as one rep.")
    }

    func testTurningFrontToSideOnWithTheFarArmHiddenFromTheFirstUnclearFrameKeepsCounting() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        let setStart = rig.log.count
        let spokenAtStart = rig.spoken.count
        rig.reps(front, count: 2)

        // The camera stalls as the turn begins, and the far arm is already behind the body on the first
        // three-quarter frame, so framing's grace runs out before 0.2 s of turn evidence could confirm the turn.
        rig.dropFrames(2)
        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time, hiding: [.rightElbow, .rightWrist]) }
        rig.play(seconds: stance.holdSeconds + 0.5) { _, time in
            ReadyPoseFixtures.demoFrame(self.side, motionTime: 0, at: time)
        }
        XCTAssertEqual(rig.session.exercise?.cameraView, .side, "Holding side-on switches the view.")
        rig.reps(side, count: 1)

        assertSetCarriedOn(rig, from: setStart, spokenFrom: spokenAtStart, reps: 3)
    }

    func testTurningSideOnToFrontWithTheFarWristHiddenAcrossTheSwitchKeepsCounting() throws {
        let rig = TurnRig()
        try rig.startSet(standing: side)
        let setStart = rig.log.count
        let spokenAtStart = rig.spoken.count
        rig.reps(side, count: 2)

        // Facing the phone again, the far wrist stays behind the body until just after the view switches.
        func facing(at time: TimeInterval) -> PoseFrame {
            without([.rightWrist], ReadyPoseFixtures.demoFrame(front, motionTime: 0, at: time))
        }
        rig.play(until: { $0.exercise?.cameraView == .front }, limit: stance.holdSeconds + 0.5) { _, time in
            facing(at: time)
        }
        XCTAssertEqual(rig.session.exercise?.cameraView, .front, "Holding a facing stance switches the view.")
        rig.play(seconds: 0.2) { _, time in facing(at: time) }
        rig.reps(front, count: 1)

        assertSetCarriedOn(rig, from: setStart, spokenFrom: spokenAtStart, reps: 3)
    }

    // MARK: - A curl across the turn

    func testCurlUpFrontTurnHoldingTheTopAndLowerSideOnCountsOnce() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        let setStart = rig.log.count
        let spokenAtStart = rig.spoken.count
        rig.reps(front, count: 1)

        curlUpAndTurnHoldingTheTop(rig, from: front, to: side)
        XCTAssertEqual(rig.session.exercise?.cameraView, .side, "Holding side-on switches the view.")
        XCTAssertEqual(rig.session.repCount, 1, "Nothing counts until the curl is lowered.")

        rig.continueCurl(side, startingAt: Self.topHoldEnd)
        XCTAssertEqual(rig.session.repCount, 2, "The curl counts when it's lowered side-on.")
        rig.play(seconds: 1) { _, time in ReadyPoseFixtures.demoFrame(self.side, motionTime: 0, at: time) }
        XCTAssertEqual(rig.session.repCount, 2, "It counts once.")
        rig.reps(side, count: 1)

        assertSetCarriedOn(rig, from: setStart, spokenFrom: spokenAtStart, reps: 3)
    }

    func testCurlUpSideOnTurnHoldingTheTopAndLowerFacingThePhoneCountsOnce() throws {
        let rig = TurnRig()
        try rig.startSet(standing: side)
        let setStart = rig.log.count
        let spokenAtStart = rig.spoken.count
        rig.reps(side, count: 1)

        curlUpAndTurnHoldingTheTop(rig, from: side, to: front)
        XCTAssertEqual(rig.session.exercise?.cameraView, .front, "Holding a facing stance switches the view.")
        XCTAssertEqual(rig.session.repCount, 1, "Nothing counts until the curl is lowered.")

        rig.continueCurl(front, startingAt: Self.topHoldEnd)
        XCTAssertEqual(rig.session.repCount, 2, "The curl counts when both arms are lowered facing the phone.")
        rig.play(seconds: 1) { _, time in ReadyPoseFixtures.demoFrame(self.front, motionTime: 0, at: time) }
        XCTAssertEqual(rig.session.repCount, 2, "It counts once.")
        rig.reps(front, count: 1)

        assertSetCarriedOn(rig, from: setStart, spokenFrom: spokenAtStart, reps: 3)
    }

    /// The guide's motion reaches the top at 2.0 s and holds it until 2.4 s.
    private static let topHold: TimeInterval = 2.2
    private static let topHoldEnd: TimeInterval = 2.4

    /// Curls up in `from`'s view, then turns through a three-quarter stance and holds the top in `to`'s stance until
    /// the view switches.
    private func curlUpAndTurnHoldingTheTop(_ rig: TurnRig, from: ExerciseDefinition, to: ExerciseDefinition) {
        rig.play(seconds: Self.topHold + 0.1) { local, time in
            ReadyPoseFixtures.demoFrame(from, motionTime: local, at: time)
        }
        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time, motionTime: Self.topHold) }
        rig.play(until: { $0.exercise?.cameraView == to.cameraView }, limit: stance.holdSeconds + 0.5) { _, time in
            ReadyPoseFixtures.demoFrame(to, motionTime: Self.topHold, at: time)
        }
    }

    // MARK: - Partway turns and leaving the frame

    func testAHeldThreeQuarterStanceNeverSwitchesViewsOrLosesTheUser() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        rig.reps(front, count: 1)
        let turnStart = rig.log.count
        let spokenAtTurn = rig.spoken.count

        rig.play(seconds: 5) { _, time in self.threeQuarter(at: time) }

        let turn = rig.log[turnStart...]
        XCTAssertTrue(turn.allSatisfy { $0.view == .front }, "An unclear stance never switches the view.")
        XCTAssertTrue(turn.allSatisfy { $0.phase == .exercising && $0.isCounting },
                      "Counting continues while the whole body is in view.")
        XCTAssertTrue(turn.contains { $0.isTurning }, "Holding the stance reads as turning.")
        XCTAssertFalse(turn.last?.isTurning ?? true, "Turning ends at its cap.")
        XCTAssertEqual(rig.session.repCount, 1)
        XCTAssertFalse(rig.spoken.dropFirst(spokenAtTurn).contains { $0.hasPrefix("I can't see you") },
                       "\(Array(rig.spoken.dropFirst(spokenAtTurn)))")
    }

    func testAThreeQuarterStanceThatHidesAnArmStaysQuietOnlyUntilTheTurningCap() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        rig.reps(front, count: 1)
        let turnStart = rig.log.count
        let turnStartTime = rig.harness.clock.now

        // The far arm disappears behind the body, so the front view loses tracking while the body stays in view.
        rig.play(seconds: 5) { _, time in self.threeQuarter(at: time, hiding: [.rightElbow, .rightWrist]) }

        let turn = rig.log[turnStart...]
        XCTAssertTrue(turn.allSatisfy { $0.view == .front && $0.phase == .exercising })
        let lost = try XCTUnwrap(rig.firstSpoken { $0.hasPrefix("I can't see you") },
                                 "Tracking loss is announced once turning has been capped.")
        let cap = stance.turningAfter + stance.turningCap
        XCTAssertGreaterThanOrEqual(lost.time - turnStartTime, cap - 0.05,
                                    "Nothing is said before the turning cap.")
        // Framing holds while turning, since the near arm is enough for the side-on view, so tracking loss and its
        // grace start at the cap.
        XCTAssertLessThan(lost.time - turnStartTime, cap + FramingConfiguration().unreliableAfter
                          + WorkoutSession.trackingLossGrace + WorkoutCoachModel.tickInterval + 0.15,
                          "The usual tracking-loss prompt follows the cap.")
        XCTAssertEqual(rig.session.repCount, 1)
    }

    func testAStanceFlickeringAtTheFacingThresholdWithAHiddenArmStillAnnouncesTrackingLoss() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        rig.reps(front, count: 1)
        let jitterStart = rig.log.count
        let jitterStartTime = rig.harness.clock.now

        // The far arm stays hidden while the stance reads unclear and facing on alternate frames, so turn evidence
        // keeps appearing and clearing without ever confirming a turn.
        rig.play(seconds: 5) { local, time in
            let unclear = Int((local * 10).rounded()).isMultiple(of: 2)
            return self.threeQuarter(at: time, ratio: stance.facingRatio + (unclear ? -0.01 : 0.01),
                                     hiding: [.rightElbow, .rightWrist])
        }

        let jitter = rig.log[jitterStart...]
        XCTAssertTrue(jitter.allSatisfy { $0.view == .front && $0.phase == .exercising && !$0.isTurning })
        let lost = try XCTUnwrap(rig.firstSpoken { $0.hasPrefix("I can't see you") },
                                 "Tracking loss is announced once the turn's budget runs out.")
        let budget = stance.turningAfter + stance.turningCap
        XCTAssertGreaterThanOrEqual(lost.time - jitterStartTime, budget, "Nothing is said before the turn's budget.")
        XCTAssertLessThan(lost.time - jitterStartTime, budget + FramingConfiguration().unreliableAfter
                          + WorkoutSession.trackingLossGrace + WorkoutCoachModel.tickInterval + 0.25,
                          "The usual tracking-loss prompt follows the budget.")
        XCTAssertFalse(rig.session.isCounting)
        XCTAssertEqual(rig.session.repCount, 1)
    }

    func testWalkingOutOfViewStillAnnouncesTrackingLossAndCountingResumesOnReturn() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        rig.reps(front, count: 1)
        let spokenBeforeLeaving = rig.spoken.count

        // Walking off to the side: the body slides out of the frame over half a second, then nobody is there.
        rig.play(seconds: 0.6) { local, time in
            self.shifted(ReadyPoseFixtures.demoFrame(self.front, motionTime: 0, at: time), by: 1000 * (local + 0.1))
        }
        let emptyStart = rig.harness.clock.now
        rig.play(seconds: 2) { _, time in
            PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: time)
        }

        XCTAssertEqual(rig.session.phase, .exercising)
        XCTAssertFalse(rig.session.isCounting, "Counting stops while nobody is in view.")
        XCTAssertEqual(rig.session.exercise?.cameraView, .front, "Leaving the frame is not a turn.")
        let lost = rig.spoken.dropFirst(spokenBeforeLeaving).filter { $0.hasPrefix("I can't see you") }
        XCTAssertEqual(lost.count, 1, "\(Array(rig.spoken.dropFirst(spokenBeforeLeaving)))")
        let announced = try XCTUnwrap(rig.firstSpoken { $0.hasPrefix("I can't see you") })
        XCTAssertLessThanOrEqual(announced.time - emptyStart, FramingConfiguration().unreliableAfter
                                 + WorkoutSession.trackingLossGrace + WorkoutCoachModel.tickInterval + 0.2,
                                 "Tracking loss is announced as promptly as for any exercise.")

        rig.play(seconds: 1) { _, time in ReadyPoseFixtures.demoFrame(self.front, motionTime: 0, at: time) }
        XCTAssertTrue(rig.session.isCounting, "Counting resumes once the user is back in view.")
        rig.reps(front, count: 1)
        XCTAssertEqual(rig.session.repCount, 2)
        XCTAssertEqual(rig.session.progress[.hammerCurl]?.setReps ?? [], [], "The set was never restarted.")
    }

    // MARK: - Locking and announcements

    func testLockingSideOnMidSetKeepsRepsAndPersistsThePreference() throws {
        let rig = TurnRig()
        try rig.startSet(standing: front)
        rig.reps(front, count: 2)
        let epoch = rig.session.analyzerEpoch

        rig.harness.model.send(.setCameraView(.locked(.sideOn)))

        XCTAssertEqual(rig.session.exercise?.cameraView, .side)
        XCTAssertEqual(rig.session.cameraViewTag, "Side-on, locked")
        XCTAssertGreaterThan(rig.session.analyzerEpoch, epoch, "The side-on view gets its own analyzer.")
        XCTAssertEqual(rig.session.repCount, 2)
        XCTAssertEqual(rig.session.phase, .exercising)
        XCTAssertTrue(rig.session.isCounting)
        XCTAssertEqual(rig.preferences.viewPreference(for: .hammerCurl), .locked(.sideOn))
        XCTAssertFalse(rig.spoken.contains("Side-on view, locked."), "Mid-set the coach stays quiet; the tag shows the lock.")
        let lockStart = rig.log.count

        rig.play(seconds: 0.5) { _, time in ReadyPoseFixtures.demoFrame(self.front, motionTime: 0, at: time) }
        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time) }
        rig.play(seconds: 1) { _, time in ReadyPoseFixtures.demoFrame(self.side, motionTime: 0, at: time) }
        rig.reps(side, count: 1)

        let locked = rig.log[lockStart...]
        XCTAssertTrue(locked.allSatisfy { $0.view == .side }, "A locked view ignores the stance.")
        XCTAssertTrue(locked.allSatisfy { $0.phase == .exercising && $0.isCounting },
                      "Counting off at \(locked.filter { !$0.isCounting }.map(\.time))")
        XCTAssertEqual(rig.session.repCount, 3)
    }

    func testTurningAtReadyIsAnnouncedAndTurningDuringRestIsSilent() throws {
        let rig = TurnRig()
        try rig.reachReady(standing: front)
        let spokenAtReady = rig.spoken.count

        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time) }
        rig.play(until: { $0.exercise?.cameraView == .side }, limit: 2) { _, time in
            ReadyPoseFixtures.demoFrame(self.side, motionTime: 0, at: time)
        }

        XCTAssertEqual(rig.session.exercise?.cameraView, .side)
        XCTAssertNotEqual(rig.session.phase, .exercising, "Turning in setup never starts a set.")
        XCTAssertEqual(rig.spoken.dropFirst(spokenAtReady).filter { $0 == "Side-on view." }.count, 1,
                       "\(Array(rig.spoken.dropFirst(spokenAtReady)))")

        rig.harness.model.send(.start)
        rig.harness.model.send(.nextSet)
        XCTAssertEqual(rig.session.phase, .resting)
        let spokenAtRest = rig.spoken.count

        rig.play(seconds: 0.3) { _, time in self.threeQuarter(at: time) }
        rig.play(seconds: stance.holdSeconds + 0.5) { _, time in
            ReadyPoseFixtures.demoFrame(self.front, motionTime: 0, at: time)
        }

        XCTAssertEqual(rig.session.phase, .resting)
        XCTAssertEqual(rig.session.exercise?.cameraView, .front, "The view still follows the stance during rest.")
        let restSpeech = Array(rig.spoken.dropFirst(spokenAtRest))
        XCTAssertFalse(restSpeech.contains("Front view.") || restSpeech.contains("Side-on view."), "\(restSpeech)")
    }

    // MARK: - Assertions and frames

    /// The set kept going from `start` on: never reset, always exercising and counting, reps only rising to `reps`,
    /// and nothing said about losing the user or the new view.
    private func assertSetCarriedOn(_ rig: TurnRig, from start: Int, spokenFrom spokenStart: Int, reps: Int,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let set = Array(rig.log[start...])
        XCTAssertEqual(rig.session.repCount, reps, file: file, line: line)
        XCTAssertEqual(rig.session.progress[.hammerCurl]?.setReps ?? [], [], "No set was completed or restarted.",
                       file: file, line: line)
        XCTAssertTrue(zip(set, set.dropFirst()).allSatisfy { $0.reps <= $1.reps },
                      "Reps went down: \(set.map(\.reps))", file: file, line: line)
        XCTAssertTrue(set.allSatisfy { $0.phase == .exercising }, "The phase left exercising.", file: file, line: line)
        let notCounting = set.filter { !$0.isCounting }
        XCTAssertTrue(notCounting.isEmpty,
                      "Counting stopped at \(notCounting.map { String(format: "%.1f", $0.time) }) s; the view switched at "
                      + "\(zip(set, set.dropFirst()).first { $0.view != $1.view }.map { String(format: "%.1f", $1.time) } ?? "never") s",
                      file: file, line: line)
        let spoken = Array(rig.spoken.dropFirst(spokenStart))
        XCTAssertFalse(spoken.contains { $0.hasPrefix("I can't see you") }, "\(spoken)", file: file, line: line)
        XCTAssertFalse(spoken.contains("Side-on view.") || spoken.contains("Front view."), "\(spoken)",
                       file: file, line: line)
    }

    /// The front pose at `motionTime` (the start by default) narrowed sideways around its shoulders until they span
    /// `ratio` torso lengths, between the facing and side-on readings, as when turning partway. `hiding` drops joints
    /// the body would cover.
    private func threeQuarter(at time: TimeInterval, motionTime: TimeInterval = 0, ratio: Double? = nil,
                              hiding hidden: Set<LandmarkType> = []) -> PoseFrame {
        let frame = ReadyPoseFixtures.demoFrame(front, motionTime: motionTime, at: time)
        guard let left = frame.point(.leftShoulder, minimumConfidence: 0),
              let right = frame.point(.rightShoulder, minimumConfidence: 0),
              let leftHip = frame.point(.leftHip, minimumConfidence: 0),
              let rightHip = frame.point(.rightHip, minimumConfidence: 0) else {
            XCTFail("The front figure has no shoulders and hips.")
            return frame
        }
        let shoulders = ArmGeometry.midpoint(left, right)
        let torso = ArmGeometry.distance(shoulders, ArmGeometry.midpoint(leftHip, rightHip))
        let target = ratio ?? (stance.facingRatio + stance.sideOnRatio) / 2
        let squeeze = CGFloat(target) * torso / ArmGeometry.distance(left, right)
        var pose = frame.pose
        for (joint, landmark) in frame.pose.landmarks {
            guard !hidden.contains(joint) else {
                pose.landmarks[joint] = nil
                continue
            }
            let point = CGPoint(x: shoulders.x + (landmark.imageLocation.x - shoulders.x) * squeeze,
                                y: landmark.imageLocation.y)
            pose.landmarks[joint] = moved(landmark, to: point, in: pose)
        }
        return PoseFrame(pose: pose, timestamp: frame.timestamp)
    }

    /// `frame` without `joints`, as when the body hides them.
    private func without(_ joints: Set<LandmarkType>, _ frame: PoseFrame) -> PoseFrame {
        var pose = frame.pose
        for joint in joints { pose.landmarks[joint] = nil }
        return PoseFrame(pose: pose, timestamp: frame.timestamp)
    }

    /// `frame` moved `dx` pixels sideways; joints that leave the image are no longer seen.
    private func shifted(_ frame: PoseFrame, by dx: CGFloat) -> PoseFrame {
        var pose = frame.pose
        for (joint, landmark) in frame.pose.landmarks {
            let point = CGPoint(x: landmark.imageLocation.x + dx, y: landmark.imageLocation.y)
            pose.landmarks[joint] = point.x < pose.imageWidth ? moved(landmark, to: point, in: pose) : nil
        }
        return PoseFrame(pose: pose, timestamp: frame.timestamp)
    }

    private func moved(_ landmark: Landmark, to point: CGPoint, in pose: BodyPose) -> Landmark {
        var result = landmark
        result.imageLocation = point
        result.normalizedLocation = CoordinateConverter.imagePixelToNormalized(
            pixel: point, imageWidth: pose.imageWidth, imageHeight: pose.imageHeight)
        return result
    }
}

/// One hammer-curl coach in Auto, fed frames at 10 Hz with the scheduler advancing first so ticks fire between frames
/// as on device. It logs what the coach showed after every frame and when each line was spoken.
@MainActor
private final class TurnRig {
    struct Sample {
        let time: TimeInterval
        let phase: WorkoutPhase
        let isCounting: Bool
        let isTurning: Bool
        let reps: Int
        let view: ExerciseCameraView?
    }

    struct NotReady: Error {}

    let preferences = InMemoryPreferences()
    let harness: WorkoutCoachHarness
    private(set) var log: [Sample] = []
    /// Each line with the time of the first frame logged after it.
    private var speech: [(time: TimeInterval, text: String)] = []

    init() {
        harness = WorkoutCoachHarness.make(preferences: preferences, initialExercise: .hammerCurl)
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
    }

    var session: WorkoutSession { harness.model.session }
    var spoken: [String] { harness.speech.utterances.map(\.text) }

    func firstSpoken(where matches: (String) -> Bool) -> (time: TimeInterval, text: String)? {
        speech.first { matches($0.text) }
    }

    /// Feeds `seconds` of frames. `pose` gets the time since this call began and the frame's timestamp.
    func play(seconds: TimeInterval, _ pose: (_ local: TimeInterval, _ time: TimeInterval) -> PoseFrame) {
        play(until: { _ in false }, limit: seconds, pose)
    }

    /// Feeds frames until `done` holds or `limit` seconds pass.
    func play(until done: (WorkoutSession) -> Bool, limit: TimeInterval,
              _ pose: (_ local: TimeInterval, _ time: TimeInterval) -> PoseFrame) {
        let frames = Int((limit * 10).rounded())
        for index in 0..<frames where !done(session) {
            harness.scheduler.advance(by: 0.1)
            let time = harness.clock.now
            harness.camera.emit(.frame(pose(Double(index) / 10, time)))
            record(at: time)
        }
    }

    /// Lets `count` frame intervals pass without a frame, as when the camera stalls.
    func dropFrames(_ count: Int) {
        for _ in 0..<count { harness.scheduler.advance(by: 0.1) }
    }

    /// `count` guide reps in `view`'s camera view, then a second at the start so the last rep confirms.
    func reps(_ view: ExerciseDefinition, count: Int) {
        let duration = view.guide.motion.duration * Double(count)
        play(seconds: duration + 1) { local, time in
            ReadyPoseFixtures.demoFrame(view, motionTime: local < duration ? local : 0, at: time)
        }
    }

    /// Starts with one bottom sample, then moves before a cold analyzer can confirm a second bottom sample.
    func immediateCurl(_ view: ExerciseDefinition) {
        let firstMovingPose = 1.4
        let remaining = view.guide.motion.duration - firstMovingPose
        play(seconds: remaining + 0.2) { local, time in
            let poseTime = local == 0 ? 0 : firstMovingPose + local - 0.1
            return ReadyPoseFixtures.demoFrame(view, motionTime: poseTime, at: time)
        }
    }

    /// Continues an already active curl through its return to the bottom.
    func continueCurl(_ view: ExerciseDefinition, startingAt poseTime: TimeInterval) {
        let remaining = view.guide.motion.duration - poseTime
        play(seconds: remaining + 0.1) { local, time in
            ReadyPoseFixtures.demoFrame(view, motionTime: poseTime + local, at: time)
        }
    }

    /// Stands still in `view`'s start position until the coach is Ready in that camera view.
    func reachReady(standing view: ExerciseDefinition, file: StaticString = #filePath, line: UInt = #line) throws {
        play(until: { $0.phase == .ready && $0.exercise?.cameraView == view.cameraView }, limit: 4) { _, time in
            ReadyPoseFixtures.demoFrame(view, motionTime: 0, at: time)
        }
        guard session.phase == .ready, session.exercise?.cameraView == view.cameraView else {
            XCTFail("Setup never reached Ready in \(view.cameraView.rawValue): \(session.phase)", file: file, line: line)
            throw NotReady()
        }
    }

    /// Ready in `view`, then the Start button.
    func startSet(standing view: ExerciseDefinition, file: StaticString = #filePath, line: UInt = #line) throws {
        try reachReady(standing: view, file: file, line: line)
        harness.model.send(.start)
        record(at: harness.clock.now)
        XCTAssertEqual(session.phase, .exercising, file: file, line: line)
        XCTAssertTrue(session.isCounting, "Counting starts with the set.", file: file, line: line)
    }

    private func record(at time: TimeInterval) {
        let said = harness.speech.utterances.map(\.text)
        speech += said.dropFirst(speech.count).map { (time: time, text: $0) }
        log.append(Sample(time: time, phase: session.phase, isCounting: session.isCounting,
                          isTurning: session.isTurning, reps: session.repCount, view: session.exercise?.cameraView))
    }
}
