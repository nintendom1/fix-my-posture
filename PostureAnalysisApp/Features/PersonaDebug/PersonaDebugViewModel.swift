import Foundation
import Observation

/// Developer page state for Extra Personable: live status, the last sent and suppressed decisions, a trace
/// detail, and a content preview that can send any configured variant without waiting for a detector.
@MainActor
@Observable
final class PersonaDebugViewModel {
    enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    private(set) var status: PersonaStatus = .inactive
    private(set) var sent: [PersonaDecisionTrace] = []
    private(set) var suppressed: [PersonaDecisionTrace] = []
    var selectedTrace: PersonaDecisionTrace?

    let contentKeys: [String]
    let loadError: String?
    private(set) var selectedContentKey: String?
    var tone: PersonaTone {
        didSet {
            guard tone != oldValue else { return }
            variantIndex = 0
            resetSendState()
        }
    }
    var familiarity: PersonaFamiliarity {
        didSet {
            guard familiarity != oldValue else { return }
            variantIndex = 0
            resetSendState()
        }
    }
    private(set) var variantIndex = 0
    var intro: Bool {
        didSet {
            guard intro != oldValue else { return }
            resetSendState()
        }
    }
    private(set) var sendState: SendState = .idle
    private(set) var authorization: WorkoutReminderAuthorizationStatus = .notDetermined
    private(set) var isSending = false

    private let catalog: PersonaContentCatalog?
    private let provider: (any PersonaDebugProviding)?
    private let scheduler: any NotificationPreviewScheduling
    private let preferences: any AppPreferencesStoring
    private let now: () -> Date
    private let calendar: Calendar

    init(
        catalog: PersonaContentCatalog?,
        loadError: String?,
        provider: (any PersonaDebugProviding)?,
        scheduler: any NotificationPreviewScheduling,
        preferences: any AppPreferencesStoring,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.catalog = catalog
        self.loadError = catalog == nil ? (loadError ?? "Persona content could not be loaded.") : nil
        self.provider = provider
        self.scheduler = scheduler
        self.preferences = preferences
        self.now = now
        self.calendar = calendar
        contentKeys = catalog?.contentKeys ?? []
        selectedContentKey = catalog?.contentKeys.first
        tone = catalog?.contentKeys.first.flatMap { catalog?.entry($0)?.defaultTone } ?? .pleased
        familiarity = .new
        intro = false
        // Status and traces load when the page appears (`refresh()` from the screen's `.task`), not when Settings opens.
    }

    /// The selected key, exposed as a concise label for the preview controls.
    var contentKey: String? { selectedContentKey }

    /// Always at least one so the stepper remains stable while catalog copy is unavailable.
    var variantCount: Int {
        guard let catalog, let selectedContentKey else { return 1 }
        return max(1, PersonaCopyComposer.variantCount(
            catalog: catalog,
            contentKey: selectedContentKey,
            tone: tone,
            familiarity: familiarity
        ))
    }

    /// The message that the Send button will schedule, if this selection composes successfully.
    var preview: PersonaComposition? {
        guard let catalog, let selectedContentKey,
              let entry = catalog.entry(selectedContentKey) else { return nil }
        return PersonaCopyComposer.compose(
            catalog: catalog,
            contentKey: selectedContentKey,
            tone: tone,
            familiarity: familiarity,
            values: entry.sample,
            variant: variantIndex,
            intro: intro
        )
    }

    /// Reloads status and trace history from the provider, retaining only the requested recent entries.
    func refresh() {
        status = provider?.personaStatus() ?? .inactive
        let traces = provider?.personaTraceState() ?? .empty
        sent = Array(traces.sent.sorted(by: Self.sentNewestFirst).prefix(10))
        suppressed = Array(traces.suppressed.sorted(by: Self.suppressedNewestFirst).prefix(20))
        if let selectedTrace,
           !(sent + suppressed).contains(where: { $0.id == selectedTrace.id }) {
            self.selectedTrace = nil
        }
    }

    /// Returns the other candidates considered in the same planner decision.
    func otherCandidates(for trace: PersonaDecisionTrace) -> [PersonaDecisionTrace] {
        (sent + suppressed)
            .filter { $0.decisionID == trace.decisionID && $0.id != trace.id }
            .sorted(by: Self.candidateNewestFirst)
    }

    func selectTrace(_ trace: PersonaDecisionTrace) {
        selectedTrace = trace
    }

    func selectContentKey(_ key: String) {
        guard contentKeys.contains(key), selectedContentKey != key else { return }
        selectedContentKey = key
        tone = catalog?.entry(key)?.defaultTone ?? .pleased
        variantIndex = 0
        resetSendState()
    }

    /// Advances or reverses through the current number of variants, wrapping at either end.
    func stepVariant(by delta: Int) {
        let count = variantCount
        variantIndex = ((variantIndex + delta) % count + count) % count
        resetSendState()
    }

