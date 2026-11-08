import AVFoundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AudioSessionParityTests: XCTestCase {
    func testPlaybackAndRecordingCategoriesActivationAndDeactivation() {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)

        audio.configureBaseCategory()
        audio.setRecordingEnabled(true)
        XCTAssertTrue(audio.activateForListening())
        audio.stopListening()

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

    func testDuckingAndRestoreOrderWhileListening() {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        XCTAssertTrue(audio.activateForListening())

        audio.beginDucking()
        XCTAssertTrue(audio.isDucking)
        audio.endDucking()

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

    func testSpeechDuckingWithoutListeningDoesNotReactivateAfterSpeech() {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)

        audio.beginDucking()
        audio.endDucking()

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

    func testDeactivateEndsDuckingAndReleasesListeningSession() {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        XCTAssertTrue(audio.activateForListening())
        audio.beginDucking()

        audio.deactivate()

        XCTAssertEqual(session.calls.suffix(3), [
            .active(false, ["notifyOthersOnDeactivation"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(false, ["notifyOthersOnDeactivation"])
        ])
        XCTAssertFalse(audio.isDucking)
        XCTAssertFalse(audio.isActive)
    }

    func testInterruptionNotificationsReportBeganAndBothResumeValues() {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        XCTAssertTrue(audio.activateForListening())
        audio.beginDucking()
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
        XCTAssertFalse(audio.isDucking)
        XCTAssertFalse(audio.isActive)
        XCTAssertEqual(session.calls, callsBeforeInterruption)
        center.post(name: AVAudioSession.interruptionNotification, object: shared, userInfo: [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
            AVAudioSessionInterruptionOptionKey: NSNumber(value: 0)
        ])
        center.post(name: AVAudioSession.interruptionNotification, object: shared, userInfo: [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
            AVAudioSessionInterruptionOptionKey:
                NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        ])

        XCTAssertEqual(events, [
            .interruptionDiagnostic(type: "began", reason: nil, wasSuspended: false, shouldResume: nil),
            .interruptionBegan,
            .interruptionDiagnostic(type: "ended", reason: nil, wasSuspended: false, shouldResume: false),
            .interruptionEnded(shouldResume: false),
            .interruptionDiagnostic(type: "ended", reason: nil, wasSuspended: false, shouldResume: true),
            .interruptionEnded(shouldResume: true)
        ])
    }

    func testRouteNotificationReasonsAndMediaServicesReset() {
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
            let expected = [AudioSessionEvent.routeDiagnostic(reason: Int(reason.rawValue),
                                                               outputs: session.outputs, inputs: session.inputs)]
                + (isDeviceChange ? [.routeChanged] : [])
            XCTAssertEqual(Array(events.dropFirst(start)), expected, "Reason \(reason.rawValue)")
        }

        audio.setRecordingEnabled(true)
        XCTAssertTrue(audio.activateForListening())
        audio.beginDucking()
        XCTAssertTrue(audio.isDucking)
        XCTAssertTrue(audio.isActive)
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: shared)

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

    func testListeningActivationAndCategoryFailuresAreReportedPrecisely() {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        session.categoryFailures = 1

        audio.configureBaseCategory()
        session.activeFailures = [true]
        XCTAssertFalse(audio.activateForListening())
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

    func testDuckCategoryFailureAndActivationFailureBothRestoreBaseState() {
        let categoryFailureSession = RecordingAudioSessioning()
        let categoryFailureAudio = WorkoutAudioSession(session: categoryFailureSession)
        categoryFailureAudio.setRecordingEnabled(true)
        categoryFailureSession.categoryFailures = 1
        categoryFailureAudio.beginDucking()
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
        XCTAssertTrue(activationFailureAudio.activateForListening())
        activationFailureSession.activeFailures = [true]
        activationFailureAudio.beginDucking()
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

    func testBusyRestoreDeactivationRecordsFirstRetryAttemptWithoutWaiting() {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        XCTAssertTrue(audio.activateForListening())
        audio.beginDucking()
        session.activeFailures = [false]

        audio.endDucking()

        XCTAssertFalse(audio.isDucking)
        XCTAssertTrue(audio.isActive, "The first busy restore leaves the session active until its scheduled retry.")
        XCTAssertEqual(session.calls.suffix(1), [.active(false, ["notifyOthersOnDeactivation"])])
    }

    func testFailedPreDuckDeactivateStillDucksAndFailedRestoreActivationLeavesSessionInactive() {
        let preDuckSession = RecordingAudioSessioning()
        let preDuckAudio = WorkoutAudioSession(session: preDuckSession)
        preDuckAudio.setRecordingEnabled(true)
        XCTAssertTrue(preDuckAudio.activateForListening())
        preDuckSession.activeFailures = [false]

        preDuckAudio.beginDucking()

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
        XCTAssertTrue(restoreAudio.activateForListening())
        restoreAudio.beginDucking()
        restoreSession.activeFailures = [true]

        restoreAudio.endDucking()

        XCTAssertFalse(restoreAudio.isDucking)
        XCTAssertFalse(restoreAudio.isActive)
        XCTAssertEqual(restoreSession.calls.suffix(3), [
            .active(false, ["notifyOthersOnDeactivation"]),
            .category("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionModeDefault",
                     ["allowBluetoothA2DP", "defaultToSpeaker", "mixWithOthers"]),
            .active(true, [])
        ])
    }

    func testStopListeningAndFinalDeactivationSwallowDeactivateFailures() {
        let session = RecordingAudioSessioning()
        let audio = WorkoutAudioSession(session: session)
        audio.setRecordingEnabled(true)
        XCTAssertTrue(audio.activateForListening())
        session.activeFailures = [false]

        audio.stopListening()

        XCTAssertFalse(audio.isActive)
        XCTAssertEqual(session.calls.suffix(1), [.active(false, ["notifyOthersOnDeactivation"])])

        XCTAssertTrue(audio.activateForListening())
        session.activeFailures = [false]
        audio.deactivate()

        XCTAssertFalse(audio.isActive)
        XCTAssertEqual(session.calls.suffix(1), [.active(false, ["notifyOthersOnDeactivation"])])
    }
}

@MainActor
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
