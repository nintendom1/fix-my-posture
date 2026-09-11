import XCTest
import CoreGraphics
@testable import PostureAnalysisApp

final class GeometryTests: XCTestCase {

    private var analyzer: PostureAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = PostureAnalyzer()
    }

    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }

    // MARK: - Test 1: Horizontal Shoulders
    func testHorizontalShoulders() {
        var landmarks: [LandmarkType: Landmark] = [:]
        let lsImg = CGPoint(x: 300, y: 300)
        let rsImg = CGPoint(x: 700, y: 300)

        landmarks[.leftShoulder] = Landmark(type: .leftShoulder, normalizedLocation: CGPoint(x: 0.3, y: 0.85), imageLocation: lsImg, confidence: 0.95)
        landmarks[.rightShoulder] = Landmark(type: .rightShoulder, normalizedLocation: CGPoint(x: 0.7, y: 0.85), imageLocation: rsImg, confidence: 0.95)

        let pose = BodyPose(landmarks: landmarks, imageWidth: 1000, imageHeight: 2000)
        let meta = ImageMetadata(width: 1000, height: 2000)

        let assessment = analyzer.analyze(pose: pose, imageMetadata: meta, view: .front)

        guard let shoulderAngle = assessment.measurements.first(where: { $0.measurementID == .shoulderLineAngle }) else {
            XCTFail("Shoulder Line Angle measurement missing")
            return
        }

        XCTAssertEqual(shoulderAngle.value, 0.0, accuracy: 0.1, "Horizontal shoulders must yield 0 degree angle.")
    }

    // MARK: - Test 2: Tilted Shoulders on Non-Square Image (Aspect Ratio Distortion Check)
    func testTiltedShouldersNonSquareImage() {
        let width: CGFloat = 1000
        let height: CGFloat = 2000 // 1:2 non-square aspect ratio

        // Pixel coordinates: ls = (300, 300), rs = (700, 400) -> dx = 400, dy = 100 in pixels
        let lsPixel = CGPoint(x: 300, y: 300)
        let rsPixel = CGPoint(x: 700, y: 400)

        let lsNorm = CoordinateConverter.imagePixelToNormalized(pixel: lsPixel, imageWidth: width, imageHeight: height)
        let rsNorm = CoordinateConverter.imagePixelToNormalized(pixel: rsPixel, imageWidth: width, imageHeight: height)

        var landmarks: [LandmarkType: Landmark] = [:]
        landmarks[.leftShoulder] = Landmark(type: .leftShoulder, normalizedLocation: lsNorm, imageLocation: lsPixel, confidence: 0.9)
        landmarks[.rightShoulder] = Landmark(type: .rightShoulder, normalizedLocation: rsNorm, imageLocation: rsPixel, confidence: 0.9)

        let pose = BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
        let meta = ImageMetadata(width: width, height: height)

        let assessment = analyzer.analyze(pose: pose, imageMetadata: meta, view: .front)

        guard let shoulderAngle = assessment.measurements.first(where: { $0.measurementID == .shoulderLineAngle }) else {
            XCTFail("Shoulder Line Angle measurement missing")
            return
        }

        // Expected true angle from aspect-correct pixel dx=400, dy=100 -> atan2(100, 400) ~ 14.036°
        let expectedTrueAngle = abs(atan2(100.0, 400.0) * 180.0 / .pi)

        XCTAssertEqual(shoulderAngle.value, expectedTrueAngle, accuracy: 0.2, "Angle must be calculated using aspect-correct pixel space.")
    }

    // MARK: - Test 3: Horizontal Angle Order Invariance
    func testHorizontalAngleOrderInvariance() {
        let p1 = CGPoint(x: 300, y: 300)
        let p2 = CGPoint(x: 700, y: 400)

        let angleNormal = analyzer.angleWithHorizontalDegrees(p1: p1, p2: p2)
        let angleReversed = analyzer.angleWithHorizontalDegrees(p1: p2, p2: p1)

        XCTAssertEqual(abs(angleNormal), abs(angleReversed), accuracy: 0.001, "Angle with horizontal must be identical regardless of point order.")
    }

    // MARK: - Test 4: Side View Forward Head & Sagittal Lean
    func testSideViewGeometry() {
        let width: CGFloat = 1000
        let height: CGFloat = 2000

        var landmarks: [LandmarkType: Landmark] = [:]
        let earPixel = CGPoint(x: 550, y: 300)
        let shoulderPixel = CGPoint(x: 500, y: 600)
        let hipPixel = CGPoint(x: 500, y: 1100)
        let kneePixel = CGPoint(x: 500, y: 1500)
        let anklePixel = CGPoint(x: 500, y: 1900)

        landmarks[.leftEar] = Landmark(type: .leftEar, normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: earPixel, imageWidth: width, imageHeight: height), imageLocation: earPixel, confidence: 0.95)
        landmarks[.leftShoulder] = Landmark(type: .leftShoulder, normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: shoulderPixel, imageWidth: width, imageHeight: height), imageLocation: shoulderPixel, confidence: 0.95)
        landmarks[.leftHip] = Landmark(type: .leftHip, normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: hipPixel, imageWidth: width, imageHeight: height), imageLocation: hipPixel, confidence: 0.95)
        landmarks[.leftKnee] = Landmark(type: .leftKnee, normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: kneePixel, imageWidth: width, imageHeight: height), imageLocation: kneePixel, confidence: 0.95)
        landmarks[.leftAnkle] = Landmark(type: .leftAnkle, normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: anklePixel, imageWidth: width, imageHeight: height), imageLocation: anklePixel, confidence: 0.95)

        let pose = BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
        let meta = ImageMetadata(width: width, height: height)

        let assessment = analyzer.analyze(pose: pose, imageMetadata: meta, view: .leftSide)

        guard let earOffset = assessment.measurements.first(where: { $0.measurementID == .earShoulderHorizontalOffset }) else {
            XCTFail("Ear-Shoulder Horizontal Offset measurement missing")
            return
        }

        // 50px dx on 1000px width = 5.0%
        XCTAssertEqual(earOffset.value, 5.0, accuracy: 0.1)
    }

    // MARK: - Test 5: View Classification
    func testViewClassification() {
        var frontLandmarks: [LandmarkType: Landmark] = [:]
        frontLandmarks[.leftShoulder] = Landmark(type: .leftShoulder, normalizedLocation: CGPoint(x: 0.2, y: 0.7), imageLocation: .zero, confidence: 0.9)
        frontLandmarks[.rightShoulder] = Landmark(type: .rightShoulder, normalizedLocation: CGPoint(x: 0.8, y: 0.7), imageLocation: .zero, confidence: 0.9)

        let frontPose = BodyPose(landmarks: frontLandmarks, imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(ViewClassifier.classify(pose: frontPose), .front)

        var sideLandmarks: [LandmarkType: Landmark] = [:]
        sideLandmarks[.leftEar] = Landmark(type: .leftEar, normalizedLocation: CGPoint(x: 0.5, y: 0.8), imageLocation: .zero, confidence: 0.9)
        sideLandmarks[.leftShoulder] = Landmark(type: .leftShoulder, normalizedLocation: CGPoint(x: 0.49, y: 0.7), imageLocation: .zero, confidence: 0.9)
        sideLandmarks[.rightShoulder] = Landmark(type: .rightShoulder, normalizedLocation: CGPoint(x: 0.51, y: 0.7), imageLocation: .zero, confidence: 0.9)

        let sidePose = BodyPose(landmarks: sideLandmarks, imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(ViewClassifier.classify(pose: sidePose), .leftSide)
    }

    // MARK: - Test 6: Baseline Comparison Engine
    func testBaselineComparisonEngine() {
        let m1 = PostureMeasurement(id: .shoulderLineAngle, name: "Shoulder Line Angle", value: 4.5, unit: "°", landmarksUsed: [.leftShoulder, .rightShoulder], confidence: 0.9, explanation: "")
        let m2 = PostureMeasurement(id: .shoulderLineAngle, name: "Shoulder Line Angle", value: 2.1, unit: "°", landmarksUsed: [.leftShoulder, .rightShoulder], confidence: 0.9, explanation: "")

        let pose = BodyPose(landmarks: [:], imageWidth: 100, imageHeight: 100)
        let baseAssessment = PostureAssessment(imageRelativePath: "", view: .front, pose: pose, measurements: [m1])
        let currAssessment = PostureAssessment(imageRelativePath: "", view: .front, pose: pose, measurements: [m2])

        let comparison = BaselineComparisonEngine.compare(current: currAssessment, baseline: baseAssessment)
        XCTAssertEqual(comparison.count, 1)
        XCTAssertEqual(comparison[0].deltaValue, -2.4, accuracy: 0.1)
    }

    // MARK: - Test 7: Realtime Selfie Front Camera Mirroring Transformation
    func testRealtimeFrontCameraSelfieMirroring() {
        let width: CGFloat = 1080
        let height: CGFloat = 1920

        // Original Vision sensor coordinate (e.g. left shoulder at norm x = 0.3)
        let rawVisionX: CGFloat = 0.3
        let rawVisionY: CGFloat = 0.75

        // For front selfie camera preview mirroring, normX is flipped: 1.0 - normX
        let mirroredNormX = 1.0 - rawVisionX
        let mirroredNormY = rawVisionY

        let mirroredNormPt = CGPoint(x: mirroredNormX, y: mirroredNormY)
        let pixelPt = CoordinateConverter.normalizedToImagePixel(normalized: mirroredNormPt, imageWidth: width, imageHeight: height)

        XCTAssertEqual(mirroredNormX, 0.7, accuracy: 0.001)
        XCTAssertEqual(pixelPt.x, 0.7 * width, accuracy: 0.1)
        XCTAssertEqual(pixelPt.y, (1.0 - 0.75) * height, accuracy: 0.1)
    }

    // MARK: - Test 8: Realtime Assessment Calculation On Selfie Feed
    func testRealtimeSelfiePostureAssessment() {
        let width: CGFloat = 1080
        let height: CGFloat = 1920

        // Create horizontal shoulder landmarks for selfie pose
        var landmarks: [LandmarkType: Landmark] = [:]
        let lsNorm = CGPoint(x: 0.3, y: 0.8)
        let rsNorm = CGPoint(x: 0.7, y: 0.8)

        let lsPixel = CoordinateConverter.normalizedToImagePixel(normalized: lsNorm, imageWidth: width, imageHeight: height)
        let rsPixel = CoordinateConverter.normalizedToImagePixel(normalized: rsNorm, imageWidth: width, imageHeight: height)

        landmarks[.leftShoulder] = Landmark(type: .leftShoulder, normalizedLocation: lsNorm, imageLocation: lsPixel, confidence: 0.95)
        landmarks[.rightShoulder] = Landmark(type: .rightShoulder, normalizedLocation: rsNorm, imageLocation: rsPixel, confidence: 0.95)

        let selfiePose = BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
        let meta = ImageMetadata(width: width, height: height)

        let assessment = analyzer.analyze(pose: selfiePose, imageMetadata: meta, view: .front)

        XCTAssertFalse(assessment.measurements.isEmpty)
        if let shoulderAngle = assessment.measurements.first(where: { $0.measurementID == .shoulderLineAngle }) {
            XCTAssertEqual(shoulderAngle.value, 0.0, accuracy: 0.1)
        } else {
            XCTFail("Shoulder Line Angle should be calculated in realtime assessment.")
        }
    }

    // MARK: - Test 9: Realtime Model Stale Result Rejection
    @MainActor
    func testRealtimeCameraModelStaleResultClearing() {
        let model = RealtimeCameraModel()
        model.setPostureView(.leftSide)
        XCTAssertNil(model.displayPose)
        XCTAssertEqual(model.state, .searchingForBody)
    }
}
