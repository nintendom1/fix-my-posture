import Foundation

/// How well the camera followed an item. `lost` and `notTracked` are explicit states, never "zero reps".
public enum TrackerStatus: String, Codable, CaseIterable, Sendable {
    /// The analyzer followed the item; `observedDose` is what it counted.
    case tracked
    /// The analyzer ran but with low confidence (for example frequent tracking gaps).
    case lowConfidence
    /// The analyzer lost the body for long enough that its count says nothing about the user.
    case lost
    /// No camera tracking: a self-reported exercise, a calibration answer, or the camera was off.
    case notTracked
}

/// A supplemental computer-vision signal (#115). V1 records but never reads these; a later policy may use the
/// ones documented as reliable to adjust confidence, never to override the user's own feedback.
public enum TrackingSignalKind: String, Codable, CaseIterable, Sendable {
    case rangeOfMotion
    case tempo
    case consistency
    case setupConfidence
}

public struct TrackingSignal: Codable, Hashable, Sendable {
    public let kind: TrackingSignalKind
    /// Normalized 0...1 where higher is better for the kind.
    public let value: Double
    public let isReliable: Bool

    public init(kind: TrackingSignalKind, value: Double, isReliable: Bool) {
        self.kind = kind
        self.value = value.isFinite ? min(1, max(0, value)) : 0
        self.isReliable = isReliable
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case isReliable
    }

    /// Decodes through the clamping initializer.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try container.decode(TrackingSignalKind.self, forKey: .kind),
                  value: try container.decode(Double.self, forKey: .value),
                  isReliable: try container.decode(Bool.self, forKey: .isReliable))
    }
}

/// What the tracker saw, kept separate from what the user confirmed.
public struct TrackerObservation: Codable, Hashable, Sendable {
    public let status: TrackerStatus
    /// What the analyzer counted, which may be zero; nil when it didn't run.
    public let observed: WorkAmount?
    /// `RepRejectionReason` raw values for attempts the analyzer let go, in the order they happened.
    public let rejectionReasons: [String]
    public let signals: [TrackingSignal]

    public init(status: TrackerStatus, observed: WorkAmount? = nil, rejectionReasons: [String] = [],
                signals: [TrackingSignal] = []) {
        self.status = status
        self.observed = status == .notTracked ? nil : observed
        self.rejectionReasons = rejectionReasons
        self.signals = signals
    }

    public static let notTracked = TrackerObservation(status: .notTracked)

    private enum CodingKeys: String, CodingKey {
        case status
        case observed
        case rejectionReasons
        case signals
    }

    /// Decodes through the normalizing initializer, so a `notTracked` observation can't carry a count.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(status: try container.decode(TrackerStatus.self, forKey: .status),
                  observed: try container.decodeIfPresent(WorkAmount.self, forKey: .observed),
                  rejectionReasons: try container.decode([String].self, forKey: .rejectionReasons),
                  signals: try container.decode([TrackingSignal].self, forKey: .signals))
    }
}
