import AdaptiveTraining
import Foundation
import SwiftData
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class SchemaMigrationTests: XCTestCase {
    func testV1StoreMigratesWithoutFallbackAndAdaptiveFactsSurviveReopen() throws {
        XCTAssertEqual(AppMigrationPlan.schemas.count, 2)
        XCTAssertEqual(AppMigrationPlan.stages.count, 1, "the V1-to-V2 migration stage must stay registered")

        let url = temporaryStoreURL()
        let folder = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let workoutID = id(1)
        let setID = id(2)
        let assessmentID = id(3)
        let startedAt = date(100)
        let workoutEntry = WorkoutRecordEntry(id: id(4), exerciseID: ExerciseID(rawValue: "wall_push_up"),
                                              name: "Wall Push-up", outcome: .completed,
                                              sets: [RecordedSet(reps: 6, side: nil, weight: nil)])
        let workout = WorkoutRecord(id: workoutID, startedAt: startedAt, endedAt: date(160), planID: setID,
                                    planName: "Morning set", entries: [workoutEntry])
        let savedItem = SavedExerciseSetItem(id: id(5), exerciseID: ExerciseID(rawValue: "wall_push_up"),
                                             setCount: 2, targetRepMinimum: 5, targetRepMaximum: 8)
        let savedSet = SavedExerciseSet(id: setID, name: "Wall set", items: [savedItem])
        let landmark = SchemaV1.LandmarkEntity(typeRawValue: "leftShoulder", normalizedX: 0.4, normalizedY: 0.7,
                                                imageX: 400, imageY: 600, confidence: 0.93,
                                                isManuallyCorrected: true)
        let measurement = SchemaV1.MeasurementEntity(measurementIDRawValue: "front.shoulder_line_angle",
                                                    name: "Shoulder line angle", value: 2.5, unit: "°",
                                                    landmarksUsedRaw: "leftShoulder,rightShoulder", confidence: 0.91,
                                                    explanation: "Shoulder height difference.")
        let assessmentDate = date(200)

        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let configuration = ModelConfiguration("PostureAnalysis", schema: schema, url: url,
                                                    cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            context.insert(SchemaV1.WorkoutRecordEntity(workout))
            context.insert(SchemaV1.SavedExerciseSetEntity(savedSet, now: date(101)))
            context.insert(SchemaV1.AssessmentEntity(id: assessmentID, date: assessmentDate,
                                                     imageRelativePath: "assessment-v1.jpg", viewRawValue: "front",
                                                     isBaseline: true, appVersion: "1.2.3", imageWidth: 1200,
                                                     imageHeight: 2400, warningsData: Data("[]".utf8),
                                                     horizonAngle: 1.25, horizonSourceRawValue: "camera",
                                                     isHorizonCompensationApplied: true, landmarks: [landmark],
                                                     measurements: [measurement]))
            try context.save()
        }

        do {
            let migrated = try AppModelContainer.make(url: url)
            let context = migrated.mainContext

            let workoutRecords = try context.fetch(FetchDescriptor<WorkoutRecordEntity>())
            XCTAssertEqual(workoutRecords.count, 1)
            XCTAssertEqual(workoutRecords.first?.value, workout)

            let savedSets = try context.fetch(FetchDescriptor<SavedExerciseSetEntity>())
            XCTAssertEqual(savedSets.count, 1)
            XCTAssertEqual(savedSets.first?.value, savedSet)

            let assessments = try context.fetch(FetchDescriptor<AssessmentEntity>())
            XCTAssertEqual(assessments.count, 1)
            let migratedAssessment = try XCTUnwrap(assessments.first)
            XCTAssertEqual(migratedAssessment.id, assessmentID)
            XCTAssertEqual(migratedAssessment.date, assessmentDate)
            XCTAssertEqual(migratedAssessment.imageRelativePath, "assessment-v1.jpg")
            XCTAssertEqual(migratedAssessment.viewRawValue, "front")
            XCTAssertTrue(migratedAssessment.isBaseline)
            XCTAssertEqual(migratedAssessment.appVersion, "1.2.3")
            XCTAssertEqual(migratedAssessment.imageWidth, 1200)
            XCTAssertEqual(migratedAssessment.imageHeight, 2400)
            XCTAssertEqual(migratedAssessment.warningsData, Data("[]".utf8))
            XCTAssertEqual(migratedAssessment.horizonAngle, 1.25)
            XCTAssertEqual(migratedAssessment.horizonSourceRawValue, "camera")
            XCTAssertEqual(migratedAssessment.isHorizonCompensationApplied, true)
            XCTAssertEqual(migratedAssessment.landmarks.count, 1)
            XCTAssertEqual(migratedAssessment.measurements.count, 1)

            let migratedLandmark = try XCTUnwrap(try context.fetch(FetchDescriptor<LandmarkEntity>()).first)
            XCTAssertEqual(migratedLandmark.typeRawValue, "leftShoulder")
            XCTAssertEqual(migratedLandmark.normalizedX, 0.4)
            XCTAssertEqual(migratedLandmark.normalizedY, 0.7)
            XCTAssertEqual(migratedLandmark.imageX, 400)
            XCTAssertEqual(migratedLandmark.imageY, 600)
            XCTAssertEqual(migratedLandmark.confidence, 0.93)
            XCTAssertTrue(migratedLandmark.isManuallyCorrected)

            let migratedMeasurement = try XCTUnwrap(try context.fetch(FetchDescriptor<MeasurementEntity>()).first)
            XCTAssertEqual(migratedMeasurement.measurementIDRawValue, "front.shoulder_line_angle")
            XCTAssertEqual(migratedMeasurement.name, "Shoulder line angle")
            XCTAssertEqual(migratedMeasurement.value, 2.5)
            XCTAssertEqual(migratedMeasurement.unit, "°")
            XCTAssertEqual(migratedMeasurement.landmarksUsedRaw, "leftShoulder,rightShoulder")
            XCTAssertEqual(migratedMeasurement.confidence, 0.91)
            XCTAssertEqual(migratedMeasurement.explanation, "Shoulder height difference.")

            let unreadableCopies = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0.contains(".unreadable-") }
            XCTAssertEqual(unreadableCopies, [], "a valid V1 store must migrate without invoking recovery")

            let repository = SwiftDataAdaptiveTrainingRepository(context: context)
            try repository.record(makePrescription(id: id(6), at: date(300)))
            try repository.record(makeEvidence(id: id(7), at: date(301)))
        }

        let reopened = try AppModelContainer.make(url: url)
        let loadedFacts = try SwiftDataAdaptiveTrainingRepository(context: reopened.mainContext).loadFacts()
        XCTAssertEqual(loadedFacts.prescriptions.map(\.id), [id(6)])
        XCTAssertEqual(loadedFacts.evidence.map(\.id), [id(7)])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<WorkoutRecordEntity>()).count, 1)
    }

    func testFreshV2StoreOpensWithSevenModelsAndNoAdaptiveFacts() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let container = try AppModelContainer.make(url: url)
        let context = container.mainContext
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<AssessmentEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<LandmarkEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<MeasurementEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<SavedExerciseSetEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<WorkoutRecordEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<AdaptiveFactEntity>()))
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<AdaptiveProfileCacheEntity>()))
        XCTAssertEqual(Schema(versionedSchema: SchemaV2.self).entities.count, 7)
        XCTAssertTrue(try SwiftDataAdaptiveTrainingRepository(context: context).loadFacts().isEmpty)
    }

    private func makePrescription(id factID: UUID, at: Date) -> Prescription {
        Prescription(id: factID, issuedAt: at, kind: .todaySession, policyVersion: .v1, catalogVersion: "ladders-1",
                     items: [PrescriptionItem(id: id(70), family: .push,
                                              target: RungDose(variant: VariantID(rawValue: "push.wall_push_up"),
                                                               dose: .reps(4)))],
                     rationale: "Continue with a comfortable set.")
    }

    private func makeEvidence(id factID: UUID, at: Date) -> AdaptiveEvidence {
        AdaptiveEvidence(id: factID, recordedAt: at, source: .adaptive, family: .push,
                         variant: VariantID(rawValue: "push.wall_push_up"), prescriptionID: id(6),
                         prescriptionItemID: id(70), prescribed: .reps(4), confirmed: .reps(3), confirmation: .user,
                         tracker: TrackerObservation(status: .tracked, observed: .reps(3)),
                         effort: .okay, completion: .completed)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaMigrationTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("posture.store")
    }

    private func id(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
