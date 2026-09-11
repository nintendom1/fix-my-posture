import SwiftUI
import AVFoundation
import CoreGraphics

/// Camera and tracking lifecycle states for realtime posture correction.
public enum RealtimeCameraState: Equatable {
    case initializing
    case starting
    case tracking(BodyPose, PostureAssessment)
    case searchingForBody
    case notAuthorized
    case interrupted
    case failed(String)
}

/// Realtime posture correction view displaying live camera selfie feed with pose alignment overlay and live metrics.
public struct RealtimeCorrectionView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cameraModel = RealtimeCameraModel()
    @State private var showOverlay: Bool = true
    @State private var selectedView: PostureView = .front

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraModel.state {
            case .notAuthorized:
                unauthorizedView
            case .failed(let message):
                failureView(message: message)
            default:
                cameraContentView
            }
        }
        .onAppear {
            cameraModel.onAppear()
        }
        .onDisappear {
            cameraModel.onDisappear()
        }
        .onChange(of: selectedView) { _, newView in
            cameraModel.setPostureView(newView)
        }
    }

    // MARK: - Camera Live Overlay View

    private var cameraContentView: some View {
        GeometryReader { geo in
            ZStack {
                // Live camera preview filling container with aspect-fit geometry matching overlay
                RealtimeCameraPreview(session: cameraModel.captureSession)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Pose Landmark Skeleton Overlay
                if showOverlay, let pose = cameraModel.displayPose {
                    LandmarkOverlayView(
                        pose: pose,
                        containerSize: geo.size
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                // HUD Controls & Metrics
                VStack {
                    // Top Control Bar
                    HStack {
                        Button(action: {
                            cameraModel.stopSession()
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                        .accessibilityIdentifier("closeRealtimeButton")

                        Spacer()

                        Text("Realtime Posture Selfie")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)

                        Spacer()

                        Button(action: { cameraModel.switchCamera() }) {
                            Image(systemName: "camera.rotate.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                        .accessibilityIdentifier("switchCameraButton")
                    }
                    .padding()

                    Spacer()

                    // Bottom Feedback Panel
                    VStack(spacing: 12) {
                        HStack {
                            Toggle("Show Overlay", isOn: $showOverlay)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .foregroundColor(.white)
                                .accessibilityIdentifier("realtimeOverlayToggle")

                            Spacer()

                            Picker("View", selection: $selectedView) {
                                ForEach(PostureView.allCases) { v in
                                    Text(v.displayName).tag(v)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            .accessibilityIdentifier("realtimeViewPicker")
                        }

                        feedbackMetricsView
                    }
                    .padding()
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Live Feedback Panel Content

    @ViewBuilder
    private var feedbackMetricsView: some View {
        switch cameraModel.state {
        case .tracking(_, let assessment):
            if !assessment.measurements.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Realtime Alignment Metrics")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white.opacity(0.8))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(assessment.measurements) { m in
                                let isLowConfidence = m.confidence < 0.5
                                let isElevated = m.value > 5.0

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(m.name)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                        if isLowConfidence {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                    }

                                    Text("\(String(format: "%.1f", m.value))\(m.unit)")
                                        .font(.headline)
                                        .foregroundColor(isLowConfidence ? .orange : (isElevated ? .amberColor : .green))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            } else {
                searchingBodyView
            }

        case .searchingForBody:
            searchingBodyView

        case .starting, .initializing:
            HStack {
                ProgressView()
                    .tint(.white)
                    .padding(.trailing, 6)
                Text("Starting camera feed...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.vertical, 4)

        case .interrupted:
            HStack {
                Image(systemName: "pause.fill")
                    .foregroundColor(.yellow)
                Text("Camera feed interrupted")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.vertical, 4)

        default:
            EmptyView()
        }
    }

    private var searchingBodyView: some View {
        HStack {
            ProgressView()
                .tint(.white)
                .padding(.trailing, 6)
            Text("Position full body in frame for posture tracking...")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Unauthorized & Failure Views

    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("Camera Access Required")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            Text("Please enable camera access in Settings to view realtime posture alignment.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
            }
        }
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("Camera Error")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// Color helper for amber/yellow metric deviation
private extension Color {
    static let amberColor = Color(red: 0.95, green: 0.70, blue: 0.20)
}

// MARK: - Camera Preview UIViewControllerRepresentable

public struct RealtimeCameraPreview: UIViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

public class CameraPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Realtime Camera Model

@MainActor
public final class RealtimeCameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published public private(set) var state: RealtimeCameraState = .initializing
    @Published public private(set) var displayPose: BodyPose? = nil

    public let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "com.postureanalysis.realtimeQueue", qos: .userInitiated)

    private var currentPosition: AVCaptureDevice.Position = .front
    private var isProcessingFrame = false
    private var postureView: PostureView = .front

    private var isViewActive = false
    private var sessionToken = UUID()

    private let poseEstimator: PoseEstimator
    private let analyzer = PostureAnalyzer()

    public init(poseEstimator: PoseEstimator = AppleVisionPoseEstimator()) {
        self.poseEstimator = poseEstimator
        super.init()
        setupNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func onAppear() {
        isViewActive = true
        checkPermissionAndSetup()
    }

    public func onDisappear() {
        isViewActive = false
        stopSession()
    }

    public func setPostureView(_ view: PostureView) {
        self.postureView = view
        clearResults()
    }

    public func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isViewActive else { return }
                    if granted {
                        self.setupSession()
                    } else {
                        self.state = .notAuthorized
                    }
                }
            }
        default:
            self.state = .notAuthorized
        }
    }

    public func setupSession() {
        guard isViewActive else { return }
        state = .starting
        clearResults()

        let currentToken = UUID()
        self.sessionToken = currentToken
        let position = self.currentPosition

        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
            for output in self.captureSession.outputs {
                self.captureSession.removeOutput(output)
            }

            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoInput) else {
                self.captureSession.commitConfiguration()
                Task { @MainActor [weak self] in
                    guard let self = self, self.sessionToken == currentToken else { return }
                    self.state = .failed("Failed to access camera hardware.")
                }
                return
            }

            self.captureSession.addInput(videoInput)

            // Deliver unmirrored CVPixelBuffers to Vision
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)

            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            if let connection = self.videoOutput.connection(with: .video) {
                // Set unmirrored video data output
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = false
                }
                // Handle video rotation using modern API
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()

            Task { @MainActor [weak self] in
                guard let self = self, self.sessionToken == currentToken else { return }
                self.state = .searchingForBody
            }
        }
    }

    public func switchCamera() {
        currentPosition = (currentPosition == .front) ? .back : .front
        setupSession()
    }

    public func stopSession() {
        sessionToken = UUID()
        clearResults()

        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    private func clearResults() {
        displayPose = nil
        if state != .notAuthorized && state != .starting && state != .initializing {
            state = .searchingForBody
        }
    }

    // MARK: - Notifications & Lifecycle Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgrounding),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForegrounding),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVCaptureSession.wasInterruptedNotification,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: captureSession
        )
    }

    @objc private func handleBackgrounding() {
        stopSession()
        state = .interrupted
    }

    @objc private func handleForegrounding() {
        if isViewActive {
            checkPermissionAndSetup()
        }
    }

    @objc private func handleInterruption() {
        state = .interrupted
    }

    @objc private func handleInterruptionEnded() {
        if isViewActive {
            setupSession()
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        Task { @MainActor [weak self] in
            guard let self = self, self.isViewActive, !self.isProcessingFrame else { return }
            self.isProcessingFrame = true

            let currentToken = self.sessionToken
            let viewToAnalyze = self.postureView
            let isFrontCamera = (self.currentPosition == .front)

            Task.detached(priority: .userInitiated) {
                do {
                    let pose = try await self.poseEstimator.estimatePose(in: pixelBuffer)
                    let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
                    let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
                    let meta = ImageMetadata(width: width, height: height)

                    let assessment = self.analyzer.analyze(pose: pose, imageMetadata: meta, view: viewToAnalyze)

                    await MainActor.run {
                        guard self.sessionToken == currentToken, self.isViewActive else {
                            self.isProcessingFrame = false
                            return
                        }

                        if pose.landmarks.isEmpty {
                            self.state = .searchingForBody
                            self.displayPose = nil
                        } else {
                            let displayPose = self.prepareDisplayPose(pose: pose, isFrontCamera: isFrontCamera)
                            self.displayPose = displayPose
                            self.state = .tracking(pose, assessment)
                        }
                        self.isProcessingFrame = false
                    }
                } catch {
                    await MainActor.run {
                        guard self.sessionToken == currentToken, self.isViewActive else {
                            self.isProcessingFrame = false
                            return
                        }
                        self.clearResults()
                        self.isProcessingFrame = false
                    }
                }
            }
        }
    }

    /// Converts unmirrored domain pose to display pose for mirrored selfie preview.
    private func prepareDisplayPose(pose: BodyPose, isFrontCamera: Bool) -> BodyPose {
        guard isFrontCamera else { return pose }

        var displayLandmarks: [LandmarkType: Landmark] = [:]
        for (type, lm) in pose.landmarks {
            let mirroredNormX = 1.0 - lm.normalizedLocation.x
            let mirroredImgX = mirroredNormX * pose.imageWidth

            let mirroredLm = Landmark(
                type: type,
                normalizedLocation: CGPoint(x: mirroredNormX, y: lm.normalizedLocation.y),
                imageLocation: CGPoint(x: mirroredImgX, y: lm.imageLocation.y),
                confidence: lm.confidence,
                isManuallyCorrected: lm.isManuallyCorrected
            )
            displayLandmarks[type] = mirroredLm
        }

        return BodyPose(landmarks: displayLandmarks, imageWidth: pose.imageWidth, imageHeight: pose.imageHeight)
    }
}
