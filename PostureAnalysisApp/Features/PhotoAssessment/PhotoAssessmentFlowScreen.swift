import SwiftUI
import PhotosUI

enum PhotoAssessmentLaunchSource: Equatable {
    case chooser
    case camera
    case library
}

struct PhotoAssessmentFlowScreen: View {
    @Environment(\.appRepositories) private var appRepositories
    @Environment(\.dismiss) private var dismiss

    let referenceProvider: PostureReferenceProviding
    let service: any PostureAssessmentService
    let launchSource: PhotoAssessmentLaunchSource

    @AppStorage(PreferenceKey.cameraTiltCompensationEnabled) private var cameraTiltCompensationEnabled = true
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showLibraryPicker = false
    @State private var inputImage: UIImage?
    @State private var currentInputSource: ImageMetadata.ImageSource?
    @State private var isProcessing = false
    @State private var currentAssessment: PostureAssessment?
    @State private var processingTime: TimeInterval = 0
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var showEditLandmarks = false
    @State private var showDebugView = false
    @State private var selectedView: PostureView

    init(
        initialView: PostureView = .uncertain,
        launchSource: PhotoAssessmentLaunchSource = .chooser,
        referenceProvider: PostureReferenceProviding = DefaultPostureReferenceProvider(),
        service: (any PostureAssessmentService)? = nil
    ) {
        self.referenceProvider = referenceProvider
        self.service = service ?? LivePostureAssessmentService(estimator: AppleVisionPoseEstimator())
        self.launchSource = launchSource
        _selectedView = State(initialValue: initialView)
    }

