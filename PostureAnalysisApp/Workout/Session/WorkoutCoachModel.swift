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

    var captureSession: AVCaptureSession { camera.session }
    var exercises: [ExerciseDefinition] { session.exercises }

    private let camera: PoseFrameSource
    private let permission: RealtimeCameraPermission
    private let speech: SpeechCoaching
    private let audio: WorkoutAudioSession?
    private let clock: () -> TimeInterval

    private var analyzer: ExerciseAnalyzing?
    private var framingEvaluator: FramingEvaluator?
    private var framingExerciseID: ExerciseID?
    private var lastFramingStatus: FramingStatus?
    private var smoother = LandmarkSmoother()
    private var isCounting = false
    private var generation = UUID()
    private var hasOpened = false
    private var isViewActive = false
    private var isApplicationActive = false
    private var isRequestingPermission = false
    private var tickTimer: Timer?

    static let tickInterval: TimeInterval = 0.5

    convenience init() {
        let audio = WorkoutAudioSession()
        self.init(camera: WorkoutCameraController(), permission: SystemCameraPermission(),
                  speech: SpeechCoach(audio: audio), audio: audio,
                  exercises: ExerciseCatalog.all, initialExercise: ExerciseCatalog.all.first?.id)
    }

    init(camera: PoseFrameSource, permission: RealtimeCameraPermission, speech: SpeechCoaching,
         audio: WorkoutAudioSession?, exercises: [ExerciseDefinition], initialExercise: ExerciseID?,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.camera = camera
        self.permission = permission
        self.speech = speech
        self.audio = audio
        self.clock = clock
        session = WorkoutSession(exercises: exercises, initialExercise: initialExercise)
        now = clock()
        audio?.onEvent = { [weak self] event in self?.handleAudio(event) }
    }

    // MARK: - Lifecycle

    private var canCapture: Bool { isViewActive && isApplicationActive && session.phase != .ended }

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
        camera.start(generation: generation) { [weak self] token, event in
            guard let self, self.canCapture, token == self.generation else { return }
            self.handle(event)
        }
    }

    private func stopCapture() {
        generation = UUID()
        camera.stop()
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

        var endSides: Set<BodySide> = []
        if let analyzer {
            let analysis = analyzer.process(frame, counting: isCounting)
            if isCounting { endSides = analysis.endPositionSides }
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
        if session.framing != .lost {
            apply(session.handle(.framingChanged(.lost), at: clock()))
        }
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
