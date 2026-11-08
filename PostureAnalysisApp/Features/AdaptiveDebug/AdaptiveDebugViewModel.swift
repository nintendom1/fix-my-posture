import AdaptiveTraining
import Foundation
import Observation
import UIKit

/// Read-only state for Adaptive training diagnostics and its deterministic JSON export.
@MainActor
@Observable
final class AdaptiveDebugViewModel {
    private(set) var snapshot: AdaptiveSnapshot?
    private(set) var exportURL: URL?
    private(set) var errorMessage: String?
    private(set) var didCopy = false
    private(set) var exportedJSON: String?
    /// Why Today's Session didn't start, when the last tap on Start produced nothing.
    private(set) var startMessage: String?

    var isEmpty: Bool { provider == nil }

    /// The engine says Today's Session is ready, and the app can start it. Enabled only then.
    var canStartToday: Bool {
        guard todayStarter != nil, case .ready? = snapshot?.today else { return false }
        return true
    }

    private let provider: (any AdaptiveDebugProviding)?
    private let now: () -> Date
    private let timeZone: TimeZone
    private let exportDirectory: URL
    private let copy: (String) -> Void
    private let todayStarter: (any TodaySessionStarting)?
    private let openTodaySession: @MainActor () -> Void

    init(provider: (any AdaptiveDebugProviding)?, now: @escaping () -> Date = Date.init,
         timeZone: TimeZone = .current, exportDirectory: URL = FileManager.default.temporaryDirectory,
         copy: @escaping (String) -> Void = { UIPasteboard.general.string = $0 },
         todayStarter: (any TodaySessionStarting)? = nil, openTodaySession: @escaping @MainActor () -> Void = {}) {
        self.provider = provider
        self.now = now
        self.timeZone = timeZone
        self.exportDirectory = exportDirectory
        self.copy = copy
        self.todayStarter = todayStarter
        self.openTodaySession = openTodaySession
    }

    /// Prepares Today's Session (saving its prescription) and opens it. Does nothing unless it is ready.
    func startTodaySession() {
        startMessage = nil
        guard canStartToday, let todayStarter else { return }
        guard todayStarter.start(asOf: now()) != nil else {
            startMessage = todayStarter.lastStartProblem ?? "Today's Session couldn't start."
            return
        }
        openTodaySession()
    }

    private var refreshGeneration = 0

    /// Builds the snapshot the screen shows, then encodes and writes the same snapshot off the main actor, so a long
    /// history never stalls the page. A newer refresh wins over an older one still encoding. Failures become visible
    /// state.
    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        snapshot = nil
        exportURL = nil
        errorMessage = nil
        exportedJSON = nil
        didCopy = false
        guard let provider else { return }

        let generatedAt = now()
        let value: AdaptiveSnapshot
        do {
            value = try provider.adaptiveSnapshot(asOf: generatedAt)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        snapshot = value

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let directory = exportDirectory
        let destination = directory.appendingPathComponent("FMP Adaptive \(formatter.string(from: generatedAt)).json",
                                                           isDirectory: false)
        let written = await Task.detached(priority: .userInitiated) {
            Result { () throws -> String in
                let data = try AdaptiveExport.encode(value)
                guard let json = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
                return json
            }
        }.value
        guard generation == refreshGeneration else { return }
        switch written {
        case .success(let json):
            exportedJSON = json
            exportURL = destination
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Copies the exact JSON written for this refresh.
    func copyJSON() {
        guard let exportedJSON else { return }
        copy(exportedJSON)
        didCopy = true
    }
}
