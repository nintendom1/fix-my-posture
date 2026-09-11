import SwiftUI

/// Shared visualization component for posture reports (new analysis and saved assessment screens).
public struct PostureReportView: View {
    public let image: UIImage?
    public let pose: BodyPose
    public var sourcePose: BodyPose?
    public let view: PostureView
    public let measurements: [PostureMeasurement]
    public let referenceProvider: PostureReferenceProviding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showMeasuredOverlay: Bool = true
    @State private var showReference: Bool = false
    @State private var showTargets = true
    @State private var showCallouts: Bool = true
    @State private var selectedStyle: ReferenceStyle = .combined

    @State private var referenceResult: ReferenceGenerationResult? = nil
    @State private var displayedReferencePose: ReferencePose? = nil

    @State private var isPlayingAnimation = false
    @State private var replayRequest: UUID? = nil

    public init(
        image: UIImage?,
        pose: BodyPose,
        view: PostureView,
        measurements: [PostureMeasurement] = [],
        sourcePose: BodyPose? = nil,
        referenceProvider: PostureReferenceProviding = DefaultPostureReferenceProvider()
    ) {
        self.image = image
        self.pose = pose
        self.sourcePose = sourcePose
        self.view = view
        self.measurements = measurements
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
                                containerSize: geo.size,
                                feedback: MeasurementPresentation.jointFeedback(measurements: measurements, pose: pose,
                                    view: view, profile: referenceProvider.profile(for: view))
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

                        if showTargets, let target = referenceResult?.staticReference {
                            AlignmentTargetOverlayView(reference: target, imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight))
                        }

                        if showCallouts, !measurements.isEmpty {
                            PostureCalloutOverlayView(
                                measurements: measurements,
                                pose: pose,
                                view: view,
                                profile: referenceProvider.profile(for: view),
                                sourcePose: sourcePose,
                                targetRects: showTargets ? AlignmentTargetOverlayView.rects(reference: referenceResult?.staticReference,
                                    imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight), containerSize: geo.size) : []
                            )
                        }
                    }
                }
                .frame(height: min(max(UIScreen.main.bounds.height - 180, 350), 700))
            }

            // Controls Section
            VStack(spacing: 12) {
                Toggle("Alignment targets", isOn: $showTargets).padding(.horizontal)
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

                HStack {
                    Toggle("Show Measurement Callouts", isOn: $showCallouts)
                        .accessibilityIdentifier("toggleMeasurementCalloutsSwitch")
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

            Text(MeasurementPresentation.convention).font(.caption).padding(.horizontal)

            // Legend
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("Measured Landmarks")
                        .font(.caption)
                        .bold()
                }

                HStack(spacing: 6) {
                    Circle()
                        .stroke(Color.purple, lineWidth: 2)
                        .frame(width: 10, height: 10)
                    Text("Alignment targets")
                        .font(.caption)
                        .bold()
                }
            }
            .padding(8)
            .background(Color(uiColor: .tertiarySystemBackground))
            .cornerRadius(8)

            // Reference Info & Explanations
            if showReference || showTargets {
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
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion { computeReference() }
        }
        .task(id: replayRequest) {
            guard replayRequest != nil, let result = referenceResult, result.isReplayAvailable, !result.motionSequence.isEmpty else { return }

            isPlayingAnimation = true
            let sequence = result.motionSequence
            let frameDuration = 2.0 / Double(max(sequence.count - 1, 1))

            for (index, stepPose) in sequence.enumerated() {
                guard !Task.isCancelled else { return }
                displayedReferencePose = stepPose
                if index < sequence.count - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(frameDuration * 1_000_000_000))
                }
            }

            guard !Task.isCancelled else { return }
            displayedReferencePose = result.staticReference
            isPlayingAnimation = false
        }
    }

    private func computeReference() {
        replayRequest = nil
        isPlayingAnimation = false

        let generator = ReferencePoseGenerator()
        let profile = referenceProvider.profile(for: view)
        let raw = generator.generateReference(for: sourcePose ?? pose, view: view, profile: profile)
        func display(_ reference: ReferencePose) -> ReferencePose {
            guard let sourcePose else { return reference }
            var result = reference
            result.jointLocations = reference.jointLocations.mapValues { point in
                let norm = CoordinateConverter.imagePixelToNormalized(pixel: point, imageWidth: sourcePose.imageWidth, imageHeight: sourcePose.imageHeight)
                let mapped = ImageNormalizer.mapNormalizedToOrientation(norm, orientation: image?.imageOrientation ?? .up, clampToImage: false)
                return CoordinateConverter.normalizedToImagePixel(normalized: mapped, imageWidth: pose.imageWidth, imageHeight: pose.imageHeight)
            }
            return result
        }
        let result = ReferenceGenerationResult(staticReference: display(raw.staticReference),
            motionSequence: raw.motionSequence.map(display), isReplayAvailable: raw.isReplayAvailable,
            unavailabilityReason: raw.unavailabilityReason)

        self.referenceResult = result
        self.displayedReferencePose = result.staticReference
    }

    private func startReplayAnimation() {
        guard let result = referenceResult, result.isReplayAvailable, !result.motionSequence.isEmpty else { return }
        replayRequest = UUID()
    }
}
