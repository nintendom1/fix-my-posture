import AVFoundation
import SwiftUI

typealias RealtimeStateReceiver = @MainActor (UUID, RealtimeCameraState) -> Void

/// Implementations serialize capture work and return generation-tagged events on the main actor.
protocol RealtimeCaptureService: AnyObject {
    var session: AVCaptureSession { get }
    func start(position: AVCaptureDevice.Position, view: PostureView, generation: UUID,
               receive: @escaping RealtimeStateReceiver)
    func stop()
    func configureFeedback(rate: Int, reduceMotion: Bool, compensationEnabled: Bool, horizonMonitor: HorizonMonitoring?, receive: @escaping @MainActor (UUID, ReferencePose?) -> Void)
}

struct FeedbackRefreshGate {
    private var lastTime = -Double.infinity
    mutating func accepts(time: Double, rate: Int) -> Bool {
        let rate = [2, 5, 10].contains(rate) ? rate : 5
        guard time - lastTime + 0.000001 >= 1 / Double(rate) else { return false }
        lastTime = time
        return true
    }
}

@MainActor
protocol RealtimeCameraPermission {
    var status: AVAuthorizationStatus { get }
    func request(_ completion: @escaping @MainActor (Bool) -> Void)
}

@MainActor
private struct SystemCameraPermission: RealtimeCameraPermission {
    var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in completion(granted) }
        }
    }
}

@MainActor
public final class RealtimeCameraModel: ObservableObject {
    @Published public private(set) var state: RealtimeCameraState = .initializing
    @Published public private(set) var isFrontCamera = true
    @Published public private(set) var target: ReferencePose?
    @Published public private(set) var horizonReading: HorizonReading?
    @Published public private(set) var isHorizonUnavailable = false

    public let horizonMonitor: HorizonMonitoring
    private var detailsPresented = false
    private var feedbackRate = 5
    private var reduceMotion = false
    private var compensationEnabled = true
    private var horizonTimer: Timer?

    public var captureSession: AVCaptureSession { camera.session }
    public var displayPose: BodyPose? {
        guard case .tracking(let pose, _) = state else { return nil }
        return RealtimePoseProcessing.displayPose(pose, mirrored: isFrontCamera)
    }

    private let camera: RealtimeCaptureService
    private let permission: RealtimeCameraPermission
    private var isViewActive = false
    private var isApplicationActive = false
    private var isRequestingPermission = false
    private var postureView: PostureView = .front
    private var generation = UUID()
    private var canCapture: Bool { isViewActive && isApplicationActive && !detailsPresented }

    public convenience init(poseEstimator: FramePoseEstimator = AppleVisionPoseEstimator(), horizonMonitor: HorizonMonitoring = CoreMotionHorizonMonitor()) {
        self.init(camera: RealtimeCameraController(estimator: poseEstimator), permission: SystemCameraPermission(), horizonMonitor: horizonMonitor)
    }

    init(camera: RealtimeCaptureService, permission: RealtimeCameraPermission, horizonMonitor: HorizonMonitoring = CoreMotionHorizonMonitor()) {
        self.camera = camera
        self.permission = permission
        self.horizonMonitor = horizonMonitor
    }

    public func setDetailsPresented(_ presented: Bool) {
        detailsPresented = presented
        if presented { stopSession() } else if canCapture { checkPermissionAndSetup() }
    }

    public func setFeedback(rate: Int, reduceMotion: Bool, compensationEnabled: Bool = true) {
        feedbackRate = [2, 5, 10].contains(rate) ? rate : 5
        self.reduceMotion = reduceMotion
        self.compensationEnabled = compensationEnabled
        if canCapture, permission.status == .authorized { startSession() }
    }

    public func onAppear(isApplicationActive: Bool = true) {
        isViewActive = true
        self.isApplicationActive = isApplicationActive
        if canCapture { checkPermissionAndSetup() }
    }

    public func onDisappear() {
        isViewActive = false
        stopSession()
    }

    public func setApplicationActive(_ active: Bool) {
        guard isApplicationActive != active else { return }
        isApplicationActive = active
        if canCapture {
            checkPermissionAndSetup()
        } else {
            stopSession()
        }
    }

    public func setPostureView(_ view: PostureView) {
        guard postureView != view else { return }
        postureView = view
        // Invalidate work already running for the previous view before queuing its replacement.
        generation = UUID()
        guard canCapture, permission.status == .authorized else { return }
        startSession()
    }

    public func checkPermissionAndSetup() {
        guard canCapture else { return }
        switch permission.status {
        case .authorized:
            startSession()
        case .notDetermined:
            guard !isRequestingPermission else { return }
            isRequestingPermission = true
            permission.request { [weak self] granted in
                guard let self else { return }
                self.isRequestingPermission = false
                guard self.canCapture else { return }
                if granted {
                    self.startSession()
                } else {
                    self.state = .notAuthorized
                }
            }
        default:
            generation = UUID()
            camera.stop()
            state = .notAuthorized
        }
    }

