import AVFoundation
import Foundation
import Observation

/// Main-actor orchestrator: feeds camera frames, commands, and lifecycle changes through the pure
/// `WorkoutSession` reducer and carries out the effects it returns.
@MainActor
@Observable
final class WorkoutCoachModel: WorkoutCoachViewModeling {
    private(set) var session: WorkoutSession
    private(set) var cameraStatus: WorkoutCameraStatus = .idle
    private(set) var overlay: WorkoutOverlayState?
    /// True after a frame has arrived; framing reliability supplies the existing loss grace period.
    private(set) var hasPoseFrame = false
    /// Refreshed on every tick for the rest timer.
    private(set) var now: TimeInterval
    private(set) var guideMetrics: GuideMetrics?
    private(set) var armReadings: [BodySide: ArmReading] = [:]
    private(set) var armThresholds: [BodySide: ArmThresholds] = [:]
    /// The phone leans forward or back enough to distort heights.
    private(set) var isPhoneTilted = false
    private(set) var isCoachSpeaking = false
    /// The camera has run and the coach has introduced the workout.
    private(set) var hasOpened = false
    private(set) var micStatus: VoiceStatus = .off
    /// The phrase behind the most recent voice command, shown briefly as a "Heard" chip.
    private(set) var heardPhrase: String?
    /// The Voice Commands help is open. Capture and listening continue behind it.
    private(set) var isHelpPresented = false
    /// The coach says nothing at all, so other audio is never ducked. Remembered between workouts.
    private(set) var isCoachMuted: Bool
    /// The microphone stays off until the user turns it back on. Remembered between workouts.
    private(set) var isMicMuted: Bool
    /// The coaching tip on screen; it clears after `tipDuration`.
    private(set) var activeTip: CoachingTip?
    /// The last rep's form values, for Show Measurements.
    private(set) var formReadings: [FormReading] = []
    private(set) var showsMeasurements: Bool
    private(set) var isGuidePresented = false

    var captureSession: AVCaptureSession? { previewProvider?.previewSession }
    var exercises: [ExerciseDefinition] { session.exercises }
    var hud: WorkoutHUDViewState {
        let visualInputs = WorkoutVisualInputs(
            session: session,
            now: now,
            isPhoneTilted: isPhoneTilted,
            activeTip: activeTip.map { WorkoutVisualTip(id: $0.id, kind: $0.cue.kind, text: $0.cue.text) },
            hasPose: hasPoseFrame
        )
        let visual = WorkoutVisualState.derive(visualInputs)
        let presentation = WorkoutHUDPresenter.derive(WorkoutHUDInputs(
            session: session,
            visual: visualInputs,
            voiceCommandsAvailable: micStatus.isUsable
        ))
        return WorkoutHUDViewState(
            presentation: presentation,
            visual: visual,
            exercise: WorkoutHUDInputs(session: session, visual: visualInputs,
                                       voiceCommandsAvailable: micStatus.isUsable).exercise,
            exerciseID: session.exerciseID,
            exerciseOptions: session.exercises.map { .init(id: $0.id, displayName: $0.displayName) },
            planName: session.plan?.name,
            isFollowingPlan: session.isFollowingPlan,
            repCount: session.repCount,
            sideReps: session.sideReps,
            currentWeights: session.currentWeights,
            readings: armReadings,
            thresholds: armThresholds,
            formReadings: formReadings,
            isPhoneTilted: isPhoneTilted,
            micStatus: micStatus,
            isMicMuted: isMicMuted,
            heardPhrase: heardPhrase,
            isCoachMuted: isCoachMuted,
            showsMeasurements: showsMeasurements
        )
    }

    @ObservationIgnored private let camera: PoseFrameSource
    @ObservationIgnored private let previewProvider: CameraPreviewProviding?
    @ObservationIgnored private let permission: CameraPermissionProviding
    @ObservationIgnored private let speech: SpeechCoaching
    @ObservationIgnored private let audio: AudioSessionControlling?
    @ObservationIgnored private let tiltMonitor: PhoneTiltMonitoring?
    @ObservationIgnored private let voice: VoiceControlling?
    @ObservationIgnored private let preferences: any AppPreferencesStoring
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let scheduler: Scheduling

