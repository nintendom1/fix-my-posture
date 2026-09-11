import SwiftUI
import AVFoundation
import CoreGraphics
import CoreVideo

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
    @Environment(\.scenePhase) private var scenePhase

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
            cameraModel.onAppear(isApplicationActive: scenePhase == .active)
        }
        .onDisappear {
            cameraModel.onDisappear()
        }
        .onChange(of: selectedView) { _, newView in
            cameraModel.setPostureView(newView)
        }
        .onChange(of: scenePhase) { _, phase in
            cameraModel.setApplicationActive(phase == .active)
        }
    }

    // MARK: - Camera Live Overlay View

    private var cameraContentView: some View {
        GeometryReader { geo in
            ZStack {
                // Live camera preview filling container with aspect-fit geometry matching overlay
                RealtimeCameraPreview(session: cameraModel.captureSession, isMirrored: cameraModel.isFrontCamera)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    .clipped()

                // Pose Landmark Skeleton Overlay
                if showOverlay, let pose = cameraModel.displayPose {
                    LandmarkOverlayView(
                        pose: pose,
                        containerSize: geo.size
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                }

                // HUD Controls & Metrics
                VStack {
                    // Top Control Bar
                    HStack {
                        Button(action: {
                            cameraModel.onDisappear()
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                        .accessibilityIdentifier("closeRealtimeButton")
                        .accessibilityLabel("Close realtime correction")

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
                        .accessibilityLabel("Switch camera")
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
                                ForEach([PostureView.front, .leftSide, .rightSide]) { v in
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
                                        .foregroundColor(isLowConfidence ? .orange : .white)
                                    if isLowConfidence {
                                        Text("Low confidence")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                            }
                        }
                    }
                    Text("Geometric observations, not a diagnosis. Keep your full body visible.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
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

// MARK: - Camera Preview UIViewControllerRepresentable

public struct RealtimeCameraPreview: UIViewRepresentable {
    public let session: AVCaptureSession
    public let isMirrored: Bool

    public init(session: AVCaptureSession, isMirrored: Bool = true) {
        self.session = session
        self.isMirrored = isMirrored
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.isMirrored = isMirrored
        view.configureConnection()
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        uiView.isMirrored = isMirrored
        uiView.configureConnection()
    }
}

public class CameraPreviewUIView: UIView {
    var isMirrored = true

    public override func layoutSubviews() {
        super.layoutSubviews()
        configureConnection()
    }

    func configureConnection() {
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
