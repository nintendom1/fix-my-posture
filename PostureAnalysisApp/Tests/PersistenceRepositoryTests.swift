import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class PersistenceRepositoryTests: XCTestCase {
    private let press = ShoulderPressExercise.definition()

    func testWorkoutHistoryRepositorySavesNewestFirstUpdatesWeightsAndDeletes() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataWorkoutHistoryRepository(context: container.mainContext)
        let old = workoutRecord(startedAt: Date(timeIntervalSince1970: 10))
        let newest = workoutRecord(startedAt: Date(timeIntervalSince1970: 20))

        try repository.save(old)
        try repository.save(newest)
        XCTAssertEqual(try repository.list().map(\.id), [newest.id, old.id])

        var updated = newest
        updated.entries[0].sets[0].weight = .mass(12, .pounds)
        try repository.updateWeights(for: updated)
        XCTAssertEqual(try repository.list().first?.entries[0].sets[0].weight, .mass(12, .pounds))

        try repository.delete(id: newest.id)
        XCTAssertEqual(try repository.list().map(\.id), [old.id])
    }

    func testRoutineRepositorySavesDuplicatesWithCopyNameAndDeletes() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataRoutineRepository(context: container.mainContext)
        let original = SavedExerciseSet(name: "Legs", items: [SavedExerciseSetItem(exercise: press)])

        try repository.save(original)
        let copy = try repository.duplicate(original)
        XCTAssertEqual(copy.name, "Legs Copy")
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertNotEqual(copy.items.first?.id, original.items.first?.id)
        XCTAssertEqual(try repository.list().map(\.name), ["Legs", "Legs Copy"])

        try repository.delete(id: original.id)
        XCTAssertEqual(try repository.list().map(\.id), [copy.id])
    }

    func testAssessmentRepositoryMapsSavedAssessmentAndKeepsBaselinePerView() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataAssessmentRepository(context: container.mainContext)
        let front = assessment(view: .front, at: Date(timeIntervalSince1970: 10))
        let anotherFront = assessment(view: .front, at: Date(timeIntervalSince1970: 20))
        let side = assessment(view: .leftSide, at: Date(timeIntervalSince1970: 30))

        try repository.save(front, imageRelativePath: "front.jpeg")
        try repository.save(anotherFront, imageRelativePath: "front-new.jpeg")
        try repository.save(side, imageRelativePath: "side.jpeg")
        try repository.setBaseline(id: front.id, isBaseline: true)
        try repository.setBaseline(id: side.id, isBaseline: true)

        let listed = try repository.list()
        XCTAssertEqual(listed.map(\.id), [side.id, anotherFront.id, front.id])
        XCTAssertEqual(listed.map(\.isBaseline), [true, false, true])
        XCTAssertEqual(listed.first(where: { $0.id == front.id })?.pose.landmarks[.leftShoulder]?.imageLocation.x, 10)
        XCTAssertEqual(listed.first(where: { $0.id == front.id })?.measurements.first?.measurementID, .shoulderLineAngle)

        try repository.setBaseline(id: front.id, isBaseline: false)
        let afterToggle = try repository.list()
        XCTAssertFalse(try XCTUnwrap(afterToggle.first(where: { $0.id == front.id })).isBaseline)
        XCTAssertTrue(try XCTUnwrap(afterToggle.first(where: { $0.id == side.id })).isBaseline)

        try repository.delete(id: anotherFront.id)
        XCTAssertFalse(try repository.list().contains(where: { $0.id == anotherFront.id }))
    }

    func testCorruptSavedSetAndWorkoutEntryJSONDecodeAsEmptyLists() {
        let set = SavedExerciseSetEntity(SavedExerciseSet(name: "Broken", items: []))
        set.itemsData = Data("{".utf8)
        XCTAssertTrue(set.value.items.isEmpty)

        let record = WorkoutRecordEntity(workoutRecord(startedAt: Date()))
        record.entriesData = Data("not json".utf8)
        XCTAssertTrue(record.value.entries.isEmpty)
    }

    private func workoutRecord(startedAt: Date) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            planName: nil,
            entries: [WorkoutRecordEntry(exerciseID: press.id, name: press.displayName, sets: [RecordedSet(reps: 1)])]
        )
    }

    private func assessment(view: PostureView, at date: Date) -> PostureAssessment {
        let landmark = Landmark(type: .leftShoulder, normalizedLocation: CGPoint(x: 0.1, y: 0.2),
                                imageLocation: CGPoint(x: 10, y: 20), confidence: 0.9)
        let pose = BodyPose(landmarks: [.leftShoulder: landmark], imageWidth: 100, imageHeight: 200)
        let measurement = PostureMeasurement(id: .shoulderLineAngle, name: "Shoulder Line Angle", value: 3,
                                             unit: "°", landmarksUsed: [.leftShoulder], confidence: 0.8,
                                             explanation: "Observed angle")
        return PostureAssessment(date: date, imageRelativePath: "", view: view, pose: pose,
                                 measurements: [measurement], isBaseline: false)
    }
}
