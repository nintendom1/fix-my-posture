import AVFoundation
import SwiftUI

/// Overlay display state in mirrored, normalized Vision coordinates.
struct WorkoutOverlayState: Equatable {
    var imageSize: CGSize
    var joints: [LandmarkType: OverlayJoint]
    var segments: [FocusSegment]
    /// Arms at their counted end position while counting.
    var endPositionSides: Set<BodySide>
    /// Every detected joint, mirrored but unsmoothed; tips keep clear of the whole body.
    var pose: BodyPose
    /// Joints the active corrective tip refers to; drawn amber.
    var emphasizedJoints: Set<LandmarkType> = []
}

/// Smoothed arm-segment lengths in image pixels, used to fit the ghost demo to the user.
struct GuideMetrics: Equatable {
    var upperArm: CGFloat
    var forearm: CGFloat

    /// Typical proportions relative to shoulder width, used until segments have been measured.
    static let upperArmToShoulderWidth: CGFloat = 0.85
    static let forearmToShoulderWidth: CGFloat = 0.72
    /// Measured segments outside this shoulder-width-relative range are treated as noise.
    static let plausibleSegmentRatio: ClosedRange<CGFloat> = 0.45...1.4
    /// From the side, shoulder width vanishes, so segments are judged against torso length instead.
    static let upperArmToTorso: CGFloat = 0.53
    static let forearmToTorso: CGFloat = 0.47
    static let plausibleTorsoRatio: ClosedRange<CGFloat> = 0.3...0.9
    static let smoothing: CGFloat = 0.25
}

/// Main-actor orchestrator: feeds camera frames, commands, and lifecycle changes through the pure
/// `WorkoutSession` reducer and carries out the effects it returns.
@MainActor
final class WorkoutCoachModel: ObservableObject {
    enum CameraStatus: Equatable {
        case idle
        case starting
        case running
        case interrupted
        case notAuthorized
        case failed(String)
    }

    @Published private(set) var session: WorkoutSession
    @Published private(set) var cameraStatus: CameraStatus = .idle
    @Published private(set) var overlay: WorkoutOverlayState?
    /// Refreshed on every tick for the rest timer.
    @Published private(set) var now: TimeInterval
    @Published private(set) var guideMetrics: GuideMetrics?
    @Published private(set) var armReadings: [BodySide: ArmReading] = [:]
    @Published private(set) var armThresholds: [BodySide: ArmThresholds] = [:]
    /// The phone leans forward or back enough to distort heights.
    @Published private(set) var isPhoneTilted = false
    @Published private(set) var isCoachSpeaking = false
    /// The camera has run and the coach has introduced the workout.
    @Published private(set) var hasOpened = false
    @Published private(set) var micStatus: WorkoutVoiceController.Status = .off
    /// The phrase behind the most recent voice command, shown briefly as a "Heard" chip.
    @Published private(set) var heardPhrase: String?
    /// The Voice Commands help is open. Capture and listening continue behind it.
    @Published private(set) var isHelpPresented = false
    /// The coach says nothing at all, so other audio is never ducked. Remembered between workouts.
    @Published private(set) var isCoachMuted: Bool
    /// The microphone stays off until the user turns it back on. Remembered between workouts.
    @Published private(set) var isMicMuted: Bool
    /// The coaching tip on screen; it clears after `tipDuration`.
    @Published private(set) var activeTip: CoachingTip?
    /// The last rep's form values, for Show Measurements.
    @Published private(set) var formReadings: [FormReading] = []

    var captureSession: AVCaptureSession { camera.session }
    var exercises: [ExerciseDefinition] { session.exercises }

    private let camera: PoseFrameSource
    private let permission: RealtimeCameraPermission
    private let speech: SpeechCoaching
    private let audio: WorkoutAudioSession?
    private let tiltMonitor: PhoneTiltMonitoring?
    private let voice: WorkoutVoiceController?
    private let defaults: UserDefaults
    private let clock: () -> TimeInterval

    private var analyzer: ExerciseAnalyzing?
    private var framingEvaluator: FramingEvaluator?
    private var framingExerciseID: ExerciseID?
    private var lastFramingStatus: FramingStatus?
    private var smoother = LandmarkSmoother()
    private var isCounting = false
    private var generation = UUID()
    private var isGuidePresented = false
    private var lastStartPositionHeld = false
    private var tiltDetector = PhoneTiltDetector()
    private var isViewActive = false
    private var isApplicationActive = false
    private var isRequestingPermission = false
    private var tickTimer: Timer?
    private var heardGeneration = 0

