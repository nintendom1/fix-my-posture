import Foundation

/// Persists the persona trace state as JSON in Application Support. Safe to call from any thread.
/// A missing or unreadable file loads as empty state.
final class FilePersonaTraceStore: PersonaTraceStoring {
    let url: URL
    private let lock = NSLock()

    init(url: URL = FilePersonaTraceStore.defaultURL()) {
        self.url = url
    }

    static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("persona-traces.json")
    }

    func load() -> PersonaTraceState {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(PersonaTraceState.self, from: data)) ?? .empty
    }

    func save(_ state: PersonaTraceState) {
        lock.lock()
        defer { lock.unlock() }

        let directory = url.deletingLastPathComponent()
        guard (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )) != nil else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