    var body: some View {
        Group {
            if isProcessing {
                VStack(spacing: 16) {
                    ProgressView("Analyzing Posture...")
                        .scaleEffect(1.2)
                    Text("Detecting body landmarks on device...")
                        .font(.caption)
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let assessment = currentAssessment, let image = inputImage {
                resultScreen(assessment: assessment, image: image)
            } else {
                sourcePicker
            }
        }
        .background(ColorTokens.palette().backgroundPrimary.ignoresSafeArea())
        .photosPicker(isPresented: $showLibraryPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .onAppear {
            switch launchSource {
            case .chooser: break
            case .camera: showCamera = true
            case .library: showLibraryPicker = true
            }
        }
        .navigationTitle(currentAssessment == nil ? "Photo Assessment" : "Assessment Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(currentAssessment != nil)
        .toolbar {
            if currentAssessment != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: closeCurrentAssessment)
                        .accessibilityIdentifier("closeAssessmentButton")
                        .accessibilityHint("Returns to Posture without saving the assessment")
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { capturedImage, isCamera, reading in
                processImage(capturedImage, isCamera: isCamera, horizonReading: reading)
            }
        }
        .sheet(isPresented: $showEditLandmarks) {
            if let assessment = currentAssessment, let image = inputImage {
                LandmarkEditingView(
                    pose: Binding(
                        get: { currentAssessment?.pose ?? assessment.pose },
                        set: { updatedPose in reanalyze(with: assessment.view, customPose: updatedPose) }
                    ),
                    image: image,
                    onSave: { updatedPose in
                        reanalyze(with: assessment.view, customPose: updatedPose)
                        showEditLandmarks = false
                    },
                    onCancel: { showEditLandmarks = false }
                )
            }
        }
        .sheet(isPresented: $showDebugView) {
            if let assessment = currentAssessment {
                DeveloperDebugView(assessment: assessment, processingDuration: processingTime)
            }
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.stand")
                .font(.system(size: 54, weight: .medium, design: .rounded))
                .foregroundStyle(ColorTokens.palette().tabPostureActive)
            Text("Choose a standing photo")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
            Text("Use a full-body front or side view. Photos are analyzed on this iPhone.")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(ColorTokens.palette().danger)
                    .padding()
                    .background(ColorTokens.palette().danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }
            Spacer()
            VStack(spacing: 12) {
                Button { showCamera = true } label: {
                    Label("Take Standing Photo", systemImage: "camera")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(.white)
                        .background(GradientTokens.posture, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("takePhotoButton")

                Button { showLibraryPicker = true } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .background(ColorTokens.palette().backgroundCard, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("choosePhotoButton")
            }
            .padding(.horizontal, Metrics.Spacing.screenMargin)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultScreen(assessment: PostureAssessment, image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                PostureReportView(
                    image: image,
                    pose: assessment.pose,
                    view: assessment.view,
                    measurements: assessment.measurements,
                    horizonContext: assessment.horizonContext,
                    referenceProvider: referenceProvider
                )

                if currentInputSource == .camera, assessment.horizonContext != nil {
                    Toggle("Compensate camera tilt", isOn: Binding(
                        get: { currentAssessment?.horizonContext?.isCompensationApplied ?? false },
                        set: { newValue in
                            currentAssessment?.horizonContext?.isCompensationApplied = newValue
                            reanalyze(with: assessment.view)
                        }
                    ))
                    .padding(.horizontal)
                    .accessibilityIdentifier("compensateCameraTiltToggle")
                } else if currentInputSource == .camera {
                    Text("Camera horizon was unavailable. Measurements use the image axes without tilt compensation.")
                        .font(.footnote)
                        .foregroundStyle(ColorTokens.palette().warning)
                        .padding(.horizontal)
                } else {
                    Text("Camera tilt was not evaluated for library photos.")
                        .font(.footnote)
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .padding(.horizontal)
                }

                HStack {
                    Text("View:")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                    Picker("View", selection: Binding(
                        get: { assessment.view },
                        set: { reanalyze(with: $0) }
                    )) {
                        ForEach(PostureView.allCases) { view in
                            Text(view.displayName).tag(view)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("postureViewPicker")

                    Spacer()

                    Button { showEditLandmarks = true } label: {
                        Label("Edit Points", systemImage: "pencil.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("editLandmarksButton")
                }
                .padding(.horizontal)

                if !assessment.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Image Quality Warnings", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(ColorTokens.palette().warning)
                        ForEach(assessment.warnings, id: \.self) { warning in
                            Text("• " + warning)
                                .font(.footnote)
                                .foregroundStyle(ColorTokens.palette().textSecondary)
                        }
                    }
                    .padding()
                    .background(ColorTokens.palette().warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                Text("Measurements are geometric observations from this photo.")
                    .font(.caption)
                    .foregroundStyle(ColorTokens.palette().textSubtle)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Objective Measurements")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)

                    ForEach(assessment.measurements) { measurement in
                        let feedback = MeasurementFeedbackEvaluator().feedback(
                            for: measurement,
                            view: assessment.view,
                            profile: referenceProvider.profile(for: assessment.view)
                        )
                        PostureMeasurementCard(
                            measurement: measurement,
                            feedback: feedback,
                            explanation: MeasurementPresentation.explanation(measurement),
                            reading: MeasurementPresentation.reading(
                                measurement,
                                pose: assessment.pose,
                                view: assessment.view,
                                horizonContext: assessment.horizonContext
                            )
                        )
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button(action: saveCurrentAssessment) {
                        Label("Save Assessment", systemImage: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .foregroundStyle(.white)
                            .background(GradientTokens.posture, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("saveAssessmentButton")

                    Button { showDebugView = true } label: {
                        Image(systemName: "ladybug")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("developerDebugButton")
                }
                .padding(.horizontal)
                .padding(.bottom, 18)
            }
        }
        .scrollIndicators(.hidden)
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            if item != nil { errorMessage = "The selected photo could not be opened." }
            return
        }
        processImage(image)
    }

    private func processImage(_ image: UIImage, isCamera: Bool = false, horizonReading: HorizonReading? = nil) {
        let normalizedImage = ImageNormalizer.normalizeToUpright(image)
        guard let cgImage = normalizedImage.cgImage else {
            errorMessage = "The selected photo could not be opened."
            return
        }
        inputImage = normalizedImage
        currentInputSource = isCamera ? .camera : .photoLibrary
        isProcessing = true
        errorMessage = nil
        let startTime = CFAbsoluteTimeGetCurrent()
        let horizonContext: HorizonContext? = {
            guard isCamera, let horizonReading else { return nil }
            return HorizonContext(
                angleDegrees: horizonReading.angleDegrees,
                source: .deviceMotion,
                isCompensationApplied: cameraTiltCompensationEnabled
            )
        }()
        let metadata = ImageMetadata(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height),
            source: isCamera ? .camera : .photoLibrary
        )
        let requestedView = selectedView == .uncertain ? nil : selectedView

        Task {
            do {
                let assessment = try await service.analyze(
                    in: cgImage,
                    metadata: metadata,
                    selectedView: requestedView,
                    horizonContext: horizonContext
                )
                await MainActor.run {
                    processingTime = CFAbsoluteTimeGetCurrent() - startTime
                    currentAssessment = assessment
                    self.selectedView = assessment.view
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to process photo: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }

    private func reanalyze(with newView: PostureView, customPose: BodyPose? = nil) {
        guard let image = inputImage, let cgImage = image.cgImage else { return }
        let pose = customPose ?? currentAssessment?.pose ?? BodyPose(
            landmarks: [:],
            imageWidth: CGFloat(cgImage.width),
            imageHeight: CGFloat(cgImage.height)
        )
        let metadata = ImageMetadata(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height),
            source: currentInputSource ?? .photoLibrary
        )
        var updated = PostureAnalyzer().analyze(
            pose: pose,
            imageMetadata: metadata,
            view: newView,
            horizonContext: currentAssessment?.horizonContext
        )
        updated.pose = pose
        currentAssessment = updated
        selectedView = newView
    }

    private func closeCurrentAssessment() {
        showEditLandmarks = false
        showDebugView = false
        currentAssessment = nil
        inputImage = nil
        currentInputSource = nil
        selectedPhotoItem = nil
        processingTime = 0
        errorMessage = nil
        dismiss()
    }

    private func saveCurrentAssessment() {
        guard let assessment = currentAssessment, let image = inputImage else { return }
        guard let appRepositories else {
            errorMessage = "Failed to save assessment: local storage is unavailable."
            return
        }
        do {
            let relativePath = try appRepositories.images.saveImage(image)
            try appRepositories.assessments.save(assessment, imageRelativePath: relativePath)
            closeCurrentAssessment()
        } catch {
            errorMessage = "Failed to save assessment: \(error.localizedDescription)"
        }
    }
}
