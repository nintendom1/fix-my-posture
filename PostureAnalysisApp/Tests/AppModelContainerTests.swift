import Foundation
import SwiftData
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AppModelContainerTests: XCTestCase {
    func testInMemoryContainerOpensWithAllSevenModels() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext

        XCTAssertNoThrow(try context.fetch(FetchDescriptor<AssessmentEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<LandmarkEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<MeasurementEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<SavedExerciseSetEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<WorkoutRecordEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<AdaptiveFactEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<AdaptiveProfileCacheEntity>()))
        XCTAssertEqual(Schema(versionedSchema: SchemaV2.self).entities.count, 7)
    }

    func testOnDiskContainerSavesAndReopens() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let recordID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        do {
            let container = try AppModelContainer.make(url: url)
            container.mainContext.insert(WorkoutRecordEntity(WorkoutRecord(
                id: recordID,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(60),
                planName: "Saved plan",
                entries: []
            )))
            try container.mainContext.save()
        }

        let reopened = try AppModelContainer.make(url: url)
        let records = try reopened.mainContext.fetch(FetchDescriptor<WorkoutRecordEntity>())
        XCTAssertEqual(records.map(\.id), [recordID])
        XCTAssertEqual(records.first?.value.planName, "Saved plan")
    }

    func testIncompatibleStoreIsReplacedWithFreshStore() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a SwiftData store".utf8).write(to: url)

        let container = try AppModelContainer.make(url: url)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<WorkoutRecordEntity>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<SavedExerciseSetEntity>()).isEmpty)

        let kept = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("posture.store.unreadable-") && !$0.hasSuffix("-shm") && !$0.hasSuffix("-wal") }
        XCTAssertEqual(kept.count, 1, "the unreadable store is kept beside the fresh one, not deleted")
        let keptName = try XCTUnwrap(kept.first)
        let keptData = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(keptName))
        XCTAssertEqual(keptData, Data("not a SwiftData store".utf8))
    }

    func testMovingStoreAsideKeepsEveryFileAndNeverOverwritesEarlierCopies() throws {
        let url = temporaryStoreURL()
        let folder = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = "posture.store.unreadable-20270115-080000"

        var keptURLs: [URL] = []
        for round in 1...2 {
            try writeStoreGroup(at: url, label: "\(round)")
            keptURLs.append(try AppModelContainer.moveStoreFilesAside(at: url, now: fixedNow))
        }

        XCTAssertEqual(keptURLs.map(\.lastPathComponent), [stamp, "\(stamp)-2"])
        for suffix in ["", "-shm", "-wal"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + suffix), "original\(suffix) is gone")
            XCTAssertEqual(try contents(folder, "\(stamp)\(suffix)"), "\(suffix.isEmpty ? "-db" : suffix) 1")
            XCTAssertEqual(try contents(folder, "\(stamp)-2\(suffix)"), "\(suffix.isEmpty ? "-db" : suffix) 2")
        }
    }

    func testMovingStoreAsideSkipsANameWhoseCompanionIsAlreadyTaken() throws {
        let url = temporaryStoreURL()
        let folder = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = "posture.store.unreadable-20270115-080000"
        try Data("old wal".utf8).write(to: folder.appendingPathComponent("\(stamp)-wal"))
        try Data("old shm".utf8).write(to: folder.appendingPathComponent("\(stamp)-2-shm"))
        try writeStoreGroup(at: url, label: "new")

        let kept = try AppModelContainer.moveStoreFilesAside(at: url, now: fixedNow)

        XCTAssertEqual(kept.lastPathComponent, "\(stamp)-3")
        XCTAssertEqual(try contents(folder, "\(stamp)-wal"), "old wal")
        XCTAssertEqual(try contents(folder, "\(stamp)-2-shm"), "old shm")
        XCTAssertEqual(try contents(folder, "\(stamp)-3-wal"), "-wal new")
    }

    func testMovingStoreAsideLeavesOriginalsUntouchedWhenACopyFails() throws {
        let url = temporaryStoreURL()
        let folder = url.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path + "-wal")
            try? FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeStoreGroup(at: url, label: "live")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path + "-wal")

        XCTAssertThrowsError(try AppModelContainer.moveStoreFilesAside(at: url, now: fixedNow))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path + "-wal")
        XCTAssertEqual(try contents(folder, "posture.store"), "-db live")
        XCTAssertEqual(try contents(folder, "posture.store-shm"), "-shm live")
        XCTAssertEqual(try contents(folder, "posture.store-wal"), "-wal live")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("unreadable") }
        XCTAssertEqual(leftovers, [], "partial copies are removed")
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00:00 UTC

    private func writeStoreGroup(at url: URL, label: String) throws {
        try Data("-db \(label)".utf8).write(to: url)
        try Data("-shm \(label)".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))
        try Data("-wal \(label)".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
    }

    private func contents(_ folder: URL, _ name: String) throws -> String {
        String(decoding: try Data(contentsOf: folder.appendingPathComponent(name)), as: UTF8.self)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelContainerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("posture.store")
    }
}
