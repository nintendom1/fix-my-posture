import Foundation

extension ProgressionCatalog {
    /// The V1 ladders. Each floor sits under a lift the app already has, so one rep of anything harder that is
    /// too hard always has somewhere safe to go. "Shallow", "partial", and "supported" rungs are modifiers on
    /// one exercise, not separate exercises. Neck and core grow by dose only.
    ///
    /// Exercise IDs that the app hasn't built yet are skipped through `Availability`, so a ladder can be complete
    /// before every variant exists.
    public static let v1 = ProgressionCatalog(version: "ladders-1", families: [
        MovementFamily(id: .push, debugName: "Push", rungs: [
            ProgressionRung(id: VariantID(rawValue: "push.wall_push_up.shallow"), exerciseID: "wall_push_up",
                            modifiers: [.reducedRange], doseRange: .reps(1...8), isFloor: true),
            ProgressionRung(id: VariantID(rawValue: "push.wall_push_up"), exerciseID: "wall_push_up",
                            doseRange: .reps(1...12)),
            ProgressionRung(id: VariantID(rawValue: "push.incline_push_up"), exerciseID: "incline_push_up",
                            doseRange: .reps(1...12)),
            ProgressionRung(id: VariantID(rawValue: "push.push_up"), exerciseID: "push_up",
                            doseRange: .reps(1...15))
        ]),
        MovementFamily(id: .squat, debugName: "Squat", rungs: [
            ProgressionRung(id: VariantID(rawValue: "squat.sit_to_stand.partial"), exerciseID: "sit_to_stand",
                            modifiers: [.reducedRange], doseRange: .reps(1...8), isFloor: true),
            ProgressionRung(id: VariantID(rawValue: "squat.sit_to_stand"), exerciseID: "sit_to_stand",
                            doseRange: .reps(1...12)),
            ProgressionRung(id: VariantID(rawValue: "squat.air_squat"), exerciseID: "air_squat",
                            doseRange: .reps(1...20))
        ]),
        MovementFamily(id: .row, debugName: "Row", rungs: [
            ProgressionRung(id: VariantID(rawValue: "row.scapular_squeeze.seated"), exerciseID: "scapular_squeeze",
                            doseRange: .reps(1...12), isFloor: true),
            ProgressionRung(id: VariantID(rawValue: "row.dumbbell_row"), exerciseID: "dumbbell_row",
                            doseRange: .reps(1...12), requiredEquipment: [.dumbbells])
        ]),
        MovementFamily(id: .overhead, debugName: "Overhead", rungs: [
            ProgressionRung(id: VariantID(rawValue: "overhead.wall_slide.partial"), exerciseID: "wall_slide",
                            modifiers: [.reducedRange, .supported], doseRange: .reps(1...8), isFloor: true),
            ProgressionRung(id: VariantID(rawValue: "overhead.wall_slide"), exerciseID: "wall_slide",
                            modifiers: [.supported], doseRange: .reps(1...12)),
            ProgressionRung(id: VariantID(rawValue: "overhead.shoulder_press"), exerciseID: "shoulder_press",
                            doseRange: .reps(1...12), requiredEquipment: [.dumbbells])
        ]),
        MovementFamily(id: .hinge, debugName: "Hinge", rungs: [
            ProgressionRung(id: VariantID(rawValue: "hinge.hip_hinge.supported_shallow"), exerciseID: "hip_hinge",
                            modifiers: [.reducedRange, .supported], doseRange: .reps(1...8), isFloor: true),
            ProgressionRung(id: VariantID(rawValue: "hinge.hip_hinge"), exerciseID: "hip_hinge",
                            doseRange: .reps(1...12)),
            ProgressionRung(id: VariantID(rawValue: "hinge.stiff_leg_deadlift"), exerciseID: "stiff_leg_deadlift",
                            doseRange: .reps(1...12), requiredEquipment: [.dumbbells])
        ]),
        MovementFamily(id: .glute, debugName: "Glute", rungs: [
            ProgressionRung(id: VariantID(rawValue: "glute.glute_squeeze"), exerciseID: "glute_squeeze",
                            doseRange: .seconds(5...30), isFloor: true),
            ProgressionRung(id: VariantID(rawValue: "glute.glute_bridge"), exerciseID: "glute_bridge",
                            doseRange: .reps(1...15))
        ]),
        MovementFamily(id: .lunge, debugName: "Lunge", rungs: [
            ProgressionRung(id: VariantID(rawValue: "lunge.weight_shift.supported"), exerciseID: "weight_shift",
                            modifiers: [.supported], doseRange: .reps(1...10), isFloor: true),
            ProgressionRung(id: VariantID(rawValue: "lunge.weight_shift"), exerciseID: "weight_shift",
                            doseRange: .reps(1...12)),
            ProgressionRung(id: VariantID(rawValue: "lunge.rear_lunge"), exerciseID: "rear_lunge",
                            doseRange: .reps(1...10), requiredEquipment: [.dumbbells])
        ]),
        MovementFamily(id: .neck, debugName: "Neck", rungs: [
            ProgressionRung(id: VariantID(rawValue: "neck.chin_tuck"), exerciseID: "chin_tuck",
                            doseRange: .reps(1...12), isFloor: true)
        ]),
        MovementFamily(id: .core, debugName: "Core", rungs: [
            ProgressionRung(id: VariantID(rawValue: "core.abdominal_brace"), exerciseID: "abdominal_brace",
                            doseRange: .seconds(5...45), isFloor: true)
        ])
    ])
}
