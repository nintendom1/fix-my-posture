import SwiftUI
import UIKit

/// Workout Coach (Beta): mirrored selfie preview, focus-joint overlay, rep counter, and spoken coaching.
struct WorkoutCoachView: View {
    static let coordinateSpace = "workoutOverlay"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appRepositories) private var appRepositories
    @Environment(\.preferences) private var preferences
    @State private var model: any WorkoutCoachViewModeling
    /// Open the Voice Commands help once the guide finishes dismissing.
    @State private var showVoiceCommandsAfterGuide = false
    /// Top and bottom HUD frames, which tips keep clear of.
    @State private var hudRects: [CGRect] = []
    @State private var startedAt = Date()
    @State private var historySaved = false

    init(model: any WorkoutCoachViewModeling) {
        _model = State(initialValue: model)
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
            guard phase == .ended else { return }
            saveHistory()
            if model.session.endedAfterCompletion { close() }
        }
        .sheet(isPresented: Binding(get: { model.isGuidePresented },
                                    set: { routeIntent($0 ? .showGuide : .hideGuide) }),
               onDismiss: guideDismissed) {
            if let exercise = model.session.exercise {
                ExerciseGuideView(
                    exercise: exercise,
                    hasStarted: model.hasOpened,
                    isSpeaking: model.isCoachSpeaking,
                    onReadAloud: { routeIntent(.readGuideAloud) },
                    onStopReading: { routeIntent(.stopSpeaking) },
                    onShowVoiceCommands: {
                        showVoiceCommandsAfterGuide = true
                        routeIntent(.hideGuide)
                    },
                    onDone: { routeIntent(.hideGuide) }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: Binding(get: { model.isHelpPresented },
                                    set: { routeIntent($0 ? .showVoiceHelp : .hideVoiceHelp) })) {
            VoiceCommandsHelpView(
                sections: VoiceCommandHelp.sections(exercises: model.exercises),
                suggestions: VoiceCommandHelp.entries(for: model.session.suggestedCommands, exercises: model.exercises),
                micStatus: model.micStatus,
                isMicMuted: model.isMicMuted,
                isCoachMuted: model.isCoachMuted,
                onSetMicMuted: { routeIntent(.setMicrophoneMuted($0)) },
                onSetCoachMuted: { routeIntent(.setCoachMuted($0)) },
                progressLine: model.hud.presentation.progressLine,
                onRetry: { routeIntent(.retryVoice) },
                onOpenSettings: { routeIntent(.openSettings) },
                onDone: { routeIntent(.hideVoiceHelp) }
            )
            .presentationDetents([.large])
        }
    }

    private var workoutContent: some View {
        GeometryReader { geo in
            ZStack {
                if let captureSession = model.captureSession {
                    RealtimeCameraPreview(session: captureSession, isMirrored: true)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                        .clipped()
                }

                if let overlay = model.overlay {
                    if model.hud.visual.overlay == .ghostDemo,
                       let metrics = model.guideMetrics,
                       let exercise = model.session.exercise {
                        WorkoutGhostOverlayView(overlay: overlay, metrics: metrics, motion: exercise.guide.motion,
                                                cameraView: exercise.cameraView)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    if model.hud.visual.overlay == .repThresholds {
                        RepThresholdOverlayView(thresholds: model.hud.thresholds, imageSize: overlay.imageSize)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
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

                WorkoutHUDView(state: model.hud, send: sendHUDIntent)

                if model.hud.visual.showsCompletionCard {
                    ExerciseCompleteCard(session: model.session,
                                         onAnotherRound: { routeIntent(.anotherRound) },
                                         onChooseExercise: { routeIntent(.changeExercise) },
                                         onEndWorkout: { routeIntent(.endWorkout) })
                        .transition(.opacity)
                }

                if model.hud.visual.showsExerciseChooser {
                    ExerciseChooserOverlay(session: model.session, voiceActive: model.session.voiceControlActive,
                                           onSelect: { routeIntent(.chooseExercise($0)) },
                                           onCancel: { routeIntent(.cancelExerciseChange) })
                }
            }
            .coordinateSpace(name: Self.coordinateSpace)
            .onPreferenceChange(WorkoutHUDRects.self) { hudRects = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.hud.visual.showsCompletionCard)
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
        // Closing without ending still keeps any finished sets.
        saveHistory()
        routeIntent(.closeWorkout)
        dismiss()
    }

    private func routeIntent(_ intent: WorkoutIntent) {
        switch intent {
        case .closeWorkout:
            model.send(intent)
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        default:
            model.send(intent)
        }
    }

    private func sendHUDIntent(_ intent: WorkoutIntent) {
        if intent == .closeWorkout {
            close()
        } else {
            routeIntent(intent)
        }
    }

    /// Saves what was done once per workout; nothing is saved when no set was finished.
    private func saveHistory() {
        guard !historySaved else { return }
        historySaved = true
        guard let record = WorkoutRecord(session: model.session, startedAt: startedAt, endedAt: Date()) else { return }
        try? appRepositories?.workoutHistory.save(record)
    }

    // MARK: - Guide

    private func presentGuide() {
        guard model.session.exercise != nil else { return }
        routeIntent(.showGuide)
    }

    private func presentGuideIfUnseen() {
        guard !model.isGuidePresented, let id = model.session.exerciseID,
              !WorkoutGuidePreferences.hasSeen(id, preferences: preferences) else { return }
        presentGuide()
    }

    private func guideDismissed() {
        if let id = model.session.exerciseID { WorkoutGuidePreferences.markSeen(id, preferences: preferences) }
        routeIntent(.hideGuide)
        if showVoiceCommandsAfterGuide {
            showVoiceCommandsAfterGuide = false
            routeIntent(.showVoiceHelp)
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
                Button("Open Settings") { routeIntent(.openSettings) }
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
    static func hasSeen(_ id: ExerciseID, preferences: any AppPreferencesStoring) -> Bool {
        preferences.guideSeen(for: id.rawValue)
    }

    static func markSeen(_ id: ExerciseID, preferences: any AppPreferencesStoring) {
        preferences.setGuideSeen(true, for: id.rawValue)
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
            if let plan = session.plan {
                Text(plan.name)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(plan.items.enumerated()), id: \.element.id) { index, item in
                        PlanItemSummaryRow(index: index, item: item, record: session.planRecords[item.id],
                                           exercise: session.exercises.first { $0.id == item.exerciseID })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                            Text(reps.enumerated().map { "\(exercise.setLabel(entry: $0.offset)): \($0.element)" }.joined(separator: " · "))
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