    private func startSession() {
        generation = UUID()
        state = .starting
        target = nil
        horizonMonitor.isFrontCamera = isFrontCamera
        horizonMonitor.startUpdates()

        horizonTimer?.invalidate()
        horizonTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateHorizonDisplay()
            }
        }

        camera.configureFeedback(rate: feedbackRate, reduceMotion: reduceMotion, compensationEnabled: compensationEnabled, horizonMonitor: horizonMonitor) { [weak self] token, target in
            guard let self, self.canCapture, self.generation == token,
                  case .tracking = self.state else { return }
            self.target = target
        }
        camera.start(position: isFrontCamera ? .front : .back, view: postureView, generation: generation) {
            [weak self] token, state in
            guard let self, self.canCapture, self.generation == token else { return }
            self.state = state
            if case .tracking = state {} else { self.target = nil }
        }
    }

    private func updateHorizonDisplay() {
        horizonMonitor.isFrontCamera = isFrontCamera
        let reading = horizonMonitor.latestReading
        if compensationEnabled {
            if let reading {
                horizonReading = reading
                isHorizonUnavailable = false
            } else {
                horizonReading = nil
                isHorizonUnavailable = true
            }
        } else {
            horizonReading = reading
            isHorizonUnavailable = false
        }
    }

    public func switchCamera() {
        guard canCapture, permission.status == .authorized else { return }
        isFrontCamera.toggle()
        startSession()
    }

    public func stopSession() {
        generation = UUID()
        target = nil
        horizonTimer?.invalidate()
        horizonTimer = nil
        horizonMonitor.stopUpdates()
        horizonReading = nil
        isHorizonUnavailable = false
        state = .interrupted
        camera.stop()
    }
}

/// Display transforms never alter the unmirrored pose used for measurement geometry.
enum RealtimePoseProcessing {
    static func smoothedTarget(_ target: ReferencePose, previous: ReferencePose?, imageWidth: CGFloat, reduceMotion: Bool) -> ReferencePose {
        guard !reduceMotion, let previous else { return target }
        var result = target
        for (joint, point) in target.jointLocations {
            if let old = previous.jointLocations[joint], hypot(point.x - old.x, point.y - old.y) < imageWidth * 0.025 {
                result.jointLocations[joint] = CGPoint(x: old.x + (point.x - old.x) * 0.4, y: old.y + (point.y - old.y) * 0.4)
            }
        }
        return result
    }

    static func reliablePose(_ pose: BodyPose) -> BodyPose {
        var result = pose
        result.landmarks = pose.landmarks.filter { $0.value.confidence >= 0.3 }
        return result
    }

    static func displayPose(_ pose: BodyPose, mirrored: Bool) -> BodyPose {
        guard mirrored else { return pose }
        var result = pose
        result.landmarks = pose.landmarks.mapValues { landmark in
            var result = landmark
            result.normalizedLocation.x = 1 - landmark.normalizedLocation.x
            result.imageLocation = CoordinateConverter.normalizedToImagePixel(
                normalized: result.normalizedLocation, imageWidth: pose.imageWidth, imageHeight: pose.imageHeight)
            return result
        }
        return result
    }
}

