import Foundation

/// One evidence row as the debug view and export show it: what was asked, what the user confirmed, what the
/// tracker saw, and what the policy did with it.
public struct EvidenceSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let source: EvidenceSource
    public let variant: VariantID
    public let prescribed: Dose?
    public let confirmed: WorkAmount?
    public let confirmation: ConfirmationSource
    public let trackerStatus: TrackerStatus
    public let trackerObserved: WorkAmount?
    public let rejectionReasons: [String]
    public let effort: EffortFeedback?
    public let midSetTooHard: Bool
    public let bonus: BonusRecord?
    public let completion: CompletionReason
    /// What the replay decided for this fact.
    public let decision: DecisionKind?
    public let codes: [ReasonCode]
    public let summary: String?

    public init(id: UUID, recordedAt: Date, source: EvidenceSource, variant: VariantID, prescribed: Dose?,
                confirmed: WorkAmount?, confirmation: ConfirmationSource, trackerStatus: TrackerStatus,
                trackerObserved: WorkAmount?, rejectionReasons: [String], effort: EffortFeedback?, midSetTooHard: Bool,
                bonus: BonusRecord?, completion: CompletionReason, decision: DecisionKind?, codes: [ReasonCode],
                summary: String?) {
        self.id = id
        self.recordedAt = recordedAt
        self.source = source
        self.variant = variant
        self.prescribed = prescribed
        self.confirmed = confirmed
        self.confirmation = confirmation
        self.trackerStatus = trackerStatus
        self.trackerObserved = trackerObserved
        self.rejectionReasons = rejectionReasons
        self.effort = effort
        self.midSetTooHard = midSetTooHard
        self.bonus = bonus
        self.completion = completion
        self.decision = decision
        self.codes = codes
        self.summary = summary
    }

    /// The tracker failed or was unsure; shown, never folded into capacity.
    public var isTrackingIssue: Bool { trackerStatus == .lost || trackerStatus == .lowConfidence }
}

public struct EffortCounts: Codable, Hashable, Sendable {
    public var tooHard = 0
    public var okay = 0
    public var easy = 0

    public init(tooHard: Int = 0, okay: Int = 0, easy: Int = 0) {
        self.tooHard = tooHard
        self.okay = okay
        self.easy = easy
    }
}

public struct BonusCounts: Codable, Hashable, Sendable {
    public var offered = 0
    public var accepted = 0
    public var declined = 0

    public init(offered: Int = 0, accepted: Int = 0, declined: Int = 0) {
        self.offered = offered
        self.accepted = accepted
        self.declined = declined
    }
}

public struct SourceCount: Codable, Hashable, Sendable {
    public let source: EvidenceSource
    public let count: Int

    public init(source: EvidenceSource, count: Int) {
        self.source = source
        self.count = count
    }
}

/// Everything the debug view shows for one family.
public struct FamilySummary: Codable, Hashable, Identifiable, Sendable {
    public var id: MovementFamilyID { family }
    public let family: MovementFamilyID
    public let debugName: String
    public let isActive: Bool
    public let current: RungDose?
    /// Confidence as of the snapshot time (time away lowers it).
    public let confidence: RecommendationConfidence?
    public let lastPerformedAt: Date?
    public let lastChangedAt: Date?
    /// The latest decision that changed or held the prescription, as one readable line.
    public let latestRationale: String?
    /// Newest first, at most `AdaptiveSnapshot.recentEvidenceLimit`.
    public let recentEvidence: [EvidenceSummary]
    public let effort: EffortCounts
    public let bonus: BonusCounts
    public let trackingIssues: Int
    public let sources: [SourceCount]

    public init(family: MovementFamilyID, debugName: String, isActive: Bool, current: RungDose?,
                confidence: RecommendationConfidence?, lastPerformedAt: Date?, lastChangedAt: Date?,
                latestRationale: String?, recentEvidence: [EvidenceSummary], effort: EffortCounts,
                bonus: BonusCounts, trackingIssues: Int, sources: [SourceCount]) {
        self.family = family
        self.debugName = debugName
        self.isActive = isActive
        self.current = current
        self.confidence = confidence
        self.lastPerformedAt = lastPerformedAt
        self.lastChangedAt = lastChangedAt
        self.latestRationale = latestRationale
        self.recentEvidence = recentEvidence
        self.effort = effort
        self.bonus = bonus
        self.trackingIssues = trackingIssues
        self.sources = sources
    }
}

/// The developer export and the debug view's single source: facts, the engine's interpretation, and everything
/// needed to interpret its ids, so another tool can explain or replay a recommendation without the database.
/// It holds no photos, video, camera frames, or device and account identifiers.
public struct AdaptiveSnapshot: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1
    public static let recentEvidenceLimit = 10
    public static let developerNote = "Developer data from Fix My Posture adaptive training: facts the user and "
        + "tracker produced and the engine's interpretation. No photos, video, camera frames, or device identifiers."

    public let format: String
    public let formatVersion: Int
    public let note: String
    public let generatedAt: Date
    public let appVersion: String
    /// The time zone that decided calendar days during replay.
    public let timeZone: String
    public let policyVersion: PolicyVersion
    public let parameters: PolicyParameters
    public let catalog: ProgressionCatalog
    public let availability: Availability
    public let today: TodaySessionStatus
    public let families: [FamilySummary]
    public let profile: AdaptiveProfile
    public let events: [AdaptiveEvent]
    public let facts: AdaptiveFacts

    public init(generatedAt: Date, appVersion: String, timeZone: String, policyVersion: PolicyVersion,
                parameters: PolicyParameters, catalog: ProgressionCatalog, availability: Availability,
                today: TodaySessionStatus, families: [FamilySummary], profile: AdaptiveProfile,
                events: [AdaptiveEvent], facts: AdaptiveFacts) {
        format = "fmp-adaptive-training"
        formatVersion = Self.currentFormatVersion
        note = Self.developerNote
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.timeZone = timeZone
        self.policyVersion = policyVersion
        self.parameters = parameters
        self.catalog = catalog
        self.availability = availability
        self.today = today
        self.families = families
        self.profile = profile
        self.events = events
        self.facts = facts
    }
}

/// Stable, human-readable JSON for exports: sorted keys, pretty printed, unescaped slashes, and UTC ISO-8601 dates with
/// nine fractional digits. The dates are lossless, so decoding an export and encoding it again gives the same bytes,
/// and replaying it gives the engine's decisions exactly (facts a fraction of a millisecond apart keep their order).
/// Decoding also accepts fewer fractional digits, or none.
public enum AdaptiveExport {
    public static func encode(_ snapshot: AdaptiveSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ExportDate.string(date))
        }
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> AdaptiveSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ExportDate.date(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Expected a UTC ISO-8601 date such as 2025-01-15T20:00:00.000Z.")
            }
            return date
        }
        return try decoder.decode(AdaptiveSnapshot.self, from: data)
    }
}
