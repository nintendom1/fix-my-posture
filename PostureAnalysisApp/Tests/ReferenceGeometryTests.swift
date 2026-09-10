import XCTest
import CoreGraphics
@testable import PostureAnalysisApp

final class ReferenceGeometryTests: XCTestCase {

    private var generator: ReferencePoseGenerator!
    private var defaultProvider: DefaultPostureReferenceProvider!

    override func setUp() {
        super.setUp()
        generator = ReferencePoseGenerator()
        defaultProvider = DefaultPostureReferenceProvider()
    }

    override func tearDown() {
        generator = nil
        defaultProvider = nil
        super.tearDown()
    }

    // MARK: - Helper Fixtures

    private func createFrontPose(width: CGFloat, height: CGFloat, shoulderTilt: CGFloat = 40.0) -> BodyPose {
        var landmarks: [LandmarkType: Landmark] = [:]

        // Ankle midpoint x = 500
        let lAnklePx = CGPoint(x: 400, y: 1800)
        let rAnklePx = CGPoint(x: 600, y: 1800)

        let lKneePx = CGPoint(x: 390, y: 1400)
        let rKneePx = CGPoint(x: 610, y: 1400)

        let lHipPx = CGPoint(x: 420, y: 1000)
        let rHipPx = CGPoint(x: 580, y: 1000)

        let lShPx = CGPoint(x: 350, y: 500 - shoulderTilt)
        let rShPx = CGPoint(x: 650, y: 500 + shoulderTilt)

        let neckPx = CGPoint(x: 500, y: 480)
        let nosePx = CGPoint(x: 500, y: 350)
        let lEyePx = CGPoint(x: 470, y: 330)
        let rEyePx = CGPoint(x: 530, y: 330)

        let keys: [(LandmarkType, CGPoint)] = [
            (.leftAnkle, lAnklePx), (.rightAnkle, rAnklePx),
            (.leftKnee, lKneePx), (.rightKnee, rKneePx),
            (.leftHip, lHipPx), (.rightHip, rHipPx),
            (.leftShoulder, lShPx), (.rightShoulder, rShPx),
            (.neck, neckPx), (.nose, nosePx),
            (.leftEye, lEyePx), (.rightEye, rEyePx)
        ]

        for (type, pixel) in keys {
            let norm = CoordinateConverter.imagePixelToNormalized(pixel: pixel, imageWidth: width, imageHeight: height)
            landmarks[type] = Landmark(type: type, normalizedLocation: norm, imageLocation: pixel, confidence: 0.95)
        }

        return BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
    }

    private func createSidePose(width: CGFloat, height: CGFloat, view: PostureView) -> BodyPose {
        var landmarks: [LandmarkType: Landmark] = [:]

        let ankleKey: LandmarkType = (view == .leftSide) ? .leftAnkle : .rightAnkle
        let kneeKey: LandmarkType = (view == .leftSide) ? .leftKnee : .rightKnee
        let hipKey: LandmarkType = (view == .leftSide) ? .leftHip : .rightHip
        let shoulderKey: LandmarkType = (view == .leftSide) ? .leftShoulder : .rightShoulder
        let earKey: LandmarkType = (view == .leftSide) ? .leftEar : .rightEar

        // Forward lean setup: ankle at 500, hip/shoulder leaning forward to 550/580
        let anklePx = CGPoint(x: 500, y: 1800)
        let kneePx = CGPoint(x: 520, y: 1400)
        let hipPx = CGPoint(x: 550, y: 1000)
        let shoulderPx = CGPoint(x: 580, y: 500)
        let earPx = CGPoint(x: 610, y: 300)

        let keys: [(LandmarkType, CGPoint)] = [
            (ankleKey, anklePx), (kneeKey, kneePx), (hipKey, hipPx),
            (shoulderKey, shoulderPx), (earKey, earPx)
        ]

        for (type, pixel) in keys {
            let norm = CoordinateConverter.imagePixelToNormalized(pixel: pixel, imageWidth: width, imageHeight: height)
            landmarks[type] = Landmark(type: type, normalizedLocation: norm, imageLocation: pixel, confidence: 0.95)
        }

        return BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
    }

    // MARK: - Test 1: Planted Ankles & Segment Length Preservation (Front View)
    func testFrontViewPlantedAnklesAndSegmentLengths() {
        let pose = createFrontPose(width: 1000, height: 2000, shoulderTilt: 30.0)
        let profile = defaultProvider.currentProfile

        let result = generator.generateReference(for: pose, view: .front, profile: profile)
        XCTAssertTrue(result.isReplayAvailable)

        let staticRef = result.staticReference

        // 1. Planted Ankles check
        guard let origLAnkle = pose[.leftAnkle]?.imageLocation,
              let origRAnkle = pose[.rightAnkle]?.imageLocation,
              let refLAnkle = staticRef.jointLocations[.leftAnkle],
              let refRAnkle = staticRef.jointLocations[.rightAnkle] else {
            XCTFail("Ankles missing in reference pose")
            return
        }

        XCTAssertEqual(refLAnkle.x, origLAnkle.x, accuracy: 0.1)
        XCTAssertEqual(refLAnkle.y, origLAnkle.y, accuracy: 0.1)
        XCTAssertEqual(refRAnkle.x, origRAnkle.x, accuracy: 0.1)
        XCTAssertEqual(refRAnkle.y, origRAnkle.y, accuracy: 0.1)

        // 2. Level Shoulders check
        if let refLSh = staticRef.jointLocations[.leftShoulder],
           let refRSh = staticRef.jointLocations[.rightShoulder] {
            XCTAssertEqual(refLSh.y, refRSh.y, accuracy: 0.5, "Reference shoulders must be leveled.")
        } else {
            XCTFail("Shoulders missing in reference pose")
        }

        // 3. Segment length preservation check across static reference and all animation steps
        let allPoses = [staticRef] + result.motionSequence
        for p in allPoses {
            if let origLHip = pose[.leftHip]?.imageLocation, let origRHip = pose[.rightHip]?.imageLocation,
               let refLHip = p.jointLocations[.leftHip], let refRHip = p.jointLocations[.rightHip] {
                let origHipWidth = hypot(origRHip.x - origLHip.x, origRHip.y - origLHip.y)
                let refHipWidth = hypot(refRHip.x - refLHip.x, refRHip.y - refLHip.y)
                XCTAssertEqual(refHipWidth, origHipWidth, accuracy: origHipWidth * 0.05, "Hip width must be preserved.")
            }
        }
    }