    static let tickInterval: TimeInterval = 0.5
    static let heardChipDuration: TimeInterval = 1.5
    static let tipDuration = CoachingCueScheduler.Configuration().tipDuration
    /// Spoken once per install, after the intro, when voice first works.
    static let voiceTipKey = "workoutCoach.voiceTipSpoken"
    static let voiceTip = "Say \u{201C}what can I say\u{201D} anytime to see voice commands."
    static let coachMutedKey = "workoutCoach.coachMuted"
    static let micMutedKey = "workoutCoach.micMuted"

    convenience init(initialExercise: ExerciseID? = nil) {
        let audio = WorkoutAudioSession()
        let exercises = ExerciseCatalog.all
        let voice = WorkoutVoiceController(recognizer: OnDeviceSpeechRecognizer(),
                                           parser: VoiceCommandParser(exercises: exercises),
                                           permissions: SystemVoicePermissions(), audio: audio)
        self.init(camera: WorkoutCameraController(), permission: SystemCameraPermission(),
                  speech: SpeechCoach(audio: audio), audio: audio, tiltMonitor: CoreMotionTiltMonitor(),
                  voice: voice, exercises: exercises, initialExercise: initialExercise ?? exercises.first?.id)
    }

    init(camera: PoseFrameSource, permission: RealtimeCameraPermission, speech: SpeechCoaching,
         audio: WorkoutAudioSession?, tiltMonitor: PhoneTiltMonitoring?, voice: WorkoutVoiceController?,
         exercises: [ExerciseDefinition], initialExercise: ExerciseID?, defaults: UserDefaults = .standard,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.camera = camera
        self.permission = permission
        self.speech = speech
        self.audio = audio
        self.tiltMonitor = tiltMonitor
        self.voice = voice
        self.defaults = defaults
        self.clock = clock
        isCoachMuted = defaults.bool(forKey: Self.coachMutedKey)
        isMicMuted = defaults.bool(forKey: Self.micMutedKey)
        session = WorkoutSession(exercises: exercises, initialExercise: initialExercise)
        now = clock()
        audio?.onEvent = { [weak self] event in self?.handleAudio(event) }
        speech.onActivityChanged = { [weak self] speaking in
            self?.coachSpeakingChanged(speaking)
        }
        voice?.onCommand = { [weak self] command in self?.send(command) }
        voice?.onHeard = { [weak self] phrase in self?.showHeard(phrase) }
        voice?.onStatusChanged = { [weak self] status in self?.voiceStatusChanged(status) }
        // A remembered muted microphone never starts listening or asks for permission.
        if isMicMuted { voice?.setMuted(true) }
    }

    // MARK: - Lifecycle

    private var canCapture: Bool {
        isViewActive && isApplicationActive && !isGuidePresented && session.phase != .ended
    }

