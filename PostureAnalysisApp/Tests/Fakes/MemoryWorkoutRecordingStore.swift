import Foundation
@testable import PostureAnalysisApp

/// Keeps a recording's lines in memory, serialized exactly as the file writer would write them.
final class MemoryWorkoutSessionWriter: WorkoutSessionWriting {
    private(set) var lines: [String] = []
    private(set) var flushCount = 0
    private(set) var drainCount = 0
    private(set) var isClosed = false
    /// False simulates a full disk: the close reports that some lines never reached the file.
    var closeSucceeds = true

    func append(_ line: DiagnosticJSON) {
        guard !isClosed else { return }
        lines.append(line.serialized)
    }

    func flush() { flushCount += 1 }
    func drain() { drainCount += 1 }

    /// Completes at once, as if the file were already written.
    func close(completion: @escaping (Bool) -> Void) {
        isClosed = true
        completion(closeSucceeds)
    }

    /// Every line, parsed.
    var objects: [[String: Any]] {
        lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    func objects(kind: String) -> [[String: Any]] {
        objects.filter { $0["k"] as? String == kind }
    }

    /// The `k` of each line, in order, for checking line order.
    var kinds: [String] { objects.compactMap { $0["k"] as? String } }

    func events(type: String) -> [[String: Any]] {
        objects(kind: "e").filter { $0["type"] as? String == type }
    }
}

/// Recordings held in memory. `fileURL` points into a temporary folder that is never written.
final class MemoryWorkoutRecordingStore: WorkoutRecordingStoring {
    private(set) var writers: [UUID: MemoryWorkoutSessionWriter] = [:]
    private(set) var summaries: [UUID: WorkoutRecordingSummary] = [:]
    private(set) var deleted: [UUID] = []
    private(set) var prunedKeeping: [UUID] = []
    var failsToCreate = false

    func makeWriter(for id: UUID) -> WorkoutSessionWriting? {
        guard !failsToCreate else { return nil }
        return writer(for: id)
    }

    /// The writer a recording with `id` gets, available before the recording begins.
    func writer(for id: UUID) -> MemoryWorkoutSessionWriter {
        if let writer = writers[id] { return writer }
        let writer = MemoryWorkoutSessionWriter()
        writers[id] = writer
        return writer
    }

    func saveSummary(_ summary: WorkoutRecordingSummary) {
        summaries[summary.id] = summary
    }

    func list() -> [WorkoutRecordingSummary] {
        summaries.values.sorted { $0.startedAt > $1.startedAt }
    }

    func fileURL(for id: UUID) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    func delete(_ id: UUID) {
        deleted.append(id)
        summaries[id] = nil
    }

    func prune(keeping id: UUID) {
        prunedKeeping.append(id)
    }
}
