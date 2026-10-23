import SwiftUI
import UIKit

/// Workout Coach (Beta): mirrored selfie preview, focus-joint overlay, rep counter, and spoken coaching.
struct WorkoutCoachView: View {
    static let coordinateSpace = "workoutOverlay"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appRepositories) private var appRepositories
    @Environment(\.appRouter) private var appRouter
    @Environment(\.preferences) private var preferences
    @Environment(\.workoutReminderReconciliation) private var workoutReminderReconciliation
    @State private var model: any WorkoutCoachViewModeling
    /// Open the Voice Commands help once the guide finishes dismissing.
    @State private var showVoiceCommandsAfterGuide = false
    /// Top and bottom HUD frames, which tips keep clear of.
    @State private var hudRects: [CGRect] = []
    @State private var startedAt = Date()
    @State private var historySaved = false
    @State private var planCompletionRecord: WorkoutRecord?
    @State private var finishedRecord: WorkoutRecord?

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

            // A manually ended workout shows its saved record; finishing a plan shows the same
            // completion screen before the workout is ended.
            if model.session.phase == .ended, !model.session.endedAfterCompletion {
                WorkoutCompleteScreen(
                    viewModel: WorkoutCompleteViewModel(record: displayCompletionRecord(), router: appRouter),
                    onDone: close
                )
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
            if phase == .exerciseComplete, model.session.plan != nil, model.session.isFollowingPlan {
                planCompletionRecord = completionRecord()
            }
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
                .presentationCornerRadius(32)
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(hex: 0x1A1526))
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
            .presentationCornerRadius(32)
            .presentationDragIndicator(.hidden)
            .presentationBackground(Color(hex: 0x1A1526))
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
                WorkoutJointOverlayView(overlay: overlay, visualState: model.hud.visual)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .opacity(model.hud.visual.primary == .lost ? 0.2 : 1)
                    if model.startHoldProgress() != nil {
                        HoldProgressRingView(overlay: overlay, progress: { model.startHoldProgress() })
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }

                WorkoutTipOverlayView(tip: model.activeTip,
                                      protectedRects: tipProtectedRects(in: geo.size),
                                      hudRects: hudRects,
                                      borderTint: model.hud.visual.primary == .tip ? ColorTokens.palette().warning : nil)
                    .frame(width: geo.size.width, height: geo.size.height)

                WorkoutCameraScreen(state: model.hud, onIntent: sendHUDIntent)

                if model.hud.visual.showsCompletionCard {
                    if model.session.plan != nil, model.session.isFollowingPlan {
                        WorkoutCompleteScreen(
                            viewModel: WorkoutCompleteViewModel(record: planCompletionRecord ?? completionRecord(),
                                                               router: appRouter),
                            onDone: { routeIntent(.endWorkout) }
                        )
                        .transition(.opacity)
                    } else {
                        ExerciseCompleteCard(session: model.session,
                                             onAnotherRound: { routeIntent(.anotherRound) },
                                             onChooseExercise: { routeIntent(.changeExercise) },
                                             onEndWorkout: { routeIntent(.endWorkout) })
                            .transition(.opacity)
                    }
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
        finishedRecord = record
        guard let history = appRepositories?.workoutHistory else { return }
        do {
            try WorkoutHistorySaver.save(record, using: history, preferences: preferences)
            workoutReminderReconciliation?.workoutSaved(record)
        } catch {
            // A failed history save is retried only through the existing workout flow.
        }
    }

    private func displayCompletionRecord() -> WorkoutRecord {
        finishedRecord ?? planCompletionRecord ?? completionRecord()
    }

    private func completionRecord() -> WorkoutRecord {
        let endedAt = Date()
        return WorkoutRecord(session: model.session, startedAt: startedAt, endedAt: endedAt)
            ?? WorkoutRecord(startedAt: startedAt, endedAt: endedAt,
                             planName: model.session.plan?.name, entries: [])
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
