import CoreGraphics
import XCTest
@testable import PostureAnalysisApp

final class PostureAssessmentServiceTests: XCTestCase {
    func testValidPoseProducesTheSameMeasurementsAsPostureAnalyzer() async throws {
        let pose = frontPose()
        let service = LivePostureAssessmentService(estimator: FakePoseEstimator(result: .success(pose)))
        let metadata = ImageMetadata(width: 600, height: 1200, source: .photoLibrary)

        let result = try await service.analyze(in: testImage(), metadata: metadata)
        let expected = PostureAnalyzer().analyze(pose: pose, imageMetadata: metadata, view: .front)

        XCTAssertEqual(result.measurements, expected.measurements)
        XCTAssertEqual(result.warnings, expected.warnings)
    }

    func testPhotoEstimationValidationErrorIsPassedThrough() async {
        let service = LivePostureAssessmentService(estimator: FakePoseEstimator(result: .failure(FakePhotoError.invalidPhoto)))

        do {
            _ = try await service.analyze(in: testImage(), metadata: ImageMetadata(width: 600, height: 1200))
            XCTFail("Expected the photo validation error to be returned")
        } catch let error as FakePhotoError {
            XCTAssertEqual(error, .invalidPhoto)
            XCTAssertEqual(error.localizedDescription, "The photo could not be analyzed.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLowQualityPhotoKeepsCurrentPhotoValidationMessages() async throws {
        let pose = BodyPose(landmarks: [:], imageWidth: 600, imageHeight: 1200)
        let service = LivePostureAssessmentService(estimator: FakePoseEstimator(result: .success(pose)))
        let metadata = ImageMetadata(width: 600, height: 1200, source: .photoLibrary)

        let result = try await service.analyze(
            in: testImage(),
            metadata: metadata,
            selectedView: .front,
            horizonContext: nil
        )

        XCTAssertTrue(result.warnings.contains { $0.hasPrefix("Fewer than 6 body landmarks were detected.") })
        XCTAssertEqual(result.warnings, PhotoValidator.validate(pose: pose, metadata: metadata).warnings)
    }

    func testDetectedViewClassificationIsPassedThrough() async throws {
        let pose = sidePose()
        let result = try await LivePostureAssessmentService(
            estimator: FakePoseEstimator(result: .success(pose))
        ).analyze(in: testImage(), metadata: ImageMetadata(width: 600, height: 1200))

        XCTAssertEqual(ViewClassifier.classify(pose: pose), .leftSide)
        XCTAssertEqual(result.view, .leftSide)
    }

    private func testImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 600,
            height: 1200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func frontPose() -> BodyPose {
        let points: [(LandmarkType, CGFloat, CGFloat)] = [
            (.nose, 300, 90), (.neck, 300, 160),
            (.leftShoulder, 220, 220), (.rightShoulder, 380, 230),
            (.leftHip, 245, 530), (.rightHip, 355, 525),
            (.leftAnkle, 250, 1080), (.rightAnkle, 350, 1080)
        ]
        return BodyPose(landmarks: Dictionary(uniqueKeysWithValues: points.map { type, x, y in
            (type, landmark(type, x: x, y: y))
        }), imageWidth: 600, imageHeight: 1200)
    }

    private func sidePose() -> BodyPose {
        BodyPose(landmarks: [
            .leftEar: landmark(.leftEar, x: 280, y: 100),
            .leftShoulder: landmark(.leftShoulder, x: 300, y: 250),
            .rightShoulder: landmark(.rightShoulder, x: 305, y: 250),
            .leftHip: landmark(.leftHip, x: 300, y: 550),
            .rightHip: landmark(.rightHip, x: 305, y: 550)
        ], imageWidth: 600, imageHeight: 1200)
    }

    private func landmark(_ type: LandmarkType, x: CGFloat, y: CGFloat) -> Landmark {
        Landmark(
            type: type,
            normalizedLocation: CGPoint(x: x / 600, y: 1 - y / 1200),
            imageLocation: CGPoint(x: x, y: y),
            confidence: 0.95
        )
    }
}

private struct FakePoseEstimator: PoseEstimator {
    let result: Result<BodyPose, FakePhotoError>

    func estimatePose(in image: CGImage) async throws -> BodyPose {
        try result.get()
    }
}

private enum FakePhotoError: Error, LocalizedError {
    case invalidPhoto

    var errorDescription: String? { "The photo could not be analyzed." }
}
