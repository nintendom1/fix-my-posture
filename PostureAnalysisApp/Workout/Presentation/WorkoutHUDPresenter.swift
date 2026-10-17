import Foundation

/// The semantic tone used by today's HUD. SwiftUI owns the mapping to its existing colors.
enum WorkoutHUDStatusTone: Equatable {
    case endPosition
    case tracked
    case attention
    case subdued
}

enum WorkoutHUDPrimaryButtonKind: Equatable {
    case start
    case startSet
    case pause
    case resume
    case disabled
}

struct WorkoutHUDPrimaryButton: Equatable {
    let kind: WorkoutHUDPrimaryButtonKind
    let label: String

    var systemImageName: String {
        switch kind {
        case .pause: return "pause.fill"
        case .start, .startSet, .resume, .disabled: return "play.fill"
        }
    }

    var isEnabled: Bool { kind != .disabled }

    var command: WorkoutCommand? {
        switch kind {
        case .start, .startSet: return .start
        case .pause: return .pause
        case .resume: return .resume
        case .disabled: return nil
        }
    }
}

enum WorkoutHUDRestTone: Equatable {
    case waiting
    case ready
}

/// The minimal exercise data needed to preserve existing HUD wording.
struct WorkoutHUDExercise: Equatable {
    let id: ExerciseID
    let displayName: String
    let targetLabel: String
    let startsByHolding: Bool
    let startPositionInstruction: String
    let sets: Int
    let setsAndRepsLabel: String
    let equipment: ExerciseEquipment
    let countsArmsIndependently: Bool
    let targetReps: ClosedRange<Int>
    let restSeconds: Int

    init(id: ExerciseID, displayName: String, targetLabel: String, startsByHolding: Bool,
         startPositionInstruction: String, sets: Int, setsAndRepsLabel: String,
         equipment: ExerciseEquipment, countsArmsIndependently: Bool,
         targetReps: ClosedRange<Int> = 1...1, restSeconds: Int = 60) {
        self.id = id
        self.displayName = displayName
        self.targetLabel = targetLabel
        self.startsByHolding = startsByHolding
        self.startPositionInstruction = startPositionInstruction
        self.sets = sets
        self.setsAndRepsLabel = setsAndRepsLabel
        self.equipment = equipment
        self.countsArmsIndependently = countsArmsIndependently
        self.targetReps = targetReps
        self.restSeconds = restSeconds
    }

    init(exercise: ExerciseDefinition, startsByHolding: Bool? = nil, restSeconds: Int? = nil) {
        self.init(id: exercise.id,
                  displayName: exercise.displayName,
                  targetLabel: exercise.targetLabel,
                  startsByHolding: startsByHolding ?? exercise.startsByHolding,
                  startPositionInstruction: exercise.guide.startPositionInstruction,
                  sets: exercise.sets,
                  setsAndRepsLabel: exercise.setsAndRepsLabel,
                  equipment: exercise.equipment,
                  countsArmsIndependently: exercise.countsArmsIndependently,
                  targetReps: exercise.targetReps,
                  restSeconds: restSeconds ?? exercise.restSeconds)
    }
}

struct WorkoutHUDInputs: Equatable {
    let visual: WorkoutVisualInputs
    let exercise: WorkoutHUDExercise?
    let voiceCommandsAvailable: Bool
    let currentSetNumber: Int
    let currentSide: BodySide?
    let repCount: Int
    let repEventCount: Int
    let isRestingBeforeNextExercise: Bool
    let planPositionLabel: String?
    let planName: String?
    let nextPlanExercise: WorkoutHUDExercise?

    init(visual: WorkoutVisualInputs, exercise: WorkoutHUDExercise?, voiceCommandsAvailable: Bool,
         currentSetNumber: Int, currentSide: BodySide?, repCount: Int, repEventCount: Int,
         isRestingBeforeNextExercise: Bool, planPositionLabel: String?,
         planName: String? = nil, nextPlanExercise: WorkoutHUDExercise? = nil) {
        self.visual = visual
        self.exercise = exercise
        self.voiceCommandsAvailable = voiceCommandsAvailable
        self.currentSetNumber = currentSetNumber
        self.currentSide = currentSide
        self.repCount = repCount
        self.repEventCount = repEventCount
        self.isRestingBeforeNextExercise = isRestingBeforeNextExercise
        self.planPositionLabel = planPositionLabel
        self.planName = planName
        self.nextPlanExercise = nextPlanExercise
    }

