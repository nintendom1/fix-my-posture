import Foundation

/// A recording's summary, kept beside it so lists don't read the whole file.
struct WorkoutRecordingSummary: Codable, Equatable, Identifiable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    /// The Saved Set's name, or the exercises done.
    var title: String
    var exerciseIDs: [String]
    var frameCount: Int
    var markerCount: Int
    /// False until the recording ends normally; a crash or force-quit leaves it false.
    var isComplete: Bool
    /// The file's size when listed; not stored.
    var byteCount: Int = 0
    /// Counts were rebuilt from the file, because the recording didn't end normally.
    var isRecovered: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, title, exerciseIDs, frameCount, markerCount, isComplete, isRecovered
    }
}

/// Where workout recordings live on the phone.
protocol WorkoutRecordingStoring: AnyObject {
    /// Starts a new recording file, or nil when it can't be created.
    func makeWriter(for id: UUID) -> WorkoutSessionWriting?
    func saveSummary(_ summary: WorkoutRecordingSummary)
    /// Newest first.
    func list() -> [WorkoutRecordingSummary]
    func fileURL(for id: UUID) -> URL
    func delete(_ id: UUID)
    /// Removes the oldest recordings beyond the limit, those without markers first, never touching `id`.
    func prune(keeping id: UUID)
}

/// Recordings as `<uuid>.json` files (a JSON array, one record per line) under Application Support/Diagnostics/Workouts,
/// each with a
/// `<uuid>.summary.json`. The folder is excluded from backups. Safe to call from any thread.
/// A typical recording is about 0.9 MB per minute, so 20 starter routines take roughly 110 MB.
final class FileWorkoutRecordingStore: WorkoutRecordingStoring {
    static let fileExtension = "json"
    /// Older recordings were JSON Lines files with these extensions; they are converted when listed.
    static let legacyFileExtensions: Set<String> = ["jsonl", "fmpsession"]
    /// At most this many recordings are kept. Beyond it the oldest without markers go first, then the oldest with.
    static let maximumRecordings = 20

    let directory: URL
    let maximumRecordings: Int
    private let lock = NSLock()

    init(directory: URL = FileWorkoutRecordingStore.defaultDirectory(),
         maximumRecordings: Int = FileWorkoutRecordingStore.maximumRecordings) {
        self.directory = directory
        self.maximumRecordings = maximumRecordings
    }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("Workouts", isDirectory: true)
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }

    private func summaryURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).summary.json")
    }

    func makeWriter(for id: UUID) -> WorkoutSessionWriting? {
        lock.lock()
        defer { lock.unlock() }
        prepareDirectory()
        return FileWorkoutSessionWriter(url: fileURL(for: id))
    }

    func saveSummary(_ summary: WorkoutRecordingSummary) {
        lock.lock()
        defer { lock.unlock() }
        prepareDirectory()
        unlockedSave(summary)
    }

    private func unlockedSave(_ summary: WorkoutRecordingSummary) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(summary) else { return }
        try? data.write(to: summaryURL(for: summary.id), options: .atomic)
    }

    func list() -> [WorkoutRecordingSummary] {
        lock.lock()
        defer { lock.unlock() }
        return unlockedList()
    }

    func delete(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        unlockedDelete(id)
    }

    func prune(keeping id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        let all = unlockedList(skippingRecoveryOf: id)
        var excess = all.count - maximumRecordings
        guard excess > 0 else { return }
        // Oldest first; recordings without markers go before any with markers.
        let candidates = all.filter { $0.id != id }.reversed()
        for summary in candidates.filter({ $0.markerCount == 0 }) + candidates.filter({ $0.markerCount > 0 }) {
            guard excess > 0 else { break }
            unlockedDelete(summary.id)
            excess -= 1
        }
    }

    /// A recording whose summary is missing, or that never ended normally, is counted from its file once, so its
    /// markers protect it from pruning. `skippingRecoveryOf` is the recording being written right now.
    private func unlockedList(skippingRecoveryOf current: UUID? = nil) -> [WorkoutRecordingSummary] {
        let manager = FileManager.default
        guard var files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        else { return [] }
        for legacy in files where Self.legacyFileExtensions.contains(legacy.pathExtension) {
            let converted = legacy.deletingPathExtension().appendingPathExtension(Self.fileExtension)
            if Self.convertLegacy(legacy, to: converted) {
                try? manager.removeItem(at: legacy)
                files = files.map { $0 == legacy ? converted : $0 }
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter(Self.isRecording).compactMap { file -> WorkoutRecordingSummary? in
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let stored = (try? Data(contentsOf: summaryURL(for: id))).flatMap {
                try? decoder.decode(WorkoutRecordingSummary.self, from: $0)
            }
            var summary: WorkoutRecordingSummary
            if let stored, stored.isComplete || stored.isRecovered == true || id == current {
                summary = stored
            } else {
                summary = Self.recoveredSummary(id: id, file: file, stored: stored)
                unlockedSave(summary)
            }
            summary.byteCount = size
            return summary
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    /// Recording files, not their `.summary.json` sidecars.
    static func isRecording(_ file: URL) -> Bool {
        file.pathExtension == fileExtension && !file.lastPathComponent.hasSuffix(".summary.json")
    }

    /// Rewrites a JSON Lines recording as a JSON array, one record per line.
    static func convertLegacy(_ legacy: URL, to converted: URL) -> Bool {
        guard FileManager.default.createFile(atPath: converted.path, contents: Data("[\n".utf8)),
              let handle = try? FileHandle(forWritingTo: converted),
              (try? handle.seekToEnd()) != nil else { return false }
        defer { try? handle.close() }
        var isFirst = true
        var buffer = Data()
        WorkoutRecordingFile.forEachLine(in: legacy) { record in
            buffer.append(contentsOf: ((isFirst ? "" : ",\n") + record).utf8)
            isFirst = false
            if buffer.count > 256 * 1024 {
                try? handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        buffer.append(contentsOf: (isFirst ? "]\n" : "\n]\n").utf8)
        return (try? handle.write(contentsOf: buffer)) != nil
    }

    /// Counts frames, markers, and exercises from the file's complete lines.
    static func recoveredSummary(id: UUID, file: URL, stored: WorkoutRecordingSummary?) -> WorkoutRecordingSummary {
        var summary = stored ?? WorkoutRecordingSummary(id: id, startedAt: creationDate(of: file), endedAt: nil,
                                                        title: "Workout", exerciseIDs: [], frameCount: 0,
                                                        markerCount: 0, isComplete: false)
        var frames = 0
        var markers = 0
        var exercises: [String] = summary.exerciseIDs
        var ended = false
        WorkoutRecordingFile.forEachLine(in: file) { line in
            if line.hasPrefix("{\"k\":\"f\"") {
                frames += 1
            } else if line.hasPrefix("{\"k\":\"marker\"") {
                markers += 1
            } else if line.hasPrefix("{\"k\":\"end\"") {
                ended = true
            } else if line.hasPrefix("{\"k\":\"pipe\""),
                      let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                      object["control"] as? String == "exercise", let exercise = object["exercise"] as? String,
                      !exercises.contains(exercise) {
                exercises.append(exercise)
            }
        }
        summary.frameCount = frames
        summary.markerCount = max(markers, summary.markerCount)
        summary.exerciseIDs = exercises
        summary.isComplete = ended && summary.isComplete
        summary.isRecovered = true
        return summary
    }

    private func unlockedDelete(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        try? FileManager.default.removeItem(at: summaryURL(for: id))
    }

    private func prepareDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Recordings are large and only useful on this phone, so they stay out of iCloud backups.
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    private static func creationDate(of file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}
