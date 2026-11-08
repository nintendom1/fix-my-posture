import AdaptiveTraining
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
    /// The "How was that?" question about an item that just finished; nil when none is open. It never pauses the
    /// workout: rest keeps running, and starting the next set closes it unrated.
    private(set) var effortCard: EffortCardState?
    /// The "That felt easy. Want one more?" offer after a prescribed item rated Easy; nil when none is open. Like the
    /// card, it never pauses the workout, and starting the next set closes it as declined.
    private(set) var bonusOffer: BonusOfferState?
    /// The "Too hard?" offer during a set; nil when none is open. It never pauses or stops the set: it closes when the
    /// set ends, or when it is dismissed.
    private(set) var tooHardOffer: TooHardOfferState?
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
            recording: recordingHUD,
            tooHardOfferIsOpen: tooHardOffer != nil
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
    /// Nil in workouts with no adaptive engine, which then never ask for effort.
    @ObservationIgnored private let adaptive: (any AdaptiveEvidenceRecording)?
    /// Set when this workout is Today's Session; its plan items carry the prescription they came from.
    @ObservationIgnored private let todayLaunch: TodaySessionLaunch?
    @ObservationIgnored private let evidenceDate: () -> Date
    @ObservationIgnored private let makeEvidenceID: () -> UUID
    /// The finished item behind the open effort card.
    @ObservationIgnored private var pendingEffort: PendingEffort?
    /// An item rated Easy whose evidence waits until its bonus is settled.
    @ObservationIgnored private var pendingBonus: PendingBonus?
    /// Items already asked about or recorded, so work the workout ended on is never recorded twice.
    @ObservationIgnored private var reportedItems = Set<FinishedWorkoutItem.Key>()
    /// What the user did about each item they flagged "Too hard?", until the item's evidence is recorded.
    @ObservationIgnored private var tooHardChoices: [FinishedWorkoutItem.Key: WorkoutOutcomeAdapter.TooHardChoice] = [:]
    /// The easier version the engine chose for the item under the open offer, ready to issue if it is taken.
    @ObservationIgnored private var pendingSwap: PendingSwap?
    /// Easier versions taken in this workout, by plan item id, so each one's evidence points at its own prescription.
    @ObservationIgnored private var easierSwaps: [UUID: IssuedEasierSwap] = [:]

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
         settings: WorkoutSettings = WorkoutSettings(), recorder: (any WorkoutSessionRecording)? = nil,
         audioTiming: AudioWorkTiming? = nil, adaptive: (any AdaptiveEvidenceRecording)? = nil,
         todayLaunch: TodaySessionLaunch? = nil, evidenceDate: @escaping () -> Date = Date.init,
         makeEvidenceID: @escaping () -> UUID = UUID.init) {
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
        self.adaptive = adaptive
        self.todayLaunch = todayLaunch
        self.evidenceDate = evidenceDate
        self.makeEvidenceID = makeEvidenceID
        workoutID = recorder?.id ?? UUID()
        isCoachMuted = preferences.workoutCoachCoachMuted
        isMicMuted = preferences.workoutCoachMicMuted
        showsMeasurements = preferences.workoutCoachShowMeasurements
        session = WorkoutSession(exercises: exercises, initialExercise: initialExercise, plan: plan, settings: settings)
        now = clock.now
        audio?.onEvent = { [weak self] event in self?.handleAudio(event) }
        // Only recordings use the timings: they show what a main-thread stall around coach speech is made of.
        if recorder != nil {
            audioTiming?.onMeasured = { [weak self] step, seconds in
                guard let self else { return }
                self.recorder?.recordEvent(.audioWork(step, seconds: seconds), at: self.clock.now)
            }
        }
        speech.onActivityChanged = { [weak self] speaking in
            self?.coachSpeakingChanged(speaking)
        }
        voice?.onCommand = { [weak self] command in self?.handleVoiceCommand(command, source: .voice) }
        voice?.onHeard = { [weak self] phrase in
            self?.lastHeardPhrase = phrase
            self?.showHeard(phrase)
        }
        voice?.onStatusChanged = { [weak self] status in self?.voiceStatusChanged(status) }
        voice?.onEffort = { [weak self] effort in
            // The spoken answer isn't a command, so its phrase must not attach to the next one.
            self?.lastHeardPhrase = nil
            self?.rateEffort(effort)
        }
        voice?.onBonus = { [weak self] answer in
            self?.lastHeardPhrase = nil
            switch answer {
            case .accept: self?.acceptBonus()
            case .decline: self?.declineBonus()
            }
        }
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
        // Leaving with the question open records the item unrated (or as its preselected answer), and so does work
        // that never finished its item. An open offer is declined and a bonus under way is kept with whatever was done.
        closeTooHardOffer()
        closeEffortCardByDefault()
        flushBonus()
        if adaptive != nil { recordUnfinishedItems() }
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
        var command = command
        // "Done" closes the help list when it's open; otherwise it finishes a self-reported set in progress.
        if command == .closeHelp, !isHelpPresented, session.phase == .exercising,
           session.exercise?.isSelfReported == true {
            command = .nextSet
        }
        let phrase = source == .voice ? lastHeardPhrase : nil
        lastHeardPhrase = nil
        recorder?.recordEvent(.command(command, source: source, phrase: phrase), at: clock.now)
        switch command {
        case .help:
            presentHelp(true)
        case .repCount, .whichSet, .repeatLast:
            // Info keeps the help open so the list stays visible.
            break
        case .tooHard:
            // Not a change to the workout: it flags the item and offers a choice, and the set keeps going.
            openTooHardOffer()
            return
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
             .cancelExerciseChange, .anotherRound, .nextExercise, .endWorkout, .tooHard:
            assertionFailure("Command-backed intents are mapped above.")
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
        let before = adaptive != nil && mayChangeFinishedItems(event) ? session : nil
        apply(session.handle(event, at: now))
        recordState()
        // The offer is about the set under way, so it goes when the set does.
        if tooHardOffer != nil, !Self.isSetActive(session.phase) { closeTooHardOffer() }
        if let before { observeEffort(since: before, at: now) }
    }

    /// Only commands, counted reps, and ticks (a hold's timer, an automatic start) can finish an item or start a set,
    /// so per-frame inputs skip the comparison.
    private func mayChangeFinishedItems(_ event: WorkoutEvent) -> Bool {
        switch event {
        case .command, .repCompleted, .tick: return true
        default: return false
        }
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

    // MARK: - Effort

    /// A finished item and who its evidence is about, kept while its question is open.
    private struct PendingEffort {
        let identity: WorkoutOutcomeAdapter.Identity
        let item: FinishedWorkoutItem
        /// What the user did about the item after flagging it "Too hard?"; nil when they never did.
        var choice: WorkoutOutcomeAdapter.TooHardChoice?
    }

    /// The easier version the engine offered for the item under the open "Too hard?" offer.
    private struct PendingSwap {
        /// The plan item the offer is about.
        let planItemID: UUID
        let item: PrescriptionItem
        let option: EasierSwapOption
    }

    /// A prescribed item rated Easy whose evidence waits for its optional bonus: offered, taken and under way, then
    /// rated. The evidence is recorded once, with the bonus, however that ends.
    private struct PendingBonus {
        enum Stage: Equatable {
            case offered
            /// Taken; the bonus set is the plan item with this id.
            case running(itemID: UUID)
        }

        /// The id of the prescribed item's evidence, which the offer and the bonus card share.
        let evidenceID: UUID
        let identity: WorkoutOutcomeAdapter.Identity
        let item: FinishedWorkoutItem
        /// The prescribed item's own answer: rated Easy, with the amount the user confirmed.
        let answer: WorkoutOutcomeAdapter.Answer
        let offered: Dose
        var stage: Stage
        /// The bonus set once it finished, for the amount it records.
        var finished: FinishedWorkoutItem?
    }

    /// Looks at what one reducer input changed. A set that starts, or the workout ending, closes the open question
    /// unrated and an open offer as declined; an item that finished opens a new question. Nothing here changes the
    /// reducer's transitions.
    private func observeEffort(since before: WorkoutSession, at now: TimeInterval) {
        let phase = session.phase
        if before.phase != phase, phase == .exercising || phase == .ended {
            if effortCard != nil { closeEffortCardByDefault() }
            if bonusOffer != nil { settleBonus(accepted: false) }
        }
        for finished in FinishedItemDetector.finishedItems(before: before, after: session, at: now) {
            if finished.isBonus {
                finishBonus(finished)
            } else {
                beginEffort(for: finished)
            }
        }
        if before.phase != .ended, phase == .ended {
            recordUnfinishedItems()
            flushBonus()
        }
    }

    /// When the workout ends or its screen closes, work that never finished its item (the first set of two, then End
    /// during rest) is recorded once, unrated, with the sets it has.
    private func recordUnfinishedItems() {
        for unfinished in FinishedItemDetector.unfinishedItems(in: session) {
            beginEffort(for: unfinished)
        }
    }

    private func beginEffort(for finished: FinishedWorkoutItem) {
        // What the user did about the item after flagging it is spent here, whatever happens next.
        let choice = tooHardChoices.removeValue(forKey: finished.key)
        // A bonus is asked about on its own card, never as an item of its own.
        guard !finished.isBonus, let identity = effortIdentity(for: finished) else { return }
        // A routine exercise skipped before any work has nothing to rate.
        if case .manual = identity.origin, finished.result == .skipped, !finished.didAnyWork { return }
        // Work the workout ended on is recorded once, however many times that is noticed.
        if finished.result == .endedWorkout, reportedItems.contains(finished.key) { return }
        reportedItems.insert(finished.key)
        // An earlier question that is still open closes first (as its preselected answer, or unrated), and an open
        // offer is declined.
        closeEffortCardByDefault()
        if pendingBonus?.stage == .offered { settleBonus(accepted: false) }
        let id = makeEvidenceID()
        guard finished.result != .endedWorkout else {
            // The workout is over, so there is no question: the item is recorded as it ended.
            recordEvidence(id: id, identity: identity, item: finished, answer: nil, tooHard: choice)
            return
        }
        // Stopping an item, or taking an easier version, said it was too hard, so the card opens on that answer.
        let preselected: EffortFeedback? = choice == .stoppedHere || choice == .switchedToEasier ? .tooHard : nil
        effortCard = EffortCardState(id: id, unit: finished.unit, setCount: finished.setAmounts.count,
                                     amount: finished.counted, preselected: preselected)
        pendingEffort = PendingEffort(identity: identity, item: finished, choice: choice)
        voice?.acceptsEffortFeedback = true
    }

    /// Today's Session items carry their prescription; any other exercise is manual work, and counts only when it is
    /// the current rung of an active family.
    private func effortIdentity(for finished: FinishedWorkoutItem) -> WorkoutOutcomeAdapter.Identity? {
        // An easier version the user took has its own prescription, so its evidence points at that one.
        if let planItemID = finished.planItemID, let swap = easierSwaps[planItemID] {
            return WorkoutOutcomeAdapter.Identity(
                origin: .adaptive(prescriptionID: swap.prescriptionID, itemID: swap.item.itemID,
                                  prescribed: swap.item.rungDose.dose),
                family: swap.item.family, variant: swap.item.rungDose.variant)
        }
        if let launch = todayLaunch, let planItemID = finished.planItemID,
           let item = launch.items.first(where: { $0.itemID == planItemID }) {
            // Only a main item whose prescription offers one may earn a bonus.
            let offersBonus = item.role == .main
                && launch.prescription.items.first(where: { $0.id == item.itemID })?.offersBonus == true
            return WorkoutOutcomeAdapter.Identity(
                origin: .adaptive(prescriptionID: launch.prescription.id, itemID: item.itemID,
                                  prescribed: item.rungDose.dose),
                family: item.family, variant: item.rungDose.variant, offersBonus: offersBonus)
        }
        guard let rung = adaptive?.activeRung(for: finished.exerciseID, reducedRange: finished.reducedRange) else {
            return nil
        }
        return WorkoutOutcomeAdapter.Identity(origin: .manual, family: rung.family, variant: rung.rungDose.variant)
    }

    /// Closes the open question without the user choosing: starting the next set, ending the workout, or leaving. A
    /// card that opened on an answer (Too Hard after "Stop here") records it; any other is recorded unrated.
    private func closeEffortCardByDefault() {
        closeEffortCard(rating: effortCard?.preselected)
    }

    /// Closes the open question and records the item with the user's rating, or unrated when `rating` is nil.
    private func closeEffortCard(rating: EffortFeedback?) {
        guard let card = effortCard else { return }
        let answer = WorkoutOutcomeAdapter.Answer(effort: rating, amount: card.amount, isAdjusted: card.isAdjusted)
        if card.isBonus {
            effortCard = nil
            voice?.acceptsEffortFeedback = false
            settleBonus(accepted: true, answer: answer)
            return
        }
        guard let pending = pendingEffort else { return }
        effortCard = nil
        pendingEffort = nil
        voice?.acceptsEffortFeedback = false
        // Easy on a main item that offers one earns a bonus offer; the evidence then waits for the offer's outcome.
        if let offered = WorkoutOutcomeAdapter.bonusOffer(identity: pending.identity, item: pending.item, answer: answer,
                                                          tooHard: pending.choice) {
            pendingBonus = PendingBonus(evidenceID: card.id, identity: pending.identity, item: pending.item,
                                        answer: answer, offered: offered, stage: .offered)
            bonusOffer = BonusOfferState(id: card.id, offered: offered)
            voice?.acceptsBonusAnswer = true
            return
        }
        recordEvidence(id: card.id, identity: pending.identity, item: pending.item, answer: answer,
                       tooHard: pending.choice)
    }

    private func recordEvidence(id: UUID, identity: WorkoutOutcomeAdapter.Identity, item: FinishedWorkoutItem,
                                answer: WorkoutOutcomeAdapter.Answer?, bonus: BonusRecord? = nil,
                                tooHard: WorkoutOutcomeAdapter.TooHardChoice? = nil) {
        adaptive?.record(WorkoutOutcomeAdapter.evidence(id: id, recordedAt: evidenceDate(), workoutID: workoutID,
                                                        identity: identity, item: item, answer: answer, bonus: bonus,
                                                        tooHard: tooHard))
    }

    // MARK: - Too hard

    /// A set is under way while exercising or paused. A chooser opened over it is not "a set to flag".
    private static func isSetActive(_ phase: WorkoutPhase) -> Bool {
        switch phase {
        case .exercising, .paused: return true
        default: return false
        }
    }

    /// "Too hard?" during a set (the button or the voice command): the item is flagged and the offer opens. Nothing
    /// stops, pauses, or changes what the tracker sees. Outside a set, or with a question open, it does nothing.
    private func openTooHardOffer() {
        guard Self.isSetActive(session.phase), effortCard == nil, bonusOffer == nil,
              let key = FinishedItemDetector.currentKey(in: session) else { return }
        if tooHardChoices[key] == nil { tooHardChoices[key] = .flagged }
        guard tooHardOffer == nil else { return }
        let easier = easierVersionToOffer()
        pendingSwap = easier?.swap
        tooHardOffer = TooHardOfferState(id: makeEvidenceID(), easierVersion: easier?.version)
    }

    /// The easier version of the item under way, only for a Today's Session main item and only when the engine has
    /// one the coach can run. The engine decides; the app just looks.
    private func easierVersionToOffer() -> (swap: PendingSwap, version: TooHardOfferState.EasierVersion)? {
        guard let adaptive, let launch = todayLaunch, let planItem = session.currentPlanItem,
              let adaptiveItem = launch.items.first(where: { $0.itemID == planItem.id }), adaptiveItem.role == .main,
              let item = launch.prescription.items.first(where: { $0.id == planItem.id }),
              let option = adaptive.easierSwapOption(for: item, asOf: evidenceDate()),
              let base = session.exercises.first(where: { $0.id == option.exerciseID }) else { return nil }
        let name = WorkoutPlanItem(id: planItem.id, exerciseID: option.exerciseID, sets: 1, targetReps: 1...1,
                                   reducedRange: option.reducedRange).resolved(from: base).displayName
        return (PendingSwap(planItemID: planItem.id, item: item, option: option),
                TooHardOfferState.EasierVersion(name: name, amountLabel: WorkAmount(option.target.dose).description))
    }

    func stopHere() {
        guard tooHardOffer != nil, Self.isSetActive(session.phase),
              let key = FinishedItemDetector.currentKey(in: session) else {
            closeTooHardOffer()
            return
        }
        tooHardChoices[key] = .stoppedHere
        closeTooHardOffer()
        endItemNow()
    }

    func takeEasierVersion() {
        guard tooHardOffer != nil, let pending = pendingSwap, let adaptive, Self.isSetActive(session.phase),
              session.currentPlanItem?.id == pending.planItemID,
              let key = FinishedItemDetector.currentKey(in: session) else { return }
        guard let issued = adaptive.issueEasierSwap(replacing: pending.item, option: pending.option,
                                                    at: evidenceDate()) else {
            // It couldn't be saved, so nothing was taken: the offer keeps only Stop here.
            pendingSwap = nil
            tooHardOffer?.easierVersion = nil
            return
        }
        easierSwaps[issued.item.itemID] = issued
        tooHardChoices[key] = .switchedToEasier
        closeTooHardOffer()
        endItemNow()
        dispatch(.startEasierSwap(EasierSwapRequest(itemID: issued.item.itemID, after: pending.planItemID,
                                                    exerciseID: issued.item.exerciseID,
                                                    reducedRange: issued.item.reducedRange,
                                                    amount: issued.item.rungDose.dose.amount)))
        // The reducer refuses a swap it can't run; no easier version is running then, so the item just stopped early.
        if session.plan?.items.contains(where: { $0.id == issued.item.itemID }) != true {
            easierSwaps[issued.item.itemID] = nil
            pendingEffort?.choice = .stoppedHere
        }
    }

    func dismissTooHardOffer() {
        closeTooHardOffer()
    }

    private func closeTooHardOffer() {
        tooHardOffer = nil
        pendingSwap = nil
    }

    /// Ends the item under way with what was done: the set finishes the way Done finishes it (the counted reps, the
    /// seconds held, or a self-reported set's prescribed amount, which the card then lets the user correct). In a plan
    /// the item's remaining sets are skipped; a standalone exercise ends without scheduling any (no rest, so nothing
    /// can start after a rest deadline).
    private func endItemNow() {
        guard session.isFollowingPlan else {
            handleVoiceCommand(.stopItem)
            return
        }
        let itemID = session.currentPlanItem?.id
        handleVoiceCommand(.nextSet)
        if let itemID, session.currentPlanItem?.id == itemID, session.planRecords[itemID] == nil {
            handleVoiceCommand(.nextExercise)
        }
    }

    // MARK: - Bonus

    /// Takes the offer: one more set of the same exercise and variant is inserted right after the item, without a
    /// rest. Nothing is recorded until the bonus is done and rated, or the workout ends.
    func acceptBonus() {
        guard let pending = pendingBonus, pending.stage == .offered, let after = pending.item.planItemID else { return }
        let itemID = makeEvidenceID()
        bonusOffer = nil
        voice?.acceptsBonusAnswer = false
        pendingBonus?.stage = .running(itemID: itemID)
        dispatch(.startBonus(BonusRequest(itemID: itemID, after: after, amount: pending.offered.amount)))
        // The reducer refuses a bonus it can't run; nothing was taken then, and nothing is lost.
        if session.plan?.items.contains(where: { $0.id == itemID }) != true { settleBonus(accepted: false) }
    }

    /// Declines the offer. The item is a full success; its evidence is recorded now.
    func declineBonus() {
        guard pendingBonus?.stage == .offered else { return }
        settleBonus(accepted: false)
    }

    /// The bonus set finished or was left: ask how it was when there is something to rate, else record it as it ended.
    private func finishBonus(_ finished: FinishedWorkoutItem) {
        // What the user did about the bonus after flagging it is spent here. The prescribed item's rating is its own.
        let choice = tooHardChoices.removeValue(forKey: finished.key)
        guard var pending = pendingBonus, case .running(let itemID) = pending.stage,
              itemID == finished.planItemID else { return }
        pending.finished = finished
        pendingBonus = pending
        // A workout that ended, or a bonus skipped before any work, has no question to ask.
        guard finished.result != .endedWorkout, finished.result == .completed || finished.didAnyWork else {
            settleBonus(accepted: true)
            return
        }
        // "Stop here" on the bonus opens its card on Too Hard, like any item's; the bonus's own rating is what it records.
        effortCard = EffortCardState(id: pending.evidenceID, unit: finished.unit, setCount: finished.setAmounts.count,
                                     amount: finished.counted, isBonus: true,
                                     preselected: choice == .stoppedHere ? .tooHard : nil)
        voice?.acceptsEffortFeedback = true
    }

    /// The workout ended or its screen closed: an open offer is declined, and a bonus under way is kept with whatever
    /// was done.
    private func flushBonus() {
        guard var pending = pendingBonus else { return }
        guard case .running(let itemID) = pending.stage else {
            settleBonus(accepted: false)
            return
        }
        // Closing the screen mid-set never ran the reducer's end transition, so the set under way is read from the
        // session now. The usual rules apply: seconds held are kept, a camera count stays unconfirmed, and a
        // self-reported set nobody marked done adds nothing.
        if pending.finished == nil, let inProgress = FinishedItemDetector.itemInProgress(in: session, at: clock.now),
           inProgress.planItemID == itemID {
            pending.finished = inProgress
            pendingBonus = pending
        }
        settleBonus(accepted: true)
    }

    /// Records the item's evidence once, with the bonus's outcome. Declining carries nothing else. A bonus taken
    /// carries the amount the user confirmed on its card, and the rating if they gave one; a lost tracker is never
    /// read as a failed bonus.
    private func settleBonus(accepted: Bool, answer: WorkoutOutcomeAdapter.Answer? = nil) {
        guard let pending = pendingBonus else { return }
        pendingBonus = nil
        bonusOffer = nil
        voice?.acceptsBonusAnswer = false
        let record = WorkoutOutcomeAdapter.bonusRecord(offered: pending.offered, accepted: accepted,
                                                       item: pending.finished, answer: answer)
        recordEvidence(id: pending.evidenceID, identity: pending.identity, item: pending.item, answer: pending.answer,
                       bonus: record)
    }

    func rateEffort(_ effort: EffortFeedback) {
        closeEffortCard(rating: effort)
    }

    func skipEffort() {
        closeEffortCard(rating: nil)
    }

    /// Changes the amount on the open card by whole steps (1 rep or 5 seconds each).
    func adjustEffortAmount(by steps: Int) {
        effortCard?.adjust(by: steps)
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
