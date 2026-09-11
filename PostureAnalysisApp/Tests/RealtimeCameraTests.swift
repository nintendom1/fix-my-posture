import XCTest
import AVFoundation
@testable import PostureAnalysisApp

final class RealtimeCameraTests: XCTestCase {
    @MainActor
    func testPermissionCompletionAfterDismissalDoesNotStartCamera() {
        let camera = FakeCaptureService()
        let permission = FakeCameraPermission(status: .notDetermined)
        let model = RealtimeCameraModel(camera: camera, permission: permission)
        model.onAppear()
        XCTAssertNotNil(permission.completion)
        model.onDisappear()
        permission.complete(granted: true)
        XCTAssertTrue(camera.starts.isEmpty)
        XCTAssertNil(model.displayPose)
    }

    @MainActor
    func testDeniedPermissionRecoversAfterReturningFromSettings() {
        let camera = FakeCaptureService()
        let permission = FakeCameraPermission(status: .denied)
        let model = RealtimeCameraModel(camera: camera, permission: permission)
        model.onAppear()
        XCTAssertEqual(model.state, .notAuthorized)
        XCTAssertTrue(camera.starts.isEmpty)
        model.setApplicationActive(false)
        permission.status = .authorized
        model.setApplicationActive(true)
        XCTAssertEqual(camera.starts.count, 1)
        XCTAssertEqual(model.state, .starting)
    }

    @MainActor
    func testPermissionGrantWhileInactiveWaitsForForeground() {
        let camera = FakeCaptureService()
        let permission = FakeCameraPermission(status: .notDetermined)
        let model = RealtimeCameraModel(camera: camera, permission: permission)
        model.onAppear()
        model.setApplicationActive(false)
        permission.complete(granted: true)
        XCTAssertTrue(camera.starts.isEmpty)
        model.setApplicationActive(true)
        XCTAssertEqual(camera.starts.count, 1)
    }

    @MainActor
    func testOldFramesRejectedAfterViewChangeCameraSwitchAndDismissal() {
        let camera = FakeCaptureService()
        let model = RealtimeCameraModel(camera: camera, permission: FakeCameraPermission(status: .authorized))
        model.onAppear()
        let tracking = trackingState()
        camera.emit(tracking, start: 0)
        XCTAssertNotNil(model.displayPose)

        model.setPostureView(.leftSide)
        XCTAssertEqual(camera.starts.last?.view, .leftSide)
        camera.emit(tracking, start: 0)
        XCTAssertEqual(model.state, .starting)
        XCTAssertNil(model.displayPose)

        camera.emit(tracking, start: 1)
        XCTAssertNotNil(model.displayPose)
        model.switchCamera()
        XCTAssertEqual(camera.starts.last?.position, .back)
        camera.emit(tracking, start: 1)
        XCTAssertEqual(model.state, .starting)

        camera.emit(tracking, start: 2)
        model.onDisappear()
        camera.emit(tracking, start: 2)
        XCTAssertNil(model.displayPose)
        XCTAssertEqual(model.state, .interrupted)
        model.setApplicationActive(false)
        model.setApplicationActive(true)
        XCTAssertEqual(camera.starts.count, 3, "An offscreen view must not restart on foregrounding.")
    }

    @MainActor
    func testTrackingLossInterruptionAndFailureClearOverlay() {
        let camera = FakeCaptureService()
        let model = RealtimeCameraModel(camera: camera, permission: FakeCameraPermission(status: .authorized))
        model.onAppear()
        for state: RealtimeCameraState in [.searchingForBody, .interrupted, .failed("Camera stopped")] {
            camera.emit(trackingState(), start: 0)
            XCTAssertNotNil(model.displayPose)
            camera.emit(state, start: 0)
            XCTAssertEqual(model.state, state)
            XCTAssertNil(model.displayPose)
        }
        camera.emit(trackingState(), start: 0)
        model.setApplicationActive(false)
        camera.emit(trackingState(), start: 0)
        XCTAssertNil(model.displayPose)
        model.setApplicationActive(true)
        camera.emit(trackingState(), start: 0)
        XCTAssertEqual(model.state, .starting)
    }

