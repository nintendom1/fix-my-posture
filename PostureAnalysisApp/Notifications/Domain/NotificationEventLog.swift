import Foundation

/// Records what the notification code decided and what iOS accepted, so a problem seen on a real iPhone
/// can be explained afterwards. Messages are plain text kept on the device; nothing is sent anywhere.
protocol NotificationEventRecording: AnyObject {
    func record(_ message: String)
}

/// Discards every message. It is the default, so tests and previews stay quiet.
final class NoNotificationEventLog: NotificationEventRecording {
    func record(_ message: String) {}
}

/// Keeps the newest lines in a text file in the caches folder. Safe to call from any thread.
final class FileNotificationEventLog: NotificationEventRecording {
    static let defaultMaximumLines = 300

    let url: URL
    private let maximumLines: Int
    private let now: () -> Date
    private let lock = NSLock()

    init(
        url: URL = FileNotificationEventLog.defaultURL(),
        maximumLines: Int = FileNotificationEventLog.defaultMaximumLines,
        now: @escaping () -> Date = Date.init
    ) {
        self.url = url
        self.maximumLines = max(1, maximumLines)
        self.now = now
    }

    static func defaultURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notification-events.log")
    }

    func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        var lines = readLines()
        lines.append("\(now().eventLogDescription) \(message)")
        if lines.count > maximumLines {
            lines.removeFirst(lines.count - maximumLines)
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// The newest `count` lines, oldest first.
    func recentLines(_ count: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(readLines().suffix(max(0, count)))
    }

    private func readLines() -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

extension Date {
    /// A local date and time such as "2026-10-24 08:18:00", used in notification logs and reports.
    var eventLogDescription: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}
