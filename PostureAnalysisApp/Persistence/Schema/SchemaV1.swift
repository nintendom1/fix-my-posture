import Foundation
import SwiftData

/// The first explicit, versioned SwiftData schema for the app.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] = [
        AssessmentEntity.self,
        LandmarkEntity.self,
        MeasurementEntity.self,
        SavedExerciseSetEntity.self,
        WorkoutRecordEntity.self
    ]

    @Model
    public final class AssessmentEntity {
        @Attribute(.unique) public var id: UUID
        public var date: Date
        public var imageRelativePath: String
        public var viewRawValue: String
        public var isBaseline: Bool
        public var appVersion: String
        public var imageWidth: Double
        public var imageHeight: Double
        public var warningsData: Data
        public var horizonAngle: Double?
        public var horizonSourceRawValue: String?
        public var isHorizonCompensationApplied: Bool?
        @Relationship(deleteRule: .cascade) public var landmarks: [SchemaV1.LandmarkEntity]
        @Relationship(deleteRule: .cascade) public var measurements: [SchemaV1.MeasurementEntity]

        public init(
            id: UUID = UUID(), date: Date = Date(), imageRelativePath: String, viewRawValue: String,
            isBaseline: Bool = false, appVersion: String = "1.0.0", imageWidth: Double = 1000.0,
            imageHeight: Double = 2000.0, warningsData: Data = Data(), horizonAngle: Double? = nil,
            horizonSourceRawValue: String? = nil, isHorizonCompensationApplied: Bool? = nil,
            landmarks: [SchemaV1.LandmarkEntity] = [], measurements: [SchemaV1.MeasurementEntity] = []
        ) {
            self.id = id
            self.date = date
            self.imageRelativePath = imageRelativePath
            self.viewRawValue = viewRawValue
            self.isBaseline = isBaseline
            self.appVersion = appVersion
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
            self.warningsData = warningsData
            self.horizonAngle = horizonAngle
            self.horizonSourceRawValue = horizonSourceRawValue
            self.isHorizonCompensationApplied = isHorizonCompensationApplied
            self.landmarks = landmarks
            self.measurements = measurements
        }
    }

    @Model
    public final class LandmarkEntity {
        public var typeRawValue: String
        public var normalizedX: Double
        public var normalizedY: Double
        public var imageX: Double
        public var imageY: Double
        public var confidence: Double
        public var isManuallyCorrected: Bool

        public init(typeRawValue: String, normalizedX: Double, normalizedY: Double, imageX: Double,
                    imageY: Double, confidence: Double, isManuallyCorrected: Bool) {
            self.typeRawValue = typeRawValue
            self.normalizedX = normalizedX
            self.normalizedY = normalizedY
            self.imageX = imageX
            self.imageY = imageY
            self.confidence = confidence
            self.isManuallyCorrected = isManuallyCorrected
        }
    }

    @Model
    public final class MeasurementEntity {
        public var measurementIDRawValue: String
        public var name: String
        public var value: Double
        public var unit: String
        public var landmarksUsedRaw: String
        public var confidence: Double
        public var explanation: String

        public init(measurementIDRawValue: String = "", name: String, value: Double, unit: String,
                    landmarksUsedRaw: String, confidence: Double, explanation: String) {
            self.measurementIDRawValue = measurementIDRawValue
            self.name = name
            self.value = value
            self.unit = unit
            self.landmarksUsedRaw = landmarksUsedRaw
            self.confidence = confidence
            self.explanation = explanation
        }

        public var resolvedID: MeasurementID {
            if !measurementIDRawValue.isEmpty, let id = MeasurementID(rawValue: measurementIDRawValue) {
                return id
            }
            return MeasurementID.fromLegacyName(name)
        }
    }

    @Model
    final class SavedExerciseSetEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var itemsData: Data
        var createdAt: Date
        var updatedAt: Date

        init(_ set: SavedExerciseSet, now: Date = Date()) {
            id = set.id
            name = set.name
            itemsData = (try? JSONEncoder().encode(set.items)) ?? Data()
            createdAt = now
            updatedAt = now
        }

        var value: SavedExerciseSet {
            SavedExerciseSet(id: id, name: name, items: (try? JSONDecoder().decode([SavedExerciseSetItem].self, from: itemsData)) ?? [])
        }

        func update(from set: SavedExerciseSet, now: Date = Date()) {
            name = set.name
            itemsData = (try? JSONEncoder().encode(set.items)) ?? Data()
            updatedAt = now
        }
    }

    @Model
    final class WorkoutRecordEntity {
        @Attribute(.unique) var id: UUID
        var startedAt: Date
        var endedAt: Date
        var planID: UUID?
        var planName: String?
        var entriesData: Data

        init(_ record: WorkoutRecord) {
            id = record.id
            startedAt = record.startedAt
            endedAt = record.endedAt
            planID = record.planID
            planName = record.planName
            entriesData = (try? JSONEncoder().encode(record.entries)) ?? Data()
        }

        var value: WorkoutRecord {
            WorkoutRecord(id: id, startedAt: startedAt, endedAt: endedAt, planID: planID, planName: planName,
                          entries: (try? JSONDecoder().decode([WorkoutRecordEntry].self, from: entriesData)) ?? [])
        }

        func update(entries: [WorkoutRecordEntry]) {
            entriesData = (try? JSONEncoder().encode(entries)) ?? Data()
        }
    }
}

public typealias AssessmentEntity = SchemaV1.AssessmentEntity
public typealias LandmarkEntity = SchemaV1.LandmarkEntity
public typealias MeasurementEntity = SchemaV1.MeasurementEntity
typealias SavedExerciseSetEntity = SchemaV1.SavedExerciseSetEntity
typealias WorkoutRecordEntity = SchemaV1.WorkoutRecordEntity
