import AVFoundation
import Dispatch
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AudioSessionParityTests: XCTestCase {
    func testPlaybackAndRecordingCategoriesActivationAndDeactivation() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)

        audio.configureBaseCategory()
        audio.setRecordingEnabled(true)
        let activated = await activate(audio)
        XCTAssertTrue(activated)
        audio.stopListening()
        await audio.waitForPendingSessionWork()

        XCTAssertEqual(session.calls, [
            .category("AVAudioSessionCategoryPlayback", "AVAudioSessionModeDefault", ["mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, []),
            .active(false, ["notifyOthersOnDeactivation"])
        ])
        XCTAssertFalse(audio.isActive)
        XCTAssertTrue(audio.isRecordingEnabled)
    }

    func testDuckingAndRestoreOrderWhileListening() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        let activated = await activate(audio)
        XCTAssertTrue(activated)

        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        XCTAssertTrue(audio.isDucking)
        audio.endDucking()
        await audio.waitForPendingSessionWork()

        XCTAssertEqual(session.calls, [
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, []),
            .active(false, []),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "duckOthers", "mixWithOthers"]),
            .active(true, []),
            .active(false, ["notifyOthersOnDeactivation"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, [])
        ])
        XCTAssertFalse(audio.isDucking)
        XCTAssertTrue(audio.isActive)
    }

    func testSpeechDuckingWithoutListeningDoesNotReactivateAfterSpeech() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)

        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        audio.endDucking()
        await audio.waitForPendingSessionWork()

        XCTAssertEqual(session.calls, [
            .category("AVAudioSessionCategoryPlayback", "AVAudioSessionModeDefault", ["duckOthers", "mixWithOthers"]),
            .active(true, []),
            .active(false, ["notifyOthersOnDeactivation"]),
            .category("AVAudioSessionCategoryPlayback", "AVAudioSessionModeDefault", ["mixWithOthers"])
        ])
        XCTAssertFalse(audio.isActive)
    }

    func testRecordingFakePreservesUnknownCategoryOptionBits() throws {
        let session = RecordingAudioSessioning()
        let unknownOption = AVAudioSession.CategoryOptions(rawValue: 1 << 20)
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetoothA2DP]
        options.formUnion(unknownOption)

        try session.setCategory(.playAndRecord, mode: .default, options: options)

        XCTAssertEqual(session.calls, [
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault", options.rawValue,
                      ["allowBluetoothA2DP", "mixWithOthers"])
        ])
    }

    func testDeactivateEndsDuckingAndReleasesListeningSession() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        let activated = await activate(audio)
        XCTAssertTrue(activated)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()

        audio.deactivate()
        await audio.waitForPendingSessionWork()

        XCTAssertEqual(session.calls.suffix(3), [
            .active(false, ["notifyOthersOnDeactivation"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(false, ["notifyOthersOnDeactivation"])
        ])
        XCTAssertFalse(audio.isDucking)
        XCTAssertFalse(audio.isActive)
    }

    func testInterruptionNotificationsReportBeganAndBothResumeValues() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        let activated = await activate(audio)
        XCTAssertTrue(activated)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        XCTAssertTrue(audio.isActive)
        XCTAssertTrue(audio.isDucking)
        var events: [AudioSessionEvent] = []
        audio.onEvent = { events.append($0) }
        let center = NotificationCenter.default
        let shared = AVAudioSession.sharedInstance()
        let callsBeforeInterruption = [
            RecordingAudioSessioning.Call.category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                                                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                      ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, []),
            .active(false, []),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                      ["allowBluetoothA2DP", "defaultToSpeaker", "duckOthers", "mixWithOthers"]),
            .active(true, [])
        ]

        center.post(name: AVAudioSession.interruptionNotification, object: shared, userInfo: [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)
        ])
        await audio.waitForPendingSessionWork()
        XCTAssertFalse(audio.isDucking)
        XCTAssertFalse(audio.isActive)
        XCTAssertEqual(session.calls, callsBeforeInterruption)
        center.post(name: AVAudioSession.interruptionNotification, object: shared, userInfo: [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
            AVAudioSessionInterruptionOptionKey: NSNumber(value: 0)
        ])
        await audio.waitForPendingSessionWork()
        center.post(name: AVAudioSession.interruptionNotification, object: shared, userInfo: [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
            AVAudioSessionInterruptionOptionKey:
                NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        ])
        await audio.waitForPendingSessionWork()

        XCTAssertEqual(events, [
            .interruptionDiagnostic(type: "began", reason: nil, wasSuspended: false, shouldResume: nil),
            .interruptionBegan,
            .interruptionDiagnostic(type: "ended", reason: nil, wasSuspended: false, shouldResume: false),
            .interruptionEnded(shouldResume: false),
            .interruptionDiagnostic(type: "ended", reason: nil, wasSuspended: false, shouldResume: true),
            .interruptionEnded(shouldResume: true)
        ])
    }

    func testRouteNotificationReasonsAndMediaServicesReset() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        var events: [AudioSessionEvent] = []
        audio.onEvent = { events.append($0) }
        let center = NotificationCenter.default
        let shared = AVAudioSession.sharedInstance()
        let reasons: [(AVAudioSession.RouteChangeReason, Bool)] = [
            (.unknown, false), (.newDeviceAvailable, true), (.oldDeviceUnavailable, true), (.categoryChange, false),
            (.override, false), (.wakeFromSleep, false), (.noSuitableRouteForCategory, false),
            (.routeConfigurationChange, false)
        ]

        for (reason, isDeviceChange) in reasons {
            let start = events.count
            center.post(name: AVAudioSession.routeChangeNotification, object: shared, userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: reason.rawValue)
            ])
            await audio.waitForPendingSessionWork()
            let expected = [AudioSessionEvent.routeDiagnostic(reason: Int(reason.rawValue),
                                                               outputs: session.outputs, inputs: session.inputs)]
                + (isDeviceChange ? [.routeChanged] : [])
            XCTAssertEqual(Array(events.dropFirst(start)), expected, "Reason \(reason.rawValue)")
        }

        audio.setRecordingEnabled(true)
        let activated = await activate(audio)
        XCTAssertTrue(activated)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        XCTAssertTrue(audio.isDucking)
        XCTAssertTrue(audio.isActive)
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: shared)
        await audio.waitForPendingSessionWork()

        XCTAssertEqual(events.last, .mediaServicesReset)
        XCTAssertFalse(audio.isActive)
        XCTAssertFalse(audio.isDucking)
        XCTAssertEqual(session.calls, [
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                      ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                      ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, []),
            .active(false, []),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                      ["allowBluetoothA2DP", "defaultToSpeaker", "duckOthers", "mixWithOthers"]),
            .active(true, []),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                      ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"])
        ])
        XCTAssertEqual(session.calls.suffix(1), [
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"])
        ])
    }

    func testListeningActivationAndCategoryFailuresAreReportedPrecisely() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        await audio.waitForPendingSessionWork()
        session.categoryFailures = 1

        audio.configureBaseCategory()
        await audio.waitForPendingSessionWork()
        session.activeFailures = [true]
        let activated = await activate(audio)
        XCTAssertFalse(activated)
        XCTAssertFalse(audio.isActive)

        XCTAssertEqual(session.calls, [
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, [])
        ])
    }

    func testDuckCategoryFailureAndActivationFailureBothRestoreBaseState() async {
        let categoryFailureSession = RecordingAudioSessioning()
        let categoryFailureAudio = WorkoutAudioSession(session: categoryFailureSession)
        categoryFailureAudio.setRecordingEnabled(true)
        await categoryFailureAudio.waitForPendingSessionWork()
        categoryFailureSession.categoryFailures = 1
        categoryFailureAudio.beginDucking()
        await categoryFailureAudio.waitForPendingSessionWork()
        XCTAssertFalse(categoryFailureAudio.isDucking)
        XCTAssertEqual(categoryFailureSession.calls, [
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "duckOthers", "mixWithOthers"])
        ])

        let activationFailureSession = RecordingAudioSessioning()
        let activationFailureAudio = WorkoutAudioSession(session: activationFailureSession)
        activationFailureAudio.setRecordingEnabled(true)
        let activated = await activate(activationFailureAudio)
        XCTAssertTrue(activated)
        activationFailureSession.activeFailures = [true]
        activationFailureAudio.beginDucking()
        await activationFailureAudio.waitForPendingSessionWork()
        XCTAssertFalse(activationFailureAudio.isDucking)
        XCTAssertTrue(activationFailureAudio.isActive)
        XCTAssertEqual(activationFailureSession.calls, [
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, []),
            .active(false, []),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "duckOthers", "mixWithOthers"]),
            .active(true, []),
            .active(false, ["notifyOthersOnDeactivation"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, [])
        ])
    }

    func testBusyRestoreDeactivationRecordsFirstRetryAttemptWithoutWaiting() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        let activated = await activate(audio)
        XCTAssertTrue(activated)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        session.activeFailures = [false]

        audio.endDucking()
        await audio.waitForPendingSessionWork()

        XCTAssertFalse(audio.isDucking)
        XCTAssertTrue(audio.isActive, "The first busy restore leaves the session active until its scheduled retry.")
        XCTAssertEqual(session.calls.suffix(1), [.active(false, ["notifyOthersOnDeactivation"])])
    }

    func testEndDuckingReturnsPromptlyWhileRestoreRunsOnTheSessionWorker() async {
        let session = RecordingAudioSessioning()
        let timing = AudioWorkTiming()
        var measurements: [(AudioWorkStep, TimeInterval, AudioWorkExecutionContext)] = []
        timing.onMeasured = { measurements.append(($0, $1, $2)) }
        let audio = WorkoutAudioSession(timing: timing, session: session)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        session.blockNextRestore()

        let start = ProcessInfo.processInfo.systemUptime
        audio.endDucking()
        let returnDuration = ProcessInfo.processInfo.systemUptime - start

        let restoreWasBlocked = await session.waitForBlockedRestore()
        XCTAssertTrue(restoreWasBlocked)
        XCTAssertLessThan(returnDuration, 0.1, "The MainActor request must return while setActive is blocked.")
        try? await Task.sleep(nanoseconds: 20_000_000)
        session.releaseBlockedRestore()
        await audio.waitForPendingSessionWork()
        XCTAssertFalse(audio.isDucking)
        XCTAssertFalse(audio.isActive)
        XCTAssertGreaterThanOrEqual(measurements.first(where: { $0.0 == .restoreOtherAudio })?.1 ?? 0, 0.02)
        XCTAssertEqual(measurements.first(where: { $0.0 == .restoreOtherAudio })?.2, .worker)
    }

    func testDuckingCompletionWaitsUntilTheOtherAudioIsActuallyDucked() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        session.blockNextDuckActivation()
        var completed = false

        audio.beginDucking { completed = true }

        let duckActivationWasBlocked = await session.waitForBlockedDuckActivation()
        XCTAssertTrue(duckActivationWasBlocked)
        XCTAssertFalse(completed)
        session.releaseBlockedDuckActivation()
        await audio.waitForPendingSessionWork()

        XCTAssertTrue(completed)
        XCTAssertTrue(audio.isDucking)
    }

    func testTeardownDrainsAfterAudioOwnerIsReleasedDuringDuckActivation() async {
        let session = RecordingAudioSessioning()
        var audio: WorkoutAudioSession? = WorkoutAudioSession(session: session)
        session.blockNextDuckActivation()

        audio?.beginDucking()
        let duckActivationWasBlocked = await session.waitForBlockedDuckActivation()
        XCTAssertTrue(duckActivationWasBlocked)

        let teardownCompleted = expectation(description: "queued teardown completes after owner release")
        audio?.deactivate { teardownCompleted.fulfill() }
        audio = nil
        session.releaseBlockedDuckActivation()

        await fulfillment(of: [teardownCompleted], timeout: 2)

        XCTAssertEqual(session.calls.filter {
            if case .active(false, ["notifyOthersOnDeactivation"]) = $0 { return true }
            return false
        }.count, 2, "Both duck restoration and final teardown deactivation must run.")
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers))
    }

    func testDuckRequestedDuringRestoreWinsAndDoubleEndIsIdempotent() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        session.blockNextRestore()

        audio.endDucking()
        let restoreWasBlocked = await session.waitForBlockedRestore()
        XCTAssertTrue(restoreWasBlocked)
        audio.endDucking()
        audio.beginDucking()
        session.releaseBlockedRestore()
        await audio.waitForPendingSessionWork()

        XCTAssertTrue(audio.isDucking)
        XCTAssertTrue(session.categoryOptions.contains(.duckOthers))
        XCTAssertEqual(session.calls.filter {
            if case .active(false, ["notifyOthersOnDeactivation"]) = $0 { return true }
            return false
        }.count, 1)
    }

    func testTeardownDuringRestoreLeavesSessionRestoredAndInactive() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        session.blockNextRestore()

        audio.endDucking()
        let restoreWasBlocked = await session.waitForBlockedRestore()
        XCTAssertTrue(restoreWasBlocked)
        audio.deactivate()
        session.releaseBlockedRestore()
        await audio.waitForPendingSessionWork()

        XCTAssertFalse(audio.isDucking)
        XCTAssertFalse(audio.isActive)
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers))
        XCTAssertEqual(session.calls.suffix(1), [.active(false, ["notifyOthersOnDeactivation"])])
    }

    func testTeardownRetriesBusyRestoreWithoutReactivatingListening() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        let activated = await activate(audio)
        XCTAssertTrue(activated)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()

        session.activeFailures = [false, false]
        let teardownCallStart = session.calls.count
        var teardownDeactivationEvents = 0
        let retryCompleted = expectation(description: "busy teardown restoration retry completes")
        audio.onEvent = { event in
            guard case .sessionOperation(let operation, let active, _, _, _, _, _, _) = event,
                  operation == "setActive", active == false else { return }
            teardownDeactivationEvents += 1
            if teardownDeactivationEvents == 3 { retryCompleted.fulfill() }
        }

        audio.deactivate()
        await fulfillment(of: [retryCompleted], timeout: 2)
        await audio.waitForPendingSessionWork()

        let teardownCalls = session.calls.dropFirst(teardownCallStart)
        let notifyDeactivations = teardownCalls.filter {
            if case .active(false, ["notifyOthersOnDeactivation"]) = $0 { return true }
            return false
        }
        XCTAssertEqual(notifyDeactivations.count, 3, "Two busy attempts must be followed by a successful retry.")
        XCTAssertFalse(teardownCalls.contains {
            if case .active(true, _) = $0 { return true }
            return false
        }, "Teardown must not reactivate listening.")
        XCTAssertFalse(audio.isDucking)
        XCTAssertFalse(audio.isActive)
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers))
    }

    func testRestoreRetriesToTheLimitAndReactivationEventReturnsOnMainActor() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        let activated = await activate(audio)
        XCTAssertTrue(activated)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        session.activeFailures = [false]
        var reactivatedEvents = 0
        var eventWasOnMainThread = false
        let reactivated = expectation(description: "a retry reactivates listening")
        audio.onEvent = { event in
            guard event == .reactivated else { return }
            reactivatedEvents += 1
            eventWasOnMainThread = Thread.isMainThread
            reactivated.fulfill()
        }

        audio.endDucking()
        await fulfillment(of: [reactivated], timeout: 2)
        await audio.waitForPendingSessionWork()

        XCTAssertEqual(reactivatedEvents, 1)
        XCTAssertTrue(eventWasOnMainThread)
        XCTAssertFalse(audio.isDucking)
        XCTAssertTrue(audio.isActive)
        XCTAssertEqual(session.calls.filter {
            if case .active(false, ["notifyOthersOnDeactivation"]) = $0 { return true }
            return false
        }.count, 2)
    }

    func testRestoreStopsAfterMaximumAttemptsWithoutLeavingDuckingEnabled() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.beginDucking()
        await audio.waitForPendingSessionWork()
        session.activeFailures = Array(repeating: false, count: WorkoutAudioSession.maximumRestoreAttempts)
        var deactivationAttempts = 0
        let restoreExhausted = expectation(description: "restore attempts reach their configured maximum")
        audio.onEvent = { event in
            guard case .sessionOperation(let operation, let active, _, _, _, _, _, _) = event,
                  operation == "setActive", active == false else { return }
            deactivationAttempts += 1
            if deactivationAttempts == WorkoutAudioSession.maximumRestoreAttempts {
                restoreExhausted.fulfill()
            }
        }

        audio.endDucking()
        await fulfillment(of: [restoreExhausted], timeout: 3)
        await audio.waitForPendingSessionWork()

        XCTAssertFalse(audio.isDucking)
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers))
        XCTAssertEqual(session.calls.filter {
            if case .active(false, ["notifyOthersOnDeactivation"]) = $0 { return true }
            return false
        }.count, WorkoutAudioSession.maximumRestoreAttempts)
    }

    func testFailedPreDuckDeactivateStillDucksAndFailedRestoreActivationLeavesSessionInactive() async {
        let preDuckSession = RecordingAudioSessioning()
        let preDuckAudio = WorkoutAudioSession(session: preDuckSession)
        preDuckAudio.setRecordingEnabled(true)
        let preDuckActivated = await activate(preDuckAudio)
        XCTAssertTrue(preDuckActivated)
        preDuckSession.activeFailures = [false]

        preDuckAudio.beginDucking()
        await preDuckAudio.waitForPendingSessionWork()

        XCTAssertTrue(preDuckAudio.isDucking)
        XCTAssertTrue(preDuckAudio.isActive)
        XCTAssertEqual(preDuckSession.calls.suffix(3), [
            .active(false, []),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "duckOthers", "mixWithOthers"]),
            .active(true, [])
        ])

        let restoreSession = RecordingAudioSessioning()
        let restoreAudio = WorkoutAudioSession(session: restoreSession)
        restoreAudio.setRecordingEnabled(true)
        let restoreActivated = await activate(restoreAudio)
        XCTAssertTrue(restoreActivated)
        restoreAudio.beginDucking()
        await restoreAudio.waitForPendingSessionWork()
        restoreSession.activeFailures = [true]

        restoreAudio.endDucking()
        await restoreAudio.waitForPendingSessionWork()

        XCTAssertFalse(restoreAudio.isDucking)
        XCTAssertFalse(restoreAudio.isActive)
        XCTAssertEqual(restoreSession.calls.suffix(3), [
            .active(false, ["notifyOthersOnDeactivation"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, [])
        ])
    }

    func testStopListeningAndFinalDeactivationSwallowDeactivateFailures() async {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        let activated = await activate(audio)
        XCTAssertTrue(activated)
        session.activeFailures = [false]

        audio.stopListening()
        await audio.waitForPendingSessionWork()

        XCTAssertFalse(audio.isActive)
        XCTAssertEqual(session.calls.suffix(1), [.active(false, ["notifyOthersOnDeactivation"])])

        let reactivated = await activate(audio)
        XCTAssertTrue(reactivated)
        session.activeFailures = [false]
        audio.deactivate()
        await audio.waitForPendingSessionWork()

        XCTAssertFalse(audio.isActive)
        XCTAssertEqual(session.calls.suffix(1), [.active(false, ["notifyOthersOnDeactivation"])])
    }

    private func activate(_ audio: WorkoutAudioSession) async -> Bool {
        await withCheckedContinuation { continuation in
            audio.activateForListening { continuation.resume(returning: $0) }
        }
    }
}