    @ObservationIgnored private var framePipeline = WorkoutFramePipeline()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isViewActive = false
    @ObservationIgnored private var isApplicationActive = false
    @ObservationIgnored private var isRequestingPermission = false
    @ObservationIgnored private var didApplyInitialMicMute = false
    @ObservationIgnored private var tickTimer: Cancellable?
    @ObservationIgnored private var tipExpiry: Cancellable?
    @ObservationIgnored private var heardExpiry: Cancellable?
    @ObservationIgnored private var unmuteTipTask: Cancellable?
    @ObservationIgnored private var heardGeneration = 0

    static let tickInterval: TimeInterval = 0.5
    static let heardChipDuration: TimeInterval = 1.5
    static let tipDuration = CoachingCueScheduler.Configuration().tipDuration
    /// Spoken once per install, after the intro, when voice first works.
    static let voiceTip = "Say \u{201C}what can I say\u{201D} anytime to see voice commands."

    init(camera: PoseFrameSource, previewProvider: CameraPreviewProviding?, permission: CameraPermissionProviding,
         speech: SpeechCoaching, audio: AudioSessionControlling?, tiltMonitor: PhoneTiltMonitoring?,
         voice: VoiceControlling?, clock: Clock, scheduler: Scheduling, preferences: any AppPreferencesStoring,
         exercises: [ExerciseDefinition], initialExercise: ExerciseID?, plan: WorkoutPlan?,
         settings: WorkoutSettings = WorkoutSettings()) {
        self.camera = camera
        self.previewProvider = previewProvider
        self.permission = permission
        self.speech = speech
        self.audio = audio
        self.tiltMonitor = tiltMonitor
        self.voice = voice
        self.preferences = preferences
        self.clock = clock
        self.scheduler = scheduler
        isCoachMuted = preferences.workoutCoachCoachMuted
        isMicMuted = preferences.workoutCoachMicMuted
        showsMeasurements = preferences.workoutCoachShowMeasurements
        session = WorkoutSession(exercises: exercises, initialExercise: initialExercise, plan: plan, settings: settings)
        now = clock.now
        audio?.onEvent = { [weak self] event in self?.handleAudio(event) }
        speech.onActivityChanged = { [weak self] speaking in
            self?.coachSpeakingChanged(speaking)
        }
        voice?.onCommand = { [weak self] command in self?.handleVoiceCommand(command) }
        voice?.onHeard = { [weak self] phrase in self?.showHeard(phrase) }
        voice?.onStatusChanged = { [weak self] status in self?.voiceStatusChanged(status) }
    }

    // MARK: - Lifecycle

    private var canCapture: Bool {
        isViewActive && isApplicationActive && !isGuidePresented && session.phase != .ended
    }

    func onAppear(isApplicationActive: Bool) {
        isViewActive = true
        self.isApplicationActive = isApplicationActive
        if isMicMuted, !didApplyInitialMicMute {
            voice?.setMuted(true)
            didApplyInitialMicMute = true
        }
        audio?.configureBaseCategory()
        startTicks()
        startCaptureIfPossible()
    }

    func onDisappear() {
        isViewActive = false
        stopTicks()
        stopCapture()
        speech.stopAll()
        audio?.deactivate()
    }

    func setApplicationActive(_ active: Bool) {
        guard active != isApplicationActive else { return }
        isApplicationActive = active
        if active {
            apply(session.handle(.appForegrounded, at: clock.now))
            startCaptureIfPossible()
        } else {
            apply(session.handle(.appBackgrounded, at: clock.now))
            stopCapture()
            speech.stopAll()
        }
    }

    private func handleVoiceCommand(_ command: WorkoutCommand) {
        switch command {
        case .help:
            isHelpPresented = true
        case .repCount, .whichSet, .repeatLast:
            // Info keeps the help open so the list stays visible.
            break
        // Sound changes apply before the reducer, so confirmations follow the new state.
        case .muteCoach:
            setCoachMuted(true)
        case .unmuteCoach:
            setCoachMuted(false)
        case .muteMicrophone:
            setMicMuted(true)
        default:
            // Close, cancel, and anything that changes the workout show the workout again.
            isHelpPresented = false
        }
        apply(session.handle(.command(command), at: clock.now))
    }

