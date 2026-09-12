import XCTest
import CoreGraphics
import CoreMotion
import SwiftUI
@testable import PostureAnalysisApp

final class HorizonTests: XCTestCase {

    private var analyzer: PostureAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = PostureAnalyzer()
    }

    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }

    // MARK: - Geometry & Pose Leveling Tests

    func testRotatePointAndRoundTrip() {
        let width: CGFloat = 1000
        let height: CGFloat = 2000
        let pt = CGPoint(x: 300, y: 400)
        let angle: Double = 15.0

        let rotated = HorizonGeometry.rotatePoint(pt, imageWidth: width, imageHeight: height, angleDegrees: angle)
        let restored = HorizonGeometry.rotatePoint(rotated, imageWidth: width, imageHeight: height, angleDegrees: -angle)

        XCTAssertEqual(restored.x, pt.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, pt.y, accuracy: 0.001)
    }

    func testSyntheticPoseRotationAndLeveling() {
        let width: CGFloat = 1000
        let height: CGFloat = 2000
        let rollAngle: Double = 10.0 // Rolled +10 degrees

        // Level horizontal shoulders: ls=(300, 500), rs=(700, 500)
        let levelLs = CGPoint(x: 300, y: 500)
        let levelRs = CGPoint(x: 700, y: 500)
        let levelHip = CGPoint(x: 500, y: 1100)
        let levelKnee = CGPoint(x: 500, y: 1500)
        let levelAnkle = CGPoint(x: 500, y: 1900)

        // Rotate level points by +10 degrees to simulate camera roll tilt
        let rolledLs = HorizonGeometry.rotatePoint(levelLs, imageWidth: width, imageHeight: height, angleDegrees: rollAngle)
        let rolledRs = HorizonGeometry.rotatePoint(levelRs, imageWidth: width, imageHeight: height, angleDegrees: rollAngle)
        let rolledHip = HorizonGeometry.rotatePoint(levelHip, imageWidth: width, imageHeight: height, angleDegrees: rollAngle)
        let rolledKnee = HorizonGeometry.rotatePoint(levelKnee, imageWidth: width, imageHeight: height, angleDegrees: rollAngle)
        let rolledAnkle = HorizonGeometry.rotatePoint(levelAnkle, imageWidth: width, imageHeight: height, angleDegrees: rollAngle)

        var landmarks: [LandmarkType: Landmark] = [:]
        landmarks[.leftShoulder] = Landmark(type: .leftShoulder, normalizedLocation: .zero, imageLocation: rolledLs, confidence: 0.95)
        landmarks[.rightShoulder] = Landmark(type: .rightShoulder, normalizedLocation: .zero, imageLocation: rolledRs, confidence: 0.95)
        landmarks[.leftHip] = Landmark(type: .leftHip, normalizedLocation: .zero, imageLocation: rolledHip, confidence: 0.95)
        landmarks[.leftKnee] = Landmark(type: .leftKnee, normalizedLocation: .zero, imageLocation: rolledKnee, confidence: 0.95)
        landmarks[.leftAnkle] = Landmark(type: .leftAnkle, normalizedLocation: .zero, imageLocation: rolledAnkle, confidence: 0.95)

        let pose = BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
        let meta = ImageMetadata(width: width, height: height)

        // 1. Analyze uncompensated
        let uncompAssessment = analyzer.analyze(pose: pose, imageMetadata: meta, view: .front)
        let uncompShoulder = uncompAssessment.measurements.first(where: { $0.measurementID == .shoulderLineAngle })
        XCTAssertNotNil(uncompShoulder)
        XCTAssertEqual(uncompShoulder!.value, 10.0, accuracy: 0.5, "Uncompensated analysis must retain the 10 degree roll tilt.")

        // 2. Analyze compensated with HorizonContext(angleDegrees: 10.0)
        let ctx = HorizonContext(angleDegrees: rollAngle, source: .deviceMotion, isCompensationApplied: true)
        let compAssessment = analyzer.analyze(pose: pose, imageMetadata: meta, view: .front, horizonContext: ctx)
        let compShoulder = compAssessment.measurements.first(where: { $0.measurementID == .shoulderLineAngle })
        XCTAssertNotNil(compShoulder)
        XCTAssertEqual(compShoulder!.value, 0.0, accuracy: 0.5, "Compensated analysis must level the shoulders to near 0 degrees.")

        // 3. Knee joint angle invariance
        let sidePose = BodyPose(landmarks: [
            .leftHip: Landmark(type: .leftHip, normalizedLocation: .zero, imageLocation: rolledHip, confidence: 0.95),
            .leftKnee: Landmark(type: .leftKnee, normalizedLocation: .zero, imageLocation: rolledKnee, confidence: 0.95),
            .leftAnkle: Landmark(type: .leftAnkle, normalizedLocation: .zero, imageLocation: rolledAnkle, confidence: 0.95)
        ], imageWidth: width, imageHeight: height)

        let uncompSide = analyzer.analyze(pose: sidePose, imageMetadata: meta, view: .leftSide)
        let compSide = analyzer.analyze(pose: sidePose, imageMetadata: meta, view: .leftSide, horizonContext: ctx)

        let uncompKnee = uncompSide.measurements.first(where: { $0.measurementID == .kneeJointAngle })?.value ?? 0
        let compKnee = compSide.measurements.first(where: { $0.measurementID == .kneeJointAngle })?.value ?? 0
        XCTAssertEqual(uncompKnee, compKnee, accuracy: 0.001, "Interior joint angles must remain mathematically identical before and after leveling.")
    }

    func testReferenceTargetInverseTransform() {
        let width: CGFloat = 1000
        let height: CGFloat = 2000
        let rollAngle: Double = 12.0

        var landmarks: [LandmarkType: Landmark] = [:]
        landmarks[.leftShoulder] = Landmark(type: .leftShoulder, normalizedLocation: .zero, imageLocation: CGPoint(x: 300, y: 500), confidence: 0.9)
        landmarks[.rightShoulder] = Landmark(type: .rightShoulder, normalizedLocation: .zero, imageLocation: CGPoint(x: 700, y: 500), confidence: 0.9)
        landmarks[.leftHip] = Landmark(type: .leftHip, normalizedLocation: .zero, imageLocation: CGPoint(x: 350, y: 1100), confidence: 0.9)
        landmarks[.rightHip] = Landmark(type: .rightHip, normalizedLocation: .zero, imageLocation: CGPoint(x: 650, y: 1100), confidence: 0.9)

        let pose = BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
        let profile = DefaultPostureReferenceProvider().profile(for: .front)
        let generator = ReferencePoseGenerator()

        let ctx = HorizonContext(angleDegrees: rollAngle, source: .deviceMotion, isCompensationApplied: true)
        let result = generator.generateStaticReference(for: pose, view: .front, profile: profile, horizonContext: ctx)

        XCTAssertFalse(result.staticReference.jointLocations.isEmpty)
    }

    // MARK: - Horizon Monitor & Sensor Filter Tests

    func testUprightGravityZeroRoll() {
        let monitor = CoreMotionHorizonMonitor()

        // Upright portrait gravity: Gx = 0, Gy = -1.0, Gz = 0
        let upright = CMAcceleration(x: 0, y: -1.0, z: 0)
        let now = ProcessInfo.processInfo.systemUptime

        monitor.processMotion(upright, isFrontCamera: false, timestamp: now)
        let reading = monitor.latestReading

        XCTAssertNotNil(reading)
        XCTAssertEqual(reading!.angleDegrees, 0.0, accuracy: 0.1)
        XCTAssertEqual(reading!.gravityMagnitude, 1.0, accuracy: 0.01)
    }

    func testFrontVsRearCameraSign() {
        let monitor = CoreMotionHorizonMonitor()
        let now = ProcessInfo.processInfo.systemUptime

        // Phone top tilted left by 10 degrees: Gx = -sin(10°), Gy = -cos(10°)
        let rad = 10.0 * .pi / 180.0
        let gravity = CMAcceleration(x: -sin(rad), y: -cos(rad), z: 0)

        // Rear camera -> Positive roll
        monitor.processMotion(gravity, isFrontCamera: false, timestamp: now)
        let rearReading = monitor.latestReading
        XCTAssertNotNil(rearReading)
        XCTAssertGreaterThan(rearReading!.angleDegrees, 0)

        // Front camera -> Inverted roll
        monitor.processMotion(gravity, isFrontCamera: true, timestamp: now)
        let frontReading = monitor.latestReading
        XCTAssertNotNil(frontReading)
        XCTAssertLessThan(frontReading!.angleDegrees, 0)
    }

    func testStaleReadingFilter() {
        let monitor = CoreMotionHorizonMonitor()
        let oldTimestamp = ProcessInfo.processInfo.systemUptime - 0.50 // 0.5s old > 0.25s limit

        let gravity = CMAcceleration(x: 0, y: -1.0, z: 0)
        monitor.processMotion(gravity, isFrontCamera: false, timestamp: oldTimestamp)

        XCTAssertNil(monitor.latestReading, "Readings older than 0.25 seconds must be rejected as stale.")
    }

    func testLowGravityFilter() {
        let monitor = CoreMotionHorizonMonitor()
        let now = ProcessInfo.processInfo.systemUptime

        // Phone lying nearly flat on table: Gy = -0.3, Gz = -0.95 -> projected XY magnitude = 0.3 < 0.75
        let flatGravity = CMAcceleration(x: 0, y: -0.3, z: -0.95)
        monitor.processMotion(flatGravity, isFrontCamera: false, timestamp: now)

        XCTAssertNil(monitor.latestReading, "Projected gravity magnitude below 0.75 must be rejected.")
    }

    func testLargeRollFilter() {
        let monitor = CoreMotionHorizonMonitor()
        let now = ProcessInfo.processInfo.systemUptime

        // 50 degree roll (> 45 degree limit)
        let rad = 50.0 * .pi / 180.0
        let extremeGravity = CMAcceleration(x: -sin(rad), y: -cos(rad), z: 0)
        monitor.processMotion(extremeGravity, isFrontCamera: false, timestamp: now)

        XCTAssertNil(monitor.latestReading, "Absolute roll angles beyond 45 degrees must be rejected.")
    }

    func testLowPassSmoothing() {
        let monitor = CoreMotionHorizonMonitor()
        let now = ProcessInfo.processInfo.systemUptime

        let g1 = CMAcceleration(x: 0, y: -1.0, z: 0)
        monitor.processMotion(g1, isFrontCamera: false, timestamp: now)

        let g2 = CMAcceleration(x: -0.2, y: -0.98, z: 0)
        monitor.processMotion(g2, isFrontCamera: false, timestamp: now + 0.03)

        let reading = monitor.latestReading
        XCTAssertNotNil(reading)
        // Smooth factor 0.2: 0.2 * (-0.2) + 0.8 * (0) = -0.04
        // atan2(0.04, 0.984) ~ 2.33 degrees (smoothed, less than raw ~11.5)
        XCTAssertLessThan(abs(reading!.angleDegrees), 5.0)
    }

    // MARK: - Persistence & Context Tests

    func testPersistenceWithHorizonContext() {
        let ctx = HorizonContext(angleDegrees: 3.5, source: .deviceMotion, isCompensationApplied: true)
        let pose = BodyPose(landmarks: [:], imageWidth: 1000, imageHeight: 2000)

        let assessment = PostureAssessment(
            imageRelativePath: "test.jpg",
            view: .front,
            pose: pose,
            measurements: [],
            horizonContext: ctx
        )

        let entity = AssessmentEntity(
            id: assessment.id,
            date: assessment.date,
            imageRelativePath: assessment.imageRelativePath,
            viewRawValue: assessment.view.rawValue,
            horizonAngle: assessment.horizonContext?.angleDegrees,
            horizonSourceRawValue: assessment.horizonContext?.source.rawValue,
            isHorizonCompensationApplied: assessment.horizonContext?.isCompensationApplied
        )

        XCTAssertEqual(entity.horizonAngle, 3.5)
        XCTAssertEqual(entity.horizonSourceRawValue, "deviceMotion")
        XCTAssertEqual(entity.isHorizonCompensationApplied, true)
    }
}