    // MARK: - Test 2: Side View Chain Alignment & Planted Ankle
    func testSideViewChainAlignment() {
        let pose = createSidePose(width: 1000, height: 2000, view: .leftSide)
        let profile = defaultProvider.currentProfile

        let result = generator.generateReference(for: pose, view: .leftSide, profile: profile)
        XCTAssertTrue(result.isReplayAvailable)

        let staticRef = result.staticReference

        guard let origAnkle = pose[.leftAnkle]?.imageLocation,
              let refAnkle = staticRef.jointLocations[.leftAnkle] else {
            XCTFail("Left ankle missing in side view")
            return
        }

        // Planted Ankle check
        XCTAssertEqual(refAnkle.x, origAnkle.x, accuracy: 0.1)
        XCTAssertEqual(refAnkle.y, origAnkle.y, accuracy: 0.1)

        // Vertical stack check: hip and shoulder x pushed toward ankle x
        if let refHip = staticRef.jointLocations[.leftHip],
           let refSh = staticRef.jointLocations[.leftShoulder] {
            XCTAssertEqual(refHip.x, origAnkle.x, accuracy: 2.0, "Side view hip x should align over visible ankle.")
            XCTAssertEqual(refSh.x, origAnkle.x, accuracy: 2.0, "Side view shoulder x should align over visible ankle.")
        }
    }

    // MARK: - Test 3: Determinism & Finite Coordinates across Aspect Ratios
    func testDeterminismAndFiniteCoordinates() {
        let aspectRatios: [(CGFloat, CGFloat)] = [(1000, 1000), (1000, 2000), (2000, 1000)]

        for (w, h) in aspectRatios {
            let pose = createFrontPose(width: w, height: h)
            let profile = defaultProvider.currentProfile

            let res1 = generator.generateReference(for: pose, view: .front, profile: profile)
            let res2 = generator.generateReference(for: pose, view: .front, profile: profile)

            XCTAssertEqual(res1.staticReference.jointLocations.count, res2.staticReference.jointLocations.count)

            for (type, pt1) in res1.staticReference.jointLocations {
                XCTAssertFalse(pt1.x.isNaN || pt1.x.isInfinite, "Coordinate must be finite.")
                XCTAssertFalse(pt1.y.isNaN || pt1.y.isInfinite, "Coordinate must be finite.")

                if let pt2 = res2.staticReference.jointLocations[type] {
                    XCTAssertEqual(pt1.x, pt2.x, accuracy: 0.001, "Results must be deterministic.")
                    XCTAssertEqual(pt1.y, pt2.y, accuracy: 0.001, "Results must be deterministic.")
                }
            }
        }
    }

    // MARK: - Test 4: Secondary Profile Injection
    func testSecondaryProfileInjection() {
        let secondProfile = PostureReferenceProfile(
            id: "custom-v2",
            name: "Strict Custom Reference",
            version: "2.0",
            perViewRules: [
                .front: [TargetAlignmentRule(measurementID: .shoulderLineAngle, targetValue: 0.0, tolerance: 0.1)]
            ]
        )

        final class CustomProvider: PostureReferenceProviding {
            let profile: PostureReferenceProfile
            init(profile: PostureReferenceProfile) { self.profile = profile }
            var currentProfile: PostureReferenceProfile { profile }
            func profile(for view: PostureView) -> PostureReferenceProfile { profile }
        }

        let provider = CustomProvider(profile: secondProfile)
        let pose = createFrontPose(width: 1000, height: 2000)

        // Generator accepts custom profile without renderer changes
        let res = generator.generateReference(for: pose, view: .front, profile: provider.currentProfile)
        XCTAssertFalse(res.staticReference.jointLocations.isEmpty)
        XCTAssertTrue(res.isReplayAvailable)
    }

    // MARK: - Test 5: Image Orientation Mapping
    func testImageOrientationMapping() {
        let origPose = createFrontPose(width: 1000, height: 2000)

        // Test rotation .right (swaps dimensions)
        let mappedRight = ImageNormalizer.mapPoseToOrientation(origPose, orientation: .right)
        XCTAssertEqual(mappedRight.imageWidth, 2000)
        XCTAssertEqual(mappedRight.imageHeight, 1000)
        XCTAssertEqual(mappedRight.landmarks.count, origPose.landmarks.count)

        for (type, origLm) in origPose.landmarks {
            if let mappedLm = mappedRight.landmarks[type] {
                XCTAssertFalse(mappedLm.imageLocation.x.isNaN)
                XCTAssertFalse(mappedLm.imageLocation.y.isNaN)
            } else {
                XCTFail("Landmark \(type) missing after orientation mapping.")
            }
        }
    }
}
