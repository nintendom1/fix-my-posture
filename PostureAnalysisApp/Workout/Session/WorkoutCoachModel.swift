import AVFoundation
import SwiftUI

/// Overlay display state in mirrored, normalized Vision coordinates.
struct WorkoutOverlayState: Equatable {
    var imageSize: CGSize
    var joints: [LandmarkType: OverlayJoint]
    var segments: [FocusSegment]
    /// Arms at their counted end position while counting.
    var endPositionSides: Set<BodySide>
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

    var captureSession: AVCaptureSession { camera.session }
    var exercises: [ExerciseDefinition] { session.exercises }

    private let camera: PoseFrameSource
    private let permission: RealtimeCameraPermission
    private let speech: SpeechCoaching
    private let audio: WorkoutAudioSession?
    private let tiltMonitor: PhoneTiltMonitoring?
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

    static let tickInterval: TimeInterval = 0.5

    convenience init() {
        let audio = WorkoutAudioSession()
        self.init(camera: WorkoutCameraController(), permission: SystemCameraPermission(),
                  speech: SpeechCoach(audio: audio), audio: audio, tiltMonitor: CoreMotionTiltMonitor(),
                  exercises: ExerciseCatalog.all, initialExercise: ExerciseCatalog.all.first?.id)
    }

    init(camera: PoseFrameSource, permission: RealtimeCameraPermission, speech: SpeechCoaching,
         audio: WorkoutAudioSession?, tiltMonitor: PhoneTiltMonitoring?,
         exercises: [ExerciseDefinition], initialExercise: ExerciseID?,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.camera = camera
        self.permission = permission
        self.speech = speech
        self.audio = audio
        self.tiltMonitor = tiltMonitor
        self.clock = clock
        session = WorkoutSession(exercises: exercises, initialExercise: initialExercise)
        now = clock()
        audio?.onEvent = { [weak self] event in self?.handleAudio(event) }
        speech.onActivityChanged = { [weak self] speaking in self?.isCoachSpeaking = speaking }
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
        apply(session.handle(.command(command), at: clock()))
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
        camera.start(generation: generation) { [weak self] token, event in
            guard let self, self.canCapture, token == self.generation else { return }
            self.handle(event)
        }
    }

    private func stopCapture() {
        generation = UUID()
        camera.stop()
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
            for rep in analysis.repEvents {
                apply(session.handle(.repCompleted(rep), at: clock()))
            }
        }

        // Display only: mirror for the selfie preview, then smooth.
        let display = RealtimePoseProcessing.displayPose(frame.pose, mirrored: true)
        overlay = WorkoutOverlayState(
            imageSize: frame.imageSize,
            joints: smoother.update(pose: display, joints: exercise.focusJoints, at: frame.timestamp),
            segments: exercise.focusSegments,
            endPositionSides: endSides
        )
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
        guard let left = frame.point(.leftShoulder, minimumConfidence: confidence),
              let right = frame.point(.rightShoulder, minimumConfidence: confidence) else { return }
        let shoulderWidth = ArmGeometry.distance(left, right)
        guard shoulderWidth > 1 else { return }
        let arms = BodySide.allCases.compactMap { ArmGeometry.arm($0, in: frame, minimumConfidence: confidence) }
        func measured(_ lengths: [CGFloat], typical: CGFloat) -> CGFloat {
            let plausible = lengths.filter { GuideMetrics.plausibleSegmentRatio.contains($0 / shoulderWidth) }
            guard !plausible.isEmpty else { return shoulderWidth * typical }
            return plausible.reduce(0, +) / CGFloat(plausible.count)
        }
        let sample = GuideMetrics(upperArm: measured(arms.map(\.upperArmLength), typical: GuideMetrics.upperArmToShoulderWidth),
                                  forearm: measured(arms.map(\.forearmLength), typical: GuideMetrics.forearmToShoulderWidth))
        guard let previous = guideMetrics else {
            guideMetrics = sample
            return
        }
        let k = GuideMetrics.smoothing
        guideMetrics = GuideMetrics(upperArm: previous.upperArm + (sample.upperArm - previous.upperArm) * k,
                                    forearm: previous.forearm + (sample.forearm - previous.forearm) * k)
    }

    private func updatePhoneTilt(at now: TimeInterval) {
        setPhoneTilted(tiltDetector.update(pitchDegrees: tiltMonitor?.latestTilt?.pitchDegrees, at: now))
    }

    private func setPhoneTilted(_ tilted: Bool) {
        guard tilted != isPhoneTilted else { return }
        isPhoneTilted = tilted
        apply(session.handle(.phoneTiltChanged(tilted), at: clock()))
    }

    private func rebuildTracking(for exercise: ExerciseDefinition) {
        framingEvaluator = FramingEvaluator(requiredJoints: exercise.requiredJoints,
                                            headroomArmLengths: exercise.headroomArmLengths)
        framingExerciseID = exercise.id
        lastFramingStatus = nil
        smoother.reset()
    }

    // MARK: - Effects

    private func apply(_ effects: [WorkoutEffect]) {
        for effect in effects {
            switch effect {
            case .speak(let utterance):
                speech.speak(utterance)
            case .repeatLastInstruction:
                speech.repeatLastInstruction()
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
            speech.stopAll()
            apply(session.handle(.interruptionBegan, at: clock()))
        case .interruptionEnded:
            apply(session.handle(.interruptionEnded, at: clock()))
        case .mediaServicesReset:
            speech.stopAll()
        }
    }
}
