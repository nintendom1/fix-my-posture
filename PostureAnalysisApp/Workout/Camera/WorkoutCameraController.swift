import AVFoundation
import CoreVideo
import Foundation

/// Front-camera pose capture for the workout coach.
/// Configuration and synchronous inference run on one serial queue at 10 Hz. Frames reach the main actor
/// through a single pending slot: at most one hop is in flight, newer frames replace older ones, and no
/// camera buffers are retained.
final class WorkoutCameraController: NSObject, PoseFrameSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let frameRate = 10

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.postureanalysis.workoutCapture", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let estimator: FramePoseEstimator
    private var observers: [NSObjectProtocol] = []

    // The request generation and the pending frame slot cross queues under these locks.
    private let requestLock = NSLock()
    private var requestedGeneration: UUID?
    private let pendingLock = NSLock()
    private var pending: (generation: UUID, frame: PoseFrame, receive: PoseFrameReceiver)?
    private var isDeliveryScheduled = false

    // The remaining mutable fields belong exclusively to queue.
    private var generation: UUID?
    private var receive: PoseFrameReceiver?
    private var gate = FeedbackRefreshGate()
    private var interrupted = false

    init(estimator: FramePoseEstimator = AppleVisionPoseEstimator()) {
        self.estimator = estimator
        super.init()
        observe(.AVCaptureSessionWasInterrupted) { controller in
            controller.interrupted = true
            controller.publish(.interrupted)
        }
        observe(.AVCaptureSessionInterruptionEnded) { controller in
            controller.interrupted = false
            if !controller.session.isRunning { controller.session.startRunning() }
            controller.publish(.running)
        }
        observe(.AVCaptureSessionRuntimeError) { controller in
            controller.interrupted = true
            controller.session.stopRunning()
            controller.publish(.failed("The camera stopped unexpectedly. Close this screen and try again."))
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        let captureSession = session
        queue.async { if captureSession.isRunning { captureSession.stopRunning() } }
    }

    func start(generation: UUID, receive: @escaping PoseFrameReceiver) {
        request(generation)
        queue.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.generation = generation
            self.receive = receive
            self.gate = FeedbackRefreshGate()
            self.interrupted = false
            if self.session.isRunning { self.session.stopRunning() }
            if let failure = PortraitCameraSession.configure(session: self.session, output: self.output,
                    position: .front, delegate: self, queue: self.queue) {
                self.publish(.failed(failure))
                return
            }
            guard self.isCurrent(generation) else { return }
            self.session.startRunning()
            self.publish(self.session.isRunning ? .running : .failed("Unable to start the camera."))
        }
    }

    func stop() {
        request(nil)
        pendingLock.lock()
        pending = nil
        pendingLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.generation = nil
            self.receive = nil
            self.output.setSampleBufferDelegate(nil, queue: nil)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let generation, isCurrent(generation), !interrupted, let receive,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let time = presentationTime.isValid ? presentationTime.seconds : ProcessInfo.processInfo.systemUptime
        guard gate.accepts(time: time, rate: Self.frameRate) else { return }
        autoreleasepool {
            let pose: BodyPose
            do {
                pose = RealtimePoseProcessing.reliablePose(try estimator.estimatePose(in: buffer))
            } catch {
                // An empty pose reads as tracking loss rather than reusing stale joints.
                pose = BodyPose(landmarks: [:], imageWidth: CGFloat(CVPixelBufferGetWidth(buffer)),
                                imageHeight: CGFloat(CVPixelBufferGetHeight(buffer)))
            }
            deliver(PoseFrame(pose: pose, timestamp: time), generation: generation, receive: receive)
        }
    }

    // MARK: - Delivery

    private func deliver(_ frame: PoseFrame, generation: UUID, receive: @escaping PoseFrameReceiver) {
        pendingLock.lock()
        pending = (generation, frame, receive)
        let shouldSchedule = !isDeliveryScheduled
        isDeliveryScheduled = true
        pendingLock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in self?.drainPendingFrame() }
    }

    private func drainPendingFrame() {
        pendingLock.lock()
        let next = pending
        pending = nil
        isDeliveryScheduled = false
        pendingLock.unlock()
        guard let next, isCurrent(next.generation) else { return }
        MainActor.assumeIsolated { next.receive(next.generation, .frame(next.frame)) }
    }

    /// Status events use the same main queue as frames, so they arrive in order.
    private func publish(_ event: PoseFrameSourceEvent) {
        guard let generation, isCurrent(generation), let receive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            MainActor.assumeIsolated { receive(generation, event) }
        }
    }

    // MARK: - Generations

    private func observe(_ name: Notification.Name, action: @escaping (WorkoutCameraController) -> Void) {
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
}
