import SwiftUI
import UIKit

/// Workout Coach (Beta): mirrored selfie preview, focus-joint overlay, rep counter, and spoken coaching.
struct WorkoutCoachView: View {
    static let coordinateSpace = "workoutOverlay"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = WorkoutCoachModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.cameraStatus {
            case .notAuthorized:
                unauthorizedView
            case .failed(let message):
                failureView(message: message)
            default:
                workoutContent
            }

            if model.session.phase == .ended {
                WorkoutSummaryView(session: model.session, onDone: close)
            }
        }
        .onAppear {
            // Hands-free use depends on the screen staying awake.
            UIApplication.shared.isIdleTimerDisabled = true
            model.onAppear(isApplicationActive: scenePhase != .background)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.onDisappear()
        }
        .onChange(of: scenePhase) { _, phase in
            model.setApplicationActive(phase != .background)
        }
    }

    private var workoutContent: some View {
        GeometryReader { geo in
            ZStack {
                RealtimeCameraPreview(session: model.captureSession, isMirrored: true)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    .clipped()

                if let overlay = model.overlay {
                    WorkoutJointOverlayView(overlay: overlay)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                WorkoutHUDView(
                    session: model.session,
                    now: model.now,
                    onClose: close,
                    onCommand: { model.send($0) }
                )
            }
            .coordinateSpace(name: Self.coordinateSpace)
        }
    }

    private func close() {
        model.onDisappear()
        dismiss()
    }

    // MARK: - Unauthorized & Failure

    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("Camera Access Required")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            Text("Enable camera access in Settings so the coach can count your reps. Frames are analyzed on this iPhone and never recorded.")
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

                Button("Close", action: close)
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
            Button("Close", action: close)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Shown after "end workout": completed sets per exercise.
private struct WorkoutSummaryView: View {
    let session: WorkoutSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Workout Summary")
                .font(.title2.bold())
            let finished = session.exercises.filter { !(session.progress[$0.id]?.setReps.isEmpty ?? true) }
            if finished.isEmpty {
                Text("No sets recorded.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(finished) { exercise in
                        let reps = session.progress[exercise.id]?.setReps ?? []
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.displayName)
                                .font(.headline)
                            Text(reps.enumerated().map { "Set \($0.offset + 1): \($0.element)" }.joined(separator: " · "))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Rep counts are geometric estimates from the camera, not medical or performance assessments.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("workoutSummaryDoneButton")
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(24)
    }
}
