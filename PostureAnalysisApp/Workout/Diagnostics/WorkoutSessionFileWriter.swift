import Foundation

/// Receives a recording's lines. Implementations serialize and store them off the main actor.
protocol WorkoutSessionWriting: AnyObject {
    func append(_ line: DiagnosticJSON)
    /// Writes buffered lines soon, as for a marker.
    func flush()
    /// Writes buffered lines before returning, as before the app is suspended.
    func drain()
    /// Flushes and closes the file; later lines are ignored. `completion` gets whether every line reached the
    /// file, on any thread, after the file is closed.
    func close(completion: @escaping (Bool) -> Void)
}

/// Writes one recording as a JSON array with one record per line, appended from a private serial queue:
///
///     [
///     {"k":"header",...},
///     {"k":"f",...}
///     ]
///
/// Each record's comma is written just before the next record, so the file is valid JSON once closed, and a crash
/// leaves every written record intact (only the closing bracket is missing). Records are buffered and written every
/// second, when the buffer passes 256 KB, and on `flush` and `close`, so a crash loses at most the last second.
final class FileWorkoutSessionWriter: WorkoutSessionWriting {
    static let flushInterval: TimeInterval = 1
    static let flushThreshold = 256 * 1024

    let url: URL
    private let queue = DispatchQueue(label: "com.postureanalysis.workoutRecorder", qos: .utility)
    // Everything below belongs to `queue`.
    private var buffer = Data()
    private var handle: FileHandle?
    private var timer: DispatchSourceTimer?
    private var isClosed = false
    private var hasFailed = false
    private var hasRecords = false

    /// Creates the file, replacing any file already at `url`. Returns nil when it can't be created.
    init?(url: URL) {
        self.url = url
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return nil
        }
        guard manager.createFile(atPath: url.path, contents: Data("[\n".utf8)),
              let handle = try? FileHandle(forWritingTo: url),
              (try? handle.seekToEnd()) != nil else { return nil }
        self.handle = handle
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
        timer.setEventHandler { [weak self] in self?.writeBuffer() }
        timer.resume()
        self.timer = timer
    }

    deinit {
        timer?.cancel()
    }

    func append(_ line: DiagnosticJSON) {
        queue.async { [self] in
            guard !isClosed else { return }
            var text = hasRecords ? ",\n" : ""
            line.write(into: &text)
            hasRecords = true
            buffer.append(contentsOf: text.utf8)
            if buffer.count >= Self.flushThreshold { writeBuffer() }
        }
    }

    func flush() {
        queue.async { [self] in writeBuffer() }
    }

    func drain() {
        queue.sync { writeBuffer() }
    }

    func close(completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            guard !isClosed else {
                completion(!hasFailed)
                return
            }
            buffer.append(contentsOf: (hasRecords ? "\n]\n" : "]\n").utf8)
            writeBuffer()
            timer?.cancel()
            timer = nil
            do {
                try handle?.close()
            } catch {
                hasFailed = true
            }
            handle = nil
            isClosed = true
            completion(!hasFailed)
        }
    }

    /// Waits for queued lines to reach the file. For tests.
    func waitUntilIdle() {
        queue.sync {}
    }

    private func writeBuffer() {
        guard !buffer.isEmpty, let handle else { return }
        do {
            try handle.write(contentsOf: buffer)
        } catch {
            // A full disk loses the recording's tail; the workout itself is unaffected, and the recording
            // stays incomplete.
            hasFailed = true
        }
        buffer.removeAll(keepingCapacity: true)
    }
}
