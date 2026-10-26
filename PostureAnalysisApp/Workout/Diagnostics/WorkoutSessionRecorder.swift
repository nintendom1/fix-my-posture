import CoreGraphics
import Foundation

/// Records one workout to a `.json` file. Building each line is cheap; the writer serializes and stores
/// it off the main actor. A recording that never received a frame is deleted when it ends.
@MainActor
final class WorkoutSessionRecorder: WorkoutSessionRecording {
    /// Recent events copied into each marker, so a marker explains itself without the rest of the file.
    static let markerContextEvents = 20
    /// A recording stops after this long; the workout carries on unrecorded.
    static let maximumDuration: TimeInterval = 60 * 60

    let id: UUID
    private(set) var isRecording = false
    private(set) var markers: [WorkoutMarker] = []

    private let store: any WorkoutRecordingStoring
    private let app: WorkoutSessionLines.AppInfo
    private let now: () -> Date
    private var writer: (any WorkoutSessionWriting)?
    private var hasBegun = false
    private var startUptime: TimeInterval = 0
    private var summary: WorkoutRecordingSummary?
    private var exerciseNames: [String: String] = [:]
    private var isPlan = false
    private var timeZone = TimeZone.current
    private var lastState: WorkoutStateSnapshot?
    private var lastStateLine: DiagnosticJSON = .null
    private var lastImageSize: CGSize?
    private var lastSequence: Int?
    private var frameCount = 0
    private var sequenceGaps = 0
    private var recentEvents: [DiagnosticJSON] = []

    init(id: UUID = UUID(), store: any WorkoutRecordingStoring, app: WorkoutSessionLines.AppInfo = .current,
         now: @escaping () -> Date = Date.init) {
        self.id = id
        self.store = store
        self.app = app
        self.now = now
    }

    func begin(_ context: WorkoutRecordingContext, at uptime: TimeInterval) {
        guard !hasBegun else { return }
        hasBegun = true
        guard let writer = store.makeWriter(for: id) else { return }
        self.writer = writer
        startUptime = uptime
        isRecording = true
        isPlan = context.plan != nil
        timeZone = context.timeZone
        exerciseNames = Dictionary(context.exercises.map { ($0.id.rawValue, $0.displayName) },
                                   uniquingKeysWith: { first, _ in first })
        writer.append(WorkoutSessionLines.header(id: id, context: context, app: app))
        let summary = WorkoutRecordingSummary(id: id, startedAt: context.startedAt, endedAt: nil,
                                              title: context.plan?.name ?? "Workout", exerciseIDs: [],
                                              frameCount: 0, markerCount: 0, isComplete: false)
        self.summary = summary
        store.saveSummary(summary)
        store.prune(keeping: id)
    }

    func recordControl(_ control: WorkoutFramePipeline.Control, at uptime: TimeInterval) {
        guard isRecording else { return }
        if case .exercise(let exercise?, _) = control { noteExercise(exercise.id.rawValue) }
        writer?.append(WorkoutSessionLines.control(control, t: time(uptime)))
    }

    func recordFrame(_ frame: PoseFrame, output: WorkoutFramePipeline.FrameOutput?, pitchDegrees: Double?,
                     at uptime: TimeInterval) {
        guard isRecording else { return }
        frameCount += 1
        if let sequence = frame.sequence {
            if let last = lastSequence, sequence > last + 1 { sequenceGaps += sequence - last - 1 }
            lastSequence = sequence
        }
        let size = frame.imageSize
        let sizeChanged = size != lastImageSize
        lastImageSize = size
        writer?.append(WorkoutSessionLines.frame(frame, output: output, pitchDegrees: pitchDegrees,
                                                 imageSizeChanged: sizeChanged, t: time(uptime)))
    }

    func recordState(_ snapshot: WorkoutStateSnapshot, at uptime: TimeInterval) {
        guard isRecording, snapshot != lastState else { return }
        lastState = snapshot
        let line = WorkoutSessionLines.state(snapshot, restEndsT: snapshot.restEndsAt.map(time), t: time(uptime))
        lastStateLine = line
        writer?.append(line)
    }

    func recordEvent(_ event: WorkoutRecordingEvent, at uptime: TimeInterval) {
        guard isRecording else { return }
        let line = WorkoutSessionLines.event(event, t: time(uptime))
        recentEvents.append(line)
        if recentEvents.count > Self.markerContextEvents { recentEvents.removeFirst(recentEvents.count - Self.markerContextEvents) }
        writer?.append(line)
    }

    @discardableResult
    func recordMarker(_ request: WorkoutMarkerRequest, at uptime: TimeInterval) -> WorkoutMarker? {
        guard isRecording else { return nil }
        let heard = request.heardAt.map(time)
        let marker = WorkoutMarker(id: UUID(), time: heard ?? time(uptime), source: request.source,
                                   note: request.note.flatMap { $0.isEmpty ? nil : $0 })
        markers.append(marker)
        let context: DiagnosticJSON = .object(("state", lastStateLine), ("recent", .array(recentEvents)))
        writer?.append(WorkoutSessionLines.marker(marker, heardT: heard, recordedT: time(uptime), context: context))
        writer?.flush()
        summary?.markerCount = markers.count
        saveSummary()
        return marker
    }

    func duration(at uptime: TimeInterval) -> TimeInterval {
        isRecording ? time(uptime) : 0
    }

    /// Writes everything buffered before returning, as the app is suspended.
    func flush() {
        writer?.drain()
        saveSummary()
    }

    func end(_ reason: WorkoutRecordingEnd, workoutRecordID: UUID?, at uptime: TimeInterval) {
        guard isRecording, let writer else { return }
        isRecording = false
        writer.append(WorkoutSessionLines.end(reason, endedAt: now(), timeZone: timeZone, frames: frameCount,
                                              sequenceGaps: sequenceGaps, workoutRecordID: workoutRecordID,
                                              t: time(uptime)))
        self.writer = nil
        // The summary says complete only once the end line is on disk; a failed write leaves it incomplete, and
        // the store recovers its counts from the file later.
        let store = store
        let id = id
        let hadFrames = frameCount > 0
        var final = summary
        final?.frameCount = frameCount
        final?.endedAt = now()
        final?.isComplete = true
        writer.close { succeeded in
            if !hadFrames {
                store.delete(id)
            } else if succeeded, let final {
                store.saveSummary(final)
            }
        }
    }

    private func time(_ uptime: TimeInterval) -> TimeInterval {
        uptime - startUptime
    }

    /// A Saved Set keeps its name; otherwise the title lists the exercises done.
    private func noteExercise(_ id: String) {
        guard var summary, !summary.exerciseIDs.contains(id) else { return }
        summary.exerciseIDs.append(id)
        if !isPlan {
            summary.title = summary.exerciseIDs.map { exerciseNames[$0] ?? $0 }.joined(separator: ", ")
        }
        self.summary = summary
    }

    private func saveSummary() {
        guard var summary else { return }
        summary.frameCount = frameCount
        self.summary = summary
        store.saveSummary(summary)
    }
}
