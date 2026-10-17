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

    init(visual: WorkoutVisualInputs, exercise: WorkoutHUDExercise?, voiceCommandsAvailable: Bool,
         currentSetNumber: Int, currentSide: BodySide?, repCount: Int, repEventCount: Int,
         isRestingBeforeNextExercise: Bool, planPositionLabel: String?) {
        self.visual = visual
        self.exercise = exercise
        self.voiceCommandsAvailable = voiceCommandsAvailable
        self.currentSetNumber = currentSetNumber
        self.currentSide = currentSide
        self.repCount = repCount
        self.repEventCount = repEventCount
        self.isRestingBeforeNextExercise = isRestingBeforeNextExercise
        self.planPositionLabel = planPositionLabel
    }

    init(session: WorkoutSession, visual: WorkoutVisualInputs, voiceCommandsAvailable: Bool) {
        self.init(
            visual: visual,
            exercise: session.exercise.map {
                WorkoutHUDExercise(
                    id: $0.id,
                    displayName: $0.displayName,
                    targetLabel: $0.targetLabel,
                    startsByHolding: $0.startsByHolding,
                    startPositionInstruction: $0.guide.startPositionInstruction,
                    sets: $0.sets,
                    setsAndRepsLabel: $0.setsAndRepsLabel,
                    equipment: $0.equipment,
                    countsArmsIndependently: $0.countsArmsIndependently
                )
            },
            voiceCommandsAvailable: voiceCommandsAvailable,
            currentSetNumber: session.currentSetNumber,
            currentSide: session.currentSide,
            repCount: session.repCount,
            repEventCount: session.repEventCount,
            isRestingBeforeNextExercise: session.isRestingBeforeNextExercise,
            planPositionLabel: session.planPositionLabel
        )
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
            if inputs.voiceCommandsAvailable, Int(inputs.visual.now / hintAlternation) % 2 == 1 {
                statusText = "Say \u{201C}what can I say\u{201D} for commands"
            } else if let exercise {
                if exercise.startsByHolding {
                    statusText = "\(exercise.startPositionInstruction) to begin"
                } else {
                    statusText = inputs.voiceCommandsAvailable ? "Say \u{201C}start\u{201D} to begin" : "Tap Start to begin"
                }
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
                                      canEndWorkout: phase != .ended)
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