    /// Asks for notification permission when needed, then schedules the selected preview at the saved delay.
    func send() async {
        guard let preview, !isSending else { return }
        isSending = true
        sendState = .sending
        defer { isSending = false }

        var currentAuthorization = await scheduler.authorizationStatus()
        if currentAuthorization == .notDetermined {
            currentAuthorization = await scheduler.requestAuthorization()
        }
        authorization = currentAuthorization
        guard currentAuthorization == .authorized else {
            sendState = .failed("Notifications are turned off for Fix My Posture.")
            return
        }

        do {
            _ = try await scheduler.schedule(
                preview.content,
                after: TimeInterval(preferences.notificationPreviewDelaySeconds)
            )
            sendState = .sent
        } catch {
            sendState = .failed("The notification could not be scheduled.")
        }
    }

    /// Re-runs reminder reconciliation and then reads the resulting status and traces.
    func runDetectorsNow() async {
        await provider?.runPersonaDetectorsNow()
        refresh()
    }

    /// Resets persona memory through the provider and then reads the cleared state.
    func resetPersona() async {
        await provider?.resetPersona()
        refresh()
    }

    /// Formats a trace time with the injected calendar's time zone.
    func shortTime(for date: Date) -> String {
        let formatter = calendar.isDate(date, inSameDayAs: now()) ? todayFormatter : otherDayFormatter
        return formatter.string(from: date)
    }

    /// Formats the reset date with the injected calendar's time zone.
    func resetDateLabel(_ date: Date) -> String {
        resetFormatter.string(from: date)
    }

    /// "Scheduled" for a sent trace that iOS has not delivered yet, otherwise the delivery mode.
    func sentRowLabel(_ trace: PersonaDecisionTrace) -> String {
        let delivery = Self.deliveryDescription(trace.delivery)
        return trace.isPending(asOf: now()) ? "Scheduled · \(delivery)" : delivery
    }

    @ObservationIgnored private lazy var todayFormatter = makeFormatter("h:mm a")
    @ObservationIgnored private lazy var otherDayFormatter = makeFormatter("MMM d, h:mm a")
    @ObservationIgnored private lazy var resetFormatter = makeFormatter("MMM d, yyyy h:mm a")

    private func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }

    static func deliveryDescription(_ delivery: PersonaDelivery) -> String {
        switch delivery {
        case .active: "Active"
        case .passive: "Passive"
        case .foldedReplace, .foldedAppend: "Folded"
        case .inAppOnly: "In app"
        case .none: "None"
        }
    }

    static func suppressionDescription(_ reason: PersonaSuppressionReason) -> String {
        switch reason {
        case .disabled: "Extra Personable, reminders, or Character style is off"
        case .recentlySent: "Already sent recently"
        case .similarDowngrade: "Similar messages were too frequent"
        case .cooling: "Quieted during cooling"
        case .dailyCapReached: "Daily limit reached"
        case .quietHours: "Quiet hours"
        case .lowSalience: "Low salience"
        case .noContent: "No matching copy"
        case .lowerPriorityThanSelected: "Another observation was selected"
        }
    }

    private func resetSendState() {
        guard !isSending else { return }
        sendState = .idle
    }

    private static func sentNewestFirst(_ lhs: PersonaDecisionTrace, _ rhs: PersonaDecisionTrace) -> Bool {
        let leftDate = lhs.fireDate ?? lhs.decidedAt
        let rightDate = rhs.fireDate ?? rhs.decidedAt
        if leftDate != rightDate { return leftDate > rightDate }
        if lhs.decidedAt != rhs.decidedAt { return lhs.decidedAt > rhs.decidedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func suppressedNewestFirst(_ lhs: PersonaDecisionTrace, _ rhs: PersonaDecisionTrace) -> Bool {
        if lhs.decidedAt != rhs.decidedAt { return lhs.decidedAt > rhs.decidedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func candidateNewestFirst(_ lhs: PersonaDecisionTrace, _ rhs: PersonaDecisionTrace) -> Bool {
        if lhs.decidedAt != rhs.decidedAt { return lhs.decidedAt > rhs.decidedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}

/// Categorical meter lengths for the Persona Debug detail sheet.
enum PersonaDebugMeters {
    static func familiarityDots(_ familiarity: PersonaFamiliarity) -> Int {
        familiarity.rank + 1
    }

    static func trajectoryDots(_ trajectory: PersonaTrajectory) -> Int {
        switch trajectory {
        case .declining: 1
        case .unknown: 0
        case .stable: 2
        case .improving: 3
        }
    }

    static func evidenceDots(strength: Int) -> Int {
        min(4, max(0, strength - 1))
    }

    static func repetitionRiskDots(recentSimilarCount: Int) -> Int {
        min(4, max(0, recentSimilarCount))
    }

    static func coolingDots(_ cooling: PersonaCoolingLevel) -> Int {
        switch cooling {
        case .none: 0
        case .mild: 2
        case .strong: 4
        }
    }
}
