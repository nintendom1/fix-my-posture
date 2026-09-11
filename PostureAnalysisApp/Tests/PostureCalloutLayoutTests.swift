import XCTest
import SwiftUI
@testable import PostureAnalysisApp

final class PostureCalloutLayoutTests: XCTestCase {
    private let profile = DefaultPostureReferenceProvider().currentProfile

    func testSelectsHighestPriorityMeasurementPerRegion() throws {
        let pose = samplePose()
        let measurements = [
            measurement(.shoulderLineAngle, value: 0.6, landmarks: [.leftShoulder, .rightShoulder]),
            measurement(.shoulderHeightAsymmetry, value: 8, landmarks: [.leftShoulder, .rightShoulder]),
            measurement(.hipLineAngle, value: 3, landmarks: [.leftHip, .rightHip])
        ]
        let items = PostureCalloutLayout.items(
            measurements: measurements, pose: pose, containerSize: CGSize(width: 390, height: 844),
            view: .front, profile: profile)

        XCTAssertEqual(items.filter { $0.region == .shoulders }.count, 1)
        XCTAssertEqual(try XCTUnwrap(items.first { $0.region == .shoulders }).measurement.measurementID,
                       .shoulderLineAngle, "A referenced measurement wins over an unsupported metric in the same region.")
        XCTAssertEqual(items.first?.region, .hips)
    }

    func testPlacementsStayInBoundsAndAvoidEachOtherAndControls() {
        let pose = samplePose()
        let size = CGSize(width: 390, height: 844)
        let items = PostureCalloutLayout.items(
            measurements: [
                measurement(.headTiltAngle, value: 4, landmarks: [.leftEye, .rightEye]),
                measurement(.shoulderLineAngle, value: 4, landmarks: [.leftShoulder, .rightShoulder]),
                measurement(.hipLineAngle, value: 4, landmarks: [.leftHip, .rightHip]),
                measurement(.kneeAnkleStanceRatio, value: 1.2, unit: "ratio", landmarks: [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle])
            ], pose: pose, containerSize: size, view: .front, profile: profile)
        let controls = [CGRect(x: 0, y: 760, width: 390, height: 84)]
        let placements = PostureCalloutLayout.placements(
            items: items, pose: pose, containerSize: size, reservedRects: controls)
        let safe = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)

