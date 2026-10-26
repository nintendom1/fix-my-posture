import Foundation

/// Camera deliveries waiting for the main actor, in capture order. A short main-thread stall used to replace all
/// but the newest frame, so the analyzer saw a gap and threw away the rep in progress; queuing them lets analysis
/// catch up instead. Past `capacity` frames (a longer stall), the oldest frames are dropped. Status changes are
/// never dropped and keep their place, so a batch can't deliver frames from after an interruption before the
/// interruption itself. Not thread-safe; the owner locks around it.
struct PendingFrameQueue<Element> {
    /// About 1.5 s of frames at the workout camera's 10 Hz.
    static var defaultCapacity: Int { 15 }

    let capacity: Int
    private var entries: [(element: Element, isFrame: Bool)] = []
    private var frameCount = 0
    /// Frames dropped because the queue was full, since creation.
    private(set) var droppedCount = 0

    init(capacity: Int = Self.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    var isEmpty: Bool { entries.isEmpty }

    mutating func appendFrame(_ element: Element) {
        entries.append((element, true))
        frameCount += 1
        while frameCount > capacity, let oldest = entries.firstIndex(where: \.isFrame) {
            entries.remove(at: oldest)
            frameCount -= 1
            droppedCount += 1
        }
    }

    mutating func appendStatus(_ element: Element) {
        entries.append((element, false))
    }

    /// Everything queued, oldest first, leaving the queue empty.
    mutating func drain() -> [Element] {
        defer { removeAll() }
        return entries.map(\.element)
    }

    mutating func removeAll() {
        entries.removeAll()
        frameCount = 0
    }
}
