import Foundation
import OSLog
import SwiftData

@MainActor
enum AppModelContainer {
    private static let logger = Logger(subsystem: "FixMyPosture", category: "Persistence")

    static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("PostureAnalysis", schema: schema, isStoredInMemoryOnly: true,
                                                cloudKitDatabase: .none)
        } else if let url {
            configuration = ModelConfiguration("PostureAnalysis", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("PostureAnalysis", schema: schema, cloudKitDatabase: .none)
        }

        if !inMemory {
            try FileManager.default.createDirectory(at: configuration.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }

        do {
            return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [configuration])
        } catch {
            guard !inMemory else { throw error }
            logger.error("Could not open SwiftData store at \(configuration.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            let keptAt = try moveStoreFilesAside(at: configuration.url, now: Date())
            logger.error("Kept the unreadable store at \(keptAt.path, privacy: .public)")
            do {
                return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [configuration])
            } catch {
                logger.error("Could not create a fresh SwiftData store at \(configuration.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    private static let storeFileSuffixes = ["", "-shm", "-wal"]

    /// Keeps the store and its SQLite `-shm`/`-wal` companions as `<store>.unreadable-<UTC time>` so a failed
    /// migration keeps the data for recovery instead of deleting it. Returns the kept store's URL.
    ///
    /// All three files are copied before any original is removed, so the kept group is always complete: if a copy
    /// fails, the partial copies are removed and the originals are left untouched (the open then fails instead of
    /// starting fresh). Companions are removed before the main file, so a failed removal never leaves a WAL
    /// beside a missing database.
    static func moveStoreFilesAside(at url: URL, now: Date) throws -> URL {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)

        func isTaken(_ candidate: URL) -> Bool {
            storeFileSuffixes.contains { fileManager.fileExists(atPath: candidate.path + $0) }
        }
        var keptURL = URL(fileURLWithPath: url.path + ".unreadable-\(stamp)")
        var attempt = 2
        while isTaken(keptURL) {
            keptURL = URL(fileURLWithPath: url.path + ".unreadable-\(stamp)-\(attempt)")
            attempt += 1
        }

        let present = storeFileSuffixes.filter { fileManager.fileExists(atPath: url.path + $0) }
        var copied: [URL] = []
        do {
            for suffix in present {
                let destination = URL(fileURLWithPath: keptURL.path + suffix)
                try fileManager.copyItem(at: URL(fileURLWithPath: url.path + suffix), to: destination)
                copied.append(destination)
            }
        } catch {
            for destination in copied {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }

        for suffix in present.reversed() {
            try fileManager.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
        return keptURL
    }
}