/// All session configuration and synchronous inference run on one serial queue.
/// No per-frame Tasks retain buffers while the UI is busy; AVFoundation drops late frames.
private final class RealtimeCameraController: NSObject, RealtimeCaptureService, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.postureanalysis.realtimeCapture", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let estimator: FramePoseEstimator
    private let analyzer = PostureAnalyzer()
    private var observers: [NSObjectProtocol] = []

    // Only the request generation crosses queues, protected by this lock.
    private let requestLock = NSLock()
    private var requestedGeneration: UUID?
    // The remaining mutable fields belong exclusively to queue.
    private var generation: UUID?
    private var view: PostureView = .front
    private var receive: RealtimeStateReceiver?
    private var gate = FeedbackRefreshGate()
    private var feedbackRate = 5
    private var reduceMotion = false
    private var compensationEnabled = true
    private var horizonMonitor: HorizonMonitoring?
    private var previousTarget: ReferencePose?
    private var referenceReceiver: (@MainActor (UUID, ReferencePose?) -> Void)?

    func configureFeedback(rate: Int, reduceMotion: Bool, compensationEnabled: Bool, horizonMonitor: HorizonMonitoring?, receive: @escaping @MainActor (UUID, ReferencePose?) -> Void) {
        queue.async {
            self.feedbackRate = rate
            self.reduceMotion = reduceMotion
            self.compensationEnabled = compensationEnabled
            self.horizonMonitor = horizonMonitor
            self.referenceReceiver = receive
        }
    }
    private var interrupted = false

    init(estimator: FramePoseEstimator) {
        self.estimator = estimator
        super.init()
        observe(.AVCaptureSessionWasInterrupted) { controller in
            controller.interrupted = true
            controller.publish(.interrupted)
        }
        observe(.AVCaptureSessionInterruptionEnded) { controller in
            controller.interrupted = false
            if !controller.session.isRunning { controller.session.startRunning() }
            controller.publish(.searchingForBody)
        }
        observe(.AVCaptureSessionRuntimeError) { controller in
            controller.interrupted = true
            controller.session.stopRunning()
            controller.publish(.failed("The camera stopped unexpectedly. Close this screen and try again."))
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        // The model normally stops on disappearance. This also covers unexpected teardown.
        let captureSession = session
        queue.async { if captureSession.isRunning { captureSession.stopRunning() } }
    }

    private func observe(_ name: Notification.Name, action: @escaping (RealtimeCameraController) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) {
            [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, let generation = self.generation, self.isCurrent(generation) else { return }
                action(self)
            }
        })
    }

    private func request(_ token: UUID?) {
        requestLock.lock()
        requestedGeneration = token
        requestLock.unlock()
    }

    private func isCurrent(_ token: UUID) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return requestedGeneration == token
    }

    func start(position: AVCaptureDevice.Position, view: PostureView, generation: UUID,
               receive: @escaping RealtimeStateReceiver) {
        request(generation)
        queue.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.generation = generation
            self.view = view
            self.receive = receive
            self.gate = FeedbackRefreshGate()
            self.previousTarget = nil
            self.interrupted = false
            if self.session.isRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                self.publish(.failed("Camera hardware is unavailable. Try again on an iPhone with a camera."))
                return
            }
            self.session.addInput(input)
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.setSampleBufferDelegate(self, queue: self.queue)
            guard self.session.canAddOutput(self.output) else {
                self.session.commitConfiguration()
                self.publish(.failed("Unable to read camera frames. Close this screen and try again."))
                return
            }
            self.session.addOutput(self.output)
            guard let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) else {
                self.session.commitConfiguration()
                self.publish(.failed("This camera does not support portrait tracking."))
                return
            }
            connection.videoRotationAngle = 90
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            self.session.commitConfiguration()
            guard self.isCurrent(generation) else { return }
            self.session.startRunning()
            self.publish(self.session.isRunning ? .searchingForBody : .failed("Unable to start the camera."))
        }
    }

    func stop() {
        request(nil)
        queue.async { [weak self] in
            guard let self else { return }
            self.generation = nil
            self.receive = nil
            self.output.setSampleBufferDelegate(nil, queue: nil)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func publish(_ state: RealtimeCameraState) {
        guard let generation, isCurrent(generation), let receive else { return }
        if case .tracking = state {} else { previousTarget = nil }
        let target = previousTarget
        let referenceReceiver = referenceReceiver
        Task { @MainActor in
            receive(generation, state)
            referenceReceiver?(generation, target)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let generation, isCurrent(generation), !interrupted,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard gate.accepts(time: now, rate: feedbackRate) else { return }
        autoreleasepool {
            do {
                let pose = RealtimePoseProcessing.reliablePose(try estimator.estimatePose(in: buffer))
                let metadata = ImageMetadata(width: pose.imageWidth, height: pose.imageHeight)

                let reading = horizonMonitor?.latestReading
                let horizonContext: HorizonContext?
                if compensationEnabled, let reading {
                    horizonContext = HorizonContext(angleDegrees: reading.angleDegrees, source: .deviceMotion, isCompensationApplied: true)
                } else if compensationEnabled, reading == nil {
                    horizonContext = HorizonContext(angleDegrees: 0, source: .deviceMotion, isCompensationApplied: false)
                } else {
                    horizonContext = reading.map { HorizonContext(angleDegrees: $0.angleDegrees, source: .deviceMotion, isCompensationApplied: false) }
                }

                let assessment = analyzer.analyze(pose: pose, imageMetadata: metadata, view: view, horizonContext: horizonContext)
                let result = ReferencePoseGenerator().generateStaticReference(for: pose, view: view,
                    profile: DefaultPostureReferenceProvider().profile(for: view), horizonContext: horizonContext)
                previousTarget = RealtimePoseProcessing.smoothedTarget(result.staticReference, previous: previousTarget,
                    imageWidth: pose.imageWidth, reduceMotion: reduceMotion)
                publish(assessment.measurements.isEmpty ? .searchingForBody : .tracking(pose, assessment))
            } catch {
                // Discard the last overlay and measurements immediately on tracking failure.
                publish(.searchingForBody)
            }
        }
    }
}
