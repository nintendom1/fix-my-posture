import SwiftUI

/// Shared visualization component for posture reports (new analysis and saved assessment screens).
public struct PostureReportView: View {
    public let image: UIImage?
    public let pose: BodyPose
    public let view: PostureView
    public let referenceProvider: PostureReferenceProviding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showMeasuredOverlay: Bool = true
    @State private var showReference: Bool = true
    @State private var selectedStyle: ReferenceStyle = .combined

    @State private var referenceResult: ReferenceGenerationResult? = nil
    @State private var displayedReferencePose: ReferencePose? = nil

    @State private var isPlayingAnimation = false
    @State private var animationTask: Task<Void, Never>? = nil

    public init(
        image: UIImage?,
        pose: BodyPose,
        view: PostureView,
        referenceProvider: PostureReferenceProviding = DefaultPostureReferenceProvider()
    ) {
        self.image = image
        self.pose = pose
        self.view = view
        self.referenceProvider = referenceProvider
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Image and Overlay Container
            if let uiImg = image {
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)

                        // 1. Measured Landmarks Overlay
                        if showMeasuredOverlay {
                            LandmarkOverlayView(
                                pose: pose,
                                containerSize: geo.size
                            )
                        }

                        // 2. Alignment Reference Overlay
                        if showReference, let refPose = displayedReferencePose {
                            AlignmentReferenceOverlayView(
                                referencePose: refPose,
                                imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight),
                                containerSize: geo.size,
                                style: selectedStyle
                            )
                        }
                    }
                }
                .frame(height: 350)
            }

            // Controls Section
            VStack(spacing: 12) {
                HStack {
                    Toggle("Show Measured Landmarks", isOn: $showMeasuredOverlay)
                        .accessibilityIdentifier("toggleMeasuredOverlaySwitch")
                }
                .padding(.horizontal)

                HStack {
                    Toggle("Show Alignment Reference", isOn: $showReference)
                        .accessibilityIdentifier("toggleReferenceSwitch")
                }
                .padding(.horizontal)

                if showReference {
                    HStack(spacing: 16) {
                        Picker("Style", selection: $selectedStyle) {
                            ForEach(ReferenceStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("referenceStylePicker")

                        Button(action: startReplayAnimation) {
                            Label("Replay", systemImage: "play.circle.fill")
                                .bold()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPlayingAnimation || reduceMotion || !(referenceResult?.isReplayAvailable ?? false))
                        .accessibilityIdentifier("replayButton")
                    }
                    .padding(.horizontal)

                    if reduceMotion {
                        Text("Motion reduced: Static alignment reference displayed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                }
            }

            // Legend
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("Measured Pose")
                        .font(.caption)
                        .bold()
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 10, height: 10)
                    Text("Alignment Reference")
                        .font(.caption)
                        .bold()
                }
            }
            .padding(8)
            .background(Color(uiColor: .tertiarySystemBackground))
            .cornerRadius(8)

            // Reference Info & Explanations
            if showReference {
                VStack(alignment: .leading, spacing: 8) {
                    let profile = referenceProvider.profile(for: view)
                    Text("Alignment Reference (\(profile.name) v\(profile.version))")
                        .font(.headline)

                    Text("A geometric illustration depicting potential alignment. Replay shows structural differences, not an exercise or prescribed movement sequence.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let result = referenceResult {
                        if let unavail = result.unavailabilityReason {
                            Text("Notice: \(unavail)")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }

                        if !result.staticReference.achievedChanges.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Represented Alignment Differences:")
                                    .font(.subheadline)
                                    .bold()
                                ForEach(result.staticReference.achievedChanges, id: \.self) { caption in
                                    Text("• " + caption)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
            }
        }
        .onAppear {
            computeReference()
        }
        .onChange(of: view) { _, _ in
            computeReference()
        }
        .onChange(of: pose) { _, _ in
            computeReference()
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private func computeReference() {
        animationTask?.cancel()
        isPlayingAnimation = false

        let generator = ReferencePoseGenerator()
        let profile = referenceProvider.profile(for: view)
        let result = generator.generateReference(for: pose, view: view, profile: profile)

        self.referenceResult = result
        self.displayedReferencePose = result.staticReference
    }

    private func startReplayAnimation() {
        guard let result = referenceResult, result.isReplayAvailable, !result.motionSequence.isEmpty else { return }

        animationTask?.cancel()
        isPlayingAnimation = true

        animationTask = Task { @MainActor in
            let sequence = result.motionSequence
            let frameDuration = 2.0 / Double(sequence.count) // Total 2 seconds

            for stepPose in sequence {
                if Task.isCancelled { break }
                self.displayedReferencePose = stepPose
                try? await Task.sleep(nanoseconds: UInt64(frameDuration * 1_000_000_000))
            }

            // Ensure ended at final static reference
            self.displayedReferencePose = result.staticReference
            self.isPlayingAnimation = false
        }
    }
}
