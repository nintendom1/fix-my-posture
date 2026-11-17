import Foundation

/// A dormant, delegation-only facade over the single audio-session owner (#132 phase 2). Not wired into production.
@MainActor
protocol AudioCoordinating: AudioSessionControlling {}

/// Forwards audio-session requests and events to `WorkoutAudioSession`, which remains the sole system owner.
@MainActor
final class WorkoutAudioCoordinator: AudioCoordinating {
    private let owner: any AudioSessionControlling

    var onEvent: ((AudioSessionEvent) -> Void)? {
        get { owner.onEvent }
        set { owner.onEvent = newValue }
    }

    init(owner: any AudioSessionControlling) {
        self.owner = owner
    }

    func configureBaseCategory() {
        owner.configureBaseCategory()
    }

    func setRecordingEnabled(_ enabled: Bool) {
        owner.setRecordingEnabled(enabled)
    }

    func activateForListening() -> Bool {
        owner.activateForListening()
    }

    func activateForListening(completion: @escaping @MainActor (Bool) -> Void) {
        owner.activateForListening(completion: completion)
    }

    func stopListening() {
        owner.stopListening()
    }

    func beginDucking() {
        owner.beginDucking()
    }

    func beginDucking(completion: @escaping @MainActor () -> Void) {
        owner.beginDucking(completion: completion)
    }

    func endDucking() {
        owner.endDucking()
    }

    func endDucking(completion: @escaping @MainActor () -> Void) {
        owner.endDucking(completion: completion)
    }

    func deactivate() {
        owner.deactivate()
    }
}