    init(session: WorkoutSession, visual: WorkoutVisualInputs, voiceCommandsAvailable: Bool) {
        self.init(
            visual: visual,
            exercise: session.exercise.map {
                WorkoutHUDExercise(
                    exercise: $0,
                    startsByHolding: session.effectiveStartsByHolding,
                    restSeconds: session.restDurationSeconds ?? session.effectiveRestSeconds ?? $0.restSeconds
                )
            },
            voiceCommandsAvailable: voiceCommandsAvailable,
            currentSetNumber: session.currentSetNumber,
            currentSide: session.currentSide,
            repCount: session.repCount,
            repEventCount: session.repEventCount,
            isRestingBeforeNextExercise: session.isRestingBeforeNextExercise,
            planPositionLabel: session.planPositionLabel,
            planName: session.isFollowingPlan ? session.plan?.name : nil,
            nextPlanExercise: Self.nextPlanExercise(in: session)
        )
    }

    private static func nextPlanExercise(in session: WorkoutSession) -> WorkoutHUDExercise? {
        guard session.isFollowingPlan, let plan = session.plan else { return nil }
        for item in plan.items.dropFirst(session.planIndex + 1) {
            guard let definition = session.exercises.first(where: { $0.id == item.exerciseID }) else { continue }
            return WorkoutHUDExercise(exercise: definition.withTarget(sets: item.sets, reps: item.targetReps))
        }
        return nil
    }
}

struct WorkoutHUDPresentation: Equatable {
    let statusText: String
    let statusTone: WorkoutHUDStatusTone
    let primaryButton: WorkoutHUDPrimaryButton
    let setLabel: String?
    let restLabel: String?
    let restTone: WorkoutHUDRestTone?
    /// The exercise plan line shown under the set label (for example, "Exercise 2 of 5").
    let planProgressLabel: String?
    /// The live line shown by Voice Commands help.
    let progressLine: String?
    let showsRepProgress: Bool
    let repEventCount: Int
    let isSetInProgress: Bool
    let canAdvanceSet: Bool
    let canEndWorkout: Bool
    let pillLabel: String
    let pillIcon: String
    let instructionText: String?
    let subtitle: String?
    let restCountdownText: String?
    let primaryAction: WorkoutIntent?
    let primaryActionLabel: String?
    let primaryActionIcon: String?
    let setSummary: String?
    let nextLine: String?
    let counterText: String
    let counterTargetText: String?
    let progressValue: Double
}

/// Pure display rules for the camera HUD and Voice Commands progress header.
enum WorkoutHUDPresenter {
    static let hintAlternation: TimeInterval = 4

