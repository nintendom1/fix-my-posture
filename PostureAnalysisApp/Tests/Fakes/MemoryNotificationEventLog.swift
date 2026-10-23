import Foundation
@testable import PostureAnalysisApp

/// Keeps notification log messages in memory so tests can read them back.
final class MemoryNotificationEventLog: NotificationEventRecording {
    private(set) var messages: [String] = []

    func record(_ message: String) {
        messages.append(message)
    }

    func contains(_ fragment: String) -> Bool {
        messages.contains { $0.contains(fragment) }
    }
}
