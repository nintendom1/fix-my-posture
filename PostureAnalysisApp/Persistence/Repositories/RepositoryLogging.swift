import OSLog

enum PersistenceRepositoryLogging {
    private static let logger = Logger(subsystem: "FixMyPosture", category: "Repositories")

    static func failed(_ operation: String, error: Error) {
        logger.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}
