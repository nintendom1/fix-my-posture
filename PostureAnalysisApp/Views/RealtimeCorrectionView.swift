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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("feedbackRefreshRate") private var feedbackRate = 5
    @State private var showTargets = true
    @State private var controlRects: [CGRect] = []
    @State private var detailsTarget: ReferencePose?
    @State private var showOverlay: Bool = true
    @State private var showCallouts: Bool = true
    @State private var showDetails: Bool = false
    @State private var detailsAssessment: PostureAssessment?
    @State private var selectedView: PostureView = .front
    private let referenceProvider: PostureReferenceProviding

    public init(referenceProvider: PostureReferenceProviding = DefaultPostureReferenceProvider()) {
        self.referenceProvider = referenceProvider
    }

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
            cameraModel.setFeedback(rate: feedbackRate, reduceMotion: reduceMotion)
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
        .onChange(of: feedbackRate) { _, rate in cameraModel.setFeedback(rate: rate, reduceMotion: reduceMotion) }
        .onChange(of: reduceMotion) { _, value in cameraModel.setFeedback(rate: feedbackRate, reduceMotion: value) }
        .sheet(isPresented: $showDetails, onDismiss: {
            cameraModel.setDetailsPresented(false)
        }) {
            detailsSheet
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
                        containerSize: geo.size,
                        distanceEmphasis: true,
                        feedback: jointFeedback
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                }

                if showTargets, let target = cameraModel.target, let pose = cameraModel.displayPose {
                    AlignmentTargetOverlayView(reference: target, imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight), mirrored: cameraModel.isFrontCamera)
                }

                if showCallouts,
                   let pose = cameraModel.displayPose,
                   case .tracking(_, let assessment) = cameraModel.state {
                    PostureCalloutOverlayView(
                        measurements: assessment.measurements,
                        pose: pose,
                        view: assessment.view,
                        profile: referenceProvider.profile(for: assessment.view),
                        sourcePose: assessment.pose,
                        targetRects: showTargets ? AlignmentTargetOverlayView.rects(reference: cameraModel.target,
                            imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight), containerSize: geo.size, mirrored: cameraModel.isFrontCamera) : [],
                        reservedRects: controlRects.isEmpty ? [
                            CGRect(x: 0, y: 0, width: geo.size.width, height: 78),
                            CGRect(x: 0, y: max(0, geo.size.height - 112), width: geo.size.width, height: 112)
                        ] : controlRects
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
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
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: RealtimeControlRects.self, value: [proxy.frame(in: .named("realtimeOverlay"))])
                    })

                    Spacer()

                    // Compact controls preserve the camera and floating feedback area.
                    VStack(spacing: 8) {
                        HStack {
                            Label(realtimeStatusLabel, systemImage: realtimeStatusSymbol)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Spacer()

                            if case .tracking(_, let assessment) = cameraModel.state {
                                Button("Details") {
                                    detailsAssessment = assessment
                                    detailsTarget = cameraModel.target
                                    cameraModel.setDetailsPresented(true)
                                    showDetails = true
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                                .accessibilityIdentifier("realtimeDetailsButton")
                            }
                        }

                        HStack(spacing: 10) {
                            Toggle("Skeleton", isOn: $showOverlay)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .foregroundColor(.white)
                                .accessibilityIdentifier("realtimeOverlayToggle")

                            Toggle("Callouts", isOn: $showCallouts)
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .foregroundColor(.white)
                                .accessibilityIdentifier("realtimeCalloutToggle")

                            Menu {
                                Toggle("Alignment targets", isOn: $showTargets)
                                Picker("Feedback refresh", selection: $feedbackRate) {
                                    ForEach([2, 5, 10], id: \.self) { rate in Text("\(rate) per second").tag(rate) }
                                }
                            } label: { Image(systemName: "gearshape.fill") }
                            .accessibilityLabel("Feedback settings")
                            .tint(.white)

                            Picker("View", selection: $selectedView) {
                                ForEach([PostureView.front, .leftSide, .rightSide]) { v in
                                    Text(v.displayName).tag(v)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            .accessibilityIdentifier("realtimeViewPicker")
                        }
                    }
                    .padding(8)
                    .background(.black.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: RealtimeControlRects.self, value: [proxy.frame(in: .named("realtimeOverlay"))])
                    })
                }
            }
            .coordinateSpace(name: "realtimeOverlay")
            .onPreferenceChange(RealtimeControlRects.self) { controlRects = $0 }
        }
    }

    private var jointFeedback: [LandmarkType: MeasurementFeedback] {
        guard case .tracking(let pose, let assessment) = cameraModel.state else { return [:] }
        return MeasurementPresentation.jointFeedback(measurements: assessment.measurements, pose: pose,
            view: assessment.view, profile: referenceProvider.profile(for: assessment.view))
    }

    private var realtimeStatusLabel: String {
        switch cameraModel.state {
        case .tracking: return "Tracking"
        case .searchingForBody: return "Show full body"
        case .starting, .initializing: return "Starting camera"
        case .interrupted: return "Camera paused"
        case .notAuthorized: return "Camera unavailable"
        case .failed: return "Camera error"
        }
    }

    private var realtimeStatusSymbol: String {
        switch cameraModel.state {
        case .tracking: return "figure.stand"
        case .searchingForBody, .starting, .initializing: return "viewfinder"
        case .interrupted: return "pause.fill"
        case .notAuthorized, .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var detailsSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Text(MeasurementPresentation.convention).font(.footnote)
                    if let reason = detailsTarget?.unavailabilityReason { Text(reason).font(.footnote) }
                    if let assessment = detailsAssessment {
                        ForEach(assessment.measurements) { measurement in
                            PostureMeasurementCard(
                                measurement: measurement,
                                feedback: MeasurementFeedbackEvaluator().feedback(
                                    for: measurement,
                                    view: assessment.view,
                                    profile: referenceProvider.profile(for: assessment.view)
                                ),
                                explanation: MeasurementPresentation.explanation(measurement),
                                reading: MeasurementPresentation.reading(measurement, pose: assessment.pose, view: assessment.view)
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDetails = false }
                }
            }
        }
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

private struct RealtimeControlRects: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}
