import Foundation
import SwiftData
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AppModelContainerTests: XCTestCase {
    func testInMemoryContainerOpensWithAllFiveModels() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext

        XCTAssertNoThrow(try context.fetch(FetchDescriptor<AssessmentEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<LandmarkEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<MeasurementEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<SavedExerciseSetEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<WorkoutRecordEntity>()))
        XCTAssertEqual(Schema(versionedSchema: SchemaV1.self).entities.count, 5)
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
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelContainerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("posture.store")
    }
}
