import Foundation

/// Every adaptive-training fact, in a stable order: by time, then by id. Recommendations are a pure function of
/// these facts and a policy version, so replaying the same facts always gives the same result.
public struct AdaptiveFacts: Codable, Hashable, Sendable {
    public let prescriptions: [Prescription]
    public let evidence: [AdaptiveEvidence]
    public let calibrations: [CalibrationSessionRecord]
    public let engagement: [EngagementFact]
    public let settings: [SettingsFact]

    public init(prescriptions: [Prescription] = [], evidence: [AdaptiveEvidence] = [],
                calibrations: [CalibrationSessionRecord] = [], engagement: [EngagementFact] = [],
                settings: [SettingsFact] = []) {
        self.prescriptions = prescriptions.sorted { Self.precedes($0.issuedAt, $0.id, $1.issuedAt, $1.id) }
        self.evidence = evidence.sorted { Self.precedes($0.recordedAt, $0.id, $1.recordedAt, $1.id) }
        self.calibrations = calibrations.sorted { Self.precedes($0.startedAt, $0.id, $1.startedAt, $1.id) }
        self.engagement = engagement.sorted { Self.precedes($0.recordedAt, $0.id, $1.recordedAt, $1.id) }
        self.settings = settings.sorted { Self.precedes($0.recordedAt, $0.id, $1.recordedAt, $1.id) }
    }

    private enum CodingKeys: String, CodingKey {
        case prescriptions
        case evidence
        case calibrations
        case engagement
        case settings
    }

    /// Decodes through the sorting initializer, so stored or exported JSON in any order replays the same way.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(prescriptions: try container.decode([Prescription].self, forKey: .prescriptions),
                  evidence: try container.decode([AdaptiveEvidence].self, forKey: .evidence),
                  calibrations: try container.decode([CalibrationSessionRecord].self, forKey: .calibrations),
                  engagement: try container.decode([EngagementFact].self, forKey: .engagement),
                  settings: try container.decode([SettingsFact].self, forKey: .settings))
    }

    public static let empty = AdaptiveFacts()

    public var isEmpty: Bool {
        prescriptions.isEmpty && evidence.isEmpty && calibrations.isEmpty && engagement.isEmpty && settings.isEmpty
    }

    /// Identifies this exact set of facts, so a cached interpretation can tell whether it is stale. Append-only facts
    /// count by id (a stored id never changes its contents); calibrations, the one fact updated in place, count by
    /// their full contents, so any change to a status, starting point, or equipment answer changes the watermark.
    public var watermark: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        var hasher = StableHasher()
        for calibration in calibrations {
            hasher.combine(String(decoding: (try? encoder.encode(calibration)) ?? Data(), as: UTF8.self))
        }
        for id in prescriptions.map(\.id) + evidence.map(\.id) + engagement.map(\.id) + settings.map(\.id) {
            hasher.combine(id.uuidString)
        }
        return "\(prescriptions.count).\(evidence.count).\(calibrations.count).\(engagement.count).\(settings.count)-\(hasher.hex)"
    }

    static func precedes(_ lhsDate: Date, _ lhsID: UUID, _ rhsDate: Date, _ rhsID: UUID) -> Bool {
        lhsDate == rhsDate ? lhsID.uuidString < rhsID.uuidString : lhsDate < rhsDate
    }
}

/// FNV-1a over UTF-8, so watermarks are identical across launches and devices (unlike `Hasher`).
struct StableHasher {
    private var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        value ^= 0xff
        value = value &* 0x0000_0100_0000_01b3
    }

    var hex: String { String(value, radix: 16) }
}
