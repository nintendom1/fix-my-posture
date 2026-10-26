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
    private(set) var ghostFitOverlay: WorkoutOverlayState?
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
    /// The REC chip's state while a developer session recording runs; nil when not recording.
    private(set) var recordingHUD: WorkoutRecordingHUD?
    /// Shared with the saved history record, so a recording and its workout can be matched.
    let workoutID: UUID

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
            showsMeasurements: showsMeasurements,
            recording: recordingHUD
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
    @ObservationIgnored private let recorder: (any WorkoutSessionRecording)?

    @ObservationIgnored private var framePipeline = WorkoutFramePipeline()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isViewActive = false
    @ObservationIgnored private var isApplicationActive = false
    @ObservationIgnored private var isRequestingPermission = false
    @ObservationIgnored private var didApplyInitialMicMute = false
    @ObservationIgnored private var didBeginRecording = false
    @ObservationIgnored private var tickTimer: Cancellable?
    @ObservationIgnored private var tipExpiry: Cancellable?
    @ObservationIgnored private var heardExpiry: Cancellable?
    @ObservationIgnored private var unmuteTipTask: Cancellable?
    @ObservationIgnored private var heardGeneration = 0
    @ObservationIgnored private var lastHeardPhrase: String?
    @ObservationIgnored private var markerConfirmationExpiry: Cancellable?
    /// The capture moment, on `clock`, of the frame being processed; nil between frames.
    @ObservationIgnored private var frameTime: TimeInterval?
    @ObservationIgnored private var lastPoseTime = -TimeInterval.infinity
    /// Frames captured before counting last started or the analyzer was replaced are recorded but not analyzed, so
    /// a backlog delivered after a Start or Resume can't count movement from before it.
    @ObservationIgnored private var analysisStart = -TimeInterval.infinity
    /// The reducer time of the input whose effects are being applied.
    @ObservationIgnored private var dispatchTime: TimeInterval?

    nonisolated static let tickInterval: TimeInterval = 0.5
    static let heardChipDuration: TimeInterval = 1.5
    static let tipDuration = CoachingCueScheduler.Configuration().tipDuration
    /// Spoken once per install, after the intro, when voice first works.
    static let voiceTip = "Say \u{201C}what can I say\u{201D} anytime to see voice commands."
    /// How long the REC chip shows "Marked" after a marker.
    static let markerConfirmationDuration: TimeInterval = 3

    init(camera: PoseFrameSource, previewProvider: CameraPreviewProviding?, permission: CameraPermissionProviding,
         speech: SpeechCoaching, audio: AudioSessionControlling?, tiltMonitor: PhoneTiltMonitoring?,
         voice: VoiceControlling?, clock: Clock, scheduler: Scheduling, preferences: any AppPreferencesStoring,
         exercises: [ExerciseDefinition], initialExercise: ExerciseID?, plan: WorkoutPlan?,
         settings: WorkoutSettings = WorkoutSettings(), recorder: (any WorkoutSessionRecording)? = nil) {
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
        self.recorder = recorder
        workoutID = recorder?.id ?? UUID()
        isCoachMuted = preferences.workoutCoachCoachMuted
        isMicMuted = preferences.workoutCoachMicMuted
        showsMeasurements = preferences.workoutCoachShowMeasurements
        session = WorkoutSession(exercises: exercises, initialExercise: initialExercise, plan: plan, settings: settings)
        now = clock.now
        audio?.onEvent = { [weak self] event in self?.handleAudio(event) }
        speech.onActivityChanged = { [weak self] speaking in
            self?.coachSpeakingChanged(speaking)
        }
        voice?.onCommand = { [weak self] command in self?.handleVoiceCommand(command, source: .voice) }
        voice?.onHeard = { [weak self] phrase in
            self?.lastHeardPhrase = phrase
            self?.showHeard(phrase)
        }
        voice?.onStatusChanged = { [weak self] status in self?.voiceStatusChanged(status) }
    }

    // MARK: - Lifecycle

    private var canCapture: Bool {
        isViewActive && isApplicationActive && !isGuidePresented && session.phase != .ended
    }

    func onAppear(isApplicationActive: Bool) {
        beginRecordingIfNeeded()
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
        endRecording(.closed)
    }

    func setApplicationActive(_ active: Bool) {
        guard active != isApplicationActive else { return }
        isApplicationActive = active
        if active {
            dispatch(.appForegrounded)
            startCaptureIfPossible()
        } else {
            dispatch(.appBackgrounded)
            stopCapture()
            speech.stopAll()
            recorder?.flush()
        }
    }

    private func handleVoiceCommand(_ command: WorkoutCommand, source: WorkoutCommandSource = .touch) {
        let phrase = source == .voice ? lastHeardPhrase : nil
        lastHeardPhrase = nil
        recorder?.recordEvent(.command(command, source: source, phrase: phrase), at: clock.now)
        switch command {
        case .help:
            presentHelp(true)
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
            presentHelp(false)
        }
        dispatch(.command(command))
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
            presentHelp(true)
        case .hideVoiceHelp:
            presentHelp(false)
        case .retryVoice:
            retryVoice()
        case .toggleMeasurements:
            showsMeasurements.toggle()
            preferences.workoutCoachShowMeasurements = showsMeasurements
            recorder?.recordEvent(.measurementsShown(showsMeasurements), at: clock.now)
        case .dropMarker:
            dropMarker(WorkoutMarkerRequest(source: .tap))
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
        presentHelp(presented)
    }

    private func presentHelp(_ presented: Bool) {
        guard presented != isHelpPresented else { return }
        isHelpPresented = presented
        recorder?.recordEvent(.helpPresented(presented), at: clock.now)
    }

    // MARK: - Guide

    /// The guide covers the camera, so capture stops while it is open and an active set pauses.
    func setGuidePresented(_ presented: Bool) {
        guard presented != isGuidePresented else { return }
        // The first-time guide opens before the screen appears, so the recording starts here too.
        beginRecordingIfNeeded()
        isGuidePresented = presented
        recorder?.recordEvent(.guidePresented(presented), at: clock.now)
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
        recordState()
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
        recordState()
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
        case .needsPermission, .unavailable: presentHelp(true)
        case .requestingPermission: break
        }
    }

    /// 0...1 while holding the start position toward an automatic start.
    func startHoldProgress() -> Double? {
        session.startHoldProgress(at: clock.now)
    }

    func readGuideAloud() {
        guard let guide = session.exercise?.guide else { return }
        // An explicit tap, so it plays even with the coach muted.
        say(Utterance(text: guide.walkthrough, isInstruction: false, interrupts: true), muted: false)
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
            dispatch(event)
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
            recorder?.recordEvent(.cameraRunning, at: clock.now)
            if !hasOpened {
                hasOpened = true
                dispatch(.opened)
                speakVoiceTipIfNeeded()
            } else if wasInterrupted {
                dispatch(.interruptionEnded)
            }
        case .frame(let frame):
            process(frame)
        case .interrupted:
            cameraStatus = .interrupted
            recorder?.recordEvent(.cameraInterrupted, at: clock.now)
            dispatch(.interruptionBegan)
            resetTracking()
        case .failed(let message):
            cameraStatus = .failed(message)
            recorder?.recordEvent(.cameraFailed(message), at: clock.now)
            dispatch(.interruptionBegan)
            resetTracking()
            speech.stopAll()
        }
    }

    private func process(_ frame: PoseFrame) {
        // A backlog delivered after a stall is placed at its capture moments, so a start hold can't complete
        // on pose evidence that later frames in it contradict.
        frameTime = poseTime(of: frame)
        defer { frameTime = nil }
        guard session.exercise != nil else {
            hasPoseFrame = false
            overlay = nil
            ghostFitOverlay = nil
            recorder?.recordFrame(frame, output: nil, pitchDegrees: tiltMonitor?.latestTilt?.pitchDegrees, at: clock.now)
            return
        }
        guard let time = frameTime, time >= analysisStart else {
            recorder?.recordFrame(frame, output: nil, pitchDegrees: tiltMonitor?.latestTilt?.pitchDegrees, at: clock.now)
            return
        }
        hasPoseFrame = true
        applyControl(.sessionPhase(session.phase))
        applyControl(.exercise(session.exercise, analyzerEpoch: session.analyzerEpoch))
        let output = framePipeline.process(frame: frame, at: clock.now)
        // Before this frame's events, so the controls they cause follow it in the recording.
        recorder?.recordFrame(frame, output: output, pitchDegrees: tiltMonitor?.latestTilt?.pitchDegrees, at: clock.now)
        overlay = output.overlay
        ghostFitOverlay = output.ghostFitOverlay
        guideMetrics = output.guideMetrics
        armReadings = output.readings
        armThresholds = output.thresholds
        formReadings = output.formReadings

        dispatch(.poseObserved)
        var checkedStartHold = false
        for event in output.events {
            dispatch(event)
            // A full start hold starts on this frame, before any rep event from the same sample.
            if !checkedStartHold, isStartHoldComplete(at: reducerTime),
               isStartPositionEvent(event) || isRepEvent(event) {
                dispatch(.tick)
                checkedStartHold = true
            }
        }
        if !checkedStartHold, isStartHoldComplete(at: reducerTime) {
            dispatch(.tick)
        }
    }

    /// The frame's capture moment on `clock`. Only earlier frames bound it, never reducer inputs such as ticks or
    /// speech changes made during a stall.
    private func poseTime(of frame: PoseFrame) -> TimeInterval {
        let time = max(lastPoseTime, clock.now - frame.deliveryDelay)
        lastPoseTime = time
        return time
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
        let events = applyControl(.resetTracking)
        hasPoseFrame = false
        overlay = framePipeline.overlay
        ghostFitOverlay = framePipeline.ghostFitOverlay
        guideMetrics = framePipeline.guideMetrics
        armReadings = framePipeline.readings
        armThresholds = framePipeline.thresholds
        formReadings = framePipeline.formReadings
        for event in events { dispatch(event) }
        if session.framing != .lost {
            dispatch(.framingChanged(.lost))
        }
    }

    // MARK: - Effects

    /// Every reducer input goes through here, so a recording sees each one and the state it led to.
    /// Recordings keep delivery time; the reducer gets the processed frame's capture time when there is one.
    private func dispatch(_ event: WorkoutEvent, at time: TimeInterval? = nil) {
        if let recorder, let recorded = WorkoutRecordingEvent(input: event) {
            recorder.recordEvent(recorded, at: time ?? clock.now)
        }
        let now = time ?? reducerTime
        let outer = dispatchTime
        dispatchTime = now
        defer { dispatchTime = outer }
        apply(session.handle(event, at: now))
        recordState()
    }

    /// The reducer's time for the next input: the frame being processed, else the clock.
    private var reducerTime: TimeInterval { frameTime ?? clock.now }

    /// Pipeline changes go through here, so a recording can rebuild the same pipeline state on replay.
    @discardableResult
    private func applyControl(_ control: WorkoutFramePipeline.Control) -> [WorkoutEvent] {
        let before = framePipeline.controlState
        let events = framePipeline.apply(control)
        if let recorder {
            var alwaysRecorded = false
            if case .resetTracking = control { alwaysRecorded = true }
            if alwaysRecorded || framePipeline.controlState != before {
                recorder.recordControl(control, at: clock.now)
            }
        }
        return events
    }

    private func apply(_ effects: [WorkoutEffect]) {
        for effect in effects {
            switch effect {
            case .speak(let utterance):
                say(utterance, muted: isCoachMuted)
            case .repeatLastInstruction:
                recorder?.recordEvent(.repeatLastInstruction(muted: isCoachMuted), at: clock.now)
                if !isCoachMuted { speech.repeatLastInstruction() }
            case .resetAnalyzer(let epoch):
                analysisStart = max(analysisStart, dispatchTime ?? clock.now)
                guard let exercise = session.exercise else {
                    applyControl(.exercise(nil, analyzerEpoch: epoch))
                    continue
                }
                applyControl(.exercise(exercise, analyzerEpoch: epoch))
                applyControl(.resetAnalyzer(epoch: epoch))
            case .setCounting(let counting):
                if counting { analysisStart = max(analysisStart, dispatchTime ?? clock.now) }
                applyControl(.counting(counting))
            case .clearFeedback:
                recorder?.recordEvent(.clearFeedback, at: clock.now)
                overlay?.endPositionSides = []
                setActiveTip(nil)
            case .showTip(let tip):
                setActiveTip(tip)
            case .stopCaptureAndVoice:
                stopTicks()
                stopCapture()
                if session.phase == .ended { endRecording(.workoutEnded) }
            }
        }
    }

    // MARK: - Recording

    private func beginRecordingIfNeeded() {
        guard let recorder, !didBeginRecording else { return }
        didBeginRecording = true
        recorder.begin(WorkoutRecordingContext(startedAt: Date(), timeZone: .current, exercises: session.exercises,
                                               plan: session.plan, settings: session.settings,
                                               tiltWarningsEnabled: preferences.tiltWarningsEnabled,
                                               isCoachMuted: isCoachMuted, isMicMuted: isMicMuted),
                       at: clock.now)
        // The chip and the extra per-frame output appear only when a file is actually being written.
        guard recorder.isRecording else { return }
        framePipeline.collectsDiagnostics = true
        recordingHUD = WorkoutRecordingHUD(markerCount: 0, confirmation: nil)
        recordState()
    }

    private func recordState() {
        guard let recorder, recorder.isRecording else { return }
        recorder.recordState(WorkoutStateSnapshot(session: session, isPhoneTilted: isPhoneTilted, activeTip: activeTip,
                                                  isCoachSpeaking: isCoachSpeaking, micStatus: micStatus,
                                                  isCoachMuted: isCoachMuted, isMicMuted: isMicMuted,
                                                  cameraStatus: cameraStatus),
                             at: clock.now)
    }

    private func endRecording(_ reason: WorkoutRecordingEnd) {
        guard let recorder, recorder.isRecording else { return }
        recordState()
        let now = Date()
        let saved = WorkoutRecord(session: session, startedAt: now, endedAt: now) != nil
        recorder.end(reason, workoutRecordID: saved ? workoutID : nil, at: clock.now)
        framePipeline.collectsDiagnostics = false
        markerConfirmationExpiry?.cancel()
        markerConfirmationExpiry = nil
        recordingHUD = nil
    }

    /// Speaks through the coach unless `muted`, and records the line either way.
    private func say(_ utterance: Utterance, muted: Bool) {
        recorder?.recordEvent(.speak(utterance, muted: muted), at: clock.now)
        if !muted { speech.speak(utterance) }
    }

    /// Records a marker and confirms it on the REC chip and, unless the coach is muted, out loud.
    private func dropMarker(_ request: WorkoutMarkerRequest) {
        guard let marker = recorder?.recordMarker(request, at: clock.now) else { return }
        markerConfirmationExpiry?.cancel()
        recordingHUD = WorkoutRecordingHUD(markerCount: recorder?.markers.count ?? 0,
                                           confirmation: "Marked \(WorkoutRecordingHUD.clockLabel(marker.time))")
        say(Utterance(text: "Marked.", isInstruction: false), muted: isCoachMuted)
        markerConfirmationExpiry = scheduler.schedule(after: Self.markerConfirmationDuration) { [weak self] in
            guard let self else { return }
            self.markerConfirmationExpiry = nil
            self.recordingHUD?.confirmation = nil
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
        if let recorder, recorder.duration(at: now) >= WorkoutSessionRecorder.maximumDuration {
            endRecording(.timeLimit)
        }
        if preferences.tiltWarningsEnabled {
            if let event = framePipeline.processTiltSample(pitchDegrees: tiltMonitor?.latestTilt?.pitchDegrees, at: now) {
                if case .phoneTiltChanged(let tilted) = event { isPhoneTilted = tilted }
                dispatch(event, at: now)
            }
        } else {
            isPhoneTilted = false
            if let event = framePipeline.resetTilt() {
                dispatch(event, at: now)
            }
        }
        dispatch(.tick, at: now)
    }

    private func handleAudio(_ event: AudioSessionEvent) {
        switch event {
        case .interruptionBegan:
            // Calls and Siri: pause, stop listening, and let other audio return.
            recorder?.recordEvent(.audioInterruptionBegan, at: clock.now)
            voice?.disable(status: .paused)
            speech.stopAll()
            dispatch(.interruptionBegan)
        case .interruptionEnded(let shouldResume):
            // The workout stays paused; voice resumes only when the system says so.
            recorder?.recordEvent(.audioInterruptionEnded(shouldResume: shouldResume), at: clock.now)
            if shouldResume, canCapture, !isMicMuted { voice?.enable() }
            dispatch(.interruptionEnded)
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
            dispatch(.voiceControlChanged(status.isUsable))
        } else {
            recordState()
        }
        speakVoiceTipIfNeeded()
    }

    /// Once per install, after the intro and once voice works, mention the help command.
    private func speakVoiceTipIfNeeded() {
        guard hasOpened, micStatus.isUsable, !isCoachMuted, !preferences.workoutCoachVoiceTipSpoken else { return }
        preferences.workoutCoachVoiceTipSpoken = true
        say(Utterance(text: Self.voiceTip, isInstruction: false), muted: false)
    }

    private func coachSpeakingChanged(_ speaking: Bool) {
        isCoachSpeaking = speaking
        voice?.setCoachSpeaking(speaking)
        dispatch(.coachSpeakingChanged(speaking))
    }

    /// Shows a tip for `tipDuration`; a newer tip or a cleared one cancels the pending hide.
    private func setActiveTip(_ tip: CoachingTip?) {
        tipExpiry?.cancel()
        tipExpiry = nil
        if let recorder {
            if let tip { recorder.recordEvent(.tipShown(tip), at: clock.now) }
            else if activeTip != nil { recorder.recordEvent(.tipCleared, at: clock.now) }
        }
        activeTip = tip
        recordState()
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