private final class RecordingAudioSessioning: AudioSessioning {
    enum Call: Equatable {
        case category(String, String, AVAudioSession.CategoryOptions.RawValue, [String])
        case active(Bool, [String])

        static func category(_ category: String, _ mode: String, _ optionNames: [String]) -> Call {
            var options: AVAudioSession.CategoryOptions = []
            let known: [(String, AVAudioSession.CategoryOptions)] = [
                ("duckOthers", .duckOthers), ("mixWithOthers", .mixWithOthers),
                ("defaultToSpeaker", .defaultToSpeaker), ("allowBluetooth", .allowBluetooth),
                ("allowBluetoothA2DP", .allowBluetoothA2DP), ("allowAirPlay", .allowAirPlay),
                ("interruptSpokenAudioAndMixWithOthers", .interruptSpokenAudioAndMixWithOthers)
            ]
            for name in optionNames {
                if let option = known.first(where: { $0.0 == name })?.1 { options.insert(option) }
            }
            return .category(category, mode, options.rawValue, optionNames)
        }
    }

    private(set) var calls: [Call] = []
    private(set) var category = AVAudioSession.Category.playback.rawValue
    private(set) var mode = AVAudioSession.Mode.default.rawValue
    private(set) var categoryOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
    let outputs = ["BuiltInSpeaker"]
    let inputs = ["BuiltInMic"]
    let isOtherAudioPlaying = true
    let secondaryAudioShouldBeSilenced = false
    var categoryFailures = 0
    var activeFailures: [Bool] = []
    private let blockedRestoreStarted = DispatchSemaphore(value: 0)
    private let releaseBlockedRestoreSemaphore = DispatchSemaphore(value: 0)
    private let blockedDuckStarted = DispatchSemaphore(value: 0)
    private let releaseBlockedDuckSemaphore = DispatchSemaphore(value: 0)
    private let blockNextRestoreSemaphore = DispatchSemaphore(value: 0)
    private let blockNextDuckSemaphore = DispatchSemaphore(value: 0)

