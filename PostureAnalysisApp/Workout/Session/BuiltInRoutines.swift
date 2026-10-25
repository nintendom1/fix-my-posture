import Foundation

/// Read-only starter routines that ship with the app. Their ids are literals that never change, so workout history
/// (`WorkoutRecord.planID`) and Up Next keep matching across launches and app updates.
enum BuiltInRoutines {
    // These ids are persisted in workout history and must never change.
    static let all: [SavedExerciseSet] = [
        SavedExerciseSet(
            id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x76)),
            name: "Upper Body",
            items: [
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x76, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01)),
                    exerciseID: .pushUp,
                    setCount: 1,
                    targetRepMinimum: 8,
                    targetRepMaximum: 8
                ),
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x76, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02)),
                    exerciseID: .dumbbellRow,
                    setCount: 1,
                    targetRepMinimum: 8,
                    targetRepMaximum: 8
                ),
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x76, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03)),
                    exerciseID: .shoulderPress,
                    setCount: 1,
                    targetRepMinimum: 8,
                    targetRepMaximum: 8
                )
            ]
        ),
        SavedExerciseSet(
            id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x77)),
            name: "Chest & Arms",
            items: [
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x77, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01)),
                    exerciseID: .pushUp,
                    setCount: 1,
                    targetRepMinimum: 10,
                    targetRepMaximum: 10
                ),
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x77, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02)),
                    exerciseID: .hammerCurl,
                    setCount: 1,
                    targetRepMinimum: 10,
                    targetRepMaximum: 10
                ),
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x77, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03)),
                    exerciseID: .tricepsExtension,
                    setCount: 1,
                    targetRepMinimum: 10,
                    targetRepMaximum: 10
                )
            ]
        ),
        SavedExerciseSet(
            id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78)),
            name: "Lower Body",
            items: [
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x78, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01)),
                    exerciseID: .airSquat,
                    setCount: 1,
                    targetRepMinimum: 10,
                    targetRepMaximum: 10
                ),
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x78, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02)),
                    exerciseID: .stiffLegDeadlift,
                    setCount: 1,
                    targetRepMinimum: 8,
                    targetRepMaximum: 8
                ),
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x78, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03)),
                    exerciseID: .rearLunge,
                    setCount: 1,
                    targetRepMinimum: 5,
                    targetRepMaximum: 5
                )
            ]
        ),
        SavedExerciseSet(
            id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79)),
            name: "Shoulders & Arms",
            items: [
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x79, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01)),
                    exerciseID: .shoulderPress,
                    setCount: 1,
                    targetRepMinimum: 8,
                    targetRepMaximum: 8
                ),
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x79, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02)),
                    exerciseID: .lateralRaise,
                    setCount: 1,
                    targetRepMinimum: 8,
                    targetRepMaximum: 8
                ),
                SavedExerciseSetItem(
                    id: UUID(uuid: (0x5E, 0x7A, 0x00, 0x79, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03)),
                    exerciseID: .hammerCurl,
                    setCount: 1,
                    targetRepMinimum: 10,
                    targetRepMaximum: 10
                )
            ]
        )
    ]

    static func contains(id: UUID) -> Bool {
        all.contains { $0.id == id }
    }

    static func routine(id: UUID) -> SavedExerciseSet? {
        all.first { $0.id == id }
    }
}