    func onAppear(isApplicationActive: Bool) {
        isViewActive = true
        self.isApplicationActive = isApplicationActive
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
            apply(session.handle(.appForegrounded, at: clock()))
            startCaptureIfPossible()
        } else {
            apply(session.handle(.appBackgrounded, at: clock()))
            stopCapture()
            speech.stopAll()
        }
    }

    func send(_ command: WorkoutCommand) {
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
        apply(session.handle(.command(command), at: clock()))
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
            if session.phase == .exercising { send(.pause) }
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
        defaults.set(muted, forKey: Self.coachMutedKey)
        if muted {
            // Cut the current line now; this also restores any ducked audio.
            speech.stopAll()
        } else {
            // After the current command, so "Coach voice on." comes first.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.speakVoiceTipIfNeeded() }
            }
        }
    }

    func setMicMuted(_ muted: Bool) {
        guard muted != isMicMuted else { return }
        isMicMuted = muted
        defaults.set(muted, forKey: Self.micMutedKey)
        voice?.setMuted(muted)
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
        session.startHoldProgress(at: clock())
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
        tiltDetector.reset()
        setPhoneTilted(false)
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
                apply(session.handle(.opened, at: clock()))
                speakVoiceTipIfNeeded()
            } else if wasInterrupted {
                apply(session.handle(.interruptionEnded, at: clock()))
            }
        case .frame(let frame):
            process(frame)
        case .interrupted:
            cameraStatus = .interrupted
            apply(session.handle(.interruptionBegan, at: clock()))
            resetTracking()
        case .failed(let message):
            cameraStatus = .failed(message)
            apply(session.handle(.interruptionBegan, at: clock()))
            resetTracking()
            speech.stopAll()
        }
    }

    private func process(_ frame: PoseFrame) {
        guard let exercise = session.exercise else {
            overlay = nil
            return
        }
        if framingExerciseID != exercise.id { rebuildTracking(for: exercise) }
        if var evaluator = framingEvaluator {
            let status = evaluator.evaluate(frame)
            framingEvaluator = evaluator
            if status != lastFramingStatus {
                lastFramingStatus = status
                apply(session.handle(.framingChanged(status), at: clock()))
            }
        }

        updateGuideMetrics(frame)

        var endSides: Set<BodySide> = []
        if let analyzer {
            let analysis = analyzer.process(frame, counting: isCounting)
            if isCounting { endSides = analysis.endPositionSides }
            if armReadings != analysis.readings { armReadings = analysis.readings }
            if armThresholds != analysis.thresholds { armThresholds = analysis.thresholds }
            setStartPositionHeld(analysis.startPositionHeld)
            // Start as soon as the hold completes rather than waiting for the next tick.
            let time = clock()
            if session.startHoldProgress(at: time) == 1 { apply(session.handle(.tick, at: time)) }
            for rep in analysis.repEvents {
                apply(session.handle(.repCompleted(rep), at: clock()))
            }
            if formReadings != analysis.formReadings { formReadings = analysis.formReadings }
            // After reps, so a rep that completes the set isn't followed by a stale cue.
            if isCounting {
                let observation = FormObservation(epoch: analyzer.epoch, repForms: analysis.repForms,
                                                  signals: analysis.formSignals)
                apply(session.handle(.formObserved(observation), at: clock()))
            }
        }

        // Display only: mirror for the selfie preview, then smooth.
        let display = RealtimePoseProcessing.displayPose(frame.pose, mirrored: true)
        overlay = WorkoutOverlayState(
            imageSize: frame.imageSize,
            joints: smoother.update(pose: display, joints: exercise.focusJoints, at: frame.timestamp),
            segments: exercise.focusSegments,
            endPositionSides: endSides,
            pose: display,
            emphasizedJoints: emphasizedJoints
        )
    }

    private var emphasizedJoints: Set<LandmarkType> {
        guard let cue = activeTip?.cue, cue.kind == .corrective else { return [] }
        return cue.joints
    }

    /// The session sees a fresh, unreliable start; the overlay clears.
    private func resetTracking() {
        framingEvaluator?.reset()
        lastFramingStatus = nil
        smoother.reset()
        overlay = nil
        guideMetrics = nil
        armReadings = [:]
        armThresholds = [:]
        formReadings = []
        setStartPositionHeld(false)
        if session.framing != .lost {
            apply(session.handle(.framingChanged(.lost), at: clock()))
        }
    }

    private func setStartPositionHeld(_ held: Bool) {
        guard held != lastStartPositionHeld else { return }
        lastStartPositionHeld = held
        apply(session.handle(.startPositionChanged(held), at: clock()))
    }

    /// Arm-segment lengths from the raw pose, smoothed so the ghost doesn't flicker. Shoulder width
    /// rejects implausible segments and stands in until the arms are measured.
    private func updateGuideMetrics(_ frame: PoseFrame) {
        let confidence = FramingConfiguration().minimumConfidence
        guard let reference = metricsReference(frame, confidence: confidence) else { return }
        let arms = BodySide.allCases.compactMap { ArmGeometry.arm($0, in: frame, minimumConfidence: confidence) }
        func measured(_ lengths: [CGFloat], typical: CGFloat) -> CGFloat {
            let plausible = lengths.filter { reference.plausible.contains($0 / reference.length) }
            guard !plausible.isEmpty else { return reference.length * typical }
            return plausible.reduce(0, +) / CGFloat(plausible.count)
        }
        let sample = GuideMetrics(upperArm: measured(arms.map(\.upperArmLength), typical: reference.upperArm),
                                  forearm: measured(arms.map(\.forearmLength), typical: reference.forearm))
        guard let previous = guideMetrics else {
            guideMetrics = sample
            return
        }
        let k = GuideMetrics.smoothing
        guideMetrics = GuideMetrics(upperArm: previous.upperArm + (sample.upperArm - previous.upperArm) * k,
                                    forearm: previous.forearm + (sample.forearm - previous.forearm) * k)
    }

    /// The body length arm segments are checked against: shoulder width from the front, torso length
    /// (shoulder to hip on either side) from the side.
    private func metricsReference(_ frame: PoseFrame, confidence: Double)
        -> (length: CGFloat, upperArm: CGFloat, forearm: CGFloat, plausible: ClosedRange<CGFloat>)? {
        if session.exercise?.cameraView == .side {
            for side in BodySide.allCases {
                guard let shoulder = frame.point(side.shoulder, minimumConfidence: confidence),
                      let hip = frame.point(side.hip, minimumConfidence: confidence) else { continue }
                let torso = ArmGeometry.distance(shoulder, hip)
                if torso > 1 {
                    return (torso, GuideMetrics.upperArmToTorso, GuideMetrics.forearmToTorso, GuideMetrics.plausibleTorsoRatio)
                }
            }
            return nil
        }
        guard let left = frame.point(.leftShoulder, minimumConfidence: confidence),
              let right = frame.point(.rightShoulder, minimumConfidence: confidence) else { return nil }
        let width = ArmGeometry.distance(left, right)
        guard width > 1 else { return nil }
        return (width, GuideMetrics.upperArmToShoulderWidth, GuideMetrics.forearmToShoulderWidth, GuideMetrics.plausibleSegmentRatio)
    }

    private func updatePhoneTilt(at now: TimeInterval) {
        guard session.exercise?.warnsAboutTilt ?? true else {
            tiltDetector.reset()
            setPhoneTilted(false)
            return
        }
        setPhoneTilted(tiltDetector.update(pitchDegrees: tiltMonitor?.latestTilt?.pitchDegrees, at: now))
    }

    private func setPhoneTilted(_ tilted: Bool) {
        guard tilted != isPhoneTilted else { return }
        isPhoneTilted = tilted
        apply(session.handle(.phoneTiltChanged(tilted), at: clock()))
    }

    private func rebuildTracking(for exercise: ExerciseDefinition) {
        framingEvaluator = FramingEvaluator(requiredJoints: exercise.requiredJoints,
                                            anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                                            headroomArmLengths: exercise.headroomArmLengths,
                                            cameraView: exercise.cameraView)
        framingExerciseID = exercise.id
        // The previous exercise's lines and readings must not linger after a switch.
        armReadings = [:]
        armThresholds = [:]
        formReadings = []
        lastFramingStatus = nil
        smoother.reset()
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
                    analyzer = nil
                    continue
                }
                analyzer = exercise.makeAnalyzer(epoch)
                if exercise.id != framingExerciseID { rebuildTracking(for: exercise) }
            case .setCounting(let counting):
                isCounting = counting
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
        tickTimer?.invalidate()
        now = clock()
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTicks() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        now = clock()
        updatePhoneTilt(at: now)
        apply(session.handle(.tick, at: now))
    }

    private func handleAudio(_ event: WorkoutAudioSession.Event) {
        switch event {
        case .interruptionBegan:
            // Calls and Siri: pause, stop listening, and let other audio return.
            voice?.disable(status: .paused)
            speech.stopAll()
            apply(session.handle(.interruptionBegan, at: clock()))
        case .interruptionEnded(let shouldResume):
            // The workout stays paused; voice resumes only when the system says so.
            if shouldResume, canCapture, !isMicMuted { voice?.enable() }
            apply(session.handle(.interruptionEnded, at: clock()))
        case .mediaServicesReset:
            speech.stopAll()
            voice?.handleAudioEvent(event)
        case .routeChanged, .reactivated:
            voice?.handleAudioEvent(event)
        }
    }

    private func voiceStatusChanged(_ status: WorkoutVoiceController.Status) {
        let wasUsable = micStatus.isUsable
        micStatus = status
        if status.isUsable != wasUsable {
            apply(session.handle(.voiceControlChanged(status.isUsable), at: clock()))
        }
        speakVoiceTipIfNeeded()
    }

    /// Once per install, after the intro and once voice works, mention the help command.
    private func speakVoiceTipIfNeeded() {
        guard hasOpened, micStatus.isUsable, !isCoachMuted, !defaults.bool(forKey: Self.voiceTipKey) else { return }
        defaults.set(true, forKey: Self.voiceTipKey)
        speech.speak(Utterance(text: Self.voiceTip, isInstruction: false))
    }

    private func coachSpeakingChanged(_ speaking: Bool) {
        isCoachSpeaking = speaking
        voice?.setCoachSpeaking(speaking)
        apply(session.handle(.coachSpeakingChanged(speaking), at: clock()))
    }

    /// Shows a tip for `tipDuration`; a newer tip or a cleared one cancels the pending hide.
    private func setActiveTip(_ tip: CoachingTip?) {
        activeTip = tip
        overlay?.emphasizedJoints = emphasizedJoints
        guard let id = tip?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tipDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.activeTip?.id == id else { return }
                self.setActiveTip(nil)
            }
        }
    }

    private func showHeard(_ phrase: String) {
        heardGeneration += 1
        let generation = heardGeneration
        heardPhrase = phrase
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.heardChipDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.heardGeneration == generation else { return }
                self.heardPhrase = nil
            }
        }
    }
}