        XCTAssertGreaterThanOrEqual(placements.count, 2)
        for placement in placements {
            XCTAssertTrue(safe.contains(placement.frame))
            XCTAssertFalse(controls[0].intersects(placement.frame))
        }
        for first in placements.indices {
            for second in placements.indices where first < second {
                XCTAssertFalse(placements[first].frame.insetBy(dx: -8, dy: -8).intersects(placements[second].frame))
            }
        }
    }

    func testImpossibleLayoutHidesCallout() {
        let pose = samplePose()
        let size = CGSize(width: 160, height: 180)
        let items = PostureCalloutLayout.items(
            measurements: [measurement(.headTiltAngle, value: 4, landmarks: [.leftEye, .rightEye])],
            pose: pose, containerSize: size, view: .front, profile: profile)
        let placements = PostureCalloutLayout.placements(
            items: items, pose: pose, containerSize: size,
            reservedRects: [CGRect(origin: .zero, size: size)])
        XCTAssertTrue(placements.isEmpty)
    }

    func testMirroredPoseMovesHeadAnchorAcrossPreview() throws {
        let size = CGSize(width: 390, height: 844)
        var pose = samplePose()
        pose[.leftEye]?.normalizedLocation.x = 0.35
        pose[.rightEye]?.normalizedLocation.x = 0.45
        let measurement = measurement(.headTiltAngle, value: 4, landmarks: [.leftEye, .rightEye])
        let original = try XCTUnwrap(PostureCalloutLayout.items(
            measurements: [measurement], pose: pose, containerSize: size, view: .front, profile: profile).first)
        let mirroredPose = RealtimePoseProcessing.displayPose(pose, mirrored: true)
        let mirrored = try XCTUnwrap(PostureCalloutLayout.items(
            measurements: [measurement], pose: mirroredPose, containerSize: size, view: .front, profile: profile).first)
        XCTAssertEqual(original.anchor.x + mirrored.anchor.x, size.width, accuracy: 0.01)
    }

    func testContinuousSegmentsTargetsAndVariableHeightStayProtected() {
        var pose = samplePose()
        pose[.leftShoulder]?.normalizedLocation.x = 0.2
        pose[.rightHip]?.normalizedLocation.x = 0.8
        let size = CGSize(width: 393, height: 852)
        let measurements = [measurement(.headTiltAngle, value: 4, landmarks: [.leftEye, .rightEye]),
                            measurement(.hipLineAngle, value: 4, landmarks: [.leftHip, .rightHip])]
        let items = PostureCalloutLayout.items(measurements: measurements, pose: pose, containerSize: size, view: .front, profile: profile)
        let target = CGRect(x: 20, y: 80, width: 26, height: 26)
        let placements = PostureCalloutLayout.placements(items: items, pose: pose, containerSize: size,
            targetRects: [target], contentHeight: { _, width in width < 100 ? 150 : 110 })
        for placement in placements {
            XCTAssertFalse(target.insetBy(dx: -8, dy: -8).intersects(placement.frame))
            XCTAssertGreaterThanOrEqual(placement.frame.height, 110)
            for (a, b) in BodyPose.connections {
                guard let a = pose[a], let b = pose[b] else { continue }
                for index in 0...100 {
                    let fraction = CGFloat(index) / 100
                    let point = CGPoint(x: a.normalizedLocation.x + (b.normalizedLocation.x - a.normalizedLocation.x) * fraction,
                                        y: a.normalizedLocation.y + (b.normalizedLocation.y - a.normalizedLocation.y) * fraction)
                    let screen = CoordinateConverter.normalizedToContainer(normalized: point,
                        imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight), containerSize: size)
                    XCTAssertFalse(placement.frame.insetBy(dx: -8, dy: -8).contains(screen))
                }
            }
        }
        let repeated = PostureCalloutLayout.placements(items: items, pose: pose, containerSize: size,
            targetRects: [target], previous: placements, contentHeight: { _, width in width < 100 ? 150 : 110 })
        XCTAssertEqual(placements, repeated)
        XCTAssertTrue(PostureCalloutLayout.placements(items: items, pose: pose, containerSize: size,
            reservedRects: [CGRect(origin: .zero, size: size)], previous: placements).isEmpty)
    }

    @MainActor
    func testRenderIPhone15ProFixtures() async throws {
        let pose = samplePose()
        let measurements = PostureAnalyzer().analyze(pose: pose,
            imageMetadata: ImageMetadata(width: pose.imageWidth, height: pose.imageHeight), view: .front).measurements
        let target = ReferencePoseGenerator().generateStaticReference(for: pose, view: .front, profile: profile).staticReference
        let size = CGSize(width: 393, height: 852)
        for (name, typeSize, blocked) in [("standard", DynamicTypeSize.large, false),
                                          ("accessibility", .accessibility3, false), ("narrow", .large, false), ("hidden", .large, true)] {
            let fixtureMeasurements = name == "narrow" ? [measurement(.earShoulderHorizontalOffset, value: 3.2, unit: "% frame width",
                landmarks: [.neck, .leftShoulder])] : measurements
            let fixtureView: PostureView = name == "narrow" ? .leftSide : .front
            let content = ZStack {
                Color.black
                LandmarkOverlayView(pose: pose, containerSize: size, distanceEmphasis: true,
                    feedback: MeasurementPresentation.jointFeedback(measurements: measurements, pose: pose, view: .front, profile: profile))
                AlignmentTargetOverlayView(reference: target, imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight))
                PostureCalloutOverlayView(measurements: fixtureMeasurements, pose: pose, view: fixtureView, profile: profile,
                    targetRects: AlignmentTargetOverlayView.rects(reference: target, imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight), containerSize: size),
                    reservedRects: blocked ? [CGRect(origin: .zero, size: size)] : name == "narrow" ? [CGRect(x: 0, y: 0, width: 25, height: 852), CGRect(x: 255, y: 0, width: 138, height: 852)] : [])
            }.frame(width: size.width, height: size.height).environment(\.dynamicTypeSize, typeSize)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "iPhone15Pro-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("posture-" + name + ".png")
            try image.pngData()?.write(to: url)
            print("POSTURE_FIXTURE " + url.path)
            window.isHidden = true
        }
    }

    private func samplePose() -> BodyPose {
        let points: [LandmarkType: CGPoint] = [
            .leftEye: CGPoint(x: 0.46, y: 0.88), .rightEye: CGPoint(x: 0.54, y: 0.88),
            .nose: CGPoint(x: 0.5, y: 0.85), .neck: CGPoint(x: 0.5, y: 0.76),
            .leftShoulder: CGPoint(x: 0.38, y: 0.72), .rightShoulder: CGPoint(x: 0.62, y: 0.72),
            .leftHip: CGPoint(x: 0.43, y: 0.5), .rightHip: CGPoint(x: 0.57, y: 0.5),
            .leftKnee: CGPoint(x: 0.44, y: 0.3), .rightKnee: CGPoint(x: 0.56, y: 0.3),
            .leftAnkle: CGPoint(x: 0.43, y: 0.08), .rightAnkle: CGPoint(x: 0.57, y: 0.08)
        ]
        let width: CGFloat = 390
        let height: CGFloat = 844
        let landmarks = Dictionary(uniqueKeysWithValues: points.map { type, point in
            (type, Landmark(type: type, normalizedLocation: point,
                            imageLocation: CoordinateConverter.normalizedToImagePixel(
                                normalized: point, imageWidth: width, imageHeight: height), confidence: 0.95))
        })
        return BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
    }

    private func measurement(
        _ id: MeasurementID,
        value: Double,
        unit: String = "°",
        landmarks: [LandmarkType]
    ) -> PostureMeasurement {
        PostureMeasurement(id: id, name: id.defaultDisplayName, value: value, unit: unit,
                           landmarksUsed: landmarks, confidence: 0.95, explanation: "")
    }
}