    func send(_ intent: WorkoutIntent) {
        if let command = intent.command {
            handleVoiceCommand(command)
            return
        }
        switch intent {
        case .toggleCoachMute:
            setCoachMuted(!isCoachMuted)
        case .setCoachMuted(let muted):
            setCoachMuted(muted)
        case .toggleMicrophoneMute, .microphoneTapped:
            microphoneTapped()
        case .setMicrophoneMuted(let muted):
            setMicMuted(muted)
        case .showGuide:
            setGuidePresented(true)
        case .hideGuide:
            setGuidePresented(false)
        case .readGuideAloud:
            readGuideAloud()
        case .stopSpeaking:
            stopSpeaking()
        case .showVoiceHelp:
            isHelpPresented = true
        case .hideVoiceHelp:
            isHelpPresented = false
        case .retryVoice:
            retryVoice()
        case .toggleMeasurements:
            showsMeasurements.toggle()
            preferences.workoutCoachShowMeasurements = showsMeasurements
        case .dismissTip:
            setActiveTip(nil)
        case .closeWorkout:
            onDisappear()
        case .openSettings:
            break
        case .start, .pause, .resume, .restartSet, .nextSet, .changeExercise, .chooseExercise,
             .cancelExerciseChange, .anotherRound, .nextExercise, .endWorkout:
            assertionFailure("Reducer-backed intents are mapped above.")
        }
    }

    /// Touch path for the Voice Commands help; opening it this way doesn't speak.
    func setHelpPresented(_ presented: Bool) {
        isHelpPresented = presented
    }

    // MARK: - Guide

    /// The guide covers the camera, so capture stops while it is open and an active set pauses.
    func setGuidePresented(_ presented: Bool) {
        guard presented != isGuidePresented else { return }
        isGuidePresented = presented
        if presented {
            if session.phase == .exercising { handleVoiceCommand(.pause) }
            stopCapture()
        } else {
            speech.stopAll()
            startCaptureIfPossible()
        }
    }

    /// Retries voice after a failure or an interruption that didn't resume on its own.
    func retryVoice() {
        guard canCapture, !isMicMuted else { return }
        voice?.retry()
    }

    // MARK: - Sound

    func setCoachMuted(_ muted: Bool) {
        guard muted != isCoachMuted else { return }
        isCoachMuted = muted
        preferences.workoutCoachCoachMuted = muted
        if muted {
            // Cut the current line now; this also restores any ducked audio.
            unmuteTipTask?.cancel()
            unmuteTipTask = nil
            speech.stopAll()
        } else {
            // After the current command, so "Coach voice on." comes first.
            unmuteTipTask?.cancel()
            unmuteTipTask = scheduler.schedule(after: 0) { [weak self] in
                guard let self else { return }
                self.unmuteTipTask = nil
                self.speakVoiceTipIfNeeded()
            }
        }
    }

    func setMicMuted(_ muted: Bool) {
        guard muted != isMicMuted else { return }
        isMicMuted = muted
        preferences.workoutCoachMicMuted = muted
        voice?.setMuted(muted)
        didApplyInitialMicMute = true
        if !muted, canCapture { voice?.enable() }
    }

    /// Mutes or unmutes, retries after a system pause, or opens help to fix permission or failures.
    func microphoneTapped() {
        switch micStatus {
        case .muted: setMicMuted(false)
        case .listening, .coachSpeaking: setMicMuted(true)
        case .paused, .off: retryVoice()
        case .needsPermission, .unavailable: isHelpPresented = true
        case .requestingPermission: break
        }
    }

    /// 0...1 while holding the start position toward an automatic start.
    func startHoldProgress() -> Double? {
        session.startHoldProgress(at: clock.now)
    }

    func readGuideAloud() {
        guard let guide = session.exercise?.guide else { return }
        speech.speak(Utterance(text: guide.walkthrough, isInstruction: false, interrupts: true))
    }

    func stopSpeaking() {
        speech.stopAll()
    }

    // MARK: - Camera

    private func startCaptureIfPossible() {
        guard canCapture else { return }
        switch permission.status {
        case .authorized:
            startCapture()
        case .notDetermined:
            guard !isRequestingPermission else { return }
            isRequestingPermission = true
            permission.request { [weak self] granted in
                guard let self else { return }
                self.isRequestingPermission = false
                guard self.canCapture else { return }
                if granted {
                    self.startCapture()
                } else {
                    self.cameraStatus = .notAuthorized
                }
            }
        default:
            cameraStatus = .notAuthorized
        }
    }

