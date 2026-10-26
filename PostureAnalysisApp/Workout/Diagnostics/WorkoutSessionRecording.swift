import Foundation

/// Where a marker came from.
enum WorkoutMarkerSource: String, Equatable {
    case voice
    case tap
}

/// A moment the user flagged during a workout, for review later.
struct WorkoutMarker: Equatable, Identifiable {
    let id: UUID
    /// Seconds since the recording began.
    let time: TimeInterval
    let source: WorkoutMarkerSource
    var note: String?
}

struct WorkoutMarkerRequest: Equatable {
    var source: WorkoutMarkerSource
    var note: String?
    /// When the trigger was heard or tapped, on the coach's clock; nil uses the time it is recorded.
    var heardAt: TimeInterval?
}

/// Facts about the workout written once, at the top of the recording.
struct WorkoutRecordingContext {
    let startedAt: Date
    let timeZone: TimeZone
    let exercises: [ExerciseDefinition]
    let plan: WorkoutPlan?
    let settings: WorkoutSettings
    let tiltWarningsEnabled: Bool
    let isCoachMuted: Bool
    let isMicMuted: Bool
}

enum WorkoutCommandSource: String, Equatable {
    case voice
    case touch
}

enum WorkoutRecordingEnd: String, Equatable {
    /// The workout reached its summary.
    case workoutEnded
    /// The camera screen closed first.
    case closed
    /// The recording reached its maximum length; the workout carried on.
    case timeLimit
}

/// A discrete happening worth a line of its own. Per-frame values go in frame lines instead.
enum WorkoutRecordingEvent: Equatable {
    /// A reducer input other than ticks, commands (recorded with their source), and per-frame form output.
    case input(WorkoutEvent)
    case command(WorkoutCommand, source: WorkoutCommandSource, phrase: String?)
    case speak(Utterance, muted: Bool)
    case repeatLastInstruction(muted: Bool)
    case tipShown(CoachingTip)
    case tipCleared
    case clearFeedback
    case cameraRunning
    case cameraInterrupted
    case cameraFailed(String)
    case audioInterruptionBegan
    case audioInterruptionEnded(shouldResume: Bool)
    case guidePresented(Bool)
    case helpPresented(Bool)
    case measurementsShown(Bool)

    /// The reducer inputs worth recording; the rest are recorded another way or are too frequent.
    init?(input event: WorkoutEvent) {
        switch event {
        case .tick, .command, .formObserved, .coachSpeakingChanged:
            return nil
        default:
            self = .input(event)
        }
    }
}

/// What the coach is doing, compared after every reducer call. A line is written only when it changes.
struct WorkoutStateSnapshot: Equatable {
    var phase: String
    var exerciseID: String?
    var planIndex: Int?
    var setNumber: Int
    var side: String?
    var repCount: Int
    var leftReps: Int
    var rightReps: Int
    var isCounting: Bool
    var analyzerEpoch: Int
    var framingReliable: Bool
    var framingGuidance: String?
    var restEndsAt: TimeInterval?
    var isPhoneTilted: Bool
    var tipCueID: String?
    var isCoachSpeaking: Bool
    var micStatus: String
    var isCoachMuted: Bool
    var isMicMuted: Bool
    var cameraStatus: String
}

/// Records one workout for later review and replay. Every call is cheap on the main actor; encoding and file
/// writes happen elsewhere. Times are on the coach's clock (`Clock.now`).
@MainActor
protocol WorkoutSessionRecording: AnyObject {
    /// Also the id of the workout's saved history record, so the two can be matched.
    var id: UUID { get }
    var isRecording: Bool { get }
    var markers: [WorkoutMarker] { get }

    func begin(_ context: WorkoutRecordingContext, at uptime: TimeInterval)
    func recordControl(_ control: WorkoutFramePipeline.Control, at uptime: TimeInterval)
    /// `processed` is false when no exercise was selected, so the pipeline never saw the frame.
    func recordFrame(_ frame: PoseFrame, output: WorkoutFramePipeline.FrameOutput?, pitchDegrees: Double?,
                     at uptime: TimeInterval)
    func recordState(_ snapshot: WorkoutStateSnapshot, at uptime: TimeInterval)
    func recordEvent(_ event: WorkoutRecordingEvent, at uptime: TimeInterval)
    @discardableResult
    func recordMarker(_ request: WorkoutMarkerRequest, at uptime: TimeInterval) -> WorkoutMarker?
    /// Seconds since the recording began, or 0 when not recording.
    func duration(at uptime: TimeInterval) -> TimeInterval
    /// Writes everything buffered before returning, as the app is suspended.
    func flush()
    func end(_ reason: WorkoutRecordingEnd, workoutRecordID: UUID?, at uptime: TimeInterval)
}

extension WorkoutStateSnapshot {
    init(session: WorkoutSession, isPhoneTilted: Bool, activeTip: CoachingTip?, isCoachSpeaking: Bool,
         micStatus: VoiceStatus, isCoachMuted: Bool, isMicMuted: Bool, cameraStatus: WorkoutCameraStatus) {
        phase = Self.label(session.phase)
        exerciseID = session.exerciseID?.rawValue
        planIndex = session.plan == nil ? nil : session.planIndex
        setNumber = session.currentSetNumber
        side = session.currentSide?.rawValue
        repCount = session.repCount
        leftReps = session.sideReps[.left] ?? 0
        rightReps = session.sideReps[.right] ?? 0
        isCounting = session.isCounting
        analyzerEpoch = session.analyzerEpoch
        framingReliable = session.framing.isReliable
        framingGuidance = session.framing.guidance?.rawValue
        restEndsAt = session.phase == .resting ? session.restEndsAt : nil
        self.isPhoneTilted = isPhoneTilted
        tipCueID = activeTip?.cue.id.rawValue
        self.isCoachSpeaking = isCoachSpeaking
        self.micStatus = String(describing: micStatus)
        self.isCoachMuted = isCoachMuted
        self.isMicMuted = isMicMuted
        self.cameraStatus = Self.label(cameraStatus)
    }

    /// "paused(user)", "changingExercise(ready)", and so on.
    static func label(_ phase: WorkoutPhase) -> String {
        switch phase {
        case .choosingExercise: return "choosingExercise"
        case .framing: return "framing"
        case .ready: return "ready"
        case .exercising: return "exercising"
        case .paused(let reason): return "paused(\(reason))"
        case .resting: return "resting"
        case .changingExercise(let previous): return "changingExercise(\(label(previous)))"
        case .exerciseComplete: return "exerciseComplete"
        case .ended: return "ended"
        }
    }

    static func label(_ status: WorkoutCameraStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .starting: return "starting"
        case .running: return "running"
        case .interrupted: return "interrupted"
        case .notAuthorized: return "notAuthorized"
        case .failed: return "failed"
        }
    }
}
