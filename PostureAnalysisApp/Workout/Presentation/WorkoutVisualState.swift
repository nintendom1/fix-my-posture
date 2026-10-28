import Foundation

/// The active coaching cue's stable presentation identity and category.
struct WorkoutVisualTip: Equatable {
    let id: Int
    let kind: CoachingCue.Kind
    let text: String?

    init(id: Int, kind: CoachingCue.Kind, text: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

/// Inputs needed to derive the workout camera's semantic visual state.
struct WorkoutVisualInputs: Equatable {
    let phase: WorkoutPhase
    let isCounting: Bool
    let framing: FramingStatus
    let restRemaining: TimeInterval?
    let isPhoneTilted: Bool
    let activeTip: WorkoutVisualTip?
    let hasPose: Bool
    let now: TimeInterval
    let lastRepAt: TimeInterval?
    /// Self-reported exercises are never "lost" and draw no ghost or threshold lines: the camera can't follow them.
    let tracking: ExerciseTracking

    init(phase: WorkoutPhase, isCounting: Bool, framing: FramingStatus,
         restRemaining: TimeInterval?, isPhoneTilted: Bool, activeTip: WorkoutVisualTip?,
         hasPose: Bool, now: TimeInterval, lastRepAt: TimeInterval?, tracking: ExerciseTracking = .camera) {
        self.phase = phase
        self.isCounting = isCounting
        self.framing = framing
        self.restRemaining = restRemaining
        self.isPhoneTilted = isPhoneTilted
        self.activeTip = activeTip
        self.hasPose = hasPose
        self.now = now
        self.lastRepAt = lastRepAt
        self.tracking = tracking
    }

    init(session: WorkoutSession, now: TimeInterval, isPhoneTilted: Bool,
         activeTip: WorkoutVisualTip?, hasPose: Bool) {
        self.init(phase: session.phase,
                  isCounting: session.isCounting,
                  framing: session.framing,
                  restRemaining: session.restRemaining(at: now),
                  isPhoneTilted: isPhoneTilted,
                  activeTip: activeTip,
                  hasPose: hasPose,
                  now: now,
                  lastRepAt: session.lastRepAt,
                  tracking: session.exercise?.tracking ?? .camera)
    }
}

/// Pure semantic state for the workout camera. The primary state follows the documented precedence;
/// secondary alerts remain available as badges, and a rep flash never replaces the primary state.
struct WorkoutVisualState: Equatable {
    enum Primary: Equatable {
        case ready
        case active
        case paused(PauseReason)
        case tip
        case rest
        case lost
        case tilt
        case complete
    }

    enum Badge: Hashable {
        case tilt
        case tip
        case lost
    }

    enum DesignRole: Equatable {
        case brand
        case neutral
        case warning
        case rest
        case danger
        case success
    }

    enum Overlay: Equatable {
        case none
        case ghostDemo
        case repThresholds
    }

    static let repFlashDuration: TimeInterval = 0.7
    static let repFlashLabel = "Rep counted"

    let primary: Primary
    let badges: Set<Badge>
    let activeTip: WorkoutVisualTip?
    let restRemaining: TimeInterval?
    let isRepFlashing: Bool
    let overlay: Overlay
    /// The live joints over the camera. Off for self-reported exercises, which the camera doesn't follow.
    var showsLiveSkeleton = true
    let showsCompletionCard: Bool
    let showsExerciseChooser: Bool

    var label: String {
        switch primary {
        case .ready: return "Get in position"
        case .active: return "Counting"
        case .paused: return "Paused"
        case .tip: return "Form tip"
        case .rest: return "Resting"
        case .lost: return "Tracking lost"
        case .tilt: return "Check the phone"
        case .complete: return "Complete"
        }
    }

    var iconName: String {
        switch primary {
        case .ready: return "accessibility_new"
        case .active: return "graphic_eq"
        case .paused: return "pause_circle"
        case .tip: return "tips_and_updates"
        case .rest: return "self_improvement"
        case .lost: return "visibility_off"
        case .tilt: return "screen_rotation"
        case .complete: return "check_circle"
        }
    }

    var designRole: DesignRole {
        switch primary {
        case .ready: return .brand
        case .active: return .neutral
        case .paused, .tip, .tilt: return .warning
        case .rest: return .rest
        case .lost: return .danger
        case .complete: return .success
        }
    }

    static func derive(_ inputs: WorkoutVisualInputs) -> WorkoutVisualState {
        let isPaused: Bool
        if case .paused = inputs.phase { isPaused = true } else { isPaused = false }

        let isComplete = inputs.phase == .exerciseComplete || inputs.phase == .ended
        let isResting = inputs.phase == .resting
        let isExercising = inputs.phase == .exercising
        let selfReported = inputs.tracking == .selfReported
        let isLost = isExercising && !selfReported && (!inputs.isCounting || !inputs.hasPose)
        let isTip = isExercising && inputs.activeTip != nil
        let isActive = isExercising && (selfReported || (inputs.isCounting && inputs.hasPose))

        let primary: Primary
        if isComplete {
            primary = .complete
        } else if isPaused {
            if case .paused(let reason) = inputs.phase {
                primary = .paused(reason)
            } else {
                primary = .paused(.user)
            }
        } else if isResting {
            primary = .rest
        } else if inputs.isPhoneTilted {
            primary = .tilt
        } else if isLost {
            primary = .lost
        } else if isTip {
            primary = .tip
        } else if isActive {
            primary = .active
        } else {
            primary = .ready
        }

        var badges = Set<Badge>()
        if inputs.isPhoneTilted && primary != .tilt { badges.insert(.tilt) }
        if isTip && primary != .tip { badges.insert(.tip) }
        if isLost && primary != .lost { badges.insert(.lost) }

        let elapsedSinceRep = inputs.lastRepAt.map { inputs.now - $0 }
        let isRepFlashing = elapsedSinceRep.map { $0 >= 0 && $0 < repFlashDuration } ?? false

        let overlay: Overlay
        switch inputs.phase {
        case _ where selfReported:
            overlay = .none
        case .framing, .ready, .resting:
            overlay = .ghostDemo
        case .exercising, .paused:
            overlay = .repThresholds
        default:
            overlay = .none
        }

        let showsExerciseChooser: Bool
        if case .changingExercise = inputs.phase { showsExerciseChooser = true } else { showsExerciseChooser = false }

        return WorkoutVisualState(
            primary: primary,
            badges: badges,
            activeTip: inputs.activeTip,
            restRemaining: isResting ? inputs.restRemaining : nil,
            isRepFlashing: isRepFlashing,
            overlay: overlay,
            showsLiveSkeleton: !selfReported,
            showsCompletionCard: inputs.phase == .exerciseComplete,
            showsExerciseChooser: showsExerciseChooser
        )
    }
}
