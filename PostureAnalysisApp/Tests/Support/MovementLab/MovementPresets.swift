import Foundation
@testable import PostureAnalysisApp

/// Small, explicit scenario plans that cover common Air Squat variations.
enum MovementPresets {
    static func airSquat(createdAt: String = "1970-01-01T00:00:00Z",
                         author: MovementAuthor = .agent) -> MovementPlan {
        let exercise = AirSquatExercise.definition()
        let motion = exercise.guide.motion
        let revision = MovementCanonicalRevision.value(for: exercise)
        let motionDuration = motion.duration
        let firstBottomMotionTime = MovementGuideTimeline.maximumHipDropTime(in: motion)
        let firstBottom = MovementGenerator.readyHold + firstBottomMotionTime
        let secondRepStart = MovementGenerator.readyHold + motionDuration
        let fifthRepMiddle = MovementGenerator.readyHold + motionDuration * 2 + 0.8
        let slowTempo = MovementMutation.tempo(scale: 2.0, reps: nil)
        let slowPauseAt = MovementGenerator.readyHold + firstBottomMotionTime * 2

        func scenario(_ id: String, _ category: MovementCategory, _ purpose: String,
                      _ mutations: [MovementMutation] = [], _ assertions: [MovementAssertion] = [],
                      _ mode: MovementMode = .constrained, _ seed: UInt64 = 133,
                      scenarioRevision: Int = 1, parentRevision: Int? = nil) -> MovementScenario {
            MovementScenario(id: id, exercise: exercise.id, category: category, purpose: purpose,
                             canonicalRevision: revision, seed: seed, reps: 5, mode: mode,
                             mutations: mutations, assertions: assertions, revision: scenarioRevision,
                             parentRevision: parentRevision)
        }

        let kneeMutations = (1...5).flatMap { rep -> [MovementMutation] in
            let peak = MovementGuideTimeline.maximumHipDropOutputTime(
                rep: rep, motion: motion, mutations: [], readyHold: MovementGenerator.readyHold)
            return [
                .jointOffset(joints: [LandmarkType.leftKnee.rawValue], dx: -0.04, dy: 0,
                             peak: peak, rise: 0.35, fall: 0.35, strength: 1),
                .jointOffset(joints: [LandmarkType.rightKnee.rawValue], dx: 0.04, dy: 0,
                             peak: peak, rise: 0.35, fall: 0.35, strength: 1)
            ]
        }

        let scenarios = [
            scenario("canonical", .canonical,
                     "Count the guide motion at its normal range.", [], [.repCount(equals: 5, min: nil, max: nil)]),
            scenario("shallow-depth", .depthROM,
                     "Revision 2 corrects the failed run's partialEnd expectation: Air Squat reports a shallow form attempt, not a partialEnd rejection; keep the frozen zero-rep expectation.",
                     [.depthScale(scale: 0.5, reps: nil)],
                     [.repCount(equals: 0, min: nil, max: nil)], scenarioRevision: 2, parentRevision: 1),
            scenario("slightly-shallow", .depthROM,
                     "Record whether a modest range reduction still counts.",
                     [.depthScale(scale: 0.85, reps: nil)], [.repCount(equals: nil, min: 4, max: nil)]),
            scenario("knees-caving", .alignment,
                     "Move both knees toward the center only around each squat bottom.", kneeMutations),
            scenario("asymmetric-hip-drop", .alignment,
                     "Lower one side of the pelvis as the squat reaches depth.",
                     [.asymmetry(side: .left, amount: 0.12)]),
            scenario("fast-tempo", .timing,
                     "Run the guide cycle at half duration.", [.tempo(scale: 0.5, reps: nil)]),
            scenario("slow-pause", .timing,
                     "Double the cycle time and hold the first maximum hip drop for 1.5 seconds.",
                     [slowTempo, .pause(at: slowPauseAt, duration: 1.5)]),
            scenario("knee-dropout", .tracking,
                     "Remove both knee landmarks during the second descent.",
                     [.dropout(joints: ["leftKnee", "rightKnee"], from: secondRepStart + 0.35,
                               to: secondRepStart + 0.8)]),
            scenario("low-ankle-confidence", .tracking,
                     "Lower ankle confidence below the live analyzer floor for part of a rep.",
                     [.confidence(joints: ["leftAnkle", "rightAnkle"], from: secondRepStart + 0.3,
                                 to: secondRepStart + 0.8, value: 0.2)]),
            scenario("mid-set-gap", .timing,
                     "Drop frames for half a second in the middle of the set.",
                     [.frameGap(at: fifthRepMiddle, duration: 0.5)]),
            scenario("too-close-framing", .sessionFraming,
                     "Revision 2 corrects the failed run: scale up and shift down until required knees and ankles leave the image, exercising FramingEvaluator's required-joint visibility rule; scale-only kept them visible.",
                     [.framing(scale: 1.6, offsetX: 0, offsetY: 0.5)],
                     [.framing(state: "reliable", reached: false)], scenarioRevision: 2, parentRevision: 1),
            scenario("raw-impossible-limb", .alignment,
                     "Preserve an intentionally impossible Vision-style knee location.",
                     [.jointOffset(joints: ["leftKnee"], dx: 0.5, dy: 0.5,
                                   peak: firstBottom, rise: 0.2, fall: 0.2, strength: 1)],
                     [.repCount(equals: nil, min: 0, max: nil)], .raw)
        ]

        return MovementPlan(id: "air-squat-core-v1", title: "Air Squat Movement Scenarios",
                            purpose: "Synthetic hypotheses for Air Squat counting, tracking, and framing.",
                            author: author, createdAt: createdAt, scenarios: scenarios)
    }
}
