import CoreGraphics
import Foundation
import SwiftData

@MainActor
protocol AssessmentRepository {
    func list() throws -> [PostureAssessment]
    func save(_ assessment: PostureAssessment, imageRelativePath: String) throws
    func update(_ assessment: PostureAssessment) throws
    func setBaseline(id: UUID, isBaseline: Bool) throws
    func delete(id: UUID) throws
}

extension AssessmentRepository {
    func update(_ assessment: PostureAssessment) throws {
        try save(assessment, imageRelativePath: assessment.imageRelativePath)
    }
}

@MainActor
final class SwiftDataAssessmentRepository: AssessmentRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func list() throws -> [PostureAssessment] {
        do {
            let descriptor = FetchDescriptor<AssessmentEntity>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            return try context.fetch(descriptor).map(domainValue(from:))
        } catch {
            PersistenceRepositoryLogging.failed("List assessments", error: error)
            throw error
        }
    }

    func save(_ assessment: PostureAssessment, imageRelativePath: String) throws {
        do {
            let landmarks = assessment.pose.landmarks.map { type, landmark in
                LandmarkEntity(typeRawValue: type.rawValue,
                               normalizedX: landmark.normalizedLocation.x,
                               normalizedY: landmark.normalizedLocation.y,
                               imageX: landmark.imageLocation.x,
                               imageY: landmark.imageLocation.y,
                               confidence: landmark.confidence,
                               isManuallyCorrected: landmark.isManuallyCorrected)
            }
            let measurements = assessment.measurements.map { measurement in
                MeasurementEntity(measurementIDRawValue: measurement.measurementID.rawValue,
                                  name: measurement.name,
                                  value: measurement.value,
                                  unit: measurement.unit,
                                  landmarksUsedRaw: measurement.landmarksUsed.map(\.rawValue).joined(separator: ","),
                                  confidence: measurement.confidence,
                                  explanation: measurement.explanation)
            }
            let entity = AssessmentEntity(
                id: assessment.id,
                date: assessment.date,
                imageRelativePath: imageRelativePath,
                viewRawValue: assessment.view.rawValue,
                isBaseline: assessment.isBaseline,
                appVersion: assessment.appVersion,
                imageWidth: Double(assessment.pose.imageWidth),
                imageHeight: Double(assessment.pose.imageHeight),
                horizonAngle: assessment.horizonContext?.angleDegrees,
                horizonSourceRawValue: assessment.horizonContext?.source.rawValue,
                isHorizonCompensationApplied: assessment.horizonContext?.isCompensationApplied,
                landmarks: landmarks,
                measurements: measurements
            )
            context.insert(entity)
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Save assessment", error: error)
            throw error
        }
    }

    func setBaseline(id: UUID, isBaseline: Bool) throws {
        do {
            let assessments = try context.fetch(FetchDescriptor<AssessmentEntity>())
            guard let selected = assessments.first(where: { $0.id == id }) else { return }
            if isBaseline {
                for item in assessments where item.viewRawValue == selected.viewRawValue && item.id != id {
                    item.isBaseline = false
                }
            }
            selected.isBaseline = isBaseline
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Set assessment baseline", error: error)
            throw error
        }
    }

    func update(_ assessment: PostureAssessment) throws {
        do {
            let descriptor = FetchDescriptor<AssessmentEntity>()
            guard let entity = try context.fetch(descriptor).first(where: { $0.id == assessment.id }) else { return }
            entity.date = assessment.date
            entity.imageRelativePath = assessment.imageRelativePath
            entity.viewRawValue = assessment.view.rawValue
            entity.isBaseline = assessment.isBaseline
            entity.appVersion = assessment.appVersion
            entity.imageWidth = Double(assessment.pose.imageWidth)
            entity.imageHeight = Double(assessment.pose.imageHeight)
            entity.horizonAngle = assessment.horizonContext?.angleDegrees
            entity.horizonSourceRawValue = assessment.horizonContext?.source.rawValue
            entity.isHorizonCompensationApplied = assessment.horizonContext?.isCompensationApplied
            entity.warningsData = (try? JSONEncoder().encode(assessment.warnings)) ?? Data()
            entity.landmarks.forEach(context.delete)
            entity.measurements.forEach(context.delete)
            entity.landmarks = assessment.pose.landmarks.map { type, landmark in
                LandmarkEntity(typeRawValue: type.rawValue,
                               normalizedX: landmark.normalizedLocation.x,
                               normalizedY: landmark.normalizedLocation.y,
                               imageX: landmark.imageLocation.x,
                               imageY: landmark.imageLocation.y,
                               confidence: landmark.confidence,
                               isManuallyCorrected: landmark.isManuallyCorrected)
            }
            entity.measurements = assessment.measurements.map { measurement in
                MeasurementEntity(measurementIDRawValue: measurement.measurementID.rawValue,
                                  name: measurement.name,
                                  value: measurement.value,
                                  unit: measurement.unit,
                                  landmarksUsedRaw: measurement.landmarksUsed.map(\.rawValue).joined(separator: ","),
                                  confidence: measurement.confidence,
                                  explanation: measurement.explanation)
            }
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Update assessment", error: error)
            throw error
        }
    }

    func delete(id: UUID) throws {
        do {
            guard let entity = try context.fetch(FetchDescriptor<AssessmentEntity>()).first(where: { $0.id == id }) else {
                return
            }
            context.delete(entity)
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Delete assessment", error: error)
            throw error
        }
    }

    private func domainValue(from entity: AssessmentEntity) -> PostureAssessment {
        var landmarks: [LandmarkType: Landmark] = [:]
        for item in entity.landmarks {
            guard let type = LandmarkType(rawValue: item.typeRawValue) else { continue }
            landmarks[type] = Landmark(type: type,
                                       normalizedLocation: CGPoint(x: item.normalizedX, y: item.normalizedY),
                                       imageLocation: CGPoint(x: item.imageX, y: item.imageY),
                                       confidence: item.confidence,
                                       isManuallyCorrected: item.isManuallyCorrected)
        }

        let measurements = entity.measurements.map { item in
            PostureMeasurement(id: item.resolvedID,
                               name: item.name,
                               value: item.value,
                               unit: item.unit,
                               landmarksUsed: item.landmarksUsedRaw.split(separator: ",")
                                   .compactMap { LandmarkType(rawValue: String($0)) },
                               confidence: item.confidence,
                               explanation: item.explanation)
        }
        let horizonContext: HorizonContext?
        if let angle = entity.horizonAngle,
           let sourceRawValue = entity.horizonSourceRawValue,
           let source = HorizonSource(rawValue: sourceRawValue),
           let applied = entity.isHorizonCompensationApplied {
            horizonContext = HorizonContext(angleDegrees: angle, source: source, isCompensationApplied: applied)
        } else {
            horizonContext = nil
        }

        return PostureAssessment(id: entity.id,
                                 date: entity.date,
                                 imageRelativePath: entity.imageRelativePath,
                                 view: PostureView(rawValue: entity.viewRawValue) ?? .uncertain,
                                 pose: BodyPose(landmarks: landmarks, imageWidth: CGFloat(entity.imageWidth),
                                                imageHeight: CGFloat(entity.imageHeight)),
                                 measurements: measurements,
                                 warnings: [],
                                 isBaseline: entity.isBaseline,
                                 appVersion: entity.appVersion,
                                 horizonContext: horizonContext)
    }
}
