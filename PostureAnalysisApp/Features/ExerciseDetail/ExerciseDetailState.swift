import Foundation

struct ExerciseDetailState: Equatable {
    let id: ExerciseID
    let name: String
    let muscles: String
    let gradient: ExerciseGradient
    let symbolName: String
    let equipmentText: String
    let cameraSetupText: String
    let watchesFor: [String]
    let steps: [GuideStep]
    var sets: Int
    var repMinimum: Int
    var repMaximum: Int
    var isGuidePresented: Bool
    var isTargetEditorPresented: Bool
    let isAvailable: Bool

    var repsLabel: String {
        repMinimum == repMaximum ? "\(repMinimum)" : "\(repMinimum)–\(repMaximum)"
    }

    init(
        id: ExerciseID,
        name: String,
        muscles: String,
        gradient: ExerciseGradient,
        symbolName: String,
        equipmentText: String,
        cameraSetupText: String,
        watchesFor: [String],
        steps: [GuideStep],
        sets: Int,
        repMinimum: Int,
        repMaximum: Int,
        isGuidePresented: Bool = false,
        isTargetEditorPresented: Bool = false,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.muscles = muscles
        self.gradient = gradient
        self.symbolName = symbolName
        self.equipmentText = equipmentText
        self.cameraSetupText = cameraSetupText
        self.watchesFor = watchesFor
        self.steps = steps
        self.sets = sets
        self.repMinimum = repMinimum
        self.repMaximum = repMaximum
        self.isGuidePresented = isGuidePresented
        self.isTargetEditorPresented = isTargetEditorPresented
        self.isAvailable = isAvailable
    }

    static func unavailable(id: ExerciseID) -> ExerciseDetailState {
        ExerciseDetailState(
            id: id,
            name: "Exercise Unavailable",
            muscles: "",
            gradient: ExerciseGradient(token: .press, stops: ["#7C4DFF", "#C04BD8"], angle: 135),
            symbolName: "dumbbell.fill",
            equipmentText: "",
            cameraSetupText: "",
            watchesFor: [],
            steps: [],
            sets: 1,
            repMinimum: 1,
            repMaximum: 1,
            isAvailable: false
        )
    }
}

enum ExerciseDetailIntent: Equatable {
    case appeared
    case back
    case decrementSets
    case incrementSets
    case editReps
    case targetEditorDismissed
    case watchGuide
    case dismissGuide
    case startFromGuide
    case startExercise
}