    func testDisplayMirroringUsesAspectFitAndPreservesMeasurementPose() throws {
        let pose = samplePose()
        let display = RealtimePoseProcessing.displayPose(pose, mirrored: true)
        let point = try XCTUnwrap(display[.leftShoulder])
        XCTAssertEqual(point.normalizedLocation.x, 0.7, accuracy: 0.001)
        XCTAssertEqual(point.imageLocation.x, 756, accuracy: 0.001)
        XCTAssertEqual(point.imageLocation.y, 480, accuracy: 0.001)
        // A square viewport letterboxes the portrait frame. This is the production overlay transform.
        let screen = CoordinateConverter.normalizedToContainer(normalized: point.normalizedLocation,
            imageSize: CGSize(width: 1080, height: 1920), containerSize: CGSize(width: 400, height: 400))
        XCTAssertEqual(screen.x, 245, accuracy: 0.001)
        XCTAssertEqual(screen.y, 100, accuracy: 0.001)
        XCTAssertEqual(RealtimePoseProcessing.displayPose(pose, mirrored: false), pose)
        XCTAssertEqual(RealtimePoseProcessing.displayPose(display, mirrored: true)[.leftShoulder]!.imageLocation.x,
                       pose[.leftShoulder]!.imageLocation.x, accuracy: 0.001)
        XCTAssertEqual(pose[.leftShoulder]!.normalizedLocation.x, 0.3)
    }

    func testLowConfidenceLandmarksCannotProduceLiveMeasurements() {
        var pose = samplePose()
        pose[.rightShoulder]?.confidence = 0.2
        let filtered = RealtimePoseProcessing.reliablePose(pose)
        XCTAssertNil(filtered[.rightShoulder])
        XCTAssertNotNil(filtered[.leftShoulder])
        let assessment = PostureAnalyzer().analyze(pose: filtered,
            imageMetadata: ImageMetadata(width: 1080, height: 1920), view: .front)
        XCTAssertTrue(assessment.measurements.isEmpty)
    }

    private func samplePose() -> BodyPose {
        let points: [(LandmarkType, CGPoint)] = [(.leftShoulder, CGPoint(x: 0.3, y: 0.75)),
                                                (.rightShoulder, CGPoint(x: 0.7, y: 0.70))]
        let landmarks = Dictionary(uniqueKeysWithValues: points.map { type, point in
            (type, Landmark(type: type, normalizedLocation: point,
                imageLocation: CoordinateConverter.normalizedToImagePixel(normalized: point, imageWidth: 1080, imageHeight: 1920),
                confidence: 0.95))
        })
        return BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920)
    }

    private func trackingState() -> RealtimeCameraState {
        let pose = samplePose()
        let assessment = PostureAnalyzer().analyze(pose: pose,
            imageMetadata: ImageMetadata(width: 1080, height: 1920), view: .front)
        return .tracking(pose, assessment)
    }
}

private final class FakeCaptureService: RealtimeCaptureService {
    let session = AVCaptureSession()
    struct Start {
        let position: AVCaptureDevice.Position
        let view: PostureView
        let generation: UUID
        let receive: RealtimeStateReceiver
    }
    var starts: [Start] = []
    var stops = 0
    func start(position: AVCaptureDevice.Position, view: PostureView, generation: UUID,
               receive: @escaping RealtimeStateReceiver) {
        starts.append(Start(position: position, view: view, generation: generation, receive: receive))
    }
    func stop() { stops += 1 }
    @MainActor func emit(_ state: RealtimeCameraState, start: Int) {
        starts[start].receive(starts[start].generation, state)
    }
}

@MainActor
private final class FakeCameraPermission: RealtimeCameraPermission {
    var status: AVAuthorizationStatus
    var completion: (@MainActor (Bool) -> Void)?
    init(status: AVAuthorizationStatus) { self.status = status }
    func request(_ completion: @escaping @MainActor (Bool) -> Void) { self.completion = completion }
    func complete(granted: Bool) {
        status = granted ? .authorized : .denied
        completion?(granted)
        completion = nil
    }
}
