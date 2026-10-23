import Foundation

/// Chooses stable copy and art variants without per-launch randomness.
enum NotificationCopyPicker {

    private static let reference = Date(timeIntervalSince1970: 0)

    /// Counts calendar days from a fixed reference date.
    static func dayNumber(for date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Produces a deterministic, nonnegative variant index.
    static func variant(scenarioID: String, dayNumber: Int, slotIndex: Int) -> Int {
        let salt = scenarioID.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return max(0, dayNumber + salt + slotIndex)
    }
}
