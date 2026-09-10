import SwiftUI

public struct LandmarkEditingView: View {
    @Binding var pose: BodyPose
    public let image: UIImage
    public var onSave: (BodyPose) -> Void
    public var onCancel: () -> Void

    @State private var originalPose: BodyPose
    @State private var selectedLandmark: LandmarkType? = nil

    public init(pose: Binding<BodyPose>, image: UIImage, onSave: @escaping (BodyPose) -> Void, onCancel: @escaping () -> Void) {
        self._pose = pose
        self.image = image
        self.onSave = onSave
        self.onCancel = onCancel
        self._originalPose = State(initialValue: pose.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            VStack {
                Text("Tap landmark to select, drag to reposition")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()

                        LandmarkOverlayView(
                            pose: pose,
                            containerSize: geo.size,
                            selectedLandmark: selectedLandmark,
                            onSelectLandmark: { type in
                                selectedLandmark = type
                            }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard let type = selectedLandmark, var landmark = pose[type] else { return }
                                    let imgSize = CGSize(width: pose.imageWidth, height: pose.imageHeight)

                                    // Use CoordinateConverter for aspect-fitted container touch mapping
                                    let normPt = CoordinateConverter.containerToNormalized(
                                        touchPoint: value.location,
                                        imageSize: imgSize,
                                        containerSize: geo.size
                                    )

                                    landmark.normalizedLocation = normPt
                                    landmark.imageLocation = CoordinateConverter.normalizedToImagePixel(
                                        normalized: normPt,
                                        imageWidth: pose.imageWidth,
                                        imageHeight: pose.imageHeight
                                    )
                                    landmark.isManuallyCorrected = true

                                    pose[type] = landmark
                                }
                        )
                    }
                }
                .padding()

                // Control bar
                HStack(spacing: 20) {
                    if let selected = selectedLandmark {
                        Button(action: {
                            if let orig = originalPose[selected] {
                                pose[selected] = orig
                            }
                        }) {
                            Label("Reset \(selected.displayName)", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("resetSingleLandmarkButton")
                    }

                    Button(role: .destructive, action: {
                        pose = originalPose
                    }) {
                        Label("Reset All", systemImage: "arrow.counterclockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("resetAllLandmarksButton")
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("Edit Landmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pose = originalPose
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(pose)
                    }
                    .bold()
                    .accessibilityIdentifier("doneEditLandmarksButton")
                }
            }
        }
    }
}