    static func derive(_ inputs: WorkoutHUDInputs) -> WorkoutHUDPresentation {
        let phase = inputs.visual.phase
        let exercise = inputs.exercise

        let statusText: String
        let statusTone: WorkoutHUDStatusTone
        switch phase {
        case .choosingExercise, .changingExercise:
            statusText = "Choose an exercise"
            statusTone = .subdued
        case .framing:
            statusText = inputs.visual.framing.guidance?.shortText ?? "Hold still"
            statusTone = .attention
        case .ready:
            if let exercise, !exercise.startsByHolding {
                statusText = inputs.voiceCommandsAvailable ? "Say \u{201C}start\u{201D} or tap play" : "Tap play to start"
            } else if inputs.voiceCommandsAvailable, Int(inputs.visual.now / hintAlternation) % 2 == 1 {
                statusText = "Say \u{201C}what can I say\u{201D} for commands"
            } else if let exercise {
                statusText = "\(exercise.startPositionInstruction) to begin"
            } else {
                statusText = "Ready"
            }
            statusTone = .endPosition
        case .exercising:
            statusText = inputs.visual.isCounting
                ? "Counting"
                : (inputs.visual.framing.guidance?.shortText ?? FramingGuidance.stepIntoView.shortText)
            statusTone = inputs.visual.isCounting ? .tracked : .attention
        case .paused:
            statusText = "Paused"
            statusTone = .subdued
        case .resting:
            statusText = "Resting"
            statusTone = .subdued
        case .exerciseComplete:
            statusText = "Exercise complete"
            statusTone = .subdued
        case .ended:
            statusText = "Workout ended"
            statusTone = .subdued
        }

        let primaryButton: WorkoutHUDPrimaryButton
        switch phase {
        case .exercising:
            primaryButton = WorkoutHUDPrimaryButton(kind: .pause, label: "Pause")
        case .paused:
            primaryButton = WorkoutHUDPrimaryButton(kind: .resume, label: "Resume")
        case .resting:
            primaryButton = WorkoutHUDPrimaryButton(kind: .startSet, label: "Start set \(inputs.currentSetNumber)")
        case .framing, .ready:
            primaryButton = WorkoutHUDPrimaryButton(kind: .start, label: "Start")
        case .choosingExercise, .changingExercise, .exerciseComplete, .ended:
            primaryButton = WorkoutHUDPrimaryButton(kind: .disabled, label: "Start")
        }

        let arm = inputs.currentSide.map { $0 == .left ? " · Left arm" : " · Right arm" } ?? ""
        let setLabel: String?
        if let exercise {
            switch phase {
            case .resting:
                setLabel = "Next: set \(inputs.currentSetNumber) of \(exercise.sets)\(arm)"
            case .exerciseComplete:
                setLabel = "All \(exercise.sets) sets done"
            default:
                setLabel = "Set \(inputs.currentSetNumber) of \(exercise.sets)\(arm)"
            }
        } else {
            setLabel = nil
        }

        let restLabel = inputs.visual.restRemaining.map { "Rest \(format($0))" }
        let restTone: WorkoutHUDRestTone? = inputs.visual.restRemaining.map { $0 > 0 ? .waiting : .ready }

        let planProgressLabel: String?
        if inputs.isRestingBeforeNextExercise, let exercise {
            planProgressLabel = "Up next: \(exercise.displayName) · \(exercise.setsAndRepsLabel)"
        } else {
            planProgressLabel = inputs.planPositionLabel
        }

        let progressLine: String?
        if let exercise {
            switch phase {
            case .exercising, .paused:
                progressLine = "Set \(inputs.currentSetNumber) of \(exercise.sets) · \(inputs.repCount) reps"
            case .resting:
                progressLine = inputs.visual.restRemaining.map { "Resting · \(format($0))" }
            default:
                progressLine = nil
            }
        } else {
            progressLine = nil
        }

        let semanticState = WorkoutVisualState.derive(inputs.visual)
        let cameraCopy = cameraCopy(for: semanticState, inputs: inputs)
        let restCountdownText = semanticState.primary == .rest
            ? inputs.visual.restRemaining.map(format)
            : nil
        let primaryAction = primaryAction(for: semanticState.primary)
        let primaryActionLabel = primaryLabel(for: semanticState.primary)
        let primaryActionIcon = primaryIcon(for: semanticState.primary)

        let setSummary = exercise.map { value in
            let side = inputs.currentSide.map { $0 == .left ? " · Left arm" : " · Right arm" } ?? ""
            return "Set \(inputs.currentSetNumber) of \(value.sets) · target \(value.targetLabel)\(side)"
        }
        let nextLine = nextLine(for: inputs, phase: phase)
        let subtitle: String?
        if let planName = inputs.planName, let position = inputs.planPositionLabel {
            subtitle = "\(planName) · \(position.replacingOccurrences(of: "Exercise", with: "exercise"))"
        } else if let setSummary {
            subtitle = setSummary
        } else {
            subtitle = nil
        }
        let progressValue: Double
        if semanticState.primary == .rest, let exercise, let remaining = inputs.visual.restRemaining {
            progressValue = min(max(1 - remaining / Double(max(1, exercise.restSeconds)), 0), 1)
        } else if let exercise {
            progressValue = min(max(Double(inputs.repCount) / Double(max(1, exercise.targetReps.upperBound)), 0), 1)
        } else {
            progressValue = 0
        }

        return WorkoutHUDPresentation(statusText: statusText,
                                      statusTone: statusTone,
                                      primaryButton: primaryButton,
                                      setLabel: setLabel,
                                      restLabel: restLabel,
                                      restTone: restTone,
                                      planProgressLabel: planProgressLabel,
                                      progressLine: progressLine,
                                      showsRepProgress: exercise != nil,
                                      repEventCount: inputs.repEventCount,
                                      isSetInProgress: isSetInProgress(phase),
                                      canAdvanceSet: canAdvanceSet(phase),
                                      canEndWorkout: phase != .ended,
                                      pillLabel: semanticState.label,
                                      pillIcon: semanticState.iconName,
                                      instructionText: cameraCopy,
                                      subtitle: subtitle,
                                      restCountdownText: restCountdownText,
                                      primaryAction: primaryAction,
                                      primaryActionLabel: primaryActionLabel,
                                      primaryActionIcon: primaryActionIcon,
                                      setSummary: setSummary,
                                      nextLine: nextLine,
                                      counterText: restCountdownText ?? "\(inputs.repCount)",
                                      counterTargetText: restCountdownText == nil ? exercise.map { "/ \($0.targetReps.upperBound)" } : nil,
                                      progressValue: progressValue)
    }

