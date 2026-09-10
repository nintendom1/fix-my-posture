import XCTest
import CoreGraphics
import UIKit
@testable import PostureAnalysisApp

private final class CustomTestProvider: PostureReferenceProviding {
    let profile: PostureReferenceProfile
    init(profile: PostureReferenceProfile) { self.profile = profile }
    var currentProfile: PostureReferenceProfile { profile }
    func profile(for view: PostureView) -> PostureReferenceProfile { profile }
}

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

        // 2. Shoulder error should improve as far as fixed torso lengths allow.
        if let refLSh = staticRef.jointLocations[.leftShoulder],
           let refRSh = staticRef.jointLocations[.rightShoulder] {
            let originalDifference = abs(pose[.leftShoulder]!.imageLocation.y - pose[.rightShoulder]!.imageLocation.y)
            XCTAssertLessThan(abs(refLSh.y - refRSh.y), originalDifference)
        } else {
            XCTFail("Shoulders missing in reference pose")
        }

        // 3. Segment length preservation check across static reference and all animation steps
        let allPoses = [staticRef] + result.motionSequence
        let constrainedSegments: [(LandmarkType, LandmarkType)] = [
            (.leftShoulder, .rightShoulder), (.leftHip, .rightHip),
            (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
        ]
        for p in allPoses {
            for (first, second) in constrainedSegments {
                guard let oldA = pose[first]?.imageLocation, let oldB = pose[second]?.imageLocation,
                      let newA = p.jointLocations[first], let newB = p.jointLocations[second] else { continue }
                XCTAssertEqual(
                    hypot(newB.x - newA.x, newB.y - newA.y),
                    hypot(oldB.x - oldA.x, oldB.y - oldA.y),
                    accuracy: 0.01,
                    "Segment \(first.rawValue)-\(second.rawValue) must be preserved."
                )
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
                .front: [TargetAlignmentRule(measurementID: .shoulderLineAngle, targetValue: 20.0, tolerance: 0.1)]
            ]
        )

        let provider = CustomTestProvider(profile: secondProfile)
        let pose = createFrontPose(width: 1000, height: 2000)

        // Generator accepts custom profile without renderer changes
        let res = generator.generateReference(for: pose, view: .front, profile: provider.currentProfile)
        XCTAssertFalse(res.staticReference.jointLocations.isEmpty)
        XCTAssertTrue(res.isReplayAvailable)

        let defaultResult = generator.generateReference(for: pose, view: .front, profile: defaultProvider.currentProfile)
        XCTAssertNotEqual(
            res.staticReference.jointLocations[.leftShoulder],
            defaultResult.staticReference.jointLocations[.leftShoulder],
            "Changing the profile target must change generated geometry."
        )
    }

    // MARK: - Test 5: Image Orientation Mapping
    func testImageOrientationMapping() {
        let origPose = createFrontPose(width: 1000, height: 2000)

        // Test rotation .right (swaps dimensions)
        let mappedRight = ImageNormalizer.mapPoseToOrientation(origPose, orientation: .right)
        XCTAssertEqual(mappedRight.imageWidth, 2000)
        XCTAssertEqual(mappedRight.imageHeight, 1000)
        XCTAssertEqual(mappedRight.landmarks.count, origPose.landmarks.count)

        for (type, _) in origPose.landmarks {
            if let mappedLm = mappedRight.landmarks[type] {
                XCTAssertFalse(mappedLm.imageLocation.x.isNaN)
                XCTAssertFalse(mappedLm.imageLocation.y.isNaN)
            } else {
                XCTFail("Landmark \(type) missing after orientation mapping.")
            }
        }
    }

    func testReplayStartsAtMeasuredPose() {
        let pose = createFrontPose(width: 1000, height: 2000, shoulderTilt: 30)
        let result = generator.generateReference(for: pose, view: .front, profile: defaultProvider.currentProfile)
        XCTAssertTrue(result.isReplayAvailable)
        XCTAssertEqual(result.motionSequence.first?.jointLocations[.leftShoulder], pose[.leftShoulder]?.imageLocation)
        XCTAssertEqual(result.motionSequence.first?.jointLocations[.leftAnkle], pose[.leftAnkle]?.imageLocation)
    }

    func testRuleWithinToleranceLeavesGeometryUnchanged() {
        let pose = createFrontPose(width: 1000, height: 2000, shoulderTilt: 40)
        let profile = PostureReferenceProfile(
            id: "wide-tolerance",
            name: "Wide Tolerance",
            version: "1",
            perViewRules: [.front: [TargetAlignmentRule(measurementID: .shoulderLineAngle, targetValue: 0, tolerance: 180)]]
        )
        let result = generator.generateReference(for: pose, view: .front, profile: profile)
        XCTAssertEqual(result.staticReference.jointLocations[.leftShoulder], pose[.leftShoulder]?.imageLocation)
        XCTAssertEqual(result.staticReference.jointLocations[.rightShoulder], pose[.rightShoulder]?.imageLocation)
        XCTAssertFalse(result.isReplayAvailable)
    }

    func testPartialGuidanceWithoutAnklesStillMovesUpperBody() {
        var pose = createFrontPose(width: 1000, height: 2000, shoulderTilt: 40)
        pose[.leftAnkle] = nil
        pose[.rightAnkle] = nil
        pose[.leftKnee] = nil
        pose[.rightKnee] = nil

        let result = generator.generateReference(for: pose, view: .front, profile: defaultProvider.currentProfile)
        XCTAssertNotEqual(result.staticReference.jointLocations[.leftShoulder], pose[.leftShoulder]?.imageLocation)
        XCTAssertTrue(result.staticReference.achievedChanges.contains(where: { $0.contains("Shoulder") }))
        XCTAssertTrue(result.unavailabilityReason?.contains("Partial guidance") == true)
    }

    func testReversedEyeOrderingDoesNotFlipHead() {
        var pose = createFrontPose(width: 1000, height: 2000, shoulderTilt: 0)
        let left = CGPoint(x: 530, y: 330)
        let right = CGPoint(x: 470, y: 330)
        pose[.leftEye]?.imageLocation = left
        pose[.rightEye]?.imageLocation = right

        let result = generator.generateReference(for: pose, view: .front, profile: defaultProvider.currentProfile)
        let newLeft = result.staticReference.jointLocations[.leftEye]!
        let newRight = result.staticReference.jointLocations[.rightEye]!
        XCTAssertGreaterThan(newLeft.x, newRight.x, "Anatomical sides must retain their observed screen order.")
        XCTAssertEqual(newLeft.y, newRight.y, accuracy: 0.001)
        XCTAssertEqual(hypot(newLeft.x - newRight.x, newLeft.y - newRight.y), hypot(left.x - right.x, left.y - right.y), accuracy: 0.001)
    }

    func testSideHeadMovesRigidly() {
        var pose = createSidePose(width: 1000, height: 2000, view: .leftSide)
        let nose = CGPoint(x: 640, y: 300)
        let eye = CGPoint(x: 630, y: 285)
        pose[.nose] = makeLandmark(.nose, nose, width: 1000, height: 2000)
        pose[.leftEye] = makeLandmark(.leftEye, eye, width: 1000, height: 2000)

        let result = generator.generateReference(for: pose, view: .leftSide, profile: defaultProvider.currentProfile)
        let originalDistance = hypot(nose.x - eye.x, nose.y - eye.y)
        let newNose = result.staticReference.jointLocations[.nose]!
        let newEye = result.staticReference.jointLocations[.leftEye]!
        XCTAssertEqual(hypot(newNose.x - newEye.x, newNose.y - newEye.y), originalDistance, accuracy: 0.001)
    }

    func testBentSideKneeKeepsBothLegSegments() {
        var pose = createSidePose(width: 1000, height: 2000, view: .leftSide)
        let bentKnee = CGPoint(x: 700, y: 1400)
        pose[.leftKnee] = makeLandmark(.leftKnee, bentKnee, width: 1000, height: 2000)
        let result = generator.generateReference(for: pose, view: .leftSide, profile: defaultProvider.currentProfile)
        XCTAssertFalse(result.staticReference.jointLocations.isEmpty)

        let oldHip = pose[.leftHip]!.imageLocation
        let oldAnkle = pose[.leftAnkle]!.imageLocation
        let newHip = result.staticReference.jointLocations[.leftHip]!
        let newKnee = result.staticReference.jointLocations[.leftKnee]!
        let newAnkle = result.staticReference.jointLocations[.leftAnkle]!
        XCTAssertEqual(hypot(newKnee.x - newHip.x, newKnee.y - newHip.y), hypot(bentKnee.x - oldHip.x, bentKnee.y - oldHip.y), accuracy: 0.01)
        XCTAssertEqual(hypot(newAnkle.x - newKnee.x, newAnkle.y - newKnee.y), hypot(oldAnkle.x - bentKnee.x, oldAnkle.y - bentKnee.y), accuracy: 0.01)
    }

    func testSideProfileTargetChangesReferenceGeometry() {
        var pose = createSidePose(width: 1000, height: 2000, view: .leftSide)
        pose[.leftKnee] = makeLandmark(.leftKnee, CGPoint(x: 700, y: 1400), width: 1000, height: 2000)
        let relaxed = PostureReferenceProfile(
            id: "relaxed-knee",
            name: "Relaxed Knee",
            version: "1",
            perViewRules: [.leftSide: [TargetAlignmentRule(measurementID: .kneeJointAngle, targetValue: 150, tolerance: 0.1)]]
        )
        let extended = PostureReferenceProfile(
            id: "extended-knee",
            name: "Extended Knee",
            version: "1",
            perViewRules: [.leftSide: [TargetAlignmentRule(measurementID: .kneeJointAngle, targetValue: 175, tolerance: 0.1)]]
        )

        let relaxedResult = generator.generateReference(for: pose, view: .leftSide, profile: relaxed)
        let extendedResult = generator.generateReference(for: pose, view: .leftSide, profile: extended)
        XCTAssertNotEqual(relaxedResult.staticReference.jointLocations[.leftHip], extendedResult.staticReference.jointLocations[.leftHip])
        XCTAssertNotEqual(relaxedResult.staticReference.jointLocations[.leftKnee], extendedResult.staticReference.jointLocations[.leftKnee])
    }

    func testUncertainViewIsUnavailable() {
        let result = generator.generateReference(for: createFrontPose(width: 1000, height: 2000), view: .uncertain, profile: defaultProvider.currentProfile)
        XCTAssertFalse(result.isReplayAvailable)
        XCTAssertTrue(result.staticReference.jointLocations.isEmpty)
    }

    func testOrientationTransformsMatchUIKitCoordinates() {
        let point = CGPoint(x: 0.25, y: 0.70)
        let expected: [UIImage.Orientation: CGPoint] = [
            .up: CGPoint(x: 0.25, y: 0.70),
            .upMirrored: CGPoint(x: 0.75, y: 0.70),
            .down: CGPoint(x: 0.75, y: 0.30),
            .downMirrored: CGPoint(x: 0.25, y: 0.30),
            .left: CGPoint(x: 0.30, y: 0.25),
            .leftMirrored: CGPoint(x: 0.30, y: 0.75),
            .right: CGPoint(x: 0.70, y: 0.75),
            .rightMirrored: CGPoint(x: 0.70, y: 0.25)
        ]
        for (orientation, expectedPoint) in expected {
            let mapped = ImageNormalizer.mapNormalizedToOrientation(point, orientation: orientation)
            XCTAssertEqual(mapped.x, expectedPoint.x, accuracy: 0.001)
            XCTAssertEqual(mapped.y, expectedPoint.y, accuracy: 0.001)
        }
    }

    func testUprightNormalizationPreservesPixelCount() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let base = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { _ in }
        let rotated = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .right)
        let normalized = ImageNormalizer.normalizeToUpright(rotated)
        XCTAssertEqual(normalized.imageOrientation, .up)
        XCTAssertEqual(normalized.cgImage!.width * normalized.cgImage!.height, base.cgImage!.width * base.cgImage!.height)
        XCTAssertEqual(normalized.cgImage!.width, base.cgImage!.height)
        XCTAssertEqual(normalized.cgImage!.height, base.cgImage!.width)
    }

    private func makeLandmark(_ type: LandmarkType, _ point: CGPoint, width: CGFloat, height: CGFloat) -> Landmark {
        Landmark(
            type: type,
            normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: point, imageWidth: width, imageHeight: height),
            imageLocation: point,
            confidence: 0.95
        )
    }
}
