import Foundation

/// Canonical bundled exercise photos and the credits displayed in Acknowledgements.
/// Keep these records synchronized with Assets.xcassets/ExerciseThumbnails/SOURCES.md.
struct ExercisePhotography: Identifiable {
    let id: ExerciseID
    let exerciseName: String
    let assetName: String
    let photographer: String
    let source: String
    let sourceURL: URL
    let license: String

    /// SF Symbols for catalog exercises waiting on approved photography. Keep empty until a source is vetted.
    static let placeholders: [ExerciseID: String] = [
        .wallPushUp: "figure.strengthtraining.functional"
    ]

    static let all: [ExercisePhotography] = [
        ExercisePhotography(
            id: .airSquat,
            exerciseName: "Air Squat",
            assetName: "ExerciseThumbnails/air_squat",
            photographer: "Polina Tankilevitch",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/women-working-out-in-the-room-6516212/")!,
            license: "Pexels License"
        ),
        ExercisePhotography(
            id: .stiffLegDeadlift,
            exerciseName: "Stiff-Legged Dumbbell Deadlift",
            assetName: "ExerciseThumbnails/stiff_leg_deadlift",
            photographer: "marcuschanmedia",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/female-weightlifter-performing-deadlift-in-gym-29825217/") ?? URL(fileURLWithPath: "/"),
            license: "Pexels License"
        ),
        ExercisePhotography(
            id: .rearLunge,
            exerciseName: "Dumbbell Rear Lunge",
            assetName: "ExerciseThumbnails/rear_lunge",
            photographer: "Anna Shvets",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/senior-man-doing-sport-exercises-5067741/")
                ?? URL(fileURLWithPath: "/"),
            license: "Pexels License"
        ),
        ExercisePhotography(
            id: .gluteBridge,
            exerciseName: "Glute Bridge",
            assetName: "ExerciseThumbnails/glute_bridge",
            photographer: "Vlada Karpovich",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/a-woman-doing-yoga-in-the-room-4534643/")!,
            license: "Pexels License"
        ),
        ExercisePhotography(
            id: .dumbbellRow,
            exerciseName: "Dumbbell Row",
            assetName: "ExerciseThumbnails/dumbbell_row",
            photographer: "Airam Dato-on",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/woman-lifting-weights-in-a-gym-13106582/")!,
            license: "Pexels License"
        ),
        ExercisePhotography(
            id: .dumbbellShrug,
            exerciseName: "Dumbbell Shrug",
            assetName: "ExerciseThumbnails/dumbbell_shrug",
            photographer: "Tima Miroshnichenko",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/man-in-black-tank-top-holding-dumbbells-5327450/")
                ?? URL(fileURLWithPath: "/"),
            license: "Pexels License"
        ),
        ExercisePhotography(
            id: .hammerCurl,
            exerciseName: "Hammer Curl",
            assetName: "ExerciseThumbnails/hammer_curl",
            photographer: "Staff Sgt. Lucas Vega",
            source: "DVIDS / U.S. Marine Corps",
            sourceURL: URL(string: "https://www.dvidshub.net/image/6272440/okinawa-marine-maintains-physical-readiness-covid-19-environment")!,
            license: "U.S. government photograph; public domain in the United States"
        ),
        ExercisePhotography(
            id: .pushUp,
            exerciseName: "Push-Up",
            assetName: "ExerciseThumbnails/push_up",
            photographer: "Polina Tankilevitch",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/woman-doing-push-up-6516167/")!,
            license: "Pexels License"
        ),
        ExercisePhotography(
            id: .shoulderPress,
            exerciseName: "Shoulder Press",
            assetName: "ExerciseThumbnails/shoulder_press",
            photographer: "Senior Airman Greydon Furstenau",
            source: "U.S. Air Force / Wikimedia Commons",
            sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Discipline_in_motion,_Incirlik_Airman_inspires_others_through_fitness_(9444781).jpg")!,
            license: "U.S. government photograph; public domain in the United States"
        ),
        ExercisePhotography(
            id: .lateralRaise,
            exerciseName: "Lateral Raise",
            assetName: "ExerciseThumbnails/lateral_raise",
            photographer: "Andrea Piacquadio",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/man-in-gray-tank-top-holding-black-dumbbells-3839506/")
                ?? URL(fileURLWithPath: "/"),
            license: "Pexels License"
        ),
        ExercisePhotography(
            id: .tricepsExtension,
            exerciseName: "Triceps Extension",
            assetName: "ExerciseThumbnails/triceps_extension",
            photographer: "Miguel González",
            source: "Pexels",
            sourceURL: URL(string: "https://www.pexels.com/photo/a-woman-lifting-a-dumbbell-14623619/")!,
            license: "Pexels License"
        )
    ]

    static func photograph(for exerciseID: ExerciseID) -> ExercisePhotography? {
        all.first { $0.id == exerciseID }
    }
}