    private func startCapture() {
        generation = UUID()
        cameraStatus = .starting
        resetTracking()
        tiltMonitor?.start()
        // After camera permission, so the microphone and speech prompts follow it in order.
        if !isMicMuted { voice?.enable() }
        camera.start(generation: generation) { [weak self] token, event in
            guard let self, self.canCapture, token == self.generation else { return }
            self.handle(event)
        }
    }

    private func stopCapture() {
        generation = UUID()
        camera.stop()
        // Paused rather than off, so prompts spoken on return still say "Say resume".
        voice?.disable(status: .paused)
        tiltMonitor?.stop()
        if let event = framePipeline.resetTilt() {
            if case .phoneTiltChanged(let tilted) = event { isPhoneTilted = tilted }
            apply(session.handle(event, at: clock.now))
        }
        if cameraStatus == .running || cameraStatus == .starting || cameraStatus == .interrupted {
            cameraStatus = .idle
        }
        resetTracking()
    }

    private func handle(_ event: PoseFrameSourceEvent) {
        switch event {
        case .running:
            let wasInterrupted = cameraStatus == .interrupted
            cameraStatus = .running
            if !hasOpened {
                hasOpened = true
                apply(session.handle(.opened, at: clock.now))
                speakVoiceTipIfNeeded()
            } else if wasInterrupted {
                apply(session.handle(.interruptionEnded, at: clock.now))
            }
        case .frame(let frame):
            process(frame)
        case .interrupted:
            cameraStatus = .interrupted
            apply(session.handle(.interruptionBegan, at: clock.now))
            resetTracking()
        case .failed(let message):
            cameraStatus = .failed(message)
            apply(session.handle(.interruptionBegan, at: clock.now))
            resetTracking()
            speech.stopAll()
        }
    }

    private func process(_ frame: PoseFrame) {
        guard session.exercise != nil else {
            hasPoseFrame = false
            overlay = nil
            return
        }
        hasPoseFrame = true
        framePipeline.setSessionPhase(session.phase)
        framePipeline.exerciseChanged(to: session.exercise, analyzerEpoch: session.analyzerEpoch)
        let output = framePipeline.process(frame: frame, at: clock.now)
        overlay = output.overlay
        guideMetrics = output.guideMetrics
        armReadings = output.readings
        armThresholds = output.thresholds
        formReadings = output.formReadings

        var checkedStartHold = false
        for event in output.events {
            apply(session.handle(event, at: clock.now))
            // A full start hold starts on this frame, before any rep event from the same sample.
            if !checkedStartHold, isStartHoldComplete(at: clock.now),
               isStartPositionEvent(event) || isRepEvent(event) {
                apply(session.handle(.tick, at: clock.now))
                checkedStartHold = true
            }
        }
        if !checkedStartHold, isStartHoldComplete(at: clock.now) {
            apply(session.handle(.tick, at: clock.now))
        }
    }

    private func isStartHoldComplete(at time: TimeInterval) -> Bool {
        session.startHoldProgress(at: time) == 1
    }

    private func isStartPositionEvent(_ event: WorkoutEvent) -> Bool {
        if case .startPositionChanged = event { return true }
        return false
    }

    private func isRepEvent(_ event: WorkoutEvent) -> Bool {
        if case .repCompleted = event { return true }
        return false
    }

    private var emphasizedJoints: Set<LandmarkType> {
        guard let cue = activeTip?.cue, cue.kind == .corrective else { return [] }
        return cue.joints
    }

    private func resetTracking() {
        let events = framePipeline.resetTracking()
        hasPoseFrame = false
        overlay = framePipeline.overlay
        guideMetrics = framePipeline.guideMetrics
        armReadings = framePipeline.readings
        armThresholds = framePipeline.thresholds
        formReadings = framePipeline.formReadings
        for event in events { apply(session.handle(event, at: clock.now)) }
        if session.framing != .lost {
            apply(session.handle(.framingChanged(.lost), at: clock.now))
        }
    }

    // MARK: - Effects

