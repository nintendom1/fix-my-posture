import Foundation

enum PoseFrameSourceEvent {
    case running
    case frame(PoseFrame)
    case interrupted
    case failed(String)
}

typealias PoseFrameReceiver = @MainActor (UUID, PoseFrameSourceEvent) -> Void

/// Supplies generation-tagged pose frames on the main actor.
/// A new generation invalidates everything delivered for older ones.
protocol PoseFrameSource: AnyObject {
    func start(generation: UUID, receive: @escaping PoseFrameReceiver)
    func stop()
}
