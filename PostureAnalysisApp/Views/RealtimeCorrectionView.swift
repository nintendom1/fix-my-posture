import SwiftUI
import AVFoundation
import Vision

/// Realtime posture correction view displaying live camera feed (selfie mode) with pose landmark overlay and live metrics.
public struct RealtimeCorrectionView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cameraModel = RealtimeCameraModel()
    @State private var showOverlay: Bool = true
    @State private var selectedView: PostureView = .front

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraModel.isCameraAuthorized {
                GeometryReader { geo in
                    ZStack {
                        RealtimeCameraPreview(session: cameraModel.captureSession)
                            .ignoresSafeArea()

                        if showOverlay, let pose = cameraModel.currentPose {
                            LandmarkOverlayView(
                                pose: pose,
                                containerSize: geo.size
                            )
                        }

                        // Live Posture Controls & Metrics Panel
                        VStack {
                            // Top Bar
                            HStack {
                                Button(action: { dismiss() }) {
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

                            // Bottom Realtime Posture Feedback Panel
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

                                if let assessment = cameraModel.currentAssessment, !assessment.measurements.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Realtime Alignment Metrics")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.white.opacity(0.8))

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(assessment.measurements) { m in
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(m.name)
                                                            .font(.caption2)
                                                            .foregroundColor(.gray)
                                                        Text("\(String(format: "%.1f", m.value))\(m.unit)")
                                                            .font(.headline)
                                                            .foregroundColor(.green)
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
                            }
                            .padding()
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(16)
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        }
                    }
                }
            } else {
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
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            cameraModel.checkPermissionAndSetup()
        }
        .onDisappear {
            cameraModel.stopSession()
        }
        .onChange(of: selectedView) { _, newView in
            cameraModel.setPostureView(newView)
        }
    }
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
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

public class CameraPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Realtime Camera & Pose Estimation Model

public final class RealtimeCameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published public var isCameraAuthorized: Bool = true
    @Published public var currentPose: BodyPose? = nil
    @Published public var currentAssessment: PostureAssessment? = nil

    public let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "com.postureanalysis.realtimeQueue", qos: .userInitiated)

    private var currentPosition: AVCaptureDevice.Position = .front
    private var isProcessingFrame = false
    private var postureView: PostureView = .front
    private let analyzer = PostureAnalyzer()

    public override init() {
        super.init()
    }

    public func setPostureView(_ view: PostureView) {
        self.postureView = view
    }

    public func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isCameraAuthorized = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.isCameraAuthorized = false
            }
        }
    }

    public func setupSession() {
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            // Remove existing inputs/outputs
            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
            for output in self.captureSession.outputs {
                self.captureSession.removeOutput(output)
            }

            // Input camera device
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoInput) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(videoInput)

            // Video output
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (self.currentPosition == .front)
                }
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }

    public func switchCamera() {
        currentPosition = (currentPosition == .front) ? .back : .front
        setupSession()
    }

    public func stopSession() {
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        isProcessingFrame = true

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
            if let observation = request.results?.first {
                let pose = buildBodyPose(from: observation, pixelBuffer: pixelBuffer, isFrontCamera: (currentPosition == .front))
                let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
                let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
                let meta = ImageMetadata(width: width, height: height)
                let assessment = analyzer.analyze(pose: pose, imageMetadata: meta, view: postureView)

                DispatchQueue.main.async { [weak self] in
                    self?.currentPose = pose
                    self?.currentAssessment = assessment
                    self?.isProcessingFrame = false
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.currentPose = nil
                    self?.currentAssessment = nil
                    self?.isProcessingFrame = false
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.isProcessingFrame = false
            }
        }
    }

    private func buildBodyPose(from observation: VNHumanBodyPoseObservation, pixelBuffer: CVPixelBuffer, isFrontCamera: Bool) -> BodyPose {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        var landmarks: [LandmarkType: Landmark] = [:]

        let jointMapping: [(VNHumanBodyPoseObservation.JointName, LandmarkType)] = [
            (.nose, .nose),
            (.neck, .neck),
            (.leftEye, .leftEye),
            (.rightEye, .rightEye),
            (.leftEar, .leftEar),
            (.rightEar, .rightEar),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.root, .root),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle)
        ]

        for (visionJoint, landmarkType) in jointMapping {
            do {
                let recognizedPoint = try observation.recognizedPoint(visionJoint)
                if recognizedPoint.confidence > 0.01 {
                    // Vision normalized coordinates (origin bottom-left)
                    var normX = recognizedPoint.location.x
                    let normY = recognizedPoint.location.y

                    // If front selfie camera preview is mirrored horizontally, mirror normX so points align with selfie preview:
                    if isFrontCamera {
                        normX = 1.0 - normX
                    }

                    let imgX = normX * width
                    let imgY = (1.0 - normY) * height

                    let landmark = Landmark(
                        type: landmarkType,
                        normalizedLocation: CGPoint(x: normX, y: normY),
                        imageLocation: CGPoint(x: imgX, y: imgY),
                        confidence: Double(recognizedPoint.confidence),
                        isManuallyCorrected: false
                    )
                    landmarks[landmarkType] = landmark
                }
            } catch {
                continue
            }
        }

        return BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
    }
}
