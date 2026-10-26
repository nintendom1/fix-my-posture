import Foundation
import Observation
import UIKit

/// The developer list of workout session recordings: the recording toggle, sharing under readable names, a
/// copyable text report, and deletion. Recordings themselves are made by `WorkoutSessionRecorder` during a workout.
@MainActor
@Observable
final class WorkoutRecordingsViewModel {
    /// Applies to the next workout; one in progress keeps recording or not.
    var isRecordingEnabled: Bool {
        didSet { preferences.workoutRecordingEnabled = isRecordingEnabled }
    }

    private(set) var recordings: [WorkoutRecordingSummary] = []
    /// The recording whose report was just copied, for a brief confirmation.
    private(set) var copiedID: UUID?
    /// The recording whose report is being built.
    private(set) var copyingID: UUID?

    var totalBytes: Int { recordings.reduce(0) { $0 + $1.byteCount } }
    var unmarkedCount: Int { recordings.filter { $0.markerCount == 0 }.count }

    private let store: any WorkoutRecordingStoring
    private let preferences: any AppPreferencesStoring
    private let copy: (String) -> Void
    private let timeZone: TimeZone
    private let shareDirectory: URL
    private var shareURLs: [UUID: URL] = [:]

    init(store: any WorkoutRecordingStoring, preferences: any AppPreferencesStoring,
         copy: @escaping (String) -> Void = { UIPasteboard.general.string = $0 },
         timeZone: TimeZone = .current,
         shareDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutRecordingShares", isDirectory: true)) {
        self.store = store
        self.preferences = preferences
        self.copy = copy
        self.timeZone = timeZone
        self.shareDirectory = shareDirectory
        isRecordingEnabled = preferences.workoutRecordingEnabled
    }

    func refresh() {
        recordings = store.list()
        prepareShareFiles()
    }

    /// The file to share, under a readable name such as "FMP Push-Up 2026-10-25 2119.json".
    func shareURL(for id: UUID) -> URL {
        shareURLs[id] ?? store.fileURL(for: id)
    }

    func delete(_ id: UUID) {
        store.delete(id)
        refresh()
    }

    /// Keeps only recordings with markers.
    func deleteUnmarked() {
        for recording in recordings where recording.markerCount == 0 { store.delete(recording.id) }
        refresh()
    }

    /// Builds the recording's text report off the main actor and copies it.
    func copyReport(of id: UUID) async {
        guard let recording = recordings.first(where: { $0.id == id }), copyingID == nil else { return }
        copyingID = id
        let url = store.fileURL(for: id)
        let timeZone = timeZone
        let report = await Task.detached(priority: .userInitiated) {
            WorkoutRecordingReport.make(fileURL: url, title: recording.title, timeZone: timeZone)
        }.value
        copy(report)
        copyingID = nil
        copiedID = id
    }

    /// "FMP Push-Up 2026-10-25 2119.json", unique among the listed recordings.
    static func shareFileName(_ recording: WorkoutRecordingSummary, timeZone: TimeZone, taken: Set<String> = []) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let title = recording.title.components(separatedBy: CharacterSet(charactersIn: "/:\\\n\t"))
            .joined(separator: "-").trimmingCharacters(in: .whitespaces)
        let base = "FMP \(title.isEmpty ? "Workout" : title) \(formatter.string(from: recording.startedAt))"
        var name = "\(base).\(FileWorkoutRecordingStore.fileExtension)"
        var number = 2
        while taken.contains(name) {
            name = "\(base) (\(number)).\(FileWorkoutRecordingStore.fileExtension)"
            number += 1
        }
        return name
    }

    static func dateLabel(_ date: Date, timeZone: TimeZone = .current) -> String {
        WorkoutRecordingReport.dateLabel(date, timeZone: timeZone)
    }

    static func byteLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Hard links under readable names, so sharing needs no copy and no extra space.
    private func prepareShareFiles() {
        let manager = FileManager.default
        try? manager.removeItem(at: shareDirectory)
        try? manager.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
        var taken = Set<String>()
        shareURLs = [:]
        for recording in recordings {
            let name = Self.shareFileName(recording, timeZone: timeZone, taken: taken)
            taken.insert(name)
            let source = store.fileURL(for: recording.id)
            let link = shareDirectory.appendingPathComponent(name)
            if (try? manager.linkItem(at: source, to: link)) != nil || (try? manager.copyItem(at: source, to: link)) != nil {
                shareURLs[recording.id] = link
            }
        }
    }
}
