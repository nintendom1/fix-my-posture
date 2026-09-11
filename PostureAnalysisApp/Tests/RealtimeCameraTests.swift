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

    func testRefreshRatesAndPreferenceChanges() {
        for rate in [2, 5, 10] {
            var gate = FeedbackRefreshGate()
            let accepted = (0..<1000).filter { gate.accepts(time: Double($0) / 1000, rate: rate) }
            XCTAssertEqual(accepted.count, rate)
        }
        var gate = FeedbackRefreshGate()
        XCTAssertTrue(gate.accepts(time: 0, rate: 2))
        XCTAssertFalse(gate.accepts(time: 0.1, rate: 2))
        XCTAssertTrue(gate.accepts(time: 0.1, rate: 10))
        XCTAssertFalse(gate.accepts(time: 0.2, rate: 5))
        XCTAssertTrue(gate.accepts(time: 0.3, rate: 5))
    }

    @MainActor
    func testDetailsStayPausedAcrossForegroundAndSettingsChanges() {
        let camera = FakeCaptureService()
        let model = RealtimeCameraModel(camera: camera, permission: FakeCameraPermission(status: .authorized))
        model.onAppear()
        model.setDetailsPresented(true)
        model.setApplicationActive(false)
        model.setFeedback(rate: 10, reduceMotion: true)
        model.setApplicationActive(true)
        model.checkPermissionAndSetup()
        camera.emit(trackingState(), start: 0)
        XCTAssertEqual(camera.starts.count, 1)
        XCTAssertNil(model.displayPose)
        model.setDetailsPresented(false)
        XCTAssertEqual(camera.starts.count, 2)
    }

    @MainActor
    func testTargetClearingAndStaleResultRejectionAfterPreferenceChange() {
        let camera = FakeCaptureService()
        let model = RealtimeCameraModel(camera: camera, permission: FakeCameraPermission(status: .authorized))
        model.onAppear()
        let target = ReferencePose(jointLocations: [.leftShoulder: CGPoint(x: 100, y: 200)])
        camera.emit(trackingState(), start: 0, target: target)
        XCTAssertEqual(model.target, target)
        model.setFeedback(rate: 2, reduceMotion: false)
        XCTAssertNil(model.target)
        camera.emit(trackingState(), start: 0, target: target)
        XCTAssertNil(model.target)
        camera.emit(trackingState(), start: 1, target: target)
        XCTAssertEqual(model.target, target)
        camera.emit(.searchingForBody, start: 1, target: target)
        XCTAssertNil(model.target)
        camera.emit(trackingState(), start: 1, target: target)
        model.setDetailsPresented(true)
        XCTAssertNil(model.target)
    }

    func testTargetSmoothingReduceMotionAndMirroring() throws {
        let old = ReferencePose(jointLocations: [.leftShoulder: CGPoint(x: 100, y: 200)])
        let target = ReferencePose(jointLocations: [.leftShoulder: CGPoint(x: 110, y: 200)])
        let smooth = RealtimePoseProcessing.smoothedTarget(target, previous: old, imageWidth: 1000, reduceMotion: false)
        XCTAssertEqual(smooth.jointLocations[.leftShoulder]?.x, 104)
        XCTAssertEqual(RealtimePoseProcessing.smoothedTarget(target, previous: old, imageWidth: 1000, reduceMotion: true), target)
        XCTAssertEqual(RealtimePoseProcessing.smoothedTarget(target, previous: old, imageWidth: 100, reduceMotion: false), target)
        let imageSize = CGSize(width: 1000, height: 2000)
        let size = CGSize(width: 393, height: 852)
        let original = try XCTUnwrap(AlignmentTargetOverlayView.rects(reference: target, imageSize: imageSize, containerSize: size).first)
        let mirrored = try XCTUnwrap(AlignmentTargetOverlayView.rects(reference: target, imageSize: imageSize, containerSize: size, mirrored: true).first)
        XCTAssertEqual(original.midX + mirrored.midX, size.width, accuracy: 0.001)
        XCTAssertEqual(original.midY, mirrored.midY)
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
        let targetReceive: (@MainActor (UUID, ReferencePose?) -> Void)?
    }
    var starts: [Start] = []
    var stops = 0
    var targetReceive: (@MainActor (UUID, ReferencePose?) -> Void)?
    func configureFeedback(rate: Int, reduceMotion: Bool, receive: @escaping @MainActor (UUID, ReferencePose?) -> Void) {
        targetReceive = receive
    }
    func start(position: AVCaptureDevice.Position, view: PostureView, generation: UUID,
               receive: @escaping RealtimeStateReceiver) {
        starts.append(Start(position: position, view: view, generation: generation, receive: receive, targetReceive: targetReceive))
    }
    func stop() { stops += 1 }
    @MainActor func emit(_ state: RealtimeCameraState, start: Int, target: ReferencePose? = nil) {
        starts[start].receive(starts[start].generation, state)
        starts[start].targetReceive?(starts[start].generation, target)
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
