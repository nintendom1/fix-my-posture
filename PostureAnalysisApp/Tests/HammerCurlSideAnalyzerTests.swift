import XCTest
@testable import PostureAnalysisApp

final class HammerCurlSideAnalyzerTests: XCTestCase {
    private var front: ExerciseDefinition { HammerCurlExercise.definition() }
    private var sideMotion: ArmMotion { HammerCurlExercise.definition(view: .side).guide.motion }

    func testFrontDefinitionKeepsItsSetupGuideAndCoachingCopy() throws {
        let exercise = front
        XCTAssertEqual(exercise.id, ExerciseID(rawValue: "hammer_curl"))
        XCTAssertEqual(exercise.displayName, "Hammer Curl")
        XCTAssertEqual(exercise.presentation, ExercisePresentation(
            shortName: "Hammer Curl",
            muscles: ["Biceps", "Forearms"],
            filterGroups: [.upper, .dumbbells],
            gradient: ExerciseGradient(token: .curl, stops: ["#b04bff", "#ff7fc8"], angle: 135),
            symbolName: "dumbbell.fill",
            equipmentLine: "Two dumbbells",
            cameraSetupLine: "Front or side-on, full arms",
            watchesFor: [
                WatchItem(cueID: .curlFullRange, text: "Full range of motion"),
                WatchItem(cueID: .curlElbowsIn, text: "Elbows staying by your sides")
            ]
        ))
        XCTAssertEqual(exercise.spokenName, "hammer curl")
        XCTAssertEqual(exercise.sets, 2)
        XCTAssertEqual(exercise.targetReps, 10...10)
        XCTAssertEqual(exercise.autoCompleteReps, 10)
        XCTAssertNil(exercise.targetRangeAnnouncementReps)
        XCTAssertEqual(exercise.restSeconds, 60)
        XCTAssertEqual(exercise.requiredJoints,
                       [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist])
        XCTAssertEqual(exercise.focusSegments, [
            FocusSegment(from: .leftShoulder, to: .leftElbow, style: .limb),
            FocusSegment(from: .leftElbow, to: .leftWrist, style: .limb),
            FocusSegment(from: .rightShoulder, to: .rightElbow, style: .limb),
            FocusSegment(from: .rightElbow, to: .rightWrist, style: .limb),
            FocusSegment(from: .leftShoulder, to: .rightShoulder, style: .reference),
            FocusSegment(from: .leftHip, to: .rightHip, style: .reference)
        ])
        XCTAssertNil(exercise.headroomArmLengths)
        XCTAssertTrue(exercise.countsArmsIndependently)
        XCTAssertEqual(exercise.setupLine, "Face the phone and let the dumbbells hang at your sides with straight arms.")
        XCTAssertEqual(exercise.voiceAliases, ["hammer curl", "hammer curls", "curl", "curls", "dumbbell curls"])
        XCTAssertEqual(exercise.cameraView, .front)
        XCTAssertEqual(exercise.views, [.front, .side])
        XCTAssertTrue(exercise.startsByHolding)
        XCTAssertFalse(exercise.perSide)
        XCTAssertEqual(exercise.doseUnit, .reps)
        XCTAssertEqual(exercise.tracking, .camera)
        XCTAssertEqual(exercise.equipment, .dumbbells)

        XCTAssertEqual(exercise.guide.summary, "2 sets × 10 reps · Two dumbbells · Palms facing in")
        XCTAssertEqual(exercise.guide.steps, [
            GuideStep(title: "Start", detail: "Stand tall facing the phone. Let the dumbbells hang at your sides with straight arms, palms facing in."),
            GuideStep(title: "Curl", detail: "Keeping your elbows by your sides, curl the dumbbells up toward your shoulders. Curl one arm at a time or both together."),
            GuideStep(title: "Lower", detail: "Lower them slowly until your arms are straight again. That's one rep for each arm.")
        ])
        XCTAssertEqual(exercise.guide.tip, "Each arm counts on its own; the rep count is the number both arms have done.")
        XCTAssertEqual(exercise.guide.walkthrough,
                       "This is the hammer curl. Stand tall, facing the phone, with a dumbbell in each hand and your palms facing in. "
                        + "Let the dumbbells hang at your sides with straight arms. "
                        + "Keeping your elbows by your sides, curl the dumbbells up toward your shoulders. "
                        + "Then lower them slowly until your arms are straight. You can curl one arm at a time or both together.")
        XCTAssertEqual(exercise.guide.startPositionInstruction, "Let the dumbbells hang with straight arms")
        XCTAssertEqual(exercise.guide.motion.forearmPlane, .sagittal)

        XCTAssertEqual(exercise.coachingCues, [
            .corrective(.curlFullRange, "Curl all the way up.", trigger: .perRep, priority: 50,
                        joints: [.leftElbow, .rightElbow, .leftWrist, .rightWrist]),
            .corrective(.curlStraightenAtBottom, "Straighten at the bottom.", trigger: .perRep, priority: 40,
                        joints: [.leftElbow, .rightElbow, .leftWrist, .rightWrist]),
            .corrective(.curlElbowsIn, "Keep your elbows by your sides.", trigger: .continuous, priority: 20,
                        joints: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow]),
            .corrective(.curlBodyStill, "Keep your body still.", trigger: .continuous, priority: 10,
                        joints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip])
        ])
        XCTAssertEqual(exercise.reminders, [
            .reminder(CoachingCueID(rawValue: "curl.reminder.elbows"), "Elbows stay close."),
            .reminder(CoachingCueID(rawValue: "curl.reminder.lower"), "Lower slowly."),
            .reminder(CoachingCueID(rawValue: "curl.reminder.tall"), "Stand tall.")
        ])
        XCTAssertEqual(exercise.motionEnvelope, MotionEnvelope(above: 0.15, below: 1.15, outward: 0.35))
    }

    func testInViewSideSharesIdentityAndDoseAndBuildsSideDefinition() throws {
        let exercise = front
        let side = exercise.inView(.side)
        XCTAssertEqual(side.cameraView, .side)
        XCTAssertEqual(side.id, exercise.id)
        XCTAssertEqual(side.displayName, exercise.displayName)
        XCTAssertEqual(side.presentation, exercise.presentation)
        XCTAssertEqual(side.spokenName, exercise.spokenName)
        XCTAssertEqual(side.voiceAliases, exercise.voiceAliases)
        XCTAssertEqual(side.sets, exercise.sets)
        XCTAssertEqual(side.targetReps, exercise.targetReps)
        XCTAssertEqual(side.autoCompleteReps, exercise.autoCompleteReps)
        XCTAssertEqual(side.targetRangeAnnouncementReps, exercise.targetRangeAnnouncementReps)
        XCTAssertEqual(side.restSeconds, exercise.restSeconds)
        XCTAssertEqual(side.perSide, exercise.perSide)
        XCTAssertEqual(side.doseUnit, exercise.doseUnit)
        XCTAssertEqual(side.tracking, exercise.tracking)
        XCTAssertEqual(side.startsByHolding, exercise.startsByHolding)
        XCTAssertEqual(side.equipment, exercise.equipment)
        XCTAssertEqual(side.requiredJoints, [])
        XCTAssertEqual(side.anyOfRequiredJoints,
                       [[.leftShoulder, .leftElbow, .leftWrist], [.rightShoulder, .rightElbow, .rightWrist]])
        XCTAssertEqual(side.focusSegments, [
            FocusSegment(from: .leftShoulder, to: .leftElbow, style: .limb),
            FocusSegment(from: .leftElbow, to: .leftWrist, style: .limb),
            FocusSegment(from: .rightShoulder, to: .rightElbow, style: .limb),
            FocusSegment(from: .rightElbow, to: .rightWrist, style: .limb),
            FocusSegment(from: .leftShoulder, to: .leftHip, style: .reference),
            FocusSegment(from: .rightShoulder, to: .rightHip, style: .reference)
        ])
        XCTAssertNil(side.headroomArmLengths)
        XCTAssertFalse(side.countsArmsIndependently)
        XCTAssertEqual(side.setupLine, "Stand side-on to the phone with your arms hanging. The arm nearer the phone is counted.")
        XCTAssertEqual(side.motionEnvelope, MotionEnvelope(above: 0.15, below: 1.15, outward: 0.6))
        XCTAssertEqual(side.guide.motion.forearmPlane, .frontal, "The forearm moves in the image plane.")
        XCTAssertEqual(side.coachingCues, exercise.coachingCues)
        XCTAssertEqual(side.reminders, exercise.reminders)
        XCTAssertTrue(exercise.makeAnalyzer(1) is HammerCurlAnalyzer)
        XCTAssertTrue(side.makeAnalyzer(1) is HammerCurlSideAnalyzer)

        let builtFront = try XCTUnwrap(side.buildView?(.front))
        XCTAssertEqual(builtFront.cameraView, .front)
        let builtSide = try XCTUnwrap(exercise.buildView?(.side))
        XCTAssertEqual(builtSide.cameraView, .side)
    }

    func testSideDiagnosticsRebuildsTheSideViewAndConfiguration() throws {
        var tuning = HammerCurlSideConfiguration.standard
        tuning.topMinRatio = 0.5
        let exercise = HammerCurlExercise.definition(view: .side, sideConfiguration: tuning)
        let diagnostics = try XCTUnwrap(exercise.diagnostics)
        let recorded = try JSONEncoder().encode(tuning)
        let rebuilt = try diagnostics.rebuild(recorded)
        XCTAssertEqual(rebuilt.cameraView, .side)
        XCTAssertEqual(rebuilt.id, exercise.id)
        XCTAssertEqual(rebuilt.presentation, exercise.presentation)
        let rebuiltDiagnostics = try XCTUnwrap(rebuilt.diagnostics)
        let rebuiltConfiguration = try JSONDecoder().decode(
            HammerCurlSideConfiguration.self,
            from: Data(rebuiltDiagnostics.configurationJSON.utf8)
        )
        XCTAssertEqual(rebuiltConfiguration, tuning)
    }

    @MainActor
    func testCountsAtHalfAndDoubleSpeedWithFifteenPercentArmVariationFromEitherSide() {
        let cases: [(speed: Double, scale: CGFloat, upperArm: CGFloat, forearm: CGFloat, rightArm: Bool, mirrored: Bool)] = [
            (0.5, 0.5, 0.85, 1.15, false, false),
            (2.0, 2.0, 1.15, 0.85, true, true)
        ]
        for sample in cases {
            let result = run(sideMotion, loops: 2, speed: sample.speed, scale: sample.scale,
                             upperArm: sample.upperArm, forearm: sample.forearm,
                             rightArm: sample.rightArm, mirrored: sample.mirrored)
            XCTAssertEqual(result.events.count, 2,
                           "speed \(sample.speed), scale \(sample.scale), upper \(sample.upperArm), forearm \(sample.forearm)")
            XCTAssertTrue(result.events.allSatisfy { $0.sides == Set(BodySide.allCases) },
                          "Each near-arm rep credits both sides.")
        }
    }

    @MainActor
    func testHalfCurlDoesNotCount() {
        let halfCurl = ArmMotion(keyframes: [
            ArmKeyframe(angles: sideMotion.startAngles, moveDuration: 0, holdDuration: 0.8, stepIndex: 0),
            ArmKeyframe(angles: ArmAngles(upperArmElevation: -90, forearmElevation: 0),
                        moveDuration: 1.0, holdDuration: 0.2, stepIndex: 1),
            ArmKeyframe(angles: sideMotion.startAngles, moveDuration: 1.0, holdDuration: 0, stepIndex: 2)
        ])
        XCTAssertTrue(run(halfCurl, loops: 1).events.isEmpty)
    }

    @MainActor
    func testRecurlFromMidwayDoesNotCountTwice() {
        let midway = ArmAngles(upperArmElevation: -90, forearmElevation: -20)
        let recurl = ArmMotion(keyframes: [
            ArmKeyframe(angles: sideMotion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: sideMotion.topAngles, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: midway, moveDuration: 0.8, holdDuration: 0.2, stepIndex: 2),
            ArmKeyframe(angles: sideMotion.topAngles, moveDuration: 0.8, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: sideMotion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
        let result = run(recurl, loops: 1)
        XCTAssertEqual(result.events.count, 1, "Only returning fully to the start ends the rep.")
        XCTAssertTrue(result.events.allSatisfy { $0.sides == Set(BodySide.allCases) })
    }

    @MainActor
    func testElbowSwingRaisesDriftCueAndLeanNeedsTheHip() throws {
        let elbowSwing = run(sideMotion, upperArmSwing: { $0 >= 4.5 ? 30 : 0 })
        XCTAssertTrue(elbowSwing.signals.contains { $0.contains(.curlElbowsIn) })
        XCTAssertTrue(elbowSwing.formReadings.contains { $0.label == "drift" })
        XCTAssertEqual(elbowSwing.events.count, 3, "Form coaching does not change counting.")
        let backwardSwing = run(sideMotion, upperArmSwing: { $0 >= 4.5 ? -30 : 0 })
        XCTAssertTrue(backwardSwing.signals.contains { $0.contains(.curlElbowsIn) })

        let leaning = run(sideMotion, lean: { $0 >= 4.5 ? 30 : 0 })
        XCTAssertTrue(leaning.signals.contains { $0.contains(.curlBodyStill) })
        XCTAssertEqual(leaning.events.count, 3)

        let noHip = run(sideMotion, hips: false, lean: { $0 >= 4.5 ? 30 : 0 })
        XCTAssertFalse(noHip.signals.contains { $0.contains(.curlBodyStill) })
        let sway = try XCTUnwrap(noHip.formReadings.first { $0.label == "sway" })
        XCTAssertEqual(sway.value, "–")
    }

    @MainActor
    func testSwitchingArmsRejectsAndResetsBeforeCountingTheNewArm() {
        let analyzer = HammerCurlSideAnalyzer(epoch: 4)
        var events: [RepEvent] = []
        var rejections: [RepRejection] = []
        var signals: [Set<CoachingCueID>] = []
        for index in 0...37 {
            let time = Double(index) / 10
            let angles: ArmAngles
            let rightArm: Bool
            switch index {
            case 0...5:
                angles = sideMotion.startAngles
                rightArm = false
            case 6...12:
                angles = sideMotion.topAngles
                rightArm = false
            case 13...22:
                angles = sideMotion.startAngles
                rightArm = true
            case 23...29:
                angles = sideMotion.topAngles
                rightArm = true
            default:
                angles = sideMotion.startAngles
                rightArm = true
            }
            let analysis = analyzer.process(sideFrame(angles: angles, rightArm: rightArm,
                                                      upperArmSwing: rightArm ? 30 : 0, at: time), counting: true)
            events += analysis.repEvents
            rejections += analysis.rejections
            signals.append(analysis.formSignals)
        }

        XCTAssertTrue(rejections.contains { rejection in
            if case .sideSwitched(.reachedEnd) = rejection.reason { return true }
            return false
        })
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events.allSatisfy { $0.sides == Set(BodySide.allCases) })
        XCTAssertTrue(signals.allSatisfy { !$0.contains(.curlElbowsIn) },
                      "The new arm establishes a fresh drift baseline.")
    }

    @MainActor
    func testGapRejectsTheAttemptAndAllowsAReacquiredRep() {
        let analyzer = HammerCurlSideAnalyzer(epoch: 5)
        var events: [RepEvent] = []
        var rejections: [RepRejection] = []
        for index in 0...12 {
            let angles = index <= 5 ? sideMotion.startAngles : sideMotion.topAngles
            let analysis = analyzer.process(sideFrame(angles: angles, at: Double(index) / 10), counting: true)
            events += analysis.repEvents
            rejections += analysis.rejections
        }

        let movedPose = CGPoint(x: 120, y: -90)
        let gapAnalysis = analyzer.process(sideFrame(angles: sideMotion.startAngles, scale: 1.2,
                                                      translation: movedPose, at: 2.0), counting: true)
        rejections += gapAnalysis.rejections
        events += gapAnalysis.repEvents
        for index in 21...43 {
            let angles: ArmAngles
            if index <= 25 || index >= 34 {
                angles = sideMotion.startAngles
            } else {
                angles = sideMotion.topAngles
            }
            let analysis = analyzer.process(sideFrame(angles: angles, scale: 1.2, translation: movedPose,
                                                      at: Double(index) / 10), counting: true)
            events += analysis.repEvents
            rejections += analysis.rejections
        }

        XCTAssertTrue(rejections.contains { rejection in
            if case .trackingGap(_, _, .reachedEnd) = rejection.reason { return true }
            return false
        })
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events.allSatisfy { $0.sides == Set(BodySide.allCases) })
    }

    @MainActor
    func testEstimatedFocusJointSkipsFormButDoesNotStopCounting() {
        let result = run(sideMotion, loops: 1, estimatedJoints: [.rightWrist])
        XCTAssertEqual(result.events.count, 1)
        XCTAssertTrue(result.forms.isEmpty)
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty))
    }

    @MainActor
    func testTooFastReturnAndReferenceTimeoutAreRejected() throws {
        var fastConfiguration = HammerCurlSideConfiguration.standard
        fastConfiguration.minimumRepDuration = 10
        let fast = run(sideMotion, loops: 1, configuration: fastConfiguration)
        XCTAssertTrue(fast.events.isEmpty)
        XCTAssertTrue(fast.rejections.contains { rejection in
            if case .tooFast = rejection.reason { return true }
            return false
        })

        let analyzer = HammerCurlSideAnalyzer(epoch: 7)
        _ = analyzer.process(sideFrame(angles: sideMotion.startAngles, at: 0), counting: true)
        _ = analyzer.process(sideFrame(angles: sideMotion.startAngles, at: 0.1), counting: true)
        _ = analyzer.process(sideFrame(angles: sideMotion.topAngles, at: 0.2), counting: true)
        _ = analyzer.process(sideFrame(angles: sideMotion.topAngles, at: 0.3), counting: true)
        var timeoutRejections: [RepRejection] = []
        for index in 4...66 {
            let analysis = analyzer.process(sideFrame(angles: sideMotion.topAngles, at: Double(index) / 10), counting: true)
            timeoutRejections += analysis.rejections
        }
        XCTAssertTrue(timeoutRejections.contains { rejection in
            if case .referenceExpired(.reachedEnd) = rejection.reason { return true }
            return false
        })
    }

    @MainActor
    func testCountingStopMidRepIsRecorded() {
        let analyzer = HammerCurlSideAnalyzer(epoch: 8)
        _ = analyzer.process(sideFrame(angles: sideMotion.startAngles, at: 0), counting: true)
        _ = analyzer.process(sideFrame(angles: sideMotion.startAngles, at: 0.1), counting: true)
        _ = analyzer.process(sideFrame(angles: sideMotion.topAngles, at: 0.2), counting: true)
        _ = analyzer.process(sideFrame(angles: sideMotion.topAngles, at: 0.3), counting: true)
        let stopped = analyzer.process(sideFrame(angles: sideMotion.topAngles, at: 0.4), counting: false)
        XCTAssertTrue(stopped.rejections.contains { rejection in
            if case .countingStopped(.reachedEnd) = rejection.reason { return true }
            return false
        })
    }

    @MainActor
    func testThresholdLinesFaceTheNoseOrFallbackToTheWrist() throws {
        let facingRight = HammerCurlSideAnalyzer(epoch: 9)
        let forward = facingRight.process(sideFrame(angles: sideMotion.startAngles, at: 0), counting: true)
        let forwardLine = try XCTUnwrap(forward.thresholds[.left]?.topLine)
        XCTAssertGreaterThan(forwardLine.to.x, forwardLine.from.x)

        let facingLeft = HammerCurlSideAnalyzer(epoch: 10)
        let backward = facingLeft.process(sideFrame(angles: sideMotion.startAngles, mirrored: true, at: 0), counting: true)
        let backwardLine = try XCTUnwrap(backward.thresholds[.left]?.topLine)
        XCTAssertLessThan(backwardLine.to.x, backwardLine.from.x)

        let noNose = HammerCurlSideAnalyzer(epoch: 11)
        let fallback = noNose.process(sideFrame(angles: sideMotion.startAngles, noseVisible: false, at: 0), counting: true)
        let fallbackLine = try XCTUnwrap(fallback.thresholds[.left]?.topLine)
        XCTAssertGreaterThan(fallbackLine.to.x, fallbackLine.from.x)
    }

    // MARK: - Camera-view hand-off

    @MainActor
    func testReportsTheTrackedCurlPastTheTopForBothSidesUntilItIsCreditedOrCountingStops() {
        let analyzer = HammerCurlSideAnalyzer(epoch: 12)
        let start = sideMotion.startAngles
        let top = sideMotion.topAngles
        var index = 0
        func feed(_ angles: ArmAngles?, counting: Bool = true) -> ExerciseAnalysis {
            defer { index += 1 }
            let time = Double(index) / 10
            let frame = angles.map { sideFrame(angles: $0, at: time) }
                ?? PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920), timestamp: time)
            return analyzer.process(frame, counting: counting)
        }

        for _ in 0..<5 { _ = feed(start) }
        XCTAssertNil(analyzer.attemptInProgress(), "Hanging at the start is no attempt.")
        _ = feed(halfCurlAngles)
        XCTAssertNil(analyzer.attemptInProgress(), "A curl that hasn't reached the top doesn't carry.")
        _ = feed(top)
        _ = feed(top)
        let both = Set(BodySide.allCases)
        XCTAssertEqual(analyzer.attemptInProgress(), RepAttemptInProgress(movementStart: 0.4, reachedEnd: 0.7, sides: both),
                       "One rep here credits both sides, so both carry.")
        _ = feed(nil)
        XCTAssertEqual(analyzer.attemptInProgress()?.sides, both, "A briefly hidden arm still carries its curl.")

        for _ in 0..<4 { _ = feed(top) }
        _ = feed(start)
        XCTAssertEqual(feed(start).repEvents.count, 1)
        XCTAssertNil(analyzer.attemptInProgress(), "A credited return leaves nothing to carry.")

        for _ in 0..<3 { _ = feed(start) }
        _ = feed(top)
        _ = feed(top)
        XCTAssertNotNil(analyzer.attemptInProgress())
        _ = feed(nil, counting: false)
        XCTAssertNil(analyzer.attemptInProgress(), "Counting stopped while the arm was hidden, so its curl is lost.")
    }

    @MainActor
    func testAResumedCurlCountsOnceWhenTheTrackedArmReachesTheStart() {
        let analyzer = HammerCurlSideAnalyzer(epoch: 13)
        // This view's warm-up saw only the top, never the curl's start.
        for index in 0..<3 {
            _ = analyzer.process(sideFrame(angles: sideMotion.topAngles, at: Double(index) / 10), counting: true)
        }
        XCTAssertNil(analyzer.attemptInProgress())

        // The front view carries the tracked arm's curl, which side-on credits for both arms.
        analyzer.resume(RepAttemptInProgress(movementStart: -1, reachedEnd: -0.5, sides: [.left]))
        XCTAssertEqual(analyzer.attemptInProgress(),
                       RepAttemptInProgress(movementStart: -1, reachedEnd: -0.5, sides: Set(BodySide.allCases)))

        var reps: [RepEvent] = []
        let lowering = [halfCurlAngles] + Array(repeating: sideMotion.startAngles, count: 12)
        for (offset, angles) in lowering.enumerated() {
            reps += analyzer.process(sideFrame(angles: angles, at: Double(3 + offset) / 10), counting: true).repEvents
        }

        XCTAssertEqual(reps, [RepEvent(epoch: 13, timestamp: 0.5, sides: Set(BodySide.allCases))])
    }

    @MainActor
    func testAFarArmCurlResumesOnlyWhenItCompletesAPair() {
        func warmed() -> HammerCurlSideAnalyzer {
            let analyzer = HammerCurlSideAnalyzer(epoch: 13)
            for index in 0..<3 {
                _ = analyzer.process(sideFrame(angles: sideMotion.topAngles, at: Double(index) / 10), counting: true)
            }
            return analyzer
        }
        let alone = warmed()
        alone.resume(RepAttemptInProgress(movementStart: -1, reachedEnd: -0.5, sides: [.right]))
        XCTAssertNil(alone.attemptInProgress(), "The far arm alone isn't a pair; the tracked arm's next curl completes it.")

        let completing = warmed()
        completing.resume(RepAttemptInProgress(movementStart: -1, reachedEnd: -0.5, sides: [.right], pairCredits: [.left]))
        XCTAssertNotNil(completing.attemptInProgress(), "With the tracked arm already credited, the far arm completes the pair.")
    }

    @MainActor
    func testAResumedCurlAlreadyBackAtTheStartCountsOnTheNextCountingFrameOnly() {
        func run(firstFrameCounting: Bool) -> [RepEvent] {
            let analyzer = HammerCurlSideAnalyzer(epoch: 14)
            // During the warm-up the arm comes down from the top and hangs straight from 0.4 s.
            let top = sideMotion.topAngles
            let start = sideMotion.startAngles
            for (index, angles) in [top, top, halfCurlAngles, start, start, start].enumerated() {
                _ = analyzer.process(sideFrame(angles: angles, at: Double(index) / 10), counting: true)
            }
            analyzer.resume(RepAttemptInProgress(movementStart: -1, reachedEnd: 0.1, sides: [.left]))
            var reps = analyzer.process(sideFrame(angles: start, at: 0.6), counting: firstFrameCounting).repEvents
            for index in 7..<20 {
                reps += analyzer.process(sideFrame(angles: start, at: Double(index) / 10), counting: true).repEvents
            }
            return reps
        }

        XCTAssertEqual(run(firstFrameCounting: true), [RepEvent(epoch: 14, timestamp: 0.6, sides: Set(BodySide.allCases))])
        XCTAssertEqual(run(firstFrameCounting: false), [], "A counting stop drops the carried curl.")
    }

    @MainActor
    func testResumeKeepsItsOwnCurlAndIgnoresAStartSeenBeforeTheCarriedTop() {
        let start = sideMotion.startAngles
        let ownCurl = HammerCurlSideAnalyzer(epoch: 15)
        let curl = Array(repeating: start, count: 3) + Array(repeating: sideMotion.topAngles, count: 8)
        for (index, angles) in curl.enumerated() {
            _ = ownCurl.process(sideFrame(angles: angles, at: Double(index) / 10), counting: true)
        }
        ownCurl.resume(RepAttemptInProgress(movementStart: 0, reachedEnd: 0.35, sides: [.left]))
        XCTAssertEqual(ownCurl.attemptInProgress(),
                       RepAttemptInProgress(movementStart: 0.2, reachedEnd: 0.4, sides: Set(BodySide.allCases)))
        var ownReps: [RepEvent] = []
        for index in 11..<20 {
            ownReps += ownCurl.process(sideFrame(angles: start, at: Double(index) / 10), counting: true).repEvents
        }
        XCTAssertEqual(ownReps.count, 1)

        // This view saw the arm at the start before the other view's top, and only a half curl since.
        let halfCurl = HammerCurlSideAnalyzer(epoch: 16)
        for (index, angles) in [start, start, start, halfCurlAngles, halfCurlAngles].enumerated() {
            _ = halfCurl.process(sideFrame(angles: angles, at: Double(index) / 10), counting: true)
        }
        halfCurl.resume(RepAttemptInProgress(movementStart: -1, reachedEnd: 0.35, sides: [.left]))
        XCTAssertNil(halfCurl.attemptInProgress())
        var halfReps: [RepEvent] = []
        for index in 5..<15 {
            halfReps += halfCurl.process(sideFrame(angles: start, at: Double(index) / 10), counting: true).repEvents
        }
        XCTAssertTrue(halfReps.isEmpty)
    }

    private var halfCurlAngles: ArmAngles { ArmAngles(upperArmElevation: -90, forearmElevation: 0) }

    private struct Run {
        var events: [RepEvent] = []
        var rejections: [RepRejection] = []
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
        var formReadings: [FormReading] = []
    }

    @MainActor
    private func run(_ motion: ArmMotion, loops: Int = 3, speed: Double = 1, scale: CGFloat = 1,
                     upperArm: CGFloat = 1, forearm: CGFloat = 1, rightArm: Bool = false,
                     mirrored: Bool = false, hips: Bool = true, noseVisible: Bool = true,
                     translation: CGPoint = .zero,
                     estimatedJoints: Set<LandmarkType> = [],
                     upperArmSwing: (TimeInterval) -> Double = { _ in 0 },
                     lean: (TimeInterval) -> CGFloat = { _ in 0 },
                     configuration: HammerCurlSideConfiguration = .standard) -> Run {
        let analyzer = HammerCurlSideAnalyzer(epoch: 1, configuration: configuration)
        var result = Run()
        let sampleCount = Int(ceil(motion.duration * Double(loops) * 10 / speed))
        for index in 0..<sampleCount {
            let time = Double(index) / 10
            var angles = motion.sample(at: time * speed).angles
            angles.upperArmElevation += upperArmSwing(time)
            let frame = sideFrame(angles: angles, scale: scale, upperArm: upperArm, forearm: forearm,
                                  mirrored: mirrored, rightArm: rightArm, hips: hips, noseVisible: noseVisible,
                                  translation: translation, lean: lean(time),
                                  estimatedJoints: estimatedJoints, at: time)
            let analysis = analyzer.process(frame, counting: true)
            result.events += analysis.repEvents
            result.rejections += analysis.rejections
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
            result.formReadings = analysis.formReadings
        }
        return result
    }

    @MainActor
    private func sideFrame(angles: ArmAngles, scale: CGFloat = 1, upperArm: CGFloat = 1, forearm: CGFloat = 1,
                           mirrored: Bool = false, rightArm: Bool = false, hips: Bool = true,
                           noseVisible: Bool = true, translation: CGPoint = .zero, lean: CGFloat = 0,
                           upperArmSwing: Double = 0,
                           estimatedJoints: Set<LandmarkType> = [], at time: TimeInterval) -> PoseFrame {
        var joints = ExerciseDemoFigureView.sideFigureJoints
        let sourceShoulder = joints[.leftShoulder] ?? CGPoint(x: 300, y: 500)
        joints[.nose]?.x -= lean
        let shoulder = CGPoint(x: sourceShoulder.x - lean, y: sourceShoulder.y)
        var adjustedAngles = angles
        adjustedAngles.upperArmElevation += upperArmSwing
        let arm = ArmMotion.place(shoulder: shoulder, outward: 1,
                                  upperArm: ExerciseDemoFigureView.upperArm * upperArm,
                                  forearm: ExerciseDemoFigureView.forearm * forearm,
                                  angles: adjustedAngles)
        let selected: BodySide = rightArm ? .right : .left
        let other: BodySide = rightArm ? .left : .right
        joints[selected.shoulder] = shoulder
        joints[selected.elbow] = arm.elbow
        joints[selected.wrist] = arm.wrist
        joints[other.shoulder] = nil
        joints[other.elbow] = nil
        joints[other.wrist] = nil
        if rightArm {
            joints[.rightHip] = joints[.leftHip]
            joints[.leftHip] = nil
        } else {
            joints[.rightHip] = nil
        }
        if !hips { joints[selected.hip] = nil }
        if !noseVisible { joints[.nose] = nil }

        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            let x = mirrored ? 300 - point.x : point.x
            return (type, Landmark(type: type, normalizedLocation: .zero,
                                   imageLocation: CGPoint(x: x * scale + 300 + translation.x,
                                                          y: point.y * scale + 400 + translation.y), confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                         timestamp: time, estimatedJoints: estimatedJoints)
    }
}
