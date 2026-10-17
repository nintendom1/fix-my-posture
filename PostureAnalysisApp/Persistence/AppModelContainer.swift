import Foundation
import OSLog
import SwiftData

@MainActor
enum AppModelContainer {
    private static let logger = Logger(subsystem: "FixMyPosture", category: "Persistence")

    static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
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
            try removeStoreFiles(at: configuration.url)
            do {
                return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [configuration])
            } catch {
                logger.error("Could not create a fresh SwiftData store at \(configuration.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    private static func removeStoreFiles(at url: URL) throws {
        let fileManager = FileManager.default
        let companionURLs = [
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal")
        ]
        for fileURL in [url] + companionURLs {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }
}