    func blockNextRestore() {
        blockNextRestoreSemaphore.signal()
    }

    /// Wait off the MainActor: the facade starts its worker command from a MainActor task, so a synchronous
    /// semaphore wait here would prevent that task from running and the fake would never reach its blocked call.
    func waitForBlockedRestore() async -> Bool {
        await waitForSignal(blockedRestoreStarted)
    }

    func releaseBlockedRestore() {
        releaseBlockedRestoreSemaphore.signal()
    }

    func blockNextDuckActivation() {
        blockNextDuckSemaphore.signal()
    }

    func waitForBlockedDuckActivation() async -> Bool {
        await waitForSignal(blockedDuckStarted)
    }

    func releaseBlockedDuckActivation() {
        releaseBlockedDuckSemaphore.signal()
    }

    private func waitForSignal(_ semaphore: DispatchSemaphore) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + 1) == .success)
            }
        }
    }

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        let optionNames = Self.categoryOptionNames(options)
        calls.append(.category(category.rawValue, mode.rawValue, options.rawValue, optionNames))
        if categoryFailures > 0 {
            categoryFailures -= 1
            throw RecordingFailure.failed
        }
        self.category = category.rawValue
        self.mode = mode.rawValue
        categoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        let optionNames = options.contains(.notifyOthersOnDeactivation) ? ["notifyOthersOnDeactivation"] : []
        calls.append(.active(active, optionNames))
        if active, blockNextDuckSemaphore.wait(timeout: .now()) == .success {
            blockedDuckStarted.signal()
            _ = releaseBlockedDuckSemaphore.wait(timeout: .now() + 2)
        }
        if !active, options.contains(.notifyOthersOnDeactivation),
           blockNextRestoreSemaphore.wait(timeout: .now()) == .success {
            blockedRestoreStarted.signal()
            _ = releaseBlockedRestoreSemaphore.wait(timeout: .now() + 2)
        }
        if activeFailures.first == active {
            activeFailures.removeFirst()
            throw RecordingFailure.failed
        }
    }

    private static func categoryOptionNames(_ options: AVAudioSession.CategoryOptions) -> [String] {
        let known: [(AVAudioSession.CategoryOptions, String)] = [
            (.duckOthers, "duckOthers"), (.mixWithOthers, "mixWithOthers"),
            (.defaultToSpeaker, "defaultToSpeaker"), (.allowBluetooth, "allowBluetooth"),
            (.allowBluetoothA2DP, "allowBluetoothA2DP"), (.allowAirPlay, "allowAirPlay"),
            (.interruptSpokenAudioAndMixWithOthers, "interruptSpokenAudioAndMixWithOthers")
        ]
        return known.compactMap { options.contains($0.0) ? $0.1 : nil }.sorted()
    }
}

private enum RecordingFailure: Error {
    case failed
}
