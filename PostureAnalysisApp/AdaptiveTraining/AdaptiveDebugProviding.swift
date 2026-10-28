import AdaptiveTraining
import Foundation

/// What the Adaptive training developer page reads. It does not record or change facts.
@MainActor
protocol AdaptiveDebugProviding: AnyObject {
    func adaptiveSnapshot(asOf now: Date) throws -> AdaptiveSnapshot
}

extension AdaptiveTrainingEngine: AdaptiveDebugProviding {
    func adaptiveSnapshot(asOf now: Date) throws -> AdaptiveSnapshot {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return try snapshot(asOf: now, appVersion: version)
    }
}
