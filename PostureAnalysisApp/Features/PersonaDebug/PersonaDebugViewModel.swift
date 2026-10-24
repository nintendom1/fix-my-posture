import Foundation
import Observation

/// Developer page state for Extra Personable: live status, the last sent and suppressed decisions, a trace
/// detail, and a content preview that can send any configured variant without waiting for a detector.
@MainActor
@Observable
final class PersonaDebugViewModel {
    // Implemented by P5.
    init(
        catalog: PersonaContentCatalog?,
        loadError: String?,
        provider: (any PersonaDebugProviding)?,
        scheduler: any NotificationPreviewScheduling,
        preferences: any AppPreferencesStoring,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {}
}
