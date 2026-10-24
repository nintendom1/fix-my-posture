import Foundation

/// Persists the persona trace state as JSON in Application Support. Safe to call from any thread.
/// A missing or unreadable file loads as empty state.
final class FilePersonaTraceStore: PersonaTraceStoring {
    let url: URL

    init(url: URL = FilePersonaTraceStore.defaultURL()) {
        self.url = url
    }

    static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("persona-traces.json")
    }

    func load() -> PersonaTraceState {
        // Implemented by P2.
        .empty
    }

    func save(_ state: PersonaTraceState) {
        // Implemented by P2.
    }
}
