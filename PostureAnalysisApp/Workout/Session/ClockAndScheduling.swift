import Foundation

/// Monotonic time used for workout deadlines and reducer events.
protocol Clock {
    var now: TimeInterval { get }
}

struct SystemClock: Clock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

@MainActor
protocol Cancellable: AnyObject {
    func cancel()
}

@MainActor
protocol Scheduling: AnyObject {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable
    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable
}

/// Main-run-loop scheduling, matching the timers and main-queue delays previously used by the coach.
@MainActor
final class MainScheduler: Scheduling {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        let timer = Timer.scheduledTimer(withTimeInterval: max(0, delay), repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        return TimerCancellation(timer)
    }

    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        return TimerCancellation(timer)
    }
}

@MainActor
private final class TimerCancellation: Cancellable {
    private var timer: Timer?

    init(_ timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
