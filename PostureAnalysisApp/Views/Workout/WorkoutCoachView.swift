import SwiftUI
import UIKit

/// Workout Coach (Beta): mirrored selfie preview, focus-joint overlay, rep counter, and spoken coaching.
struct WorkoutCoachView: View {
    static let coordinateSpace = "workoutOverlay"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: WorkoutCoachModel
    @AppStorage("workoutCoach.showMeasurements") private var showMeasurements = false
    @State private var showGuide = false
    /// Open the Voice Commands help once the guide finishes dismissing.
    @State private var showVoiceCommandsAfterGuide = false
    /// Top and bottom HUD frames, which tips keep clear of.
    @State private var hudRects: [CGRect] = []

    init(initialExercise: ExerciseID? = nil) {
        _model = StateObject(wrappedValue: WorkoutCoachModel(initialExercise: initialExercise))
    }

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

            // Ending from the completion card exits directly; it already showed the results.
            if model.session.phase == .ended, !model.session.endedAfterCompletion {
                WorkoutSummaryView(session: model.session, onDone: close)
            }
        }
        .onAppear {
            // Hands-free use depends on the screen staying awake.
            UIApplication.shared.isIdleTimerDisabled = true
            // A first-time guide opens before capture, so no permission prompt covers it.
            presentGuideIfUnseen()
            model.onAppear(isApplicationActive: scenePhase != .background)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.onDisappear()
        }
        .onChange(of: scenePhase) { _, phase in
            model.setApplicationActive(phase != .background)
        }
        .onChange(of: model.session.exerciseID) { _, _ in
            presentGuideIfUnseen()
        }
        .onChange(of: model.session.phase) { _, phase in
            if phase == .ended, model.session.endedAfterCompletion { close() }
        }
        .sheet(isPresented: $showGuide, onDismiss: guideDismissed) {
            if let exercise = model.session.exercise {
                ExerciseGuideView(
                    exercise: exercise,
                    hasStarted: model.hasOpened,
                    isSpeaking: model.isCoachSpeaking,
                    onReadAloud: { model.readGuideAloud() },
                    onStopReading: { model.stopSpeaking() },
                    onShowVoiceCommands: {
                        showVoiceCommandsAfterGuide = true
                        showGuide = false
                    },
                    onDone: { showGuide = false }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: Binding(get: { model.isHelpPresented }, set: { model.setHelpPresented($0) })) {
            VoiceCommandsHelpView(
                sections: VoiceCommandHelp.sections(exercises: model.exercises),
                suggestions: VoiceCommandHelp.entries(for: model.session.suggestedCommands, exercises: model.exercises),
                micStatus: model.micStatus,
                isMicMuted: model.isMicMuted,
                isCoachMuted: model.isCoachMuted,
                onSetMicMuted: { model.setMicMuted($0) },
                onSetCoachMuted: { model.setCoachMuted($0) },
                progressLine: progressLine,
                onRetry: { model.retryVoice() },
                onDone: { model.setHelpPresented(false) }
            )
            .presentationDetents([.large])
        }
    }

    private var workoutContent: some View {
        GeometryReader { geo in
            ZStack {
                RealtimeCameraPreview(session: model.captureSession, isMirrored: true)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    .clipped()

                switch model.session.phase {
                case .ready:
                    if let overlay = model.overlay, let metrics = model.guideMetrics, let exercise = model.session.exercise {
                        WorkoutGhostOverlayView(overlay: overlay, metrics: metrics, motion: exercise.guide.motion)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                case .exercising, .paused:
                    if let overlay = model.overlay {
                        RepThresholdOverlayView(thresholds: model.armThresholds, imageSize: overlay.imageSize)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                default:
                    EmptyView()
                }

                if let overlay = model.overlay {
                    WorkoutJointOverlayView(overlay: overlay)
                        .frame(width: geo.size.width, height: geo.size.height)
                    if model.startHoldProgress() != nil {
                        HoldProgressRingView(overlay: overlay, progress: { model.startHoldProgress() })
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }

                WorkoutTipOverlayView(tip: model.activeTip, protectedRects: tipProtectedRects(in: geo.size), hudRects: hudRects)
                    .frame(width: geo.size.width, height: geo.size.height)

                WorkoutHUDView(
                    session: model.session,
                    now: model.now,
                    readings: model.armReadings,
                    formReadings: model.formReadings,
                    isPhoneTilted: model.isPhoneTilted,
                    micStatus: model.micStatus,
                    heardPhrase: model.heardPhrase,
                    showMeasurements: $showMeasurements,
                    onClose: close,
                    onShowGuide: presentGuide,
                    isCoachMuted: model.isCoachMuted,
                    onMicrophoneTap: { model.microphoneTapped() },
                    onToggleCoachVoice: { model.setCoachMuted(!model.isCoachMuted) },
                    onShowVoiceCommands: { model.setHelpPresented(true) },
                    onCommand: { model.send($0) }
                )

                if model.session.phase == .exerciseComplete {
                    ExerciseCompleteCard(session: model.session,
                                         onAnotherRound: { model.send(.anotherRound) },
                                         onChooseExercise: { model.send(.changeExercise) },
                                         onEndWorkout: { model.send(.endWorkout) })
                        .transition(.opacity)
                }

                if case .changingExercise = model.session.phase {
                    ExerciseChooserOverlay(session: model.session, voiceActive: model.session.voiceControlActive,
                                           onSelect: { model.send(.selectExercise($0)) },
                                           onCancel: { model.send(.cancel) })
                }
            }
            .coordinateSpace(name: Self.coordinateSpace)
            .onPreferenceChange(WorkoutHUDRects.self) { hudRects = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.session.phase == .exerciseComplete)
        }
    }

    /// The body and the exercise's motion envelope, computed only while a tip is up.
    private func tipProtectedRects(in size: CGSize) -> [CGRect] {
        guard model.activeTip != nil, let overlay = model.overlay else { return [] }
        let envelope = model.session.exercise.flatMap {
            WorkoutTipLayout.envelopeRect($0.motionEnvelope, overlay: overlay, metrics: model.guideMetrics, containerSize: size)
        }
        return WorkoutTipLayout.protectedRects(pose: overlay.pose, envelope: envelope, containerSize: size)
    }

    private func close() {
        model.onDisappear()
        dismiss()
    }

    // MARK: - Guide

    private func presentGuide() {
        guard model.session.exercise != nil else { return }
        model.setGuidePresented(true)
        showGuide = true
    }

    private func presentGuideIfUnseen() {
        guard !showGuide, let id = model.session.exerciseID, !WorkoutGuidePreferences.hasSeen(id) else { return }
        presentGuide()
    }

    private func guideDismissed() {
        if let id = model.session.exerciseID { WorkoutGuidePreferences.markSeen(id) }
        model.setGuidePresented(false)
        if showVoiceCommandsAfterGuide {
            showVoiceCommandsAfterGuide = false
            model.setHelpPresented(true)
        }
    }

    /// Live set progress for the help header, since counting continues behind it.
    private var progressLine: String? {
        let session = model.session
        guard let exercise = session.exercise else { return nil }
        switch session.phase {
        case .exercising, .paused:
            return "Set \(session.currentSetNumber) of \(exercise.sets) \u{00B7} \(session.repCount) reps"
        case .resting:
            return session.restRemaining(at: model.now).map { "Resting \u{00B7} \(WorkoutHUDView.format($0))" }
        default:
            return nil
        }
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

/// Remembers which exercise guides were shown, so returning users go straight to setup.
enum WorkoutGuidePreferences {
    private static func key(_ id: ExerciseID) -> String { "workoutCoach.guideSeen.\(id.rawValue)" }

    static func hasSeen(_ id: ExerciseID) -> Bool {
        UserDefaults.standard.bool(forKey: key(id))
    }

    static func markSeen(_ id: ExerciseID) {
        UserDefaults.standard.set(true, forKey: key(id))
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
