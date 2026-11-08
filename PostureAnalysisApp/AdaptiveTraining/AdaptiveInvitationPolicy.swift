import AdaptiveTraining
import Foundation

/// When the launch invitation to find a starting point appears (#111). Filled in by the today-hero package.
enum AdaptiveInvitationPolicy {
    static let snoozeDays = 7
    static let maxDismissals = 3

    static func shouldShow(status: TodaySessionStatus, snoozedUntil: Date?, dismissCount: Int,
                           isPresentingFullScreen: Bool, now: Date) -> Bool {
        guard case .needsCalibration = status,
              !isPresentingFullScreen,
              dismissCount < maxDismissals else {
            return false
        }
        return snoozedUntil.map { now >= $0 } ?? true
    }
}
