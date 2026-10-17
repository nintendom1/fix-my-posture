import Foundation
import Observation

/// Owns the camera edge toolbar's three-second visibility window.
@MainActor
@Observable
final class EdgeToolbarVisibilityController {
    static let hideDelay: TimeInterval = 3

    private(set) var isVisible = true

    @ObservationIgnored private let scheduler: any Scheduling
    @ObservationIgnored private let isVoiceOverRunning: () -> Bool
    @ObservationIgnored private var hideTask: (any Cancellable)?

    init(scheduler: (any Scheduling)? = nil,
         isVoiceOverRunning: @escaping () -> Bool) {
        self.scheduler = scheduler ?? MainScheduler()
        self.isVoiceOverRunning = isVoiceOverRunning
    }

    func onAppear() {
        isVisible = true
        scheduleHide()
    }

    /// Called for any camera-screen interaction, including a toolbar button or the reveal handle.
    func interact() {
        isVisible = true
        scheduleHide()
    }

    /// Rechecks the injected VoiceOver source after UIKit posts its status-change notification.
    func voiceOverStatusChanged() {
        if isVoiceOverRunning() {
            isVisible = true
            cancelHide()
        } else if isVisible {
            scheduleHide()
        }
    }

    func disappear() {
        cancelHide()
    }

    private func scheduleHide() {
        cancelHide()
        guard !isVoiceOverRunning() else { return }
        hideTask = scheduler.schedule(after: Self.hideDelay) { [weak self] in
            guard let self else { return }
            self.hideTask = nil
            if self.isVoiceOverRunning() {
                self.isVisible = true
            } else {
                self.isVisible = false
            }
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}
