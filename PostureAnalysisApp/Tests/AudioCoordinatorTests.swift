import XCTest
@testable import PostureAnalysisApp

/// Tests for the dormant audio-session facade and future cue vocabulary.
@MainActor
final class AudioCoordinatorTests: XCTestCase {
    func testCoordinatorDelegatesEveryMethodAndForwardsEveryEventInOrder() {
        let direct = RecordingAudioSessionController()
        let delegatedOwner = RecordingAudioSessionController()
        let coordinator = WorkoutAudioCoordinator(owner: delegatedOwner)
        var directEvents: [AudioSessionEvent] = []
        var coordinatorEvents: [AudioSessionEvent] = []
        direct.onEvent = { directEvents.append($0) }
        coordinator.onEvent = { coordinatorEvents.append($0) }

        direct.configureBaseCategory()
        coordinator.configureBaseCategory()
        direct.setRecordingEnabled(true)
        coordinator.setRecordingEnabled(true)
        direct.setRecordingEnabled(false)
        coordinator.setRecordingEnabled(false)
        XCTAssertEqual(direct.activateForListening(), coordinator.activateForListening())
        direct.activationResult = false
        delegatedOwner.activationResult = false
        XCTAssertFalse(direct.activateForListening())
        XCTAssertFalse(coordinator.activateForListening())
        direct.stopListening()
        coordinator.stopListening()
        direct.beginDucking()
        coordinator.beginDucking()
        direct.endDucking()
        coordinator.endDucking()
        direct.deactivate()
        coordinator.deactivate()

        let events: [AudioSessionEvent] = [
            .interruptionBegan,
            .interruptionEnded(shouldResume: true),
            .interruptionDiagnostic(type: "ended", reason: 1, wasSuspended: false, shouldResume: true),
            .mediaServicesReset,
            .routeChanged,
            .routeDiagnostic(reason: 1, outputs: ["BuiltInSpeaker"], inputs: ["BuiltInMic"]),
            .sessionOperation(operation: "setActive", active: true, category: "playback", mode: "default",
                              categoryOptions: ["mixWithOthers"], activeOptions: [],
                              isOtherAudioPlaying: true, secondaryAudioShouldBeSilenced: false),
            .reactivated
        ]
        for event in events {
            direct.emit(event)
            delegatedOwner.emit(event)
        }

        XCTAssertEqual(direct.calls, delegatedOwner.calls)
        XCTAssertEqual(direct.calls, [
            "configureBaseCategory", "setRecordingEnabled:true", "setRecordingEnabled:false",
            "activateForListening", "activateForListening", "stopListening", "beginDucking", "endDucking", "deactivate"
        ])
        XCTAssertEqual(directEvents, events)
        XCTAssertEqual(coordinatorEvents, events)
    }

    func testCoordinatorEventHandlerCanBeReadReplacedAndCleared() {
        let owner = RecordingAudioSessionController()
        let coordinator = WorkoutAudioCoordinator(owner: owner)
        var firstHandlerEvents: [AudioSessionEvent] = []
        var replacementHandlerEvents: [AudioSessionEvent] = []

        coordinator.onEvent = { firstHandlerEvents.append($0) }
        XCTAssertNotNil(coordinator.onEvent)
        owner.emit(.interruptionBegan)

        coordinator.onEvent = { replacementHandlerEvents.append($0) }
        XCTAssertNotNil(coordinator.onEvent)
        owner.emit(.routeChanged)
        XCTAssertEqual(firstHandlerEvents, [.interruptionBegan])
        XCTAssertEqual(replacementHandlerEvents, [.routeChanged])

        coordinator.onEvent = nil
        XCTAssertNil(coordinator.onEvent)
        XCTAssertNil(owner.onEvent)
        owner.emit(.mediaServicesReset)
        XCTAssertEqual(replacementHandlerEvents, [.routeChanged])
    }

    func testSoundCueIDsAreUniqueStableLowercaseDottedValues() {
        let identifiers = SoundCueID.allCases.map(\.rawValue)

        XCTAssertEqual(identifiers, [
            "rep.counted", "set.completed", "rest.started", "rest.ending",
            "workout.completed", "menu.select", "dialogue.advance"
        ])
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        for identifier in identifiers {
            let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
            XCTAssertEqual(identifier, identifier.lowercased())
            XCTAssertGreaterThan(components.count, 1)
            XCTAssertTrue(components.allSatisfy { component in
                !component.isEmpty && component.allSatisfy { $0.isLowercase || $0.isNumber }
            })
        }
    }

    func testAudioPriorityAndRecognitionDuckingPolicy() {
        XCTAssertGreaterThan(AudioPriority.speech.rawValue, AudioPriority.soundEffect.rawValue)
        XCTAssertGreaterThan(AudioPriority.soundEffect.rawValue, AudioPriority.backgroundMusic.rawValue)
        XCTAssertEqual(AudioPriority.backgroundMusic.recognitionPolicy, .pauseDuringRecognition)
        XCTAssertEqual(AudioPriority.soundEffect.recognitionPolicy, .pauseDuringRecognition)
        XCTAssertEqual(AudioPriority.speech.recognitionPolicy, .unaffected)
        XCTAssertEqual(AudioPriority.backgroundMusic.speechPolicy, .duckForSpeech)
        XCTAssertEqual(AudioPriority.soundEffect.speechPolicy, .duckForSpeech)
        XCTAssertEqual(AudioPriority.speech.speechPolicy, .unaffected)
    }
}

@MainActor
private final class RecordingAudioSessionController: AudioSessionControlling {
    var onEvent: ((AudioSessionEvent) -> Void)?
    private(set) var calls: [String] = []
    var activationResult = true

    func configureBaseCategory() {
        calls.append("configureBaseCategory")
    }

    func setRecordingEnabled(_ enabled: Bool) {
        calls.append("setRecordingEnabled:\(enabled)")
    }

    func activateForListening() -> Bool {
        calls.append("activateForListening")
        return activationResult
    }

    func stopListening() {
        calls.append("stopListening")
    }

    func beginDucking() {
        calls.append("beginDucking")
    }

    func endDucking() {
        calls.append("endDucking")
    }

    func deactivate() {
        calls.append("deactivate")
    }

    func emit(_ event: AudioSessionEvent) {
        onEvent?(event)
    }
}
