import Foundation
import Observation
import UIKit

/// Drives the developer page that sends any character notification on demand.
@MainActor
@Observable
final class NotificationPreviewViewModel {
    enum SendState: Equatable {
        case idle
        case countingDown(secondsRemaining: Int)
        case sent
        case failed(String)
    }

    /// Every scenario, in file order. Empty when the scenario data could not be loaded.
    let scenarios: [NotificationScenario]
    /// Why the scenario data could not be loaded, if it could not.
    let loadError: String?

    private(set) var selectedID: String?
    private(set) var variantIndex = 0
    private(set) var authorization: WorkoutReminderAuthorizationStatus = .notDetermined
    private(set) var sendState: SendState = .idle
    private(set) var isBusy = false
    /// What iOS holds for this app's notifications; nil until refreshed or when diagnostics are unavailable.
    private(set) var diagnostics: NotificationDiagnosticsSnapshot?

    /// Seconds between tapping Send and the notification arriving, saved between launches.
    var delaySeconds: Int {
        didSet {
            let clamped = NotificationPreviewDelay.clamped(delaySeconds)
            if clamped != delaySeconds { delaySeconds = clamped }
            preferences.notificationPreviewDelaySeconds = clamped
        }
    }

    private let sampleSuggestion: String
    private let preferences: any AppPreferencesStoring
    private let scheduler: any NotificationPreviewScheduling
    private let openSettings: () -> Void
    private let sleep: (Duration) async -> Void
    private let diagnosticsProvider: (any NotificationDiagnosticsProviding)?
    private let diagnosticsReportURL: URL?

    init(
        catalog: NotificationScenarioCatalog?,
        loadError: String? = nil,
        preferences: any AppPreferencesStoring,
        scheduler: any NotificationPreviewScheduling,
        openSettings: @escaping () -> Void = NotificationPreviewViewModel.openSystemSettings,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        diagnostics: (any NotificationDiagnosticsProviding)? = nil,
        diagnosticsReportURL: URL? = nil
    ) {
        scenarios = catalog?.scenarios ?? []
        self.loadError = catalog == nil ? (loadError ?? "The notification scenarios could not be loaded.") : nil
        sampleSuggestion = catalog?.sampleSuggestion ?? ""
        selectedID = catalog?.scenarios.first?.id
        self.preferences = preferences
        self.scheduler = scheduler
        self.openSettings = openSettings
        self.sleep = sleep
        diagnosticsProvider = diagnostics
        self.diagnosticsReportURL = diagnosticsReportURL
        delaySeconds = preferences.notificationPreviewDelaySeconds
    }

    var selectedScenario: NotificationScenario? {
        scenarios.first { $0.id == selectedID }
    }

    var variantCount: Int {
        selectedScenario?.copy.count ?? 0
    }

    /// The notification the Send button would deliver, built the same way as a real one.
    var preview: CharacterNotificationContent? {
        guard let scenario = selectedScenario else { return nil }
        return NotificationContentBuilder.make(
            scenario: scenario,
            variant: variantIndex,
            values: scenario.sampleValues(suggestion: sampleSuggestion)
        )
    }

    func scenarios(of kind: NotificationScenario.Kind) -> [NotificationScenario] {
        scenarios.filter { $0.kind == kind }
    }

    func select(_ id: String) {
        guard scenarios.contains(where: { $0.id == id }) else { return }
        selectedID = id
        variantIndex = 0
        resetFinishedState()
    }

    func stepVariant(by delta: Int) {
        guard variantCount > 0 else { return }
        variantIndex = ((variantIndex + delta) % variantCount + variantCount) % variantCount
        resetFinishedState()
    }

    func refreshAuthorization() async {
        authorization = await scheduler.authorizationStatus()
    }

    func openNotificationSettings() {
        openSettings()
    }

    var hasDiagnostics: Bool { diagnosticsProvider != nil }

    /// Reads what iOS currently holds and, when a report location is set, writes it there as plain text.
    func refreshDiagnostics() async {
        guard let diagnosticsProvider else { return }
        let snapshot = await diagnosticsProvider.snapshot()
        diagnostics = snapshot
        if let diagnosticsReportURL {
            try? snapshot.report.write(to: diagnosticsReportURL, atomically: true, encoding: .utf8)
        }
    }

    /// Schedules the selected notification after the saved delay, asking for permission first if needed.
    func send() async {
        guard let preview, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        var status = await scheduler.authorizationStatus()
        if status == .notDetermined {
            status = await scheduler.requestAuthorization()
        }
        authorization = status
        guard status == .authorized else {
            sendState = .failed("Notifications are turned off for Fix My Posture.")
            return
        }

        let delay = delaySeconds
        do {
            _ = try await scheduler.schedule(preview, after: TimeInterval(delay))
        } catch {
            sendState = .failed("The notification could not be scheduled.")
            return
        }

        for remaining in stride(from: delay, to: 0, by: -1) {
            sendState = .countingDown(secondsRemaining: remaining)
            await sleep(.seconds(1))
        }
        sendState = .sent
        await refreshDiagnostics()
    }

    private func resetFinishedState() {
        guard !isBusy else { return }
        sendState = .idle
    }

    private static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
