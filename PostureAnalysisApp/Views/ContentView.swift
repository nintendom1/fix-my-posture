import SwiftUI
import SwiftData
import PhotosUI

public struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var inputImage: UIImage? = nil
    @State private var isProcessing = false
    @State private var currentAssessment: PostureAssessment? = nil
    @State private var processingTime: TimeInterval = 0.0
    @State private var showOverlay: Bool = true
    @State private var errorMessage: String? = nil

    @State private var showCamera = false
    @State private var showEditLandmarks = false
    @State private var showDebugView = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isProcessing {
                    VStack(spacing: 16) {
                        ProgressView("Analyzing Posture...")
                            .scaleEffect(1.2)
                        Text("Detecting body landmarks on device...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let assessment = currentAssessment, let image = inputImage {
                    // Assessment Result View
                    ScrollView {
                        VStack(spacing: 16) {
                            GeometryReader { geo in
                                ZStack {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(12)

                                    if showOverlay {
                                        LandmarkOverlayView(
                                            pose: assessment.pose,
                                            containerSize: geo.size
                                        )
                                    }
                                }
                            }
                            .frame(height: 350)

                            Toggle("Show Overlay Points", isOn: $showOverlay)
                                .padding(.horizontal)
                                .accessibilityIdentifier("toggleOverlaySwitch")

                            HStack {
                                Text("View:")
                                    .bold()
                                Picker("View", selection: Binding(
                                    get: { assessment.view },
                                    set: { newView in
                                        reanalyze(with: newView)
                                    }
                                )) {
                                    ForEach(PostureView.allCases) { v in
                                        Text(v.displayName).tag(v)
                                    }
                                }
                                .pickerStyle(.menu)
                                .accessibilityIdentifier("postureViewPicker")

                                Spacer()

                                Button(action: { showEditLandmarks = true }) {
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
                                        .foregroundColor(.orange)
                                    ForEach(assessment.warnings, id: \.self) { warning in
                                        Text("• " + warning)
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }

                            Text("Notice: Measurements are geometric estimations and not a medical diagnosis.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Objective Measurements")
                                    .font(.title3)
                                    .bold()

                                ForEach(assessment.measurements) { m in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(m.name)
                                                .font(.headline)
                                            Spacer()
                                            Text("\(String(format: "%.1f", m.value))\(m.unit)")
                                                .bold()
                                                .foregroundColor(.blue)
                                        }
                                        Text(m.explanation)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)

                            HStack(spacing: 16) {
                                Button(action: saveCurrentAssessment) {
                                    Label("Save Assessment", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("saveAssessmentButton")

                                Button(action: { showDebugView = true }) {
                                    Image(systemName: "ladybug")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("developerDebugButton")
                            }
                            .padding()
                        }
                    }
                } else {
                    // Home Screen
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: "figure.walk.motion")
                            .font(.system(size: 80))
                            .foregroundColor(.accentColor)

                        Text("Standing Posture Analysis")
                            .font(.title)
                            .bold()

                        Text("Analyze body landmarks, geometric alignment, and track posture metrics over time.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        if let error = errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.horizontal)
                        }

                        Spacer()

                        VStack(spacing: 14) {
                            Button(action: { showCamera = true }) {
                                Label("Take Standing Photo", systemImage: "camera")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .accessibilityIdentifier("takePhotoButton")

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .accessibilityIdentifier("choosePhotoButton")
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let uiImg = UIImage(data: data) {
                                        processImage(uiImg)
                                    }
                                }
                            }

                            NavigationLink(destination: HistoryView()) {
                                Label("View History", systemImage: "clock.arrow.circlepath")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .cornerRadius(12)
                            }
                            .accessibilityIdentifier("viewHistoryButton")
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Posture Analyzer")
            .sheet(isPresented: $showCamera) {
                CameraPickerView { capturedImage in
                    processImage(capturedImage)
                }
            }
            .sheet(isPresented: $showEditLandmarks) {
                if let assessment = currentAssessment, let image = inputImage {
                    LandmarkEditingView(
                        pose: Binding(
                            get: { assessment.pose },
                            set: { updatedPose in
                                currentAssessment?.pose = updatedPose
                                reanalyze(with: assessment.view, customPose: updatedPose)
                            }
                        ),
                        image: image,
                        onSave: { updatedPose in
                            currentAssessment?.pose = updatedPose
                            reanalyze(with: assessment.view, customPose: updatedPose)
                            showEditLandmarks = false
                        },
                        onCancel: {
                            showEditLandmarks = false
                        }
                    )
                }
            }
            .sheet(isPresented: $showDebugView) {
                if let assessment = currentAssessment {
                    DeveloperDebugView(assessment: assessment, processingDuration: processingTime)
                }
            }
        }
    }

    private func processImage(_ image: UIImage) {
        guard let cgImg = image.cgImage else { return }
        inputImage = image
        isProcessing = true
        errorMessage = nil
        let startTime = CFAbsoluteTimeGetCurrent()

        Task {
            let estimator = AppleVisionPoseEstimator()
            do {
                let pose = try await estimator.estimatePose(in: cgImg)
                let meta = ImageMetadata(width: CGFloat(cgImg.width), height: CGFloat(cgImg.height))
                let detectedView = ViewClassifier.classify(pose: pose)

                let analyzer = PostureAnalyzer()
                let assessment = analyzer.analyze(pose: pose, imageMetadata: meta, view: detectedView)

                await MainActor.run {
                    self.processingTime = CFAbsoluteTimeGetCurrent() - startTime
                    self.currentAssessment = assessment
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to process photo: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    private func reanalyze(with newView: PostureView, customPose: BodyPose? = nil) {
        guard let image = inputImage, let cgImg = image.cgImage else { return }
        let poseToUse = customPose ?? currentAssessment?.pose ?? BodyPose(landmarks: [:], imageWidth: CGFloat(cgImg.width), imageHeight: CGFloat(cgImg.height))
        let meta = ImageMetadata(width: CGFloat(cgImg.width), height: CGFloat(cgImg.height))

        let analyzer = PostureAnalyzer()
        var updated = analyzer.analyze(pose: poseToUse, imageMetadata: meta, view: newView)
        updated.pose = poseToUse
        self.currentAssessment = updated
    }

    private func saveCurrentAssessment() {
        guard let assessment = currentAssessment, let image = inputImage else { return }
        do {
            let relPath = try ImageStore.shared.saveImage(image)

            let entity = AssessmentEntity(
                id: assessment.id,
                date: assessment.date,
                imageRelativePath: relPath,
                viewRawValue: assessment.view.rawValue,
                isBaseline: assessment.isBaseline,
                appVersion: assessment.appVersion,
                imageWidth: Double(assessment.pose.imageWidth),
                imageHeight: Double(assessment.pose.imageHeight)
            )

            for (type, lm) in assessment.pose.landmarks {
                let lmEntity = LandmarkEntity(
                    typeRawValue: type.rawValue,
                    normalizedX: lm.normalizedLocation.x,
                    normalizedY: lm.normalizedLocation.y,
                    imageX: lm.imageLocation.x,
                    imageY: lm.imageLocation.y,
                    confidence: lm.confidence,
                    isManuallyCorrected: lm.isManuallyCorrected
                )
                entity.landmarks.append(lmEntity)
            }

            for m in assessment.measurements {
                let mEntity = MeasurementEntity(
                    measurementIDRawValue: m.measurementID.rawValue,
                    name: m.name,
                    value: m.value,
                    unit: m.unit,
                    landmarksUsedRaw: m.landmarksUsed.map { $0.rawValue }.joined(separator: ","),
                    confidence: m.confidence,
                    explanation: m.explanation
                )
                entity.measurements.append(mEntity)
            }

            modelContext.insert(entity)
            try modelContext.save()

            self.currentAssessment = nil
            self.inputImage = nil
        } catch {
            self.errorMessage = "Failed to save assessment: \(error.localizedDescription)"
        }
    }
}
