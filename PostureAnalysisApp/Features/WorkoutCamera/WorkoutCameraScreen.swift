import SwiftUI
import UIKit

/// Dark camera chrome. The preview and its workout overlays remain owned by WorkoutCoachView.
struct WorkoutCameraScreen: View {
    let state: WorkoutHUDViewState
    let onIntent: (WorkoutIntent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toolbarVisibility: EdgeToolbarVisibilityController
    @State private var confirmingEnd = false

    init(state: WorkoutHUDViewState,
         scheduler: (any Scheduling)? = nil,
         isVoiceOverRunning: @escaping () -> Bool = { UIAccessibility.isVoiceOverRunning },
         onIntent: @escaping (WorkoutIntent) -> Void) {
        self.state = state
        self.onIntent = onIntent
        _toolbarVisibility = State(initialValue: EdgeToolbarVisibilityController(
            scheduler: scheduler,
            isVoiceOverRunning: isVoiceOverRunning
        ))
    }

    private var colors: WorkoutStateColors {
        ColorTokens.workoutColors(for: state.visual)
    }

    private var microphoneIsOff: Bool {
        if state.isMicMuted { return true }
        switch state.micStatus {
        case .off, .muted, .paused, .needsPermission, .unavailable: return true
        case .requestingPermission, .listening, .coachSpeaking: return false
        }
    }

    private var micChip: (title: String, icon: String, tint: Color) {
        let palette = ColorTokens.palette()
        if state.isMicMuted {
            return ("Voice commands off", "mic.slash.fill", Color(hex: 0xFF9AA6))
        }
        switch state.micStatus {
        case .listening:
            return ("Listening · say “pause”", "circle.fill", palette.success)
        case .coachSpeaking:
            return ("Coach speaking", "circle.fill", palette.success)
        case .paused:
            return ("Voice commands paused", "circle.fill", palette.warning)
        case .requestingPermission:
            return ("Waiting for permission", "circle.fill", palette.warning)
        case .needsPermission:
            return ("Permission needed", "circle.fill", palette.danger)
        case .unavailable:
            return ("Voice commands unavailable", "circle.fill", palette.danger)
        case .off, .muted:
            return ("Voice commands off", "circle.fill", Color(hex: 0xFF9AA6))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                cameraScrims

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toolbarVisibility.interact() }

                VStack(spacing: 0) {
                    topGroup
                    Spacer(minLength: 0)
                    bottomGroup
                }
                .padding(.top, 4)

                EdgeToolbar(isVisible: toolbarVisibility.isVisible,
                            canRestartSet: state.presentation.isSetInProgress,
                            canAdvanceSet: state.presentation.canAdvanceSet,
                            canSkipExercise: state.isFollowingPlan,
                            canChangeExercise: state.exerciseOptions.count > 1,
                            showsMeasurements: state.showsMeasurements,
                            onAction: sendControl,
                            onReveal: { toolbarVisibility.interact() })
                    .designAnchor("camera.toolbar")
                    .position(x: geometry.size.width - 14 - (toolbarVisibility.isVisible ? 22 : 14),
                              y: geometry.size.height / 2 - 2)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: toolbarVisibility.isVisible)

                // Only while a set is under way; the offer's card takes its place once it is open.
                if state.showsTooHardButton {
                    tooHardButton
                        .padding(.leading, 20)
                        .padding(.bottom, 196)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if state.visual.isRepFlashing {
                    repFlashOverlay
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state.visual.isRepFlashing)
                }

                EdgeGlow(tint: state.visual.isRepFlashing ? ColorTokens.palette().success : colors.tint,
                         glow: state.visual.isRepFlashing ? Color(hex: 0x3CDC96, alpha: 0.55) : colors.glow)
                    .ignoresSafeArea()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .sheet(isPresented: $confirmingEnd) {
                EndWorkoutConfirmationSheet(
                    onEndWorkout: {
                        confirmingEnd = false
                        sendControl(.endWorkout)
                    },
                    onKeepGoing: { confirmingEnd = false }
                )
                .presentationDetents([.height(310)])
                .presentationCornerRadius(32)
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(hex: 0x1A1526))
            }
            .onAppear { toolbarVisibility.onAppear() }
            .onDisappear { toolbarVisibility.disappear() }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
                toolbarVisibility.voiceOverStatusChanged()
            }
        }
    }

    private var cameraScrims: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                LinearGradient(colors: [Color(hex: 0x0A0810, alpha: 0.8), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: min(220, geometry.size.height))
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, Color(hex: 0x0A0810, alpha: 0.92)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: min(330, geometry.size.height))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topGroup: some View {
        VStack(spacing: 0) {
            topBar

            let chip = micChip
            HStack(spacing: 6) {
                if let recording = state.recording {
                    recordingChip(recording)
                }
                cameraMicChip(title: chip.title, icon: chip.icon, tint: chip.tint)
                    .designAnchor("camera.micChip")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let heardPhrase = state.heardPhrase {
                StatusChip(title: "Heard: “\(heardPhrase)”", icon: "waveform",
                           tint: ColorTokens.palette().textPrimary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.opacity)
                    .accessibilityLabel("Heard \(heardPhrase)")
            }

            if let instruction = state.presentation.instructionText {
                HUDPill(icon: state.presentation.pillIcon,
                        message: instruction,
                        tint: colors.tint,
                        isTall: state.visual.primary == .ready,
                        horizontalPadding: [.lost, .tilt].contains(state.visual.primary) ? 18.1 : 17.4)
                    .designAnchor("camera.statePill")
                    .accessibilityLabel("\(state.presentation.pillLabel). \(instruction)")
                    .fixedSize(horizontal: state.visual.primary != .ready, vertical: true)
                    .padding(.top, 13)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: WorkoutHUDRects.self,
                                   value: [proxy.frame(in: .named(WorkoutCoachView.coordinateSpace))])
        })
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.heardPhrase)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            HUDIconButton(icon: "close",
                          label: "End workout",
                          backgroundTint: Color.white.opacity(0.14),
                          iconSize: 24,
                          accessibilityIdentifier: "closeWorkoutButton") {
                toolbarVisibility.interact()
                confirmingEnd = true
            }

            VStack(spacing: 1) {
                Text(state.exercise?.displayName ?? "Workout Coach")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 202)
                    .designAnchor("camera.title")

                if let subtitle = state.presentation.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 202)
                }
            }
            .frame(width: 202, height: 44)

            HUDIconButton(icon: state.isCoachMuted ? "volume_off" : "volume_up",
                          label: state.isCoachMuted ? "Coach voice muted" : "Coach voice on",
                          isOff: state.isCoachMuted,
                          backgroundTint: Color.white.opacity(0.14),
                          accessibilityIdentifier: "workoutCoachVoiceButton") {
                sendControl(.coachMute)
            }
            .designAnchor("camera.speaker")

            HUDIconButton(icon: microphoneIsOff ? "mic_off" : "mic",
                          label: microphoneIsOff ? "Voice commands off" : "Listening for voice commands",
                          isOff: microphoneIsOff,
                          backgroundTint: Color.white.opacity(0.14),
                          accessibilityHint: "Mutes voice commands. Touch and hold for Voice Commands.",
                          accessibilityIdentifier: "workoutMicrophoneButton") {
                sendControl(.microphone)
            }
            .contextMenu {
                Button { sendControl(.voiceCommands) } label: {
                    Label("Voice Commands", systemImage: "text.bubble")
                }
                if state.isMicMuted {
                    Button { onIntent(.setMicrophoneMuted(false)); toolbarVisibility.interact() } label: {
                        Label("Unmute Microphone", systemImage: "mic")
                    }
                } else if !microphoneIsOff {
                    Button { onIntent(.setMicrophoneMuted(true)); toolbarVisibility.interact() } label: {
                        Label("Mute Microphone", systemImage: "mic.slash")
                    }
                }
            }
            .designAnchor("camera.mic")
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    /// Large and labelled, for a user mid-set. Tapping it flags the item and opens the offer; the set keeps going.
    private var tooHardButton: some View {
        let palette = ColorTokens.palette()
        return Button {
            toolbarVisibility.interact()
            onIntent(.tooHard)
        } label: {
            Label("Too hard?", systemImage: "hand.raised.fill")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
                .background(palette.warning.opacity(0.28), in: Capsule())
                .overlay(Capsule().strokeBorder(palette.warning, lineWidth: 2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Too hard?")
        .accessibilityHint("Tells the coach this is too hard. The set keeps going unless you choose an option.")
        .accessibilityIdentifier("tooHardButton")
        .background(GeometryReader { proxy in
            Color.clear.preference(key: WorkoutHUDRects.self,
                                   value: [proxy.frame(in: .named(WorkoutCoachView.coordinateSpace))])
        })
    }

    /// Developer builds only: shows that the session is being recorded; tapping it marks this moment.
    private func recordingChip(_ recording: WorkoutRecordingHUD) -> some View {
        Button {
            toolbarVisibility.interact()
            onIntent(.dropMarker)
        } label: {
            cameraMicChip(title: recording.confirmation ?? (recording.markerCount > 0 ? "REC · \(recording.markerCount)" : "REC"),
                          icon: recording.confirmation == nil ? "record.circle" : "checkmark.circle.fill",
                          tint: recording.confirmation == nil ? Color(hex: 0xFF9AA6) : ColorTokens.palette().success)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recording.confirmation ?? "Recording. Mark this moment")
        .accessibilityIdentifier("workoutRecordingChip")
    }

    private func cameraMicChip(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: Metrics.Spacing.xSmall) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9.5)
        .padding(.vertical, 4)
        .frame(minHeight: Metrics.Size.statusChip)
        .background(ColorTokens.palette().backgroundPrimary.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var bottomGroup: some View {
        VStack(spacing: 0) {
            if state.showsMeasurements {
                measurementsRow
                    .padding(.bottom, 4)
            }

            HStack(alignment: .top, spacing: 8) {
                RepCounter(stateLabel: state.presentation.pillLabel,
                           count: state.presentation.counterText,
                           target: state.presentation.counterTargetText,
                           tint: colors.tint,
                           repEventCount: state.presentation.repEventCount,
                           isResting: state.presentation.restCountdownText != nil)
                Spacer(minLength: 0)
                primaryButton
                    .padding(.top, state.presentation.restCountdownText == nil ? 24 : 16.5)
            }
            .frame(height: state.presentation.restCountdownText == nil ? 124 : 116.5, alignment: .top)

            ProgressBar(progress: state.presentation.progressValue,
                        gradient: primaryGradient)
                .frame(height: Metrics.Size.progressBar)
                .designAnchor("camera.progressBar")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(state.presentation.setSummary ?? "")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let exercise = state.exercise, exercise.countsArmsIndependently {
                    Text("L \(state.sideReps[.left] ?? 0) · R \(state.sideReps[.right] ?? 0)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .lineLimit(1)
                }
                if let exercise = state.exercise,
                   let weight = state.currentWeights[exercise.id] {
                    Label(weight.label, systemImage: exercise.equipment == .band ? "lasso" : "scalemass")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .lineLimit(1)
                        .accessibilityLabel("Weight \(weight.spokenLabel)")
                }
                Spacer(minLength: 0)
                if let nextLine = state.presentation.nextLine {
                    Text(nextLine)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.top, 8)
            .frame(height: 18, alignment: .center)
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .frame(height: state.presentation.restCountdownText == nil ? 166 : 158.5, alignment: .top)
        .designAnchor("camera.setSummary")
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: WorkoutHUDRects.self,
                                   value: [proxy.frame(in: .named(WorkoutCoachView.coordinateSpace))])
        })
    }

    private var primaryButton: some View {
        Button { sendControl(.primary) } label: {
            Image(material: state.presentation.primaryActionIcon ?? "check_circle")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(width: Metrics.Size.cameraPrimary, height: Metrics.Size.cameraPrimary)
                .background {
                    Circle().fill(primaryGradient)
                }
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: colors.glow, radius: 14)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(state.presentation.primaryAction == nil)
        .accessibilityLabel(state.presentation.primaryActionLabel ?? "Workout complete")
        .accessibilityIdentifier("workoutPrimaryButton")
        .designAnchor("camera.primary")
    }

    private var primaryGradient: LinearGradient {
        switch state.visual.primary {
        case .ready, .active, .paused: return GradientTokens.workoutActive
        case .tip, .tilt: return GradientTokens.workoutAttention
        case .rest: return GradientTokens.rest
        case .lost: return GradientTokens.workoutLost
        case .complete: return GradientTokens.success
        }
    }

    private var measurementsRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                ForEach(BodySide.allCases, id: \.self) { side in
                    measurement(for: side)
                }
                Spacer(minLength: 0)
                if let exercise = state.exercise,
                   let weight = state.currentWeights[exercise.id] {
                    Label(weight.label, systemImage: exercise.equipment == .band ? "lasso" : "scalemass")
                        .accessibilityLabel("Weight \(weight.spokenLabel)")
                }
            }
            if !state.formReadings.isEmpty {
                Text("Last rep: " + state.formReadings.map { "\($0.label) \($0.value)" }.joined(separator: " · "))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(ColorTokens.palette().textSecondary)
        .accessibilityElement(children: .combine)
    }

    private func measurement(for side: BodySide) -> Text {
        guard let reading = state.readings[side] else { return Text("\(side.shortLabel) –") }
        let symbol: String
        switch reading.zone {
        case .top: symbol = "arrow.up.circle.fill"
        case .bottom: symbol = "arrow.down.circle.fill"
        case .middle: symbol = "circle.dotted"
        }
        return Text("\(side.shortLabel) \(String(format: "%.2f", reading.signal)) · \(Int(reading.elbowAngle.rounded()))° ")
            + Text(Image(systemName: symbol))
    }

    private var repFlashOverlay: some View {
        VStack(spacing: 5) {
            Image(material: "check_circle")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().success)
            Text("Rep counted")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().success)
            Text("Nice one!")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(ColorTokens.palette().success.opacity(0.8), lineWidth: 2))
        .shadow(color: ColorTokens.palette().success.opacity(0.55), radius: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rep counted. Nice one!")
    }

    private func sendControl(_ control: WorkoutCameraControl) {
        toolbarVisibility.interact()
        guard let intent = WorkoutCameraControl.intent(for: control, presentation: state.presentation) else { return }
        onIntent(intent)
    }
}

private struct EndWorkoutConfirmationSheet: View {
    let onEndWorkout: () -> Void
    let onKeepGoing: () -> Void

    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 5) {
                Text("End this workout?")
                    .font(Typography.title2)
                    .foregroundStyle(palette.textPrimary)
                Text("Your finished sets are saved to workout history.")
                    .font(Typography.body)
                    .foregroundStyle(palette.textMuted)
            }

            VStack(spacing: 8) {
                Button(action: onEndWorkout) {
                    Label("End Workout", systemImage: "flag.checkered")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(palette.danger)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(palette.danger.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("confirmEndWorkoutButton")

                Button(action: onKeepGoing) {
                    Text("Keep Going")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(palette.borderCard, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x1A1526))
        .environment(\.colorScheme, .dark)
    }
}

/// Top and bottom camera HUD regions which the floating coaching tip avoids.
struct WorkoutHUDRects: SwiftUI.PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}