    private func apply(_ effects: [WorkoutEffect]) {
        for effect in effects {
            switch effect {
            case .speak(let utterance):
                if !isCoachMuted { speech.speak(utterance) }
            case .repeatLastInstruction:
                if !isCoachMuted { speech.repeatLastInstruction() }
            case .resetAnalyzer(let epoch):
                guard let exercise = session.exercise else {
                    framePipeline.exerciseChanged(to: nil, analyzerEpoch: epoch)
                    continue
                }
                framePipeline.exerciseChanged(to: exercise, analyzerEpoch: epoch)
                framePipeline.resetAnalyzer(epoch: epoch)
            case .setCounting(let counting):
                framePipeline.setCounting(counting)
            case .clearFeedback:
                overlay?.endPositionSides = []
                setActiveTip(nil)
            case .showTip(let tip):
                setActiveTip(tip)
            case .stopCaptureAndVoice:
                stopTicks()
                stopCapture()
            }
        }
    }

    // MARK: - Clock and audio

    private func startTicks() {
        tickTimer?.cancel()
        now = clock.now
        tickTimer = scheduler.repeating(every: Self.tickInterval) { [weak self] in self?.tick() }
    }

    private func stopTicks() {
        tickTimer?.cancel()
        tickTimer = nil
    }

    private func tick() {
        now = clock.now
        if preferences.tiltWarningsEnabled {
            if let event = framePipeline.processTiltSample(pitchDegrees: tiltMonitor?.latestTilt?.pitchDegrees, at: now) {
                if case .phoneTiltChanged(let tilted) = event { isPhoneTilted = tilted }
                apply(session.handle(event, at: now))
            }
        } else {
            isPhoneTilted = false
            if let event = framePipeline.resetTilt() {
                apply(session.handle(event, at: now))
            }
        }
        apply(session.handle(.tick, at: now))
    }

    private func handleAudio(_ event: AudioSessionEvent) {
        switch event {
        case .interruptionBegan:
            // Calls and Siri: pause, stop listening, and let other audio return.
            voice?.disable(status: .paused)
            speech.stopAll()
            apply(session.handle(.interruptionBegan, at: clock.now))
        case .interruptionEnded(let shouldResume):
            // The workout stays paused; voice resumes only when the system says so.
            if shouldResume, canCapture, !isMicMuted { voice?.enable() }
            apply(session.handle(.interruptionEnded, at: clock.now))
        case .mediaServicesReset:
            speech.stopAll()
            voice?.handleAudioEvent(event)
        case .routeChanged, .reactivated:
            voice?.handleAudioEvent(event)
        }
    }

    private func voiceStatusChanged(_ status: VoiceStatus) {
        let wasUsable = micStatus.isUsable
        micStatus = status
        if status.isUsable != wasUsable {
            apply(session.handle(.voiceControlChanged(status.isUsable), at: clock.now))
        }
        speakVoiceTipIfNeeded()
    }

    /// Once per install, after the intro and once voice works, mention the help command.
    private func speakVoiceTipIfNeeded() {
        guard hasOpened, micStatus.isUsable, !isCoachMuted, !preferences.workoutCoachVoiceTipSpoken else { return }
        preferences.workoutCoachVoiceTipSpoken = true
        speech.speak(Utterance(text: Self.voiceTip, isInstruction: false))
    }

    private func coachSpeakingChanged(_ speaking: Bool) {
        isCoachSpeaking = speaking
        voice?.setCoachSpeaking(speaking)
        apply(session.handle(.coachSpeakingChanged(speaking), at: clock.now))
    }

    /// Shows a tip for `tipDuration`; a newer tip or a cleared one cancels the pending hide.
    private func setActiveTip(_ tip: CoachingTip?) {
        tipExpiry?.cancel()
        tipExpiry = nil
        activeTip = tip
        framePipeline.setEmphasizedJoints(emphasizedJoints)
        overlay?.emphasizedJoints = emphasizedJoints
        guard let id = tip?.id else { return }
        tipExpiry = scheduler.schedule(after: Self.tipDuration) { [weak self] in
            guard let self, self.activeTip?.id == id else { return }
            self.tipExpiry = nil
            self.setActiveTip(nil)
        }
    }

    private func showHeard(_ phrase: String) {
        heardGeneration += 1
        let generation = heardGeneration
        heardPhrase = phrase
        heardExpiry?.cancel()
        heardExpiry = scheduler.schedule(after: Self.heardChipDuration) { [weak self] in
            guard let self, self.heardGeneration == generation else { return }
            self.heardExpiry = nil
            self.heardPhrase = nil
        }
    }
}