    private static func cameraCopy(for state: WorkoutVisualState, inputs: WorkoutHUDInputs) -> String? {
        switch state.primary {
        case .ready:
            guard let exercise = inputs.exercise else { return nil }
            return exercise.startsByHolding ? exercise.startPositionInstruction : "Tap Start to begin"
        case .active:
            return inputs.exercise?.id == .shoulderPress ? "Breathe out as you press." : nil
        case .paused:
            return "Say “resume” or tap play"
        case .tip:
            return state.activeTip?.text
        case .rest:
            return nextLine(for: inputs, phase: inputs.visual.phase) ?? "Rest up"
        case .lost:
            return "Step back so both arms are in view"
        case .tilt:
            return "The phone is tilted. Stand it upright."
        case .complete:
            return nil
        }
    }

    private static func primaryAction(for state: WorkoutVisualState.Primary) -> WorkoutIntent? {
        switch state {
        case .ready: return .start
        case .active, .tip, .lost, .tilt: return .pause
        case .paused: return .resume
        case .rest: return .nextSet
        case .complete: return nil
        }
    }

    private static func primaryLabel(for state: WorkoutVisualState.Primary) -> String? {
        switch state {
        case .ready: return "Start set"
        case .active, .tip, .lost, .tilt: return "Pause"
        case .paused: return "Resume"
        case .rest: return "Skip rest"
        case .complete: return nil
        }
    }

    private static func primaryIcon(for state: WorkoutVisualState.Primary) -> String? {
        switch state {
        case .ready, .paused: return "play_arrow"
        case .active, .tip, .lost, .tilt: return "pause"
        case .rest: return "skip_next"
        case .complete: return nil
        }
    }

    private static func nextLine(for inputs: WorkoutHUDInputs, phase: WorkoutPhase) -> String? {
        guard let exercise = inputs.exercise else { return nil }
        if inputs.isRestingBeforeNextExercise {
            return "Next: set 1 of \(exercise.sets) · \(exercise.targetLabel) reps"
        }
        if phase == .resting {
            return "Next: set \(inputs.currentSetNumber) of \(exercise.sets) · \(exercise.targetLabel) reps"
        }
        if let next = inputs.nextPlanExercise {
            let displayName = next.displayName.replacingOccurrences(of: "One-Arm ", with: "")
            return "Next: \(displayName)"
        }
        guard inputs.currentSetNumber < exercise.sets else { return nil }
        return "Next: set \(inputs.currentSetNumber + 1) of \(exercise.sets) · \(exercise.targetLabel) reps"
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func isSetInProgress(_ phase: WorkoutPhase) -> Bool {
        switch phase {
        case .exercising, .paused: return true
        default: return false
        }
    }

    private static func canAdvanceSet(_ phase: WorkoutPhase) -> Bool {
        isSetInProgress(phase) || phase == .resting
    }
}
